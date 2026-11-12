# frozen_string_literal: true

module Live
  # A collection stream with no initial rows that keeps the newest three
  class Ticker < LiveCable::Component
    Tick = Data.define(:id)

    stream :ticks, dom_id: ->(tick) { "tick-#{tick.id}" }, limit: 3

    actions :push, :push_first, :clear

    def push = stream_insert(:ticks, next_tick)

    def push_first = stream_insert(:ticks, next_tick, at: :start)

    def clear = stream_reset(:ticks)

    private

    # Untracked, so a push sends only its row
    def next_tick = Tick.new(id: @last_id = (@last_id || 0) + 1)
  end
end
