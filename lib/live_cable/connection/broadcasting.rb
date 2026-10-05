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
        rendered = Set.new
        shared_changeset = containers[SHARED_CONTAINER]&.changeset
        changed = lambda do |component|
          containers[component.live_id]&.changed? || component.shared_reactive_variables.intersect?(shared_changeset)
        end

        list = components.values
        list = list.any?(&changed) ? parents_first(list) : []

        list.each do |component|
          # Component may have already been re-rendered by a parent, so don't render it again
          next if rendered.include?(component)
          next unless changed.call(component)

          # Still last cycle's: a render that a callback halts doesn't replace it
          component.rendered_children.clear

          begin
            component.broadcast_render
          rescue StandardError => error
            handle_error(component, error)
            add_tree(component, :owned_children, rendered)
          end

          add_tree(component, :rendered_children, rendered)
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

          component.broadcast_events
        end

        rendered.to_a
      end

      # Parents come before the children they own, so a child its parent
      # renders inline is already handled when the loop reaches it.
      def parents_first(list)
        children = list.to_h { |component| [component, component.owned_children] }
        owned = children.values.flatten.to_set
        ordered = {}
        visit = lambda do |component|
          next if ordered.key?(component) || !children.key?(component)

          ordered[component] = true
          children[component].each(&visit)
        end
        list.each { |component| visit.call(component) unless owned.include?(component) }

        ordered.keys | list
      end

      def add_tree(component, children, seen)
        return unless seen.add?(component)

        component.public_send(children).each { |child| add_tree(child, children, seen) }
      end
    end
  end
end
