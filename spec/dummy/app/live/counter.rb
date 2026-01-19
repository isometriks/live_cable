# frozen_string_literal: true

module Live
  class Counter < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :step, -> { 1 }

    actions :increment, :decrement, :reset

    def increment
      self.count += step.to_i
    end

    def decrement
      self.count -= step.to_i
    end

    def reset
      self.count = 0
    end
  end
end
