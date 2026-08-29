# frozen_string_literal: true

module Live
  class LocalVars < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :label, -> {}
    reactive :multiplier, -> {}
    reactive :hidden, -> { 0 }

    actions :increment, :set_label, :set_multiplier, :bump_hidden

    def increment
      self.count += 1
    end

    def set_label
      self.label = 'custom'
    end

    def set_multiplier
      self.multiplier = 3
    end

    def bump_hidden
      self.hidden += 1
    end
  end
end
