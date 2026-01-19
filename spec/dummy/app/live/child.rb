# frozen_string_literal: true

module Live
  class Child < LiveCable::Component
    reactive :i, -> { 'NONE' }

    def renders
      @total_renders || 0
    end

    def render_in(...)
      @total_renders ||= 0
      @total_renders += 1

      super
    end
  end
end
