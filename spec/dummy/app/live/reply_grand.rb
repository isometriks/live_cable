# frozen_string_literal: true

module Live
  class ReplyGrand < LiveCable::Component
    reactive :tick, -> { 0 }, shared: true
  end
end
