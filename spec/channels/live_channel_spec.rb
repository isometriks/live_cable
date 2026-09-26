# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveChannel, type: :channel do
  let(:live_connection) { LiveCable::Connection.new(ActionDispatch::TestRequest.create) }

  before do
    stub_connection(live_connection:)
  end

  # Build the component as normal, then make one of its methods raise
  def build_component_that_fails(method, message)
    allow(LiveCable).to receive(:instance_from_string).and_wrap_original do |original, *args|
      original.call(*args).tap do |component|
        allow(component).to receive(method).and_raise(RuntimeError, message)
      end
    end
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

    it 'transmits an _error when the component fails before it has a channel' do
      allow(Rails.error).to receive(:report)
      build_component_that_fails(:apply_defaults, 'bad default')

      subscribe(component: 'counter', id: 'c1')

      expect(transmissions.last['_error']).to include('bad default')
    end

    it 'lets the client unsubscribe clean up a component whose subscribe failed' do
      allow(Rails.error).to receive(:report)
      build_component_that_fails(:broadcast_render, 'bad template')

      subscribe(component: 'counter', id: 'c1')
      expect(live_connection.get_component('counter/c1')).to be_present

      unsubscribe

      expect(live_connection.get_component('counter/c1')).to be_nil
    end

    it 'refuses a connection whose live_connection is shadowed by a leftover identified_by' do
      stub_connection(live_connection: nil)

      expect do
        subscribe(component: 'counter', id: 'c1')
      end.to raise_error(LiveCable::Error, /identified_by :live_connection/)
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
