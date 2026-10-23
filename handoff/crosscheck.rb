# Run from the repo root: bundle exec ruby handoff/crosscheck.rb   (see handoff/HANDOFF.md)
require 'rspec/core'
require 'json'
require './spec/dummy/config/environment'
# Renders a template under many states, then emits every (from -> to) transition
# with the server's diff and the HTML the client must end up with.
src = <<~ERB
  <section>
    <% if todos.any? %>
      <h2><%= todos.size %> todos, filter <%= filter %></h2>
      <ul>
      <% todos.each do |t| %>
        <li id="todo-<%= t[0] %>" class="<%= 'done' if t[2] %>">
          <% if t[2] %><s><%= t[1] %></s><% else %><%= t[1] %><% end %>
        </li>
      <% end %>
      </ul>
      <% case filter %><% when :all %><b>all</b><% when :done %><i>done</i><% else %><u>?</u><% end %>
    <% else %>
      <p>Nothing</p>
    <% end %>
    <% (todos.size).times do |i| %><span><%= i %></span><% end %>
  </section>
ERB
klass = Class.new { def initialize(l) = @l = l; def method_missing(n, *a) = @l.fetch(n) { super }; def respond_to_missing?(n, p = false) = @l.key?(n) || super }
e = LiveCable::Rendering::Renderer.new; c = LiveCable::Rendering::Compiler.new(e, structured: true)
Herb.parse(src, track_whitespace: true).value.accept(c); c.generate_output
partial = eval(e.src)
render = ->(l) { partial.for_component(klass.new(l), ApplicationController.new.view_context).render_changes(:all) }
states = [
  { todos: [], filter: :all },
  { todos: [[1, 'Milk', false]], filter: :all },
  { todos: [[1, 'Milk', false], [2, 'Eggs <&>', true]], filter: :done },
  { todos: [[2, 'Eggs <&>', true], [1, 'Milk', true]], filter: :x },
  { todos: [[3, 'Bread', false], [1, 'Milk', false], [2, 'Eggs <&>', false]], filter: :all },
  { todos: [[3, 'Bread', false]], filter: :done },
]
cases = states.each_with_index.to_a.permutation(2).map do |(a, i), (b, j)|
  pa = render.(a); pb = render.(b)
  { from: i, to: j, held: pa.as_json,
    update: pa.zip(pb).map { |x, y| y.is_a?(Hash) ? LiveCable::Rendering::Tree.diff(x, y) : (x == y ? nil : y) }.as_json,
    html: pb.sum('') { |p| LiveCable::Rendering::Tree.render(p, partial.statics) } }
end
puts JSON.generate(statics: partial.statics.as_json, cases:)
