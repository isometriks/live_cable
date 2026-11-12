# frozen_string_literal: true

module Live
  class HaltingSharer < LiveCable::Component
    reactive :total, -> { 0 }, shared: true
    reactive :paused, -> { false }

    after_connect do
      self.paused = true
      self.total += 1
    end

    before_render { throw :abort if paused }
  end
end
