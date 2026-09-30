# frozen_string_literal: true

require 'rails_helper'
require 'action_dispatch/testing/test_request'

RSpec.describe 'Component rescue_from' do
  # A distinct exception class so the handler only matches what we intend.
  let(:handled_error) { stub_const('HandledError', Class.new(StandardError)) }

  let(:component_class) do
    error_class = handled_error

    Class.new(LiveCable::Component) do
      def self.name
        'Live::RescuableExample'
      end

      reactive :message, -> {}
      actions :fail_handled, :fail_quietly, :fail_unhandled

      rescue_from error_class do |error|
        self.message = "handled: #{error.message}" unless error.message == 'quiet'
      end

      define_method(:fail_handled) { raise error_class, 'boom' }
      define_method(:fail_quietly) { raise error_class, 'quiet' }

      def fail_unhandled
        raise 'unhandled'
      end
    end
  end

  let(:connection) { LiveCable::Connection.new(ActionDispatch::TestRequest.create('rack.session' => {})) }
  let(:channel) { LiveCable::Testing::TestChannel.new }
  let(:component) do
    component_class.new('r1').tap do |component|
      connection.add_component(component)
      component.connect(channel)
    end
  end

  def perform(action)
    connection.receive(component, 'messages' => [{ '_action' => action }])
  end

  def transmitted(key)
    channel.transmissions.select { |transmission| transmission.key?(key) }
  end

  it 'lets a component handle an error raised by an action and re-renders what the handler set' do
    # No template for this anonymous class; the render itself isn't under test
    allow(component).to receive(:broadcast_render) { channel.broadcast(_refresh: component.message) }

    perform('fail_handled')

    expect(transmitted(:_error)).to be_empty
    expect(transmitted(:_refresh)).to eq([{ _refresh: 'handled: boom' }])
  end

  it 'still answers the batch when the handler changed nothing, so the client is not left loading' do
    perform('fail_quietly')

    expect(transmitted(:_error)).to be_empty
    expect(transmitted(:_ack)).not_to be_empty
  end

  it 'offers an error raised in a stream callback to rescue_from and renders what the handler set' do
    allow(component).to receive(:broadcast_render) { channel.broadcast(_refresh: component.message) }
    component.send(:stream_from, 'feed') { raise handled_error, 'from the stream' }

    channel.broadcast_to('feed', {})

    expect(transmitted(:_error)).to be_empty
    expect(transmitted(:_refresh)).to eq([{ _refresh: 'handled: from the stream' }])
  end

  it 'sends the default _error when a rescue_from handler itself raises in a stream callback' do
    allow(component).to receive(:rescue_with_handler).and_raise('handler broke')
    component.send(:stream_from, 'feed') { raise handled_error, 'from the stream' }

    expect { channel.broadcast_to('feed', {}) }.not_to raise_error
    expect(transmitted(:_error)).not_to be_empty
  end

  it 'falls back to the default _error when no handler matches' do
    perform('fail_unhandled')

    expect(transmitted(:_error)).not_to be_empty
  end

  context 'with a handler broad enough to catch the framework guards' do
    before { component_class.rescue_from(StandardError) { self.message = 'swallowed' } }

    it 'still rejects an action the component does not expose' do
      perform('destroy_everything')

      expect(component.message).to be_nil
      expect(transmitted(:_error)).not_to be_empty
    end

    it 'still rejects a write to a non-writable reactive variable' do
      connection.receive(component, 'messages' => [{ '_action' => '_reactive', 'name' => 'message', 'value' => 'x' }])

      expect(component.message).to be_nil
      expect(transmitted(:_error)).not_to be_empty
    end

    it 'still rejects a reactive write with no name' do
      connection.receive(component, 'messages' => [{ '_action' => '_reactive', 'value' => 'x' }])

      expect(component.message).to be_nil
      expect(transmitted(:_error)).not_to be_empty
    end

    it 'still rejects an action that is not a string' do
      connection.receive(component, 'messages' => [{ '_action' => 5 }])

      expect(component.message).to be_nil
      expect(transmitted(:_error)).not_to be_empty
    end
  end

  it 'does not consult rescue_from from handle_error, which reports framework failures such as a subscribe' do
    connection.handle_error(component, handled_error.new('boom'))

    expect(component.message).to be_nil
    expect(transmitted(:_error)).not_to be_empty
  end
end
