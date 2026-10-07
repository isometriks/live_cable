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
      #
      # @param rendered [Boolean] whether a parent's frame carried its render
      def broadcast_ack(rendered: false)
        data = { _ack: true }
        data[:_rendered] = true if rendered
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

        run_callbacks :render do
          result = render
          events = flush_events

          # Leaves the reply unclaimed, so the message is answered with an _ack
          if !subscribed && result.is_a?(LiveCable::Rendering::RenderResult) && result.blank?
            broadcast(_events: events) if events.any?
            next
          end

          data = { _refresh: result.as_json, _reply: live_connection&.take_reply(self) }
          data[:_subscribed] = true if subscribed
          live_connection&.carried(data[:_refresh][:c])

          # Events ride along with the render so the client can fire them
          # after the DOM has been morphed
          data[:_events] = events if events.any?

          broadcast(data)
          sent = true
        end

        sent
      end
    end
  end
end
