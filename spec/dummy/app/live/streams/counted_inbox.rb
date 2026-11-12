# frozen_string_literal: true

module Live
  module Streams
    # Live::Streams::Inbox with a count beside the list, so each broadcast
    # changes a part as well as the stream. A repeated message isn't counted
    # again, since the system spec sends one until the page shows it.
    class CountedInbox < LiveCable::Component
      reactive :count, -> { 0 }

      stream :messages, dom_id: ->(message) { "message-#{message['id']}" }

      after_connect do
        seen = Set.new
        stream_from('inbox', coder: ActiveSupport::JSON) do |message|
          stream_insert(:messages, message)
          self.count = seen.add(message['id']).size
        end
      end
    end
  end
end
