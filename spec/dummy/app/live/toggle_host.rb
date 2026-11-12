# frozen_string_literal: true

module Live
  class ToggleHost < LiveCable::Component
    reactive :visible, -> { true }

    actions :flip

    def flip
      self.visible = !visible
    end
  end
end
