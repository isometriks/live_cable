# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Rendering::Renderer do
  def code_metadata(source)
    engine = described_class.new
    compiler = LiveCable::Rendering::Compiler.new(engine)
    Herb.parse(source, track_whitespace: true).value.accept(compiler)
    compiler.generate_output
    engine.send(:build_metadata).compact.reject { |part| part[:type] == :text }
  end

  describe 'part dependencies' do
    it 'does not record block parameters as component dependencies' do
      block, = code_metadata(<<~ERB)
        <% items.each do |item| %>
          <%= item.name %>
        <% end %>
      ERB

      expect(block[:component_dependencies]).to eq([:items])
    end

    it 'keeps a local assigned inside a block out of later parts' do
      block, expr = code_metadata(<<~ERB)
        <% items.each do |item| %>
          <% css = item.css %>
        <% end %>
        <%= css %>
      ERB

      expect(block[:defines_locals]).to be_empty
      expect(expr).to include(component_dependencies: [:css], local_dependencies: [])
    end

    it 'records a top-level local written inside a block' do
      _, loop, expr = code_metadata(<<~ERB)
        <% total = 0 %>
        <% counts.each { |count| total += count } %>
        <%= total %>
      ERB

      expect(loop).to include(component_dependencies: [:counts], local_dependencies: [:total], defines_locals: [:total])
      expect(expr).to include(component_dependencies: [], local_dependencies: [:total])
    end

    it 'makes a conditional write depend on the earlier value' do
      _, branch, = code_metadata(<<~ERB)
        <% badge = 'old' %>
        <% if flagged %><% badge = 'new' %><% end %>
        <%= badge %>
      ERB

      expect(branch).to include(component_dependencies: [:flagged], local_dependencies: [:badge])
    end

    it 'records every target of a multiple assignment' do
      assign, expr = code_metadata(<<~ERB)
        <% first, *rest = items %>
        <%= first %> and <%= rest.size %> more
      ERB

      expect(assign[:defines_locals]).to contain_exactly(:first, :rest)
      expect(expr).to include(component_dependencies: [], local_dependencies: [:first])
    end

    it 'marks a part whose top-level local a later part reads' do
      group, loop, read = code_metadata(<<~ERB)
        <% if admin %><% label = 'Admin' %><b><%= label %></b><% end %>
        <% for item in items %><%= item %><% end %>
        <%= item %>
      ERB

      expect(group[:feeds_later_parts]).to be(false)
      expect(loop[:feeds_later_parts]).to be(true)
      expect(read[:feeds_later_parts]).to be(false)
    end
  end
end
