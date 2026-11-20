# frozen_string_literal: true

module Live
  class Pausable < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :paused, -> { false }
    reactive :label, -> { '' }

    actions :increment, :pause, :resume

    before_render { throw :abort if paused }

    def increment
      self.count += 1
    end

    def pause
      self.paused = true
    end

    def resume
      self.paused = false
    end
  end
end
