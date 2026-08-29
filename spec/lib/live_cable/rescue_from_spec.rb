# frozen_string_literal: true

require 'rails_helper'
require 'action_dispatch/testing/test_request'

# A distinct exception class so the handler only matches what we intend.
class RescueFromHandledError < StandardError; end

RSpec.describe 'Component rescue_from' do
  def build_connection
    LiveCable::Connection.new(ActionDispatch::TestRequest.create('rack.session' => {}))
  end

  let(:component_class) do
    Class.new(LiveCable::Component) do
      def self.name = 'Live::RescuableExample'

      reactive :message, -> {}

      rescue_from RescueFromHandledError do |error|
        self.message = "handled: #{error.message}"
      end
    end
  end

  it 'lets a component handle its own error and skips the default error broadcast' do
    connection = build_connection
    component = component_class.new('r1')
    connection.add_component(component)
    channel = LiveCable::Testing::TestChannel.new
    component.connect(channel)

    connection.handle_error(component, RescueFromHandledError.new('boom'))

    expect(component.message).to eq('handled: boom')
    expect(channel.transmissions.select { |t| t.key?(:_error) }).to be_empty
  end

  it 'falls back to the default error broadcast when no handler matches' do
    connection = build_connection
    component = component_class.new('r2')
    connection.add_component(component)
    channel = LiveCable::Testing::TestChannel.new
    component.connect(channel)

    connection.handle_error(component, RuntimeError.new('unhandled'))

    expect(channel.transmissions.select { |t| t.key?(:_error) }).not_to be_empty
  end
end
