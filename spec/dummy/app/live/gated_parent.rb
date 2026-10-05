# frozen_string_literal: true

module Live
  class GatedParent < LiveCable::Component
    reactive :open, -> { false }, shared: true
    reactive :show, -> { true }
    reactive :label, -> { 'a' }

    actions :unlock, :relabel, :toggle

    def unlock
      self.open = true
    end

    def relabel
      self.label += 'b'
    end

    def toggle
      self.show = !show
    end
  end
end
