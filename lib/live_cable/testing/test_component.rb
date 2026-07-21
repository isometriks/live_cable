# frozen_string_literal: true

require 'delegate'

module LiveCable
  module Testing
    # Wraps a mounted component for testing. Delegates unknown methods to
    # the component itself, so reactive variables and component methods can
    # be read directly (e.g. +counter.count+).
    class TestComponent < SimpleDelegator
      # @return [LiveCable::Connection]
      attr_reader :connection

      # @return [LiveCable::Testing::TestChannel]
      attr_reader :channel

      def initialize(component, connection, channel)
        super(component)
        @connection = connection
        @channel = channel
        @broadcasts = []

        capture_broadcasts(component)
      end

      # @return [LiveCable::Component] The underlying component instance
      def component
        __getobj__
      end

      # Dispatch an action through the real message pipeline, as if it was
      # triggered by live-action or live-form in the browser.
      #
      # Params go through a query-string round trip, so values arrive as
      # ActionController::Parameters with string values - exactly like
      # production.
      #
      # @param action [Symbol, String] The action name
      # @param params [Hash] Parameters for the action
      def perform(action, params = {})
        receive_message(
          '_action' => action.to_s,
          'params' => ::Rack::Utils.build_nested_query(params)
        )
      end

      # Update a writable reactive variable, as if the client sent a
      # live-reactive input update. Raises (or broadcasts an _error when
      # mounted with raise_errors: false) for non-writable variables.
      #
      # @param name [Symbol, String] The reactive variable name
      # @param value [Object] The new value
      def set_reactive(name, value)
        receive_message(
          '_action' => '_reactive',
          'name' => name.to_s,
          'value' => value
        )
      end

      # Simulate an external ActionCable broadcast arriving on a stream the
      # component subscribed to via stream_from.
      #
      # @param stream_name [String] The stream name
      # @param payload [Object] The broadcast payload
      def receive_stream(stream_name, payload)
        channel.broadcast_to(stream_name, payload)
      end

      # Everything the component has broadcast since mounting (renders,
      # acks, status updates, errors), oldest first.
      #
      # @param key [Symbol, nil] Filter to broadcasts containing this key
      #   (e.g. :_refresh, :_ack, :_error, :_status)
      # @return [Array<Hash>]
      def broadcasts(key = nil)
        return @broadcasts.dup unless key

        @broadcasts.select { |broadcast| broadcast.key?(key) }
      end

      # Forget previously captured broadcasts. Useful after mounting, to
      # assert on the effects of a single action.
      def clear_broadcasts
        @broadcasts.clear
      end

      # The component's current HTML, reconstructed from its _refresh
      # broadcasts the same way the JavaScript client builds the DOM.
      #
      # @return [String]
      def rendered_html
        state = RenderState.new

        broadcasts(:_refresh).each do |broadcast|
          state.apply(broadcast[:_refresh])
        end

        state.html
      end

      # The rendered HTML wrapped in a Capybara node, for use with matchers
      # like have_css / have_content. Requires the capybara gem.
      #
      # @return [Capybara::Node::Simple]
      def rendered
        # ::-prefixed because Delegator subclasses can't resolve top-level
        # constants through their BasicObject ancestry
        unless defined?(::Capybara)
          raise ::LiveCable::Error,
            'Capybara is required for rendered - add it to your Gemfile or use rendered_html'
        end

        ::Capybara.string(rendered_html)
      end

      # Disconnect the component, running disconnect lifecycle callbacks and
      # cleaning up its state - like a client unsubscribing.
      def unmount
        component.disconnect
      end

      private

      def receive_message(message)
        connection.receive(component, { 'messages' => [message] })
      end

      def capture_broadcasts(component)
        captured = @broadcasts

        component.define_singleton_method(:broadcast) do |data|
          captured << data
        end
      end
    end
  end
end
