# frozen_string_literal: true

module Live
  class Lane < LiveCable::Component
    reactive :lane, -> { 'todo' }
    reactive :cards, -> { [] }, shared: true

    def lane_cards = cards.select { |card| card[:lane] == lane }
  end
end
