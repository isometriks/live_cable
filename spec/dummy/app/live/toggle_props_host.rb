# frozen_string_literal: true

module Live
  class TogglePropsHost < LiveCable::Component
    reactive :visible, -> { false }

    actions :flip

    def flip
      self.visible = !visible
    end
  end
end
