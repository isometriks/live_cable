# frozen_string_literal: true

module Live
  class TranslatedCompound < LiveCable::Component
    compound

    reactive :count, -> { 0 }

    actions :bump

    def variant
      count.odd? ? 'odd' : 'even'
    end

    def bump
      self.count += 1
    end
  end
end
