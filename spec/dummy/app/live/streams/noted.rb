# frozen_string_literal: true

module Live
  module Streams
    class Noted < LiveCable::Component
      stream :entries, -> { ChatMessage.recent }
    end
  end
end
