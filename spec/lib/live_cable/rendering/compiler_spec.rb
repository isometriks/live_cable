# frozen_string_literal: true

require 'spec_helper'
require 'prism'

RSpec.describe LiveCable::Rendering::Compiler do
  def compile_parts(source)
    parse_result = Herb.parse(source, track_whitespace: true)
    engine = LiveCable::Rendering::Renderer.new
    compiler = described_class.new(engine)
    parse_result.value.accept(compiler)
    compiler.generate_output
    engine.send(:parts)
  end

  def block_parts(parts)
    parts.select { |part| part.first == :block }
  end

  describe 'part splitting' do
    it 'emits text and expressions outside blocks as separate parts' do
      parts = compile_parts('<p>Count: <%= count %></p>')

      expect(parts.map(&:first)).to eq(%i[text expr text])
      expect(parts[1][1]).to include('count')
    end

    it 'groups an if control structure into a single block part' do
      parts = compile_parts(<<~ERB)
        <% if count > 2 %>
          <p>big</p>
        <% end %>
      ERB

      blocks = block_parts(parts)
      expect(blocks.length).to eq(1)

      code = blocks.first[1]
      expect(code).to include('if count > 2')
      expect(code).to include('<p>big</p>')
      expect(code).to include('end')
    end

    it 'groups an iteration block into a single block part' do
      parts = compile_parts(<<~ERB)
        <% items.each do |item| %>
          <li><%= item %></li>
        <% end %>
      ERB

      blocks = block_parts(parts)
      expect(blocks.length).to eq(1)

      code = blocks.first[1]
      expect(code).to include('items.each do |item|')
      expect(code).to include('<li>')
      expect(code).to include('end')
    end

    it 'groups an output block (<%= ... do %>) into a single block part' do
      parts = compile_parts(<<~ERB)
        <%= form_with url: '/x' do |f| %>
          <%= f.text_field :name %>
        <% end %>
      ERB

      blocks = block_parts(parts)
      expect(blocks.length).to eq(1)

      code = blocks.first[1]
      expect(code).to include(".append= form_with url: '/x' do |f|")
      expect(code).to include('f.text_field :name')
      expect(code).to include('end')
    end

    it 'groups nested control structures into one outer block part' do
      parts = compile_parts(<<~ERB)
        <% items.each do |item| %>
          <% if item.visible? %>
            <li><%= item %></li>
          <% end %>
        <% end %>
      ERB

      blocks = block_parts(parts)
      expect(blocks.length).to eq(1)

      code = blocks.first[1]
      expect(code).to include('items.each do |item|')
      expect(code).to include('if item.visible?')
    end

    it 'keeps content around a block in separate parts' do
      parts = compile_parts(<<~ERB)
        <p>before</p>
        <% if flag %>
          <p>inside</p>
        <% end %>
        <p>after</p>
      ERB

      expect(parts.map(&:first)).to eq(%i[text block text])
      expect(parts[0][1]).to include('before')
      expect(parts[1][1]).to include('inside')
      expect(parts[2][1]).to include('after')
    end

    it 'generates syntactically valid Ruby for every part' do
      parts = compile_parts(<<~ERB)
        <p>Count: <%= count %></p>
        <% if count > 2 %>
          <p>big</p>
        <% end %>
        <%= form_with url: '/x' do |f| %>
          <%= f.text_field :name %>
        <% end %>
        <% items.each do |item| %>
          <li><%= item %></li>
        <% end %>
      ERB

      parts.each do |type, code|
        result = Prism.parse(code)
        expect(result.success?).to be(true), "expected #{type} part to be valid Ruby, got: #{code.inspect}"
      end
    end
  end
end
