# frozen_string_literal: true

require 'spec_helper'
require 'prism'
require_relative '../../../fixtures/test_method_dependency_component'

RSpec.describe LiveCable::Rendering::MethodDependencyVisitor do
  let(:component_class) { TestMethodDependencyComponent }
  let(:reactive_vars) { %i[username count] }
  let(:visitor) { described_class.new(component_class, reactive_vars) }

  def parse_method(method_name)
    source_location = component_class.instance_method(method_name).source_location
    file_path = source_location[0]
    source_code = File.read(file_path)
    parsed = Prism.parse(source_code)

    # Find the specific method node
    method_finder = Class.new(Prism::Visitor) do
      attr_accessor :target_method, :target_name

      def initialize(target_name)
        super()
        @target_name = target_name
        @target_method = nil
      end

      def visit_def_node(node)
        if node.name == @target_name
          @target_method = node
        end
        super
      end
    end

    finder = method_finder.new(method_name)
    finder.visit(parsed.value)
    finder.target_method
  end

  describe '#visit_call_node' do
    it 'tracks method calls with implicit self receiver' do
      method_node = parse_method(:implicit_self_call)
      visitor.visit(method_node)

      expect(visitor.method_calls).to include(:filtered_todos)
    end

    it 'tracks method calls with explicit self receiver' do
      method_node = parse_method(:explicit_self_call)
      visitor.visit(method_node)

      expect(visitor.method_calls).to include(:filtered_todos)
    end

    it 'does NOT track method calls with variable receiver' do
      method_node = parse_method(:variable_receiver_call)
      visitor.visit(method_node)

      # filtered_todos is called on component parameter, not self
      expect(visitor.method_calls).not_to include(:filtered_todos)
    end

    it 'tracks reactive variable accesses' do
      method_node = parse_method(:uses_reactive_var)
      visitor.visit(method_node)

      expect(visitor.reactive_var_reads).to include(:username)
    end

    it 'tracks multiple method calls and reactive vars' do
      method_node = parse_method(:mixed_calls)
      visitor.visit(method_node)

      expect(visitor.method_calls).to include(:helper_method, :username, :count)
      expect(visitor.reactive_var_reads).to include(:username, :count)
    end
  end
end
