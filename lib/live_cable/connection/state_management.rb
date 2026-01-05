# frozen_string_literal: true

module LiveCable
  class Connection
    module StateManagement
      extend ActiveSupport::Concern

      def get(container_name, component, variable, initial_value)
        containers[container_name][variable] ||= process_initial_value(component, variable, initial_value)
      end

      def set(container_name, variable, value)
        dirty(container_name, variable)

        containers[container_name][variable] = value
      end

      def dirty(container_name, *variables)
        containers[container_name].mark_dirty(*variables)
      end

      def reset_changeset
        containers.each_value(&:reset_changeset)
      end

      private

      def process_initial_value(component, variable, initial_value)
        case initial_value
        when nil
          nil
        when Proc
          args = []
          args << component if initial_value.arity.positive?

          initial_value.call(*args)
        else
          raise LiveCable::Error, "Initial value for \":#{variable}\" must be a proc or nil"
        end
      rescue StandardError => e
        handle_error(component, e)
      end
    end
  end
end
