# frozen_string_literal: true

module Live
  class LostFramePanel < LiveCable::Component
    reactive :open, -> { true }, shared: true
  end
end
