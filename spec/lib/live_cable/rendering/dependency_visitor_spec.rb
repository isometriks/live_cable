# frozen_string_literal: true

require 'spec_helper'
require 'prism'

RSpec.describe LiveCable::Rendering::DependencyVisitor do
  let(:visitor) { described_class.new }

  def parse_and_visit(code)
    parsed = Prism.parse(code)
    visitor.visit(parsed.value)
  end

  describe '#visit_call_node' do
    context 'when tracking component method calls' do
      it 'tracks component.method_name with LocalVariableReadNode receiver' do
        code = <<~RUBY
          component.filtered_todos.each do |todo|
            puts todo
          end
        RUBY

        parse_and_visit(code)

        expect(visitor.component_method_calls).to include(:filtered_todos)
      end

      it 'tracks component.method_name with CallNode receiver' do
        code = <<~RUBY
          component().filtered_todos
        RUBY

        parse_and_visit(code)

        expect(visitor.component_method_calls).to include(:filtered_todos)
      end

      it 'tracks multiple component method calls' do
        code = <<~RUBY
          component.filtered_todos.each do |todo|
            component.status
          end
        RUBY

        parse_and_visit(code)

        expect(visitor.component_method_calls).to include(:filtered_todos, :status)
      end

      it 'does NOT track methods on other receivers' do
        code = <<~RUBY
          other_object.filtered_todos
        RUBY

        parse_and_visit(code)

        expect(visitor.component_method_calls).not_to include(:filtered_todos)
      end

      it 'tracks nested component calls' do
        code = <<~RUBY
          if component.active?
            result = component.filtered_todos.map { |t| t.name }
          end
        RUBY

        parse_and_visit(code)

        expect(visitor.component_method_calls).to include(:active?, :filtered_todos)
      end
    end

    context 'when tracking variable calls' do
      it 'tracks implicit method calls (variable_call)' do
        code = <<~RUBY
          username
          count
        RUBY

        parse_and_visit(code)

        expect(visitor.local_reads).to include(:username, :count)
      end
    end

    context 'when tracking local variable reads' do
      it 'tracks local variable reads' do
        code = <<~RUBY
          x = 5
          y = x + 10
        RUBY

        parse_and_visit(code)

        expect(visitor.local_reads).to include(:x)
        expect(visitor.local_writes).to include(:x, :y)
      end
    end
  end

  describe 'integration test with erb-like code' do
    it 'tracks component method calls in output buffer code' do
      code = <<~RUBY
        component.filtered_todos.each do |todo|
          @output_buffer.safe_append = '<li class="mb-1" live-key="'
          @output_buffer.append = todo[:id]
          @output_buffer.safe_append = '">'
          @output_buffer.append = live("todo/item", id: todo[:id], todo: todo)
          @output_buffer.safe_append = '</li>'
        end
      RUBY

      parse_and_visit(code)

      expect(visitor.component_method_calls).to include(:filtered_todos)
    end
  end
end
