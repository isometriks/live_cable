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
        run_callbacks :render do
          rendered = render
          # Generate template_id from current template path
          template_id = generate_template_id_from_path(to_partial_path)
          # Always send JSON string in _refresh with template_id
          broadcast(
            _refresh: rendered.parts,
            _template_id: template_id,
            _live_id: live_id,
          )
        end
      end

      private

      def generate_template_id_from_path(template_path)
        # Generate a short hash of the template path to avoid revealing server paths
        # Use Digest::SHA256 and take first 12 characters for compactness
        require 'digest'
        Digest::SHA256.hexdigest(template_path)[0..11]
      end
    end
  end
end
