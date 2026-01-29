# frozen_string_literal: true

module LiveCable
  class Component
    module MethodDependencyTracking
      extend ActiveSupport::Concern

      class_methods do
        # Get the analyzer instance for this component class
        # Lazily creates and caches the analyzer
        # @return [LiveCable::Rendering::MethodAnalyzer]
        def method_dependencies_analyzer
          @method_dependencies_analyzer ||= begin
            analyzer = LiveCable::Rendering::MethodAnalyzer.new(self)
            analyzer.analyze_all_methods # Parse and analyze upfront
            analyzer
          end
        end

        # Get the dependency analysis for this component class
        # Lazily analyzes methods on first access
        def method_dependencies
          method_dependencies_analyzer.dependencies
        end

        # Get dependencies for a specific method
        # @param method_name [Symbol]
        # @return [Hash, nil] { instance_vars: Set, methods: Set, reactive_vars: Set }
        def dependencies_for_method(method_name)
          method_dependencies_analyzer.analyze_method(method_name)
        end

        # Given a set of changed instance variables or reactive variables,
        # return the set of methods that depend on them
        # @param changed [Array<Symbol>] Changed instance vars or reactive vars
        # @return [Set<Symbol>] Method names that depend on changed variables
        def methods_affected_by_changes(changed)
          changed_set = Set.new(changed)
          affected = Set.new

          method_dependencies.each do |method_name, deps|
            next unless deps

            # Check if method depends on any of the changed variables
            if deps[:instance_vars].intersect?(changed_set) ||
               deps[:reactive_vars].intersect?(changed_set)
              affected << method_name
            end
          end

          affected
        end
      end

      # Instance method to get affected methods based on current changes
      # This integrates with the existing changeset system
      def methods_affected_by_changeset
        return [] unless live_connection

        changeset = live_connection.changeset_for(self)
        return [] if changeset.empty?

        self.class.methods_affected_by_changes(changeset)
      end
    end
  end
end
