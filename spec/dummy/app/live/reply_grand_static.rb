# frozen_string_literal: true

module Live
  class ReplyGrandStatic < LiveCable::Component
    reactive :tick, -> { 0 }, shared: true
  end
end
