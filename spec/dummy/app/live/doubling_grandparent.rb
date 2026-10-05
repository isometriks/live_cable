# frozen_string_literal: true

module Live
  class DoublingGrandparent < LiveCable::Component
    reactive :amount, -> { 2 }, shared: true

    actions :add, :overflow

    def add
      self.amount += 10
    end

    def overflow
      self.amount += 1000
    end
  end
end
