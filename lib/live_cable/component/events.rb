# frozen_string_literal: true

module LiveCable
  class Component
    module Events
      extend ActiveSupport::Concern

      # Queue a DOM event to be dispatched on the client. Events are
      # delivered with the next broadcast for this component - attached to
      # the render when state changed, or on their own when it didn't - and
      # fire on the client after the DOM has been morphed, so handlers see
      # the updated markup.
      #
      # On the client the event is a bubbling CustomEvent dispatched from
      # the component's root element (or from window with window: true), so
      # it can be handled with plain Stimulus data-action syntax:
      #
      #   <div data-controller="chat" data-action="chat:message-sent->chat#scrollToBottom">
      #
      # @param name [String, Symbol] The event name (e.g. 'chat:message-sent')
      # @param detail [Hash] JSON-serializable payload, available as event.detail.
      #   Can be passed positionally or as bare keyword arguments; use the
      #   positional form if the payload itself needs a :window key.
      # @param window [Boolean] Dispatch on window instead of the component root
      def dispatch_event(name, positional_detail = nil, window: false, **detail)
        detail = positional_detail if positional_detail

        pending_events << { name: name.to_s, detail: detail.as_json, window: }
      end

      # Drain the queued events. Called when a broadcast is sent so each
      # event is delivered exactly once.
      #
      # @return [Array<Hash>]
      def flush_events
        events = pending_events.dup
        pending_events.clear
        events
      end

      private

      # @return [Array<Hash>]
      def pending_events
        @pending_events ||= []
      end
    end
  end
end
