# frozen_string_literal: true

module LiveCable
  module Rendering
    class DependencyVisitor < Prism::Visitor
      attr_reader :local_reads, :local_writes

      def initialize
        super()
        @local_reads = []
        @local_writes = []
      end

      # Track all local variable reads
      def visit_local_variable_read_node(node)
        @local_reads |= [node.name]
        super
      end

      # Track variable method calls (e.g., `foo` without parens)
      def visit_call_node(node)
        @local_reads |= [node.name] if node.variable_call?
        super
      end

      # Track local variable writes
      def visit_local_variable_write_node(node)
        @local_writes |= [node.name]
        super
      end

      # Track local variable operator writes (+=, ||=, etc)
      def visit_local_variable_operator_write_node(node)
        @local_writes |= [node.name]
        @local_reads |= [node.name]  # Reads before writing
        super
      end

      def visit_local_variable_and_write_node(node)
        @local_writes |= [node.name]
        @local_reads |= [node.name]
        super
      end

      def visit_local_variable_or_write_node(node)
        @local_writes |= [node.name]
        @local_reads |= [node.name]
        super
      end
    end
  end
end
