# frozen_string_literal: true

require 'prism'

module LiveCable
  module Rendering
    class DependencyVisitor < Prism::Visitor
      # @return [Array<Symbol>]
      attr_reader :variable_calls

      # @return [Array<Symbol>]
      attr_reader :local_reads

      # @return [Array<Symbol>]
      attr_reader :local_writes

      # @return [Set<Symbol>]
      attr_reader :component_method_calls

      def initialize
        super
        @variable_calls = []
        @local_reads = []
        @local_writes = []
        @component_method_calls = Set.new
        @scope_depth = 0
      end

      def visit_block_node(node) = nested_scope { super }

      def visit_lambda_node(node) = nested_scope { super }

      # Prism never resolves a name past a def, so nothing inside one counts as top level
      def visit_def_node(node) = nested_scope { super }

      # Track reads of top-level locals
      # @param node [Prism::LocalVariableReadNode]
      # @return [void]
      def visit_local_variable_read_node(node)
        @local_reads |= [node.name] if top_level?(node)
        super
      end

      # Track argument-less receiverless calls (e.g., `foo`, `foo()` or the value
      # of a `foo:` hash shorthand) and calls on component or self (e.g.,
      # `component.foo`), which read the component too
      # @param node [Prism::CallNode]
      # @return [void]
      def visit_call_node(node)
        if node.variable_call? || bare_call?(node) || explicit_component_receiver?(node.receiver)
          @variable_calls |= [node.name]
        end

        @component_method_calls << node.name if component_receiver?(node.receiver)

        super
      end

      # Track local variable writes
      # @param node [Prism::LocalVariableWriteNode]
      # @return [void]
      def visit_local_variable_write_node(node)
        @local_writes |= [node.name] if top_level?(node)
        super
      end

      # Track multiple assignment, rescue and pattern targets
      # @param node [Prism::LocalVariableTargetNode]
      # @return [void]
      def visit_local_variable_target_node(node)
        @local_writes |= [node.name] if top_level?(node)
        super
      end

      # Track local variable operator writes (+=, ||=, etc)
      # @param node [Prism::LocalVariableOperatorWriteNode]
      # @return [void]
      def visit_local_variable_operator_write_node(node)
        read_and_write(node)
        super
      end

      # Track local variable and writes (&&=)
      # @param node [Prism::LocalVariableAndWriteNode]
      # @return [void]
      def visit_local_variable_and_write_node(node)
        read_and_write(node)
        super
      end

      # Track local variable or writes (||=)
      # @param node [Prism::LocalVariableOrWriteNode]
      # @return [void]
      def visit_local_variable_or_write_node(node)
        read_and_write(node)
        super
      end

      private

      def nested_scope
        @scope_depth += 1
        yield
      ensure
        @scope_depth -= 1
      end

      # Prism's depth is how many scopes up it found the local
      def top_level?(node)
        node.depth == @scope_depth
      end

      def read_and_write(node)
        return unless top_level?(node)

        @local_reads |= [node.name]
        @local_writes |= [node.name]
      end

      # @param node [Prism::CallNode]
      # @return [Boolean]
      def bare_call?(node)
        node.receiver.nil? && node.arguments.nil? && node.block.nil?
      end

      # @param receiver [Prism::Node, nil]
      # @return [Boolean]
      def component_receiver?(receiver)
        receiver.nil? || explicit_component_receiver?(receiver)
      end

      # Part code runs on the renderer, which hands unknown names to the component,
      # so `self.foo` reads the component just as `component.foo` does
      # @param receiver [Prism::Node, nil]
      # @return [Boolean]
      def explicit_component_receiver?(receiver)
        return true if receiver.is_a?(Prism::SelfNode)
        return false unless receiver.try(:name) == :component

        receiver.is_a?(Prism::CallNode) || receiver.is_a?(Prism::LocalVariableReadNode)
      end
    end
  end
end
