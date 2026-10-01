# frozen_string_literal: true

module Live
  class SharedCounter < LiveCable::Component
    reactive :total, -> { 0 }, shared: true

    actions :bump, :slow_bump

    def bump
      self.total += 1
    end

    def slow_bump
      sleep 0.5
      bump
    end
  end
end
