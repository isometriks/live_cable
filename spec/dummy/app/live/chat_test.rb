# frozen_string_literal: true

module Live
  class ChatTest < LiveCable::Component
    STREAM_NAME = 'live_cable_chat_test'

    reactive :messages, -> { [] }
    reactive :draft, -> { '' }, writable: true
    reactive :note, -> { '' }, writable: true
    reactive :slow_draft, -> { '' }, writable: true

    after_connect :listen

    # Leaves time to type while the update is on its way
    before_dispatch { sleep 0.5 if current_dispatch.name == :slow_draft }

    private

    def listen
      stream_from(STREAM_NAME, coder: ActiveSupport::JSON) do |data|
        messages << data['text']
      end
    end
  end
end
