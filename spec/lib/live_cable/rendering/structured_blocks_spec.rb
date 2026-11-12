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

      def live_connection = nil

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
    component = component_class.new(locals)
    view_context = ApplicationController.new.view_context
    view_context.send(:context_stack).push(LiveCable::RenderContext.new(component))
    partial.for_component(component, view_context).render_changes(:all)
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
    'comments and a heredoc in tags inside a loop' => <<~'ERB',
      <ul>
        <% todos.each do |todo| # each todo %>
          <li id="todo-<%= todo.id # key %>"><%= todo.title # title %><%= <<~TEXT.strip
            #{todo.id}!
          TEXT
          %></li>
        <% end %>
      </ul>
    ERB
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

  it 'renders a helper block inside a loop where the helper yields it' do
    source = "<div><% todos.each do |todo| %><%= card todo.title do %><b><%= todo.id %></b><% end %><% end %></div>\n"
    html = render(source, structured: true, todos: [todo.new(1, 'Milk')])

    expect(Capybara.string(html)).to have_css('section[data-testid="card"] h2 + b', text: '1')
    expect(html).to eq(render(source, structured: false, todos: [todo.new(1, 'Milk')]))
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

    it 'keys rows by an interpolated string of the loop variable' do
      todos = [todo.new(1, 'Milk', false), todo.new(2, 'Eggs', true)]
      source = <<~'ERB'
        <ul><% todos.each do |todo| %><li live-key="<%= "todo-#{todo.id}" %>"><%= todo.title %></li><% end %></ul>
      ERB

      expect(nodes(source, todos:).first['k']).to eq(%w[todo-1 todo-2])
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

    it 'renders a long loop in time that grows with its rows, not their square' do
      partial, = compile(templates['a keyed loop with attributes'], structured: true)
      time = lambda do |count|
        todos = Array.new(count) { |i| todo.new(i, 'x' * 100, false) }
        node = render_parts(partial, { todos: }).grep(Hash).first
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        LiveCable::Rendering::Tree.render(node, partial.statics)
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      end
      time.call(1_000)

      expect(time.call(20_000) / time.call(2_000)).to be < 40
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

    it 'sends an inserted row as one op, without the key order' do
      diff = LiveCable::Rendering::Tree.diff(tree_for(states['two']), tree_for(states['inserted at the front']))

      expect(diff.dig('d', '1')).to eq('o' => [['p', '3', %w[3 Bread]]])
    end
  end

  describe 'keyed loop diffs' do
    def loop_node(*keys, titles: {})
      keys = keys.map(&:to_s)
      { 't' => 0, 'r' => keys.map { |key| [key, titles.fetch(key, "Row #{key}")] }, 'k' => keys }
    end

    def ops(from, to)
      LiveCable::Rendering::Tree.diff(from, to)&.fetch('o')
    end

    def apply(stored, ops)
      LiveCable::Rendering::Tree.apply(stored, { 'o' => ops })
    end

    it 'appends a row after the last one' do
      expect(ops(loop_node(1, 2), loop_node(1, 2, 3))).to eq([['a', '3', ['3', 'Row 3']]])
    end

    it 'prepends a row before the first one' do
      expect(ops(loop_node(1, 2), loop_node(3, 1, 2))).to eq([['p', '3', ['3', 'Row 3']]])
    end

    it 'inserts a row after the key before it' do
      expect(ops(loop_node(1, 2), loop_node(1, 3, 2))).to eq([['i', '3', ['3', 'Row 3'], '1']])
    end

    it 'deletes removed rows in one op' do
      expect(ops(loop_node(1, 2, 3, 4), loop_node(1, 3))).to eq([%w[d 2 4]])
    end

    it 'updates a changed row with the values that changed' do
      expect(ops(loop_node(1, 2), loop_node(1, 2, titles: { '2' => 'Eggs' }))).to eq([['u', '2', { '1' => 'Eggs' }]])
    end

    it 'moves only the rows that left their order' do
      expect(ops(loop_node(1, 2, 3, 4), loop_node(2, 3, 4, 1))).to eq([%w[m 1 4]])
      expect(ops(loop_node(1, 2, 3, 4), loop_node(4, 1, 2, 3))).to eq([['m', '4', nil]])
    end

    it 'sends the new order of the kept rows when that is smaller than moving them' do
      expect(ops(loop_node(1, 2, 3, 4), loop_node(4, 3, 2, 1))).to eq([%w[s 4 3 2 1]])
      expect(ops(loop_node(1, 2, 3, 4), loop_node(4, 5, 3, 1, titles: { '1' => 'Milk' }))).
        to eq([%w[d 2], %w[s 4 3 1], ['i', '5', ['5', 'Row 5'], '4'], ['u', '1', { '1' => 'Milk' }]])
    end

    it 'sends a re-sort of a long list in about the size of its key order' do
      keys = (1..2000).map { |key| "item-#{key}" }
      diff = LiveCable::Rendering::Tree.diff(loop_node(*keys), loop_node(*keys.shuffle(random: Random.new(1))))

      expect(diff.to_json.bytesize).to be < keys.to_json.bytesize + 20
    end

    it 'sends only updates when the key order is unchanged' do
      expect(ops(loop_node(1, 2, 3), loop_node(1, 2, 3, titles: { '1' => 'Milk', '3' => 'Jam' }))).
        to eq([['u', '1', { '1' => 'Milk' }], ['u', '3', { '1' => 'Jam' }]])
      expect(LiveCable::Rendering::Tree.diff(loop_node(1, 2), loop_node(1, 2))).to be_nil
    end

    it 'sends a whole node when no row is kept' do
      expect(LiveCable::Rendering::Tree.diff(loop_node(1, 2), loop_node(3))).to eq(loop_node(3))
      expect(LiveCable::Rendering::Tree.diff(loop_node, loop_node(1))).to eq(loop_node(1))
      expect(LiveCable::Rendering::Tree.diff(loop_node(1), loop_node)).to eq(loop_node)
    end

    it 'sends nothing for two empty loops' do
      expect(LiveCable::Rendering::Tree.diff(loop_node, loop_node)).to be_nil
    end

    it 'sends a removal from a long list as its key alone' do
      keys = (1..2000).to_a

      expect(LiveCable::Rendering::Tree.diff(loop_node(*keys), loop_node(*(keys - [1000]))).to_json).
        to eq('{"o":[["d","1000"]]}')
    end

    it 'reproduces the new rows from the ops for any reordering' do
      random = Random.new(20_261_112)

      300.times do
        from = (1..12).to_a.shuffle(random:).take(random.rand(1..10))
        to = ((1..14).to_a.sample(random.rand(0..6), random:) | from.sample(random.rand(0..from.size), random:)).
          shuffle(random:)
        titles = to.sample(random.rand(0..to.size), random:).to_h { |key| [key.to_s, "New #{key}"] }
        previous = loop_node(*from)
        current = loop_node(*to, titles:)

        diff = LiveCable::Rendering::Tree.diff(previous, current)
        applied = diff.nil? ? previous : LiveCable::Rendering::Tree.apply(previous, diff)

        expect(applied).to eq(current), "#{from} -> #{to}"
        expect(diff.keys).to eq(%w[o]) unless diff.nil? || diff.key?('t')
      end
    end

    describe 'applying' do
      it 'drops every row on a reset, before the ops after it' do
        expect(apply(loop_node(1, 2), [['r'], ['a', '3', ['3', 'Row 3']]])).to eq(loop_node(3))
      end

      it 'replaces a row inserted under a key it already holds where it is' do
        expect(apply(loop_node(1, 2, 3), [['p', '3', %w[3 Bread]]])).
          to eq(loop_node(1, 2, 3, titles: { '3' => 'Bread' }))
        expect(apply(loop_node(1, 2, 3), [['i', '1', %w[1 Bread], '2']])).
          to eq(loop_node(1, 2, 3, titles: { '1' => 'Bread' }))
      end

      it 'ignores a delete of a key it does not hold' do
        expect(apply(loop_node(1, 2), [%w[d 2 9]])).to eq(loop_node(1))
      end

      it 'orders the rows a sort names, skipping keys it does not hold, with the rest after them' do
        expect(apply(loop_node(1, 2, 3, 4), [%w[s 3 9 1 3]])).to eq(loop_node(3, 1, 2, 4))
      end

      it 'replaces a row an update sends whole' do
        expect(apply(loop_node(1, 2), [['u', '2', %w[2 Eggs]]])).to eq(loop_node(1, 2, titles: { '2' => 'Eggs' }))
      end

      it 'ignores an update of a key it does not hold, and appends an insert after one' do
        expect(apply(loop_node(1), [['u', '9', { '1' => 'x' }], ['u', '8', %w[8 x]], %w[d 8]])).to eq(loop_node(1))
        expect(apply(loop_node(1), [['i', '2', %w[2 x], '9']])).to eq(loop_node(1, 2, titles: { '2' => 'x' }))
      end

      it 'raises on a move of a row it does not hold' do
        expect { apply(loop_node(1), [['m', '2', nil]]) }.to raise_error(KeyError)
        expect { apply(loop_node(1, 2), [%w[m 2 9]]) }.to raise_error(KeyError)
      end

      # The same cases run in test/tree.test.js
      JSON.parse(File.read(File.expand_path('../../../fixtures/loop_ops.json', __dir__))).each do |example|
        it example['name'] do
          applied = LiveCable::Rendering::Tree.apply(example['node'], { 'o' => example['ops'] })

          expect(applied.slice('k', 'r')).to eq(example['result'])
          expect(applied.except('k', 'r')).to eq(example['node'].except('k', 'r'))
          next unless example['html']

          expect(LiveCable::Rendering::Tree.render(applied, example['statics'])).to eq(example['html'])
        end
      end
    end
  end

  describe 'stream nodes' do
    let(:tree) { LiveCable::Rendering::Tree }
    let(:placeholder) { tree::StreamPlaceholder.for(:messages, 2) }
    let(:stream) { tree::StreamNode.build(:messages, 2, { 'a' => %w[a A], 'b' => %w[b B] }, nil) }

    it 'are sent whole, and a placeholder diffs to nothing against the one kept' do
      expect(tree.diff(placeholder, stream)).to eq(stream)
      expect(tree.diff({ 't' => 0, 'd' => ['x', placeholder] }, { 't' => 0, 'd' => ['y', placeholder] })).
        to eq('d' => { '0' => 'y' })
    end

    it 'raise for a placeholder where the client holds something else' do
      expect { tree.diff({ 't' => 0, 'd' => ['x'] }, { 't' => 0, 'd' => [placeholder] }) }.
        to raise_error(LiveCable::Error, /stream :messages was left as the client holds it/)
    end

    it 'keep the last rows up to a limit' do
      expect(tree::StreamNode.build(:log, 1, { 'a' => ['a'], 'b' => ['b'], 'c' => ['c'] }, 2)).
        to eq('t' => 1, 'st' => 'log', 'r' => [['b'], ['c']], 'k' => %w[b c], 'l' => 2)
    end

    it 'are found and replaced by their placeholder along their path, when the branches match' do
      node = { 't' => 0, 'd' => ['x', { 't' => 1, 'd' => [stream] }] }
      path = [[0, 1], [1, 0]]

      expect(tree.node_at(node, path)).to eq(stream)
      expect(tree.without_stream_rows(node, path, placeholder)).
        to eq('t' => 0, 'd' => ['x', { 't' => 1, 'd' => [placeholder] }])
      expect(tree.node_at(node, [[0, 1], [5, 0]])).to be_nil
      expect(tree.without_stream_rows(node, [[0, 1], [5, 0]], placeholder)).to equal(node)
    end

    it 'join a part diff at their path' do
      update = tree.path_diff([[0, 1], [1, 0]], { 'o' => [%w[d a]] })

      expect(update).to eq('d' => { '1' => { 'd' => { '0' => { 'o' => [%w[d a]] } } } })
      expect(tree.merge_diff(nil, update)).to eq(update)
      expect(tree.merge_diff({ 'd' => { '0' => 'y', '1' => { 'd' => { '1' => 'z' } } } }, update)).
        to eq('d' => { '0' => 'y', '1' => { 'd' => { '1' => 'z', '0' => { 'o' => [%w[d a]] } } } })
      expect { tree.merge_diff({ 't' => 0, 'd' => [] }, update) }.to raise_error(LiveCable::Error)
    end
  end
end
