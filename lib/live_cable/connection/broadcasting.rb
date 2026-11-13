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

      # Connects a component to its channel and sends what it subscribes with:
      # its render, or only its status when a parent already rendered it and
      # nothing changed for it since, or when a callback halts the render.
      #
      # @param rendered [Boolean] whether a parent rendered it before it subscribed
      def subscribe_component(component, channel, rendered:)
        synchronize do
          component.connect(channel)

          if rendered && !component.render_pending?
            component.broadcast_subscribe
          else
            @shipped_shared = nil
            shared = shared_changeset
            component.rendered_children.clear
            component.broadcast_subscribe unless component.broadcast_render(subscribed: true)

            sent = Set.new.compare_by_identity
            add_tree(component, :rendered_children, sent)
            settle_shared(shared, sent)
          end

          components.each_value(&:discard_absent_stream_ops)
        end
      end

      private

      def broadcast_changeset_unsynchronized
        rendered = Set.new.compare_by_identity
        @shipped_shared = nil
        shared = shared_changeset
        changed = lambda do |component|
          containers[component.live_id].changed? || component.shared_reactive_variables.intersect?(shared) ||
            component.streams_pending?
        end

        list = components.values
        list = list.any?(&changed) ? parents_first(list) : []

        dropping do
          list.each do |component|
            # Its changes wait for its subscribe, which has a channel to send them on
            next unless component.subscribed?
            # Component may have already been re-rendered by a parent, so don't render it again
            next if rendered.include?(component)
            # Taken off the connection by a refusal earlier in the cycle
            next unless components[component.live_id].equal?(component)
            next unless changed.call(component)

            # Still last cycle's: a render that a callback halts doesn't replace it
            component.rendered_children.clear

            begin
              component.broadcast_render
            rescue StandardError, ScriptError => error
              add_tree(component, :owned_children, rendered)
              handle_error(component, error)
            end

            add_tree(component, :rendered_children, rendered)
          end
        end

        settle_shared(shared, rendered)

        # Ops for a stream the client doesn't hold have nowhere to go, unless
        # a render revealed it this cycle and took them
        components.each_value(&:discard_absent_stream_ops)

        # Deliver events from components that didn't broadcast a render this
        # cycle (no state change, or rendered inline by a parent) - rendered
        # components already flushed their events with the refresh, and the
        # component awaiting its reply sends them with its _ack.
        #
        # A component rendered inline by a parent has no channel of its own
        # yet, so it can't deliver anything. Leave its events queued (don't
        # flush) so they're delivered when its own subscription connects,
        # rather than silently dropped here.
        components.each_value do |component|
          next unless component.subscribed?
          next if awaiting_reply?(component)

          component.broadcast_events
        end

        rendered.to_a
      end

      # Parents come before the children they own, so a child its parent
      # renders inline is already handled when the loop reaches it.
      def parents_first(list)
        children = list.each_with_object({}.compare_by_identity) do |component, by_parent|
          by_parent[component] = component.owned_children
        end
        owned = Set.new.compare_by_identity.merge(children.values.flatten)
        ordered = {}.compare_by_identity
        visit = lambda do |component|
          next if ordered.key?(component) || !children.key?(component)

          ordered[component] = true
          children[component].each(&visit)
        end
        list.each { |component| visit.call(component) unless owned.include?(component) }

        ordered.keys.concat(list.reject { |component| ordered.key?(component) })
      end

      def add_tree(component, children, seen)
        return unless seen.add?(component)

        component.public_send(children).each { |child| add_tree(child, children, seen) }
      end
    end
  end
end
