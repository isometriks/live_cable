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

    it "does not count a read after the part's own assignment as reading an earlier part" do
      first_loop, second_loop, first_if, second_if = code_metadata(<<~ERB)
        <% for item in items %><%= item %><% end %>
        <% for item in tags %><%= item %><% end %>
        <% if admin %><% label = 'Admin' %><b><%= label %></b><% end %>
        <% if owner %><% label = 'Owner' %><i><%= label %></i><% end %>
      ERB

      expect(first_loop[:feeds_later_parts]).to be(false)
      expect(second_loop[:exposed_local_reads]).to be_empty
      expect(first_if[:feeds_later_parts]).to be(false)
      expect(second_if[:exposed_local_reads]).to be_empty
    end

    it 'counts a read after an assignment that might not run' do
      _, group = code_metadata(<<~ERB)
        <% label = 'base' %>
        <% if admin %><% if owner %><% label = 'Owner' %><% end %><%= label %><% end %>
      ERB

      expect(group[:exposed_local_reads]).to eq([:label])
    end

    it 'does not count a write alone as reading an earlier part' do
      _, group = code_metadata(<<~ERB)
        <% label = 'base' %>
        <% if admin %><% label = 'Admin' %><% end %>
      ERB

      expect(group).to include(local_dependencies: [:label], exposed_local_reads: [])
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
