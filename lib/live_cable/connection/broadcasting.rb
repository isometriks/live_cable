# frozen_string_literal: true

module LiveCable
  class Connection
    module Broadcasting
      extend ActiveSupport::Concern

      def broadcast_changeset
        rendered = []
        shared_changeset = containers[SHARED_CONTAINER]&.changeset

        # Use a copy of the components since new ones can get added while rendering
        # and causes an issue here.
        components.values.dup.each do |component|
          # Component may have already been re-rendered by a parent, so don't render it again
          next if rendered.include?(component)

          container = containers[component.live_id]

          if container&.changed? || component.shared_reactive_variables.intersect?(shared_changeset)
            component.broadcast_render
            rendered |= component.rendered_children
          end
        end
      end
    end
  end
end
