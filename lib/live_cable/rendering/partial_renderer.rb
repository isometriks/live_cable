# frozen_string_literal: true

module LiveCable
  module Rendering
    # Base class for partial renderers with common functionality
    class PartialRenderer
      # @return [LiveCable::Component]
      attr_reader :component

      def initialize(component, parts, view_context)
        @component = component
        @parts = parts
        @view_context = view_context
      end

      def render(changes = :all)
        # No changes, different from :all (:all means render all)
        # Return an array of nils
        if changes == []
          return Array.new(parts.size, nil)
        end

        @locals = {}
        @dirty_locals = Set.new  # Track which locals were recomputed this render
        @method_deps_cache = {}  # Cache method dependency expansion for this render cycle
        parts.each_with_index.map do |_, index|
          send("render_part_#{index}", changes)
        end
      end

      def mark_locals_dirty(locals)
        locals.each { |local| dirty_locals << local }
      end

      # Expand component.method_name calls to their transitive dependencies
      # Results are cached per render cycle to avoid redundant analysis
      # @param method_names [Array<Symbol>] Method names called on component
      # @return [Array<Symbol>] Reactive variables these methods depend on
      def expand_component_method_dependencies(method_names)
        return [] if method_names.empty?

        # Use cache key based on the sorted method names array
        cache_key = method_names.sort

        # Return cached result if available
        return method_deps_cache[cache_key] if method_deps_cache.key?(cache_key)

        # Get the analyzer for the component class
        analyzer = component.class.method_dependencies_analyzer

        expanded = []
        method_names.each do |method_name|
          # Get transitive dependencies for this method
          deps = analyzer.expanded_dependencies(method_name)
          expanded.concat(deps.to_a)
        end

        # Cache and return the result
        method_deps_cache[cache_key] = expanded.uniq
      end

      # Check if this part should be skipped based on its dependencies
      # @param changes [Symbol|Array] Changed variables, :all, or :dynamic
      # @param component_dependencies [Array<Symbol>] Direct component dependencies
      # @param component_method_calls [Array<Symbol>] Component methods called
      # @param local_dependencies [Array<Symbol>] Local variable dependencies
      # @return [Boolean] true if the part should be skipped
      def should_skip_part?(changes, component_dependencies, component_method_calls, local_dependencies)
        # Always render on initial render (all parts)
        return false if changes == :all

        # Always render on template switch (all dynamic parts must render)
        return false if changes == :dynamic

        # Expand component.method_name calls to their transitive dependencies
        expanded_deps = expand_component_method_dependencies(component_method_calls)
        all_component_deps = component_dependencies | expanded_deps

        # Render if any component dependencies changed
        return false if changes.intersect?(all_component_deps)

        # Render if any local dependencies are dirty
        return false if dirty_locals.intersect?(local_dependencies)

        # Otherwise, skip rendering this part
        true
      end

      def method_missing(method, ...)
        if locals.key?(method)
          return locals[method]
        end

        if component.respond_to?(method)
          return component.public_send(method, ...)
        end

        if view_context.respond_to?(method)
          return view_context.public_send(method, ...)
        end

        super
      end

      def respond_to_missing?(method, _include_private = false)
        locals.key?(method) || component.respond_to?(method) || view_context.respond_to?(method)
      end

      private

      # @return [Array]
      attr_reader :parts

      # @return [ActionView::Base]
      attr_reader :view_context

      # @return [Hash]
      attr_reader :locals

      # @return [Set]
      attr_reader :dirty_locals

      # @return [Hash]
      attr_reader :method_deps_cache

      def with_buffer(&block)
        @output_buffer = ActionView::OutputBuffer.new
        block.call
        @output_buffer.to_s
      end

      def store_local(name, value)
        locals[name] = value
      end
    end
  end
end
