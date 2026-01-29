# frozen_string_literal: true

require 'prism'

module LiveCable
  module Rendering
    # Visitor that tracks dependencies within a method body
    class MethodDependencyVisitor < Prism::Visitor
      # @return [Set<Symbol>]
      attr_reader :method_calls

      # @return [Set<Symbol>]
      attr_reader :reactive_var_reads

      # @param component_class [Class] The component class being analyzed
      # @param reactive_vars [Array<Symbol>] List of reactive variable names
      def initialize(component_class, reactive_vars)
        super()
        @component_class = component_class
        @method_calls = Set.new
        @reactive_var_reads = Set.new
        @reactive_vars = reactive_vars
      end

      # Track method calls
      # @param node [Prism::CallNode]
      # @return [void]
      def visit_call_node(node)
        method_name = node.name

        # Track if this is a reactive variable access
        @reactive_var_reads << method_name if reactive_vars.include?(method_name)

        # Track method calls on self (implicit receiver or explicit self)
        if node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)
          @method_calls << method_name
        end

        super
      end

      private

      # @return [Class]
      attr_reader :component_class

      # @return [Array<Symbol>]
      attr_reader :reactive_vars
    end
  end
end
