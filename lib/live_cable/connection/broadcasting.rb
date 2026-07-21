# frozen_string_literal: true

module LiveCable
  class Connection
    module Broadcasting
      extend ActiveSupport::Concern

      # @return [Array<LiveCable::Component>] Components that were broadcast to
      #   (rendered or errored), including children rendered by their parents
      def broadcast_changeset
        rendered = []
        shared_changeset = containers[SHARED_CONTAINER]&.changeset

        # Use a copy of the components since new ones can get added while rendering
        # and causes an issue here.
        components.values.dup.each do |component|
          # Component may have already been re-rendered by a parent, so don't render it again
          next if rendered.include?(component)

          container = containers[component.live_id]

          next unless container&.changed? || component.shared_reactive_variables.intersect?(shared_changeset)

          begin
            component.broadcast_render
          rescue StandardError => error
            handle_error(component, error)
          end

          rendered |= [component] | component.rendered_children
        end

        # Deliver events from components that didn't broadcast a render this
        # cycle (no state change, or rendered inline by a parent) - rendered
        # components already flushed their events with the refresh
        components.each_value do |component|
          events = component.flush_events
          component.broadcast(_events: events) if events.any?
        end

        rendered
      end
    end
  end
end
