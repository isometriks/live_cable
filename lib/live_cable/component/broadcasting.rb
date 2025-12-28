# frozen_string_literal: true

module LiveCable
  class Component
    module Broadcasting
      extend ActiveSupport::Concern

      def broadcast(data)
        ActionCable.server.broadcast(channel_name, data)
      end

      def broadcast_subscribe
        broadcast({ _status: 'subscribed', id: live_id })
        @subscribed = true
      end

      def broadcast_destroy
        broadcast({ _status: 'destroy' })
        @subscribed = false
      end

      def broadcast_render
        before_render
        broadcast(_refresh: render)
        after_render
      end
    end
  end
end
