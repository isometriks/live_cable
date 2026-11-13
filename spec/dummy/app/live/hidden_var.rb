# frozen_string_literal: true

module Live
  # Has reactive variables the template never renders, one of them shared, to
  # exercise the "changed state that produces no visible output" path.
  class HiddenVar < LiveCable::Component
    reactive :shown, -> { 0 }
    reactive :hidden, -> { 0 }
    reactive :total, -> { 0 }, shared: true

    actions :bump_shown, :bump_hidden, :bump_hidden_with_event

    attr_reader :render_count

    after_render { @render_count = (@render_count || 0) + 1 }

    def bump_shown
      self.shown += 1
    end

    def bump_hidden
      self.hidden += 1
    end

    def bump_hidden_with_event
      self.hidden += 1
      dispatch_event('hidden:changed')
    end
  end
end
