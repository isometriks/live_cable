# frozen_string_literal: true

module LiveCable
  class Connection
    module StateManagement
      extend ActiveSupport::Concern

      def get(container_name, component, variable, initial_value)
        container = containers[container_name]

        return container[variable] if container.key?(variable)

        container[variable] = process_initial_value(component, initial_value)
        container[variable]
      end

      def set(container_name, variable, value)
        dirty(container_name, variable)
        store(container_name, variable, value)
      end

      def store(container_name, variable, value)
        containers[container_name][variable] = value
      end

      def dirty(container_name, *variables)
        containers[container_name].mark_dirty(*variables)
      end

      # @api private
      # @return [Array(Array<Symbol>, Array<Symbol>)] the names no render has
      #   shipped yet: in the component's own container, and the shared ones it reads
      def pending_changes(component)
        own = containers.key?(component.live_id) ? containers[component.live_id].changeset.dup : []

        [own, component.shared_reactive_variables & shared_changeset]
      end

      # @api private
      # @param changes [Array(Array<Symbol>, Array<Symbol>)] what a render of
      #   the component shipped, from #pending_changes
      def consume(component, changes)
        own, shared = changes
        containers[component.live_id].consume(own) if containers.key?(component.live_id)
        shipped_shared[component.live_id].merge(shared)
      end

      # @api private
      # @return [Array<Symbol>]
      def shared_changeset
        containers.key?(SHARED_CONTAINER) ? containers[SHARED_CONTAINER].changeset.dup : []
      end

      def changeset_for(component)
        shared = containers[SHARED_CONTAINER].changeset
        container = containers[component.live_id]

        changeset = container.changeset | component.shared_reactive_variables.intersection(shared)
        return changeset if changeset.empty?

        changeset | component.shared_variables
      end

      private

      # Consumes shared names the cycle's renders shipped. A sharer that didn't
      # render keeps them in its own changeset, so it renders them later.
      #
      # @param snapshot [Array<Symbol>] the shared names pending when the renders started
      # @param rendered [Set<LiveCable::Component>] compared by identity
      def settle_shared(snapshot, rendered)
        shipped = shipped_shared
        @shipped_shared = nil
        pending = shared_changeset
        return if pending.empty?

        components.each_value do |component|
          next if rendered.include?(component)

          names = component.shared_reactive_variables & snapshot
          containers[component.live_id].mark_dirty(*names) if names.any?
        end

        # Marked during the renders, as in before_render: settled once every sharer shipped it
        marked = (pending - snapshot).select do |name|
          components.each_value.all? do |component|
            component.shared_reactive_variables.exclude?(name) || shipped[component.live_id].include?(name)
          end
        end

        containers[SHARED_CONTAINER].consume(snapshot | marked)
      end

      # @return [Hash{String => Set<Symbol>}] the shared names each component's
      #   renders shipped since the last settle, by live id
      def shipped_shared
        @shipped_shared ||= Hash.new { |shipped, live_id| shipped[live_id] = Set.new }
      end

      def process_initial_value(component, initial_value)
        return if initial_value.nil?

        args = []
        args << component if initial_value.arity.positive?

        initial_value.call(*args)
      end
    end
  end
end
