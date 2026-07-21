# frozen_string_literal: true

module Live
  class StreamTest < LiveCable::Component
    reactive :messages, -> { [] }

    after_connect :subscribe_to_messages

    private

    def subscribe_to_messages
      stream_from('test_messages', coder: ActiveSupport::JSON) do |data|
        messages << data['text']
      end
    end
  end
end
