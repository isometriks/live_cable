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
        return channel.transmissions.dup unless key

        channel.transmissions.select { |broadcast| broadcast.key?(key) }
      end

      # Forget previously captured broadcasts. Useful after mounting, to
      # assert on the effects of a single action. Doesn't affect rendered.
      def clear_broadcasts
        channel.transmissions.clear
      end

      # Whether the component called refuse!, which stops it on the client.
      # The reason is in broadcasts(:_refused).last[:_reason].
      #
      # @return [Boolean]
      def refused?
        channel.transmissions.any? { |broadcast| broadcast[:_refused] }
      end

      # All events the component has dispatched via dispatch_event, in
      # order, whether they rode along with a render or an _ack, or were
      # broadcast on their own.
      #
      # @return [Array<Hash>] Event hashes ({ name:, detail:, window: })
      def dispatched_events
        broadcasts(:_events).flat_map { |broadcast| broadcast[:_events] }
      end

      # The component's current HTML, reconstructed from its _refresh
      # broadcasts the same way the JavaScript client builds the DOM.
      #
      # @return [String]
      def rendered_html
        state = RenderState.new

        channel.refreshes.each do |refresh|
          state.apply(refresh)
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

      # Subscribe a child this component rendered inline, as the child's own
      # controller does once the render reaches the page. The child sends its
      # render if anything changed for it since, or only its status.
      #
      # @param live_id [String] The child's live id (e.g. 'todo/write')
      # @return [LiveCable::Testing::TestComponent]
      def subscribe_child(live_id)
        child = connection.get_component(live_id)
        raise ::LiveCable::Error, "No component #{live_id.inspect} has been rendered on this connection" unless child

        test_child = TestComponent.new(child, connection,
                                       TestChannel.new(path: channel.params[:path], connection: channel.connection))

        begin
          connection.subscribe_component(child, test_child.channel, rendered: true)
        rescue StandardError, ScriptError => error
          connection.handle_error(child, error, channel: test_child.channel)
        end

        test_child
      end

      # Disconnect the component and the children it renders, running
      # disconnect lifecycle callbacks and cleaning up their state - like a
      # client unsubscribing.
      def unmount
        connection.synchronize { connection.disconnect_component(component) }
      end

      private

      def receive_message(message)
        if component.live_connection.equal?(connection) && !component.subscribed?
          error = ::LiveCable::Error.new("#{component.class.name} didn't connect, so it cannot receive messages")
          return connection.handle_error(component, error, channel:)
        end

        connection.receive(component, { 'messages' => [message] })
      rescue StandardError, ScriptError => error
        connection.handle_error(component, error, channel:)
      end
    end
  end
end
