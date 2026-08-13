# frozen_string_literal: true

module LiveCable
  class Component
    module Broadcasting
      extend ActiveSupport::Concern

      # Every payload a component sends to its client goes through here.
      #
      # A component's stream belongs to exactly one websocket: Connection mints
      # a fresh UUID per ActionCable connection, so channel_name is
      # live_<uuid>/<live_id> (see Connection::ChannelManagement) and can never
      # have a second subscriber. Writing straight to the channel is therefore
      # equivalent to publishing over pubsub, minus the round trip - and it
      # closes a race. ActionCable registers stream_from asynchronously, so a
      # payload published in the same breath as LiveChannel#subscribed could
      # arrive before the subscription existed and be dropped, leaving the
      # component stuck on its server-rendered "disconnected" state forever.
      #
      # A component has no channel until its own controller subscribes; children
      # rendered by a parent sit in that state, and nothing is listening to their
      # stream yet either, so there is nobody to deliver to.
      def broadcast(data)
        channel&.broadcast(data)
      end

      def broadcast_subscribe
        broadcast({ _status: 'subscribed', id: live_id })
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
