# frozen_string_literal: true

module Live
  class Compound < LiveCable::Component
    compound

    reactive :count, -> { 1 }

    actions :increment

    def variant
      count.odd? ? 'odd' : 'even'
    end

    def increment
      self.count += 1
    end
  end
end
