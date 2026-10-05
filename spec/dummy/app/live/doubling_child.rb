# frozen_string_literal: true

module Live
  class DoublingChild < LiveCable::Component
    reactive :amount, -> { 2 }, shared: true
    reactive :label, -> { '' }
    reactive :doubled, -> { 0 }

    attr_reader :render_count

    before_render do
      raise 'child before_render failed' if amount.negative?

      @render_count = (@render_count || 0) + 1
      self.doubled = amount * 2
    end
  end
end
