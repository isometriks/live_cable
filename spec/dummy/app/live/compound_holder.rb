# frozen_string_literal: true

module Live
  class CompoundHolder < LiveCable::Component
    compound

    reactive :show, -> { true }

    actions :hide

    def variant
      show ? 'shown' : 'hidden'
    end

    def hide
      self.show = false
    end
  end
end
