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
      # nothing changed, or its render went out inside its parent's.
      def broadcast_ack
        broadcast({ _ack: true })
      end

      def broadcast_destroy
        broadcast({ _status: 'destroy' })
        @subscribed = false
      end

      # @param subscribed [Boolean] whether this is the render sent when the
      #   component subscribes
      def broadcast_render(subscribed: false)
        run_callbacks :render do
          data = { _refresh: render.as_json, _reply: live_connection&.take_reply(self) }
          data[:_subscribed] = true if subscribed

          # Events ride along with the render so the client can fire them
          # after the DOM has been morphed
          events = flush_events
          data[:_events] = events if events.any?

          broadcast(data)
        end
      end
    end
  end
end
