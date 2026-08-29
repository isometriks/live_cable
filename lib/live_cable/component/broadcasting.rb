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

      # Render and broadcast the component. Returns true when a _refresh was
      # actually sent, false when the render was a no-op (so the caller can
      # fall back to an _ack).
      def broadcast_render
        broadcasted = false

        run_callbacks :render do
          result = render
          events = flush_events

          # Skip broadcasting a diff that changed nothing in the rendered
          # output. It would cost a WebSocket message plus a full client-side
          # rebuild and morph for no visible effect - common when a shared
          # reactive variable changes but this component doesn't display it.
          # Queued events are still delivered on their own.
          if result.is_a?(LiveCable::Rendering::RenderResult) && result.blank?
            broadcast(_events: events) if events.any?
          else
            data = { _refresh: result.as_json }
            # Events ride along with the render so the client can fire them
            # after the DOM has been morphed
            data[:_events] = events if events.any?

            broadcast(data)
            broadcasted = true
          end
        end

        broadcasted
      end
    end
  end
end
