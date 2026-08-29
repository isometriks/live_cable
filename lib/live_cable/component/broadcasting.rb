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
        broadcast({ _status: 'subscribed', id: live_id })

        # Deliver any events queued before this component had a channel of its
        # own (e.g. dispatched while it was rendered inline by a parent). The
        # broadcast_render path flushes events itself, so this only matters for
        # an already-rendered component that subscribes without re-rendering.
        events = flush_events
        broadcast(_events: events) if events.any?
      end

      # Sent when a received message didn't change any reactive variables,
      # so the client can clear its loading state without a re-render.
      def broadcast_ack
        broadcast({ _ack: true })
      end

      def broadcast_destroy
        broadcast({ _status: 'destroy' })
        @subscribed = false
      end

      def broadcast_render
        run_callbacks :render do
          data = { _refresh: render.as_json }

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
