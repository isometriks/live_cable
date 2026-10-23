# Run from the repo root: bundle exec ruby handoff/bench.rb   (see handoff/HANDOFF.md)
# Payload size per action for the TodoList component, structured vs HTML blocks.
require 'rspec/core'
require 'json'
require './spec/dummy/config/environment'
require 'live_cable/testing'
LiveCable.configuration.structured_blocks = ENV['STRUCTURED'] == '1'
include LiveCable::Testing

count = Integer(ENV.fetch('TODOS', '20'))
component = live_mount('todo_list')
titles = Array.new(count) { |i| "Todo item number #{i + 1}" }
titles.reverse_each { |t| component.perform(:add, title: t) }
bytes = ->(c) { c.broadcasts(:_refresh).sum { |b| JSON.generate(b[:_refresh].as_json).bytesize } }

# A fresh client's first full render of the 20-todo list
component.component.instance_variable_set(:@static_sent, {})
component.clear_broadcasts
component.component.broadcast_render
results = { 'first full render' => bytes.(component) }

steps = {
  'toggle one todo' => -> { component.perform(:toggle, id: 5) },
  'rename one todo' => -> { component.perform(:rename, id: 6, title: 'Renamed todo') },
  'add a todo (top)' => -> { component.perform(:add, title: 'Brand new todo') },
  'remove a todo' => -> { component.perform(:remove, id: 3) },
  'filter: active' => -> { component.perform(:show, filter: 'active') },
  'filter: all' => -> { component.perform(:show, filter: 'all') },
  'clear completed' => -> { component.perform(:clear_done) },
}
steps.each do |name, step|
  component.clear_broadcasts
  step.call
  results[name] = bytes.(component)
end
html = component.rendered_html
puts JSON.generate(results:, html_bytes: html.bytesize, html_digest: Digest::SHA256.hexdigest(html))
