# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveChannel, type: :channel do
  let(:session) { {} }
  let(:request) { ActionDispatch::TestRequest.create('rack.session' => session) }
  let(:live_connection) { LiveCable::Connection.new(request) }

  before do
    stub_connection(live_connection:)
  end

  describe '#subscribed' do
    it 'renders the component' do
      subscribe(component: 'counter', id: 'c1')

      expect(subscription).to be_confirmed
      expect(transmissions.last).to have_key('_refresh')
    end

    it 'hands out no token when the handshake carried no origin' do
      subscribe(component: 'counter', id: 'c1')

      expect(transmissions.flat_map(&:keys)).not_to include('_csrf_token')
    end

    context 'when the handshake came from the application itself' do
      let(:session) { { _csrf_token: SecureRandom.urlsafe_base64(32) } }
      let(:request) { ActionDispatch::TestRequest.create('rack.session' => session, 'HTTP_ORIGIN' => 'http://test.host') }

      it 'hands the page a token for the socket\'s session before rendering' do
        subscribe(component: 'counter', id: 'c1')

        expect(transmissions.first.keys).to eq(['_csrf_token'])
        expect(transmissions.last).to have_key('_refresh')
      end

      it 'accepts a batch carrying the token it handed out' do
        subscribe(component: 'counter', id: 'c1')
        token = transmissions.first['_csrf_token']
        connection.transmissions.clear

        perform(:receive, messages: [{ '_action' => 'increment' }], _csrf_token: token)

        expect(transmissions.last).to have_key('_refresh')
        expect(live_connection.get_component('counter/c1').count).to eq(1)
      end
    end

    it 'transmits an _error when no component could be built' do
      allow(Rails.error).to receive(:report)

      subscribe(component: 'no_such_component', id: 'c1')

      expect(Rails.error).to have_received(:report).with(an_instance_of(LiveCable::Error))
      expect(transmissions.last['_error']).to include('LiveCable::Error')
    end
  end

  describe '#receive' do
    it 'answers a message batch' do
      subscribe(component: 'counter', id: 'c1')
      connection.transmissions.clear

      perform(:receive, messages: [{ '_action' => 'increment' }])

      expect(transmissions.size).to eq(1)
      expect(transmissions.last).to have_key('_refresh')
    end

    context 'when the session has a CSRF token' do
      let(:session) { { _csrf_token: SecureRandom.urlsafe_base64(32) } }

      it 'accepts a token minted from the socket\'s session' do
        token = LiveCable::CsrfChecker.new(request).token
        subscribe(component: 'counter', id: 'c1')
        connection.transmissions.clear

        perform(:receive, messages: [{ '_action' => 'increment' }], _csrf_token: token)

        expect(transmissions.last).to have_key('_refresh')
      end

      it 'asks the client to reconnect and replay a batch whose token it cannot verify' do
        subscribe(component: 'counter', id: 'c1')
        connection.transmissions.clear
        messages = [{ '_action' => 'increment', 'params' => '' }]

        perform(:receive, messages:, _csrf_token: 'from-a-newer-session')

        expect(transmissions.size).to eq(1)
        expect(transmissions.last['_reconnect']).to be(true)
        expect(transmissions.last['messages']).to eq(messages)
      end

      it 'does not run the batch it refused' do
        subscribe(component: 'counter', id: 'c1')
        component = live_connection.get_component('counter/c1')

        perform(:receive, messages: [{ '_action' => 'increment' }], _csrf_token: 'from-a-newer-session')

        expect(component.count).to eq(0)
      end
    end

    it 'transmits an _error instead of raising when there is no component' do
      allow(Rails.error).to receive(:report)
      subscribe(component: 'no_such_component', id: 'c1')
      connection.transmissions.clear

      expect do
        perform(:receive, messages: [{ '_action' => 'increment' }])
      end.not_to raise_error

      expect(transmissions.size).to eq(1)
      expect(transmissions.last['_error']).to include('cannot receive messages')
    end

    it 'transmits an _error instead of raising when the connection raises' do
      allow(Rails.error).to receive(:report)
      subscribe(component: 'counter', id: 'c1')
      connection.transmissions.clear
      allow(live_connection).to receive(:receive).and_raise(RuntimeError, 'boom')

      expect do
        perform(:receive, messages: [{ '_action' => 'increment' }])
      end.not_to raise_error

      expect(transmissions.size).to eq(1)
      expect(transmissions.last['_error']).to include('boom')
    end
  end
end
