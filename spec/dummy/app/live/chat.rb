# frozen_string_literal: true

module Live
  # A chat whose messages are a collection stream: the server keeps none of
  # them, and each broadcast sends the page one row
  class Chat < LiveCable::Component
    reactive :room_name, -> { 'Lobby' }
    reactive :expanded, -> { true }

    stream :messages, -> { ChatStore.all }, dom_id: ->(message) { message_key(message.id) }

    actions :toggle, :rename, :like

    after_connect do
      stream_from(ChatStore::CHANNEL, coder: ActiveSupport::JSON) { |payload| receive(payload) }
    end

    def toggle = self.expanded = !expanded

    def rename(params) = self.room_name = params[:name].to_s

    def like(params)
      message = ChatStore.like(params[:id])
      stream_update(:messages, message) if message
    end

    private

    def message_key(id) = "message-#{id}"

    def receive(payload)
      return stream_delete(:messages, message_key(payload['id'])) if payload['event'] == 'deleted'

      message = ChatStore.find(payload['id']) or return

      case payload['event']
      when 'created' then stream_insert(:messages, message)
      when 'announced' then announce(message)
      else stream_update(:messages, message)
      end
    end

    def announce(message)
      self.room_name = 'Announcements'
      stream_insert(:messages, message, at: :start)
    end
  end
end
