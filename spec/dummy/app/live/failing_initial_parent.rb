# frozen_string_literal: true

module Live
  class FailingInitialParent < LiveCable::Component
    reactive :show_child, -> { false }

    actions :reveal

    def reveal
      self.show_child = true
    end
  end
end
