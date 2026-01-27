# frozen_string_literal: true

module LiveCable
  module Rendering
    class DependencyVisitor < Prism::Visitor
      def add_dependency(name)
        @dependencies ||= []
        @dependencies |= [name]
      end

      def dependencies
        @dependencies || []
      end

      def visit_local_variable_read_node(node)
        add_dependency(node.name)
        super
      end

      def visit_call_node(node)
        add_dependency(node.name) if node.variable_call?
        super
      end
    end
  end
end
