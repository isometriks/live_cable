# frozen_string_literal: true

module LiveCable
  class Connection
    module Broadcasting
      extend ActiveSupport::Concern

      # @return [Array<LiveCable::Component>] Components that were broadcast to
      #   (rendered or errored), including children rendered by their parents
      def broadcast_changeset
        synchronize { broadcast_changeset_unsynchronized }
      end

      private

      def broadcast_changeset_unsynchronized
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
            broadcasted = component.broadcast_render
          rescue StandardError => error
            handle_error(component, error)
            next
          end

          # Only mark the component (and the children it rendered inline) as
          # handled when it actually broadcast. A no-op render leaves it out,
          # so the message path can fall back to an _ack and any child with its
          # own changes still renders on its own.
          rendered |= [component] | component.rendered_children if broadcasted
        end

        # Deliver events from components that didn't broadcast a render this
        # cycle (no state change, or rendered inline by a parent) - rendered
        # components already flushed their events with the refresh.
        #
        # A component rendered inline by a parent has no channel of its own
        # yet, so it can't deliver anything. Leave its events queued (don't
        # flush) so they're delivered when its own subscription connects,
        # rather than silently dropped here.
        components.each_value do |component|
          next unless component.subscribed?

          events = component.flush_events
          component.broadcast(_events: events) if events.any?
        end

        rendered
      end
    end
  end
end
