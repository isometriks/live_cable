# frozen_string_literal: true

require 'rails_helper'

# Control blocks compile to nodes (see LiveCable::Rendering::Tree) instead of
# HTML strings. These examples hold the two compilations to the same output:
# every template is rendered once with structured blocks and once without,
# and the HTML must match byte for byte.
RSpec.describe 'Structured control blocks' do
  # Answers the template's locals the way a component answers its reactive
  # variables.
  let(:component_class) do
    Class.new do
      def initialize(locals)
        @locals = locals
      end

      def method_missing(name, *args)
        @locals.key?(name) ? @locals[name] : super
      end

      def respond_to_missing?(name, include_private = false)
        @locals.key?(name) || super
      end
    end
  end

  let(:todo) { Struct.new(:id, :title, :done) }

  def compile(source, structured:)
    engine = LiveCable::Rendering::Renderer.new
    compiler = LiveCable::Rendering::Compiler.new(engine, structured:)
    Herb.parse(source, track_whitespace: true).value.accept(compiler)
    compiler.generate_output
    [eval(engine.src), engine.send(:parts)] # rubocop:disable Security/Eval
  end

  def render_parts(partial, locals)
    view_context = ApplicationController.new.view_context
    partial.for_component(component_class.new(locals), view_context).render_changes(:all)
  end

  def render(source, structured:, **locals)
    partial, = compile(source, structured:)
    render_parts(partial, locals).sum('') { |part| LiveCable::Rendering::Tree.render(part, partial.statics) }
  end

  def part_types(source)
    _, parts = compile(source, structured: true)
    parts.map(&:first)
  end

  def expect_same_output(source, **locals)
    structured = render(source, structured: true, **locals)
    plain = render(source, structured: false, **locals)

    expect(structured).to eq(plain)
  end

  templates = {
    'an if with elsif and else' => <<~ERB,
      <div>
        <% if count > 10 %>
          <p class="big"><%= count %> is big</p>
        <% elsif count > 2 %>
          <p>Medium: <%= count %></p>
        <% else %>
          <p>Small</p>
        <% end %>
      </div>
    ERB
    'a case with pattern matching' => <<~ERB,
      <p><% case [count, filter] %><% in [0, _] %>none<% in [Integer => n, :done] %><%= n %> done<% else %>other<% end %></p>
    ERB
    'an until loop' => <<~ERB,
      <p><% n = count %><% until n <= 0 %><b><%= n %></b><% n -= 4 %><% end %></p>
    ERB
    'branches nested three deep' => <<~ERB,
      <div>
        <% if todos.any? %>
          <% todos.each do |todo| %>
            <% if todo.done %>
              <% if count > 5 %><em><%= todo.title %></em><% elsif count > 1 %><s><%= todo.title %></s><% else %><%= todo.id %><% end %>
            <% else %>
              <span><%= todo.title %></span>
            <% end %>
          <% end %>
        <% end %>
      </div>
    ERB
    'a capture whose variable is used inside the block' => <<~ERB,
      <p><% if count > 0 %><% c = capture do %>hi <%= filter %><% end %><%= c %><% end %></p>
    ERB
    'a capture whose variable is used after the block' => <<~ERB,
      <div><% if count > 0 %><% c = capture do %>hi<% end %><% end %><b><%= c %></b></div>
    ERB
    'a begin and rescue that sets a variable' => <<~ERB,
      <p><% if count > 0 %><% begin %><% total = Integer(count.to_s) %><% rescue %><% total = 0 %><% end %><%= total %><% end %></p>
    ERB
    'a variable set in a captured region inside a loop' => <<~ERB,
      <ul><% todos.each do |todo| %><% begin %><% v = todo.id * 2 %><% rescue %><% end %><li><%= v %></li><% end %></ul>
    ERB
    'next inside a captured region inside a loop' => <<~ERB,
      <ul><% todos.each do |todo| %><% begin %><% next if todo.done %><% rescue %><% end %><li><%= todo.title %></li><% end %></ul>
    ERB
    'break inside a captured region inside a loop' => <<~ERB,
      <ul><% todos.each do |todo| %><% begin %><% break if todo.done %><% rescue %><% end %><li><%= todo.title %></li><% end %></ul>
    ERB
    'next inside an output tag inside a loop' => <<~ERB,
      <ul><% todos.each do |todo| %><li><%= todo.done ? next : todo.title %></li><% end %></ul>
    ERB
    'a block helper whose arguments mention an iteration method' => <<~ERB,
      <div><% if count > 0 %><% html = capture step: 1 do %><i><%= filter %></i><% end %><p><%= html %></p><% end %></div>
    ERB
    'a key with a side effect' => <<~ERB,
      <ul><% n = 0 %><% todos.each do |todo| %><li id="r<%= n += 1 %>"><%= todo.title %></li><% end %></ul>
    ERB
    'a key that cycles' => <<~ERB,
      <ul><% todos.each do |todo| %><li id="row-<%= cycle('a', 'b') %>"><%= todo.title %></li><% end %></ul>
    ERB
    'a conditional used as a value' => <<~ERB,
      <p><% x = if count > 0 %><% 'some' %><% else %><% 'none' %><% end %><%= x %></p>
    ERB
    'windows line endings' => "<div>\r\n<% if count > 0 %>\r\n  <b><%= count %></b>\r\n<% end %>\r\n</div>\r\n",
    'an unless with else' => <<~ERB,
      <div><% unless count.zero? %><span><%= count %></span><% else %><em>none</em><% end %></div>
    ERB
    'a case' => <<~ERB,
      <div>
        <% case filter %>
        <% when :all %>
          <b>All <%= count %></b>
        <% when :done %>
          <i>Done</i>
        <% else %>
          <u>Other</u>
        <% end %>
      </div>
    ERB
    'a keyed loop with attributes' => <<~ERB,
      <ul>
        <% todos.each do |todo| %>
          <li id="todo-<%= todo.id %>" class="<%= 'done' if todo.done %>"><%= todo.title %></li>
        <% end %>
      </ul>
    ERB
    'a loop with a conditional inside' => <<~ERB,
      <ul>
        <% todos.each_with_index do |todo, index| %>
          <li>
            <%= index + 1 %>.
            <% if todo.done %>
              <s><%= todo.title %></s>
            <% else %>
              <%= todo.title %>
            <% end %>
          </li>
        <% end %>
      </ul>
    ERB
    'a conditional around a nested loop' => <<~ERB,
      <section>
        <% if todos.any? %>
          <h2><%= todos.size %> todos</h2>
          <% todos.each do |todo| %><span live-key="<%= todo.id %>"><%= todo.title %></span><% end %>
        <% else %>
          <p>Nothing to do</p>
        <% end %>
      </section>
    ERB
    'for and while loops' => <<~ERB,
      <ol>
        <% for todo in todos %><li><%= todo.title %></li><% end %>
        <% i = 0 %>
        <% while i < count %>
          <li><%= i %></li>
          <% i += 1 %>
        <% end %>
      </ol>
    ERB
    'trim tags and raw output' => <<~ERB,
      <div>
        <%- if count > 2 -%>
          <%== '<b>raw</b>' %> and <%= '<b>escaped</b>' %>
        <%- end -%>
      </div>
    ERB
    'block helpers inside a loop' => <<~ERB,
      <div>
        <% todos.each do |todo| %>
          <%= content_tag :p, class: 'todo' do %>
            <%= todo.title %>
          <% end %>
          <% content_for :sidebar do %>ignored<% end %>
        <% end %>
      </div>
    ERB
    'a block that leaves early' => <<~ERB,
      <ul>
        <% todos.each do |todo| %>
          <% next if todo.done %>
          <li><%= todo.title %></li>
        <% end %>
      </ul>
    ERB
    'begin and rescue inside a conditional' => <<~ERB,
      <div>
        <% if count > 0 %>
          <% begin %><%= Integer('oops') %><% rescue ArgumentError %><em>bad</em><% end %>
        <% end %>
      </div>
    ERB
    'a conditional inside an attribute' => <<~ERB,
      <div class="todo <% if count > 2 %>wide<% else %>narrow<% end %>">x</div>
    ERB
    'several blocks with text between' => <<~ERB,
      <div>
        <h1><%= filter %></h1>

        <% if count > 1 %>
          <p>many</p>
        <% end %>

        <% todos.each do |todo| %>
          <i><%= todo.title %></i>
        <% end %>
        <footer><%= count %></footer>
      </div>
    ERB
  }

  locals_cases = {
    'empty' => { count: 0, filter: :all, todos: [] },
    'some' => {
      count: 3,
      filter: :done,
      todos: [[1, 'Milk', false], [2, 'Eggs <&>', true], [3, 'Bread', false]],
    },
    'many' => {
      count: 12,
      filter: :other,
      todos: [[1, 'Milk', true], [2, 'Eggs', true]],
    },
  }

  templates.each do |name, source|
    locals_cases.each do |case_name, locals|
      it "renders #{name} the same as an HTML block (#{case_name})" do
        locals = locals.merge(todos: locals[:todos].map { |values| todo.new(*values) })

        expect_same_output(source, **locals)
      end
    end
  end

  # The HTML path wraps the expression in parentheses on one line, so the
  # comment swallows the closing parenthesis there.
  it 'renders an expression with a trailing comment inside a block' do
    html = render("<div><% if count > 0 %><%= count # how many %><% end %></div>\n", structured: true, count: 3)

    expect(html).to eq("<div>3</div>\n")
  end

  describe 'which blocks become trees' do
    it 'turns branches and iteration loops into tree parts' do
      expect(part_types(templates['an if with elsif and else'])).to eq(%i[text tree text])
      expect(part_types(templates['a keyed loop with attributes'])).to eq(%i[text tree text])
      expect(part_types(templates['a case'])).to eq(%i[text tree text])
    end

    it 'keeps a block that leaves its body early as HTML' do
      expect(part_types(templates['a block that leaves early'])).to eq(%i[text block text])
    end

    it 'keeps a top-level block helper as HTML' do
      expect(part_types("<div><%= content_tag :p do %>x<% end %></div>\n")).to eq(%i[text block text])
    end

    it 'captures a block helper inside a tree as one value' do
      types = part_types(templates['block helpers inside a loop'])

      expect(types).to eq(%i[text tree text])
    end

    it 'keeps a block that comes before any output as HTML, since it may hold the root element' do
      expect(part_types("\n<% if count > 0 %>\n  <div>on</div>\n<% else %>\n  <div>off</div>\n<% end %>\n")).
        to eq(%i[block])
      expect(part_types("<%# note %>\n<% if count > 0 %><div>on</div><% end %>\n").first).to eq(:block)
    end

    it 'only treats a block as a loop when the call that owns it iterates' do
      ['cache [todo, step] do', 'content_for :side, each do', "cache 'sidebar each' do",
        "render layout: 'card', locals: { step: step } do"].each do |opening|
        expect(part_types("<div><% #{opening} %>x<% end %></div>\n")).to eq(%i[text block text]), opening
      end

      expect(part_types("<ul><% todos.each_with_index do |todo, i| %><li><%= i %></li><% end %></ul>\n")).
        to eq(%i[text tree text])
    end

    it 'compiles every block to HTML when structuring is off' do
      _, parts = compile(templates['an if with elsif and else'], structured: false)

      expect(parts.map(&:first)).to eq(%i[text block text])
    end
  end

  describe 'nodes' do
    def nodes(source, **locals)
      partial, = compile(source, structured: true)
      render_parts(partial, locals).grep(Hash)
    end

    it 'keys loop rows by their element id' do
      todos = [todo.new(1, 'Milk', false), todo.new(2, 'Eggs', true)]
      node = nodes(templates['a keyed loop with attributes'], todos:).first

      expect(node['k']).to eq(%w[todo-1 todo-2])
      expect(node['r'].map(&:last)).to eq(%w[Milk Eggs])
    end

    it 'keys rows by a dom_id of the loop variable' do
      todos = [todo.new(1, 'Milk', false)]
      source = "<ul><% todos.each do |todo| %><li id=\"<%= dom_id(todo) %>\"><%= todo.title %></li><% end %></ul>\n"
      todo_class = Class.new(Struct.new(:id, :title, :done)) do
        extend ActiveModel::Naming

        def self.name = 'Todo'
        def to_key = [id]
      end
      node = nodes(source, todos: todos.map { |item| todo_class.new(*item.to_a) }).first

      expect(node['k']).to eq(%w[todo_1])
    end

    it 'leaves rows unkeyed when the key could change what the row renders' do
      todos = [todo.new(1, 'Milk', false), todo.new(2, 'Eggs', false)]

      expect(nodes(templates['a key with a side effect'], todos:).first).not_to have_key('k')
      expect(nodes(templates['a key that cycles'], todos:).first).not_to have_key('k')
    end

    it 'drops the keys when they repeat' do
      todos = [todo.new(1, 'Milk', false), todo.new(1, 'Eggs', true)]
      node = nodes(templates['a keyed loop with attributes'], todos:).first

      expect(node).not_to have_key('k')
    end

    it 'leaves a loop unkeyed when its body is more than one element' do
      todos = [todo.new(1, 'Milk', false)]
      node = nodes(templates['for and while loops'], todos:, count: 1).first

      expect(node).not_to have_key('k')
    end

    it 'marks a conditional with no branch taken' do
      node = nodes("<div><% if count > 1 %>x<% end %></div>\n", count: 0).first

      expect(node).to eq('t' => nil)
    end
  end

  describe 'diffing' do
    let(:source) { templates['a conditional around a nested loop'] }

    def tree_for(todos)
      partial, = compile(source, structured: true)
      render_parts(partial, { todos: todos.map { |values| todo.new(*values) } }).grep(Hash).first
    end

    states = {
      'empty' => [],
      'one' => [[1, 'Milk', false]],
      'two' => [[1, 'Milk', false], [2, 'Eggs', false]],
      'renamed' => [[1, 'Oat milk', false], [2, 'Eggs', false]],
      'reordered' => [[2, 'Eggs', false], [1, 'Milk', false]],
      'inserted at the front' => [[3, 'Bread', false], [1, 'Milk', false], [2, 'Eggs', false]],
    }

    states.to_a.permutation(2).each do |(from_name, from), (to_name, to)|
      it "turns #{from_name} into #{to_name} by applying the diff" do
        previous = tree_for(from)
        current = tree_for(to)
        diff = LiveCable::Rendering::Tree.diff(previous, current)

        expect(LiveCable::Rendering::Tree.apply(previous, diff)).to eq(current)
      end
    end

    it 'sends nothing when nothing changed' do
      expect(LiveCable::Rendering::Tree.diff(tree_for(states['two']), tree_for(states['two']))).to be_nil
    end

    it 'sends only the changed row value when one title changes' do
      diff = LiveCable::Rendering::Tree.diff(tree_for(states['two']), tree_for(states['renamed']))

      expect(diff.to_json).not_to include('Eggs')
      expect(diff.to_json).to include('Oat milk')
    end

    it 'sends the new key order and the new row when a row is inserted' do
      diff = LiveCable::Rendering::Tree.diff(tree_for(states['two']), tree_for(states['inserted at the front']))
      loop_diff = diff.dig('d', '1')

      expect(loop_diff['k']).to eq(%w[3 1 2])
      expect(loop_diff['r'].keys).to eq(%w[3])
    end
  end
end
