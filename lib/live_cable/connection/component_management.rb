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
        components.delete(component.live_id)
        containers.delete(component.live_id)
      end
    end
  end
end
