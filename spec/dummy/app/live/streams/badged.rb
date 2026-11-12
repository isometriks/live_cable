# frozen_string_literal: true

module Live
  module Streams
    class Badged < LiveCable::Component
      stream :messages, -> { ChatMessage.recent }
    end
  end
end
