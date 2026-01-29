# frozen_string_literal: true

module LiveCable
  module Rendering
    class DependencyVisitor < Prism::Visitor
      # @return [Array<Symbol>]
      attr_reader :local_reads

      # @return [Array<Symbol>]
      attr_reader :local_writes

      # @return [Set<Symbol>]
      attr_reader :component_method_calls

      def initialize
        super
        @local_reads = []
        @local_writes = []
        @component_method_calls = Set.new
      end

      # Track all local variable reads
      # @param node [Prism::LocalVariableReadNode]
      # @return [void]
      def visit_local_variable_read_node(node)
        @local_reads |= [node.name]
        super
      end

      # Track variable method calls (e.g., `foo` without parens)
      # Also track component.method_name calls
      # @param node [Prism::CallNode]
      # @return [void]
      def visit_call_node(node)
        # Track variable calls (implicit self)
        @local_reads |= [node.name] if node.variable_call?

        # Track component.method_name calls
        if component_receiver?(node.receiver)
          @component_method_calls << node.name
        end

        super
      end

      # Track local variable writes
      # @param node [Prism::LocalVariableWriteNode]
      # @return [void]
      def visit_local_variable_write_node(node)
        @local_writes |= [node.name]
        super
      end

      # Track local variable operator writes (+=, ||=, etc)
      # @param node [Prism::LocalVariableOperatorWriteNode]
      # @return [void]
      def visit_local_variable_operator_write_node(node)
        @local_writes |= [node.name]
        @local_reads |= [node.name] # Reads before writing
        super
      end

      # Track local variable and writes (&&=)
      # @param node [Prism::LocalVariableAndWriteNode]
      # @return [void]
      def visit_local_variable_and_write_node(node)
        @local_writes |= [node.name]
        @local_reads |= [node.name]
        super
      end

      # Track local variable or writes (||=)
      # @param node [Prism::LocalVariableOrWriteNode]
      # @return [void]
      def visit_local_variable_or_write_node(node)
        @local_writes |= [node.name]
        @local_reads |= [node.name]
        super
      end

      private

      # Check if receiver is a reference to 'component'
      # @param receiver [Prism::Node, nil]
      # @return [Boolean]
      def component_receiver?(receiver)
        # No receiver, calling something lke live_id or any component method
        return true if receiver.nil?

        # Ignore these because they're not component methods, just output methods
        return false if receiver.try(:name) == :@output_buffer

        # If there is a receiver, it must be a component method call or local variable read
        return false unless receiver.try(:name) == :component

        receiver.is_a?(Prism::CallNode) || receiver.is_a?(Prism::LocalVariableReadNode)
      end
    end
  end
end
