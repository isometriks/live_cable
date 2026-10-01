# frozen_string_literal: true

module Live
  class KernelNames < LiveCable::Component
    reactive :open, -> { false }
    reactive :display, -> { 'compact' }
    reactive :price, -> { 1.5 }

    actions :toggle

    def toggle
      self.open = !open
    end

    def test
      'from the component'
    end
  end
end
