# frozen_string_literal: true

module Live
  module Streams
    # Live::StreamTest as a collection stream: each broadcast inserts one row
    # and tells the page it arrived
    class Inbox < LiveCable::Component
      stream :messages, dom_id: ->(message) { "message-#{message['id']}" }

      after_connect do
        stream_from('inbox', coder: ActiveSupport::JSON) do |message|
          stream_insert(:messages, message)
          dispatch_event('inbox:message-received', id: message['id'])
        end
      end
    end
  end
end
