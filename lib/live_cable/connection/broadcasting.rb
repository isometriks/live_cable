# frozen_string_literal: true

module LiveCable
  class Connection
    module Broadcasting
      extend ActiveSupport::Concern

      def broadcast_changeset
        # Use a copy of the components since new ones can get added while rendering
        # and causes an issue here.
        components.values.dup.each do |component|
          container = containers[component.live_id]
          if container&.changed?
            component.broadcast_render

            next
          end

          shared_changeset = containers[SHARED_CONTAINER]&.changeset || []

          if (component.shared_reactive_variables || []).intersect?(shared_changeset)
            component.broadcast_render
          end
        end
      end
    end
  end
end
