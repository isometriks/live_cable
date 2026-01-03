# frozen_string_literal: true

module LiveCable
  class Connection
    module ComponentManagement
      extend ActiveSupport::Concern

      def get_component(id)
        components[id]
      end

      def add_component(component)
        component.live_connection = self
        components[component.live_id] = component
      end

      def remove_component(component)
        # Clean up the container to break observer reference chains
        container = containers.delete(component.live_id)
        container&.cleanup

        components.delete(component.live_id)

        # Clean up shared container if no components remain
        cleanup_shared_container
      end

      private

      def cleanup_shared_container
        return if components.any?

        shared = containers.delete(Connection::SHARED_CONTAINER)
        shared&.cleanup
      end
    end
  end
end
