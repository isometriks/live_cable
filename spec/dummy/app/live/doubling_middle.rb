# frozen_string_literal: true

module Live
  class DoublingMiddle < LiveCable::Component
    reactive :amount, -> { 2 }, shared: true

    actions :overflow

    before_render { throw :abort if amount > 1000 }

    def overflow
      self.amount += 1000
    end
  end
end
