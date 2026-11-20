# frozen_string_literal: true

module Live
  class LostFrameHost < LiveCable::Component
    reactive :panel, -> { false }
    reactive :open, -> { true }, shared: true

    actions :show_panel, :collapse

    def show_panel
      self.panel = true
    end

    def collapse
      self.open = false
    end
  end
end
