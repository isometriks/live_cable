# frozen_string_literal: true

module Live
  # Has a reactive variable the template never renders, to exercise the
  # "changed state that produces no visible output" path.
  class HiddenVar < LiveCable::Component
    reactive :shown, -> { 0 }
    reactive :hidden, -> { 0 }

    actions :bump_shown, :bump_hidden, :bump_hidden_with_event

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
