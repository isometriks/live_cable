# frozen_string_literal: true

module LiveCable
  class Component
    module Broadcasting
      extend ActiveSupport::Concern

      # Nil until the component's own controller subscribes; children rendered
      # by a parent have no channel to deliver to yet.
      def broadcast(data)
        channel&.broadcast(data)
      end

      def broadcast_subscribe
        broadcast({ _status: 'subscribed', id: live_id, _subscribed: true })

        # Deliver any events queued before this component had a channel of its
        # own (e.g. dispatched while it was rendered inline by a parent). The
        # broadcast_render path flushes events itself, so this only matters for
        # an already-rendered component that subscribes without re-rendering.
        broadcast_events
      end

      # Sends any queued events on their own, for when there's no render for
      # them to ride along with.
      def broadcast_events
        events = flush_events
        broadcast(_events: events) if events.any?
      end

      # Answers a message batch when the component's own render didn't -
      # nothing changed, or its render went out inside its parent's. Events
      # the batch queued ride along, so they fire once the loading state ends.
      #
      # @param rendered [Boolean] whether a parent's frame carried its render
      def broadcast_ack(rendered: false)
        data = { _ack: true }
        data[:_rendered] = true if rendered
        events = flush_events
        data[:_events] = events if events.any?
        broadcast(data)
      end

      def broadcast_destroy
        broadcast({ _status: 'destroy' })
        @subscribed = false
      end

      # @param subscribed [Boolean] whether this is the render sent when the
      #   component subscribes
      # @return [Boolean] false when the render changed nothing on the page, so
      #   no _refresh went out
      def broadcast_render(subscribed: false)
        sent = false

        while_rendering do
          run_callbacks :render do
            result = render

            # Leaves the reply unclaimed, so the message is answered with an _ack
            if !subscribed && result.is_a?(LiveCable::Rendering::RenderResult) && result.blank?
              broadcast_events unless live_connection&.awaiting_reply?(self)
              next
            end

            events = flush_events
            data = { _refresh: result.as_json, _reply: live_connection&.take_reply(self) }
            data[:_subscribed] = true if subscribed
            live_connection&.carried(data[:_refresh][:c])

            # A component a parent rendered inline has no channel until its own
            # subscription connects, so this render never reaches the client.
            # The next one that does must be a full render rather than a diff
            # against what was just rendered here.
            forget_client_render_state unless channel

            # Events ride along with the render so the client can fire them
            # after the DOM has been morphed
            data[:_events] = events if events.any?

            broadcast(data)
            sent = true
          end
        end

        sent
      end

      private

      def while_rendering(&)
        live_connection ? live_connection.rendering(&) : yield
      end
    end
  end
end
