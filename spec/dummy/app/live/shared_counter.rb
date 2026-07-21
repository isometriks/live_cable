# frozen_string_literal: true

module Live
  class SharedCounter < LiveCable::Component
    reactive :total, -> { 0 }, shared: true

    actions :bump

    def bump
      self.total += 1
    end
  end
end
