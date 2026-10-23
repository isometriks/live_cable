# Run from the repo root: bundle exec ruby handoff/cpu.rb   (see handoff/HANDOFF.md)
require 'rspec/core'
require 'benchmark'
require './spec/dummy/config/environment'
require 'live_cable/testing'
LiveCable.configuration.structured_blocks = ENV['STRUCTURED'] == '1'
include LiveCable::Testing
c = live_mount('todo_list')
200.times { |i| c.perform(:add, title: "Todo item number #{i + 1}") }
c.perform(:toggle, id: 1)
n = 200
t = Benchmark.realtime { n.times { |i| c.perform(:toggle, id: (i % 200) + 1); c.clear_broadcasts } }
puts format('structured=%s  %.2f ms per toggle (200 todos)', ENV['STRUCTURED'], t * 1000 / n)
