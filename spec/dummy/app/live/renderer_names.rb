# frozen_string_literal: true

module Live
  class RendererNames < LiveCable::Component
    reactive :parts, -> { %w[wheel bolt] }
    reactive :changes, -> { %w[paint tyres] }

    actions :swap

    def swap
      self.changes = changes.reverse
    end
  end
end
