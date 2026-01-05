# frozen_string_literal: true

module LiveCable
  class Component
    module ReactiveVariables
      extend ActiveSupport::Concern

      included do
        class_attribute :shared_variables, default: []
        class_attribute :reactive_variables, default: []
        class_attribute :shared_reactive_variables, default: []
      end

      class_methods do
        def reactive(variable, initial_value = nil, shared: false)
          if shared
            self.shared_reactive_variables = (shared_reactive_variables || []).dup << variable
          else
            self.reactive_variables = (reactive_variables || []).dup << variable
          end

          create_reactive_variables(variable, initial_value, shared: shared)
        end

        def shared(variable, initial_value = nil)
          self.shared_variables = (shared_variables || []).dup << variable

          create_reactive_variables(variable, initial_value, shared: true)
        end

        def actions(*names)
          @allowed_actions = names.map!(&:to_sym).freeze
        end

        def allowed_actions
          @allowed_actions || []
        end

        private

        def create_reactive_variables(variable, initial_value, shared: false)
          define_method(variable) do
            container_name = shared ? Connection::SHARED_CONTAINER : live_id

            if live_connection
              return live_connection.get(container_name, self, variable, initial_value)
            elsif prerender_container.key?(variable)
              return prerender_container[variable]
            end

            return if initial_value.nil?

            if initial_value.arity.positive?
              initial_value.call(self)
            else
              initial_value.call
            end
          end

          define_method("#{variable}=") do |value|
            container_name = shared ? Connection::SHARED_CONTAINER : live_id

            if live_connection
              live_connection.set(container_name, variable, value)
            else
              prerender_container[variable] = value
            end
          end
        end
      end

      def all_reactive_variables
        self.class.reactive_variables + self.class.shared_reactive_variables
      end

      def dirty(*variables)
        variables.each do |variable|
          unless all_reactive_variables.include?(variable)
            raise Error, "Invalid reactive variable: #{variable}"
          end

          container_name = self.class.reactive_variables.include?(variable) ? live_id : Connection::SHARED_CONTAINER

          live_connection.dirty(container_name, variable)
        end
      end

      def defaults=(defaults)
        @defaults = (defaults || {}).symbolize_keys
      end

      def prerender_container
        @prerender_container ||= {}
      end

      def apply_defaults
        # Don't set defaults more than once
        return if @defaults_applied

        defaults = (@defaults || {}).symbolize_keys
        keys = all_reactive_variables & defaults.keys

        keys.each do |key|
          public_send("#{key}=", defaults[key])
        end

        @defaults_applied = true
      end
    end
  end
end
