# frozen_string_literal: true

module Live
  module Streams
    class OwnIds < LiveCable::Component
      stream :messages, -> { ChatMessage.recent }

      def prefix = 'Said:'
    end
  end
end
