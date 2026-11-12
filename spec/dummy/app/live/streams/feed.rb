# frozen_string_literal: true

module Live
  module Streams
    class Feed < LiveCable::Component
      reactive :topic, -> { '' }

      stream :entries, -> { ChatMessage.recent }
    end
  end
end
