# frozen_string_literal: true

require 'spec_helper'
require 'prism'

RSpec.describe LiveCable::Rendering::DependencyVisitor do
  let(:visitor) { described_class.new }

  def parse_and_visit(code, outer_locals: [])
    parsed = Prism.parse(code, scopes: [outer_locals])
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

        expect(visitor.variable_calls).to include(:username, :count)
      end

      it 'tracks the implicit value of hash shorthand' do
        parse_and_visit("render('badge', page:)\n{ count: }")

        expect(visitor.variable_calls).to include(:page, :count)
      end

      it 'tracks calls with empty parentheses' do
        parse_and_visit('count()')

        expect(visitor.variable_calls).to include(:count)
      end

      it 'does not track calls with arguments or a block' do
        parse_and_visit("format(value)\nitems { 1 }")

        expect(visitor.variable_calls).not_to include(:format, :items)
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

  describe 'scopes' do
    it 'tracks top-level locals that a block reads and writes' do
      code = <<~RUBY
        counts.each { |count| total += count * factor }
      RUBY

      parse_and_visit(code, outer_locals: %i[total factor])

      expect(visitor.local_reads).to contain_exactly(:total, :factor)
      expect(visitor.local_writes).to eq([:total])
    end

    it 'ignores block parameters and locals assigned inside blocks and lambdas' do
      code = <<~RUBY
        items.each do |item|
          css = item.css
          format = -> { label = css }
        end
      RUBY

      parse_and_visit(code)

      expect(visitor.local_reads).to be_empty
      expect(visitor.local_writes).to be_empty
      expect(visitor.variable_calls).to eq([:items])
    end

    it 'ignores locals inside a method definition' do
      code = <<~RUBY
        def label(total)
          [1].each { |n| total += n }
          total
        end
      RUBY

      parse_and_visit(code, outer_locals: [:total])

      expect(visitor.local_reads).to be_empty
      expect(visitor.local_writes).to be_empty
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
