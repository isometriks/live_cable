# frozen_string_literal: true

require 'prism'

module LiveCable
  module Rendering
    # Visitor that collects all method definitions and their dependencies
    class MethodCollector < Prism::Visitor
      # @return [Hash]
      attr_reader :dependencies

      # @param component_class [Class] The component class to analyze
      def initialize(component_class)
        super()

        @component_class = component_class
        @dependencies = {}
        @reactive_vars = component_class.all_reactive_variables
      end

      # Visit each method definition
      # @param node [Prism::DefNode]
      # @return [void]
      def visit_def_node(node)
        method_name = node.name

        return if node.receiver

        # Skip private/internal methods
        return super if %i[render render_in].include?(method_name)

        # Analyze this method's dependencies
        visitor = MethodDependencyVisitor.new(component_class, reactive_vars)
        visitor.visit(node)

        # Nested and sibling classes in the same file share this table, so a
        # clashing name may only add dependencies, never replace them.
        entry = @dependencies[method_name] ||= { methods: Set.new, reactive_vars: Set.new }
        entry[:methods].merge(visitor.method_calls)
        entry[:reactive_vars].merge(visitor.reactive_var_reads)

        super
      end

      # Methods in `class << self` are never instance methods a template calls
      # @param node [Prism::SingletonClassNode]
      # @return [void]
      def visit_singleton_class_node(node); end

      private

      # @return [Class]
      attr_reader :component_class

      # @return [Array<Symbol>]
      attr_reader :reactive_vars
    end
  end
end
