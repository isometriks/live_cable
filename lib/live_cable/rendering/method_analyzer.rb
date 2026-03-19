# frozen_string_literal: true

module LiveCable
  module Rendering
    # Analyzes component methods to track their dependencies on reactive variables
    # and other methods, enabling fine-grained change tracking
    class MethodAnalyzer
      # @return [Hash]
      attr_reader :dependencies

      def initialize(component_class)
        @component_class = component_class
        @dependencies = {}
        @analyzed = false
      end

      # Analyze all methods in the component and build dependency graph
      # @return [Hash] { method_name => { methods: Set, reactive_vars: Set } }
      def analyze_all_methods
        return dependencies if analyzed

        # Get the source file for this component
        source_location = Object.const_source_location(component_class.name)

        file_path = source_location[0]
        return {} unless File.exist?(file_path)

        # Parse the entire file once
        source_code = File.read(file_path)
        parsed = Prism.parse(source_code)

        # Collect all method definitions in one pass
        collector = MethodCollector.new(component_class)
        collector.visit(parsed.value)

        @dependencies = collector.dependencies
        @analyzed = true
        dependencies
      end

      # Get dependencies for a specific method (analyzes all if not done yet)
      # @param method_name [Symbol] The method name
      # @return [Hash, nil] { methods: Set, reactive_vars: Set }
      def analyze_method(method_name)
        analyze_all_methods unless analyzed
        dependencies[method_name]
      end

      # Get the expanded/transitive dependencies for a method.
      # Results are cached permanently since method definitions don't change at runtime.
      # @param method_name [Symbol] The method to expand
      # @return [Set] Set of reactive variable names
      def expanded_dependencies(method_name)
        analyze_all_methods unless analyzed

        @expanded_deps_cache ||= {}
        return @expanded_deps_cache[method_name] if @expanded_deps_cache.key?(method_name)

        @expanded_deps_cache[method_name] = compute_expanded_dependencies(method_name)
      end

      private

      # @return [Class]
      attr_reader :component_class

      # @return [Boolean]
      attr_reader :analyzed

      def compute_expanded_dependencies(method_name)
        deps = dependencies[method_name]
        return Set.new unless deps

        reactive_vars = deps[:reactive_vars].dup
        visited = Set.new([method_name])

        to_visit = deps[:methods].to_a
        while (current_method = to_visit.shift)
          next if visited.include?(current_method)

          visited << current_method

          method_deps = dependencies[current_method]
          next unless method_deps

          reactive_vars.merge(method_deps[:reactive_vars])
          to_visit.concat(method_deps[:methods].to_a)
        end

        reactive_vars
      end
    end
  end
end
