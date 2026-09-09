# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveChannel, type: :channel do
  let(:live_connection) { LiveCable::Connection.new(ActionDispatch::TestRequest.create) }

  before do
    stub_connection(live_connection:)
  end

  describe '#subscribed' do
    it 'renders the component' do
      subscribe(component: 'counter', id: 'c1')

      expect(subscription).to be_confirmed
      expect(transmissions.last).to have_key('_refresh')
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
