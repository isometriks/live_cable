# frozen_string_literal: true

module Live
  module Streams
    # Live::Room as a collection stream: a switch refills the list from the
    # new room's history
    class Lobby < LiveCable::Component
      reactive :room_id, -> { 1 }

      stream :messages, ->(lobby) { RoomHistory.for(lobby.room_id) },
        dom_id: ->(message) { "message-#{message['id']}" }

      actions :switch_room

      after_connect :join_room

      def switch_room(params)
        stop_stream_from(room_stream)
        self.room_id = params[:room_id].to_i
        stream_reset(:messages)
        join_room
      end

      private

      def room_stream = "lobby_#{room_id}"

      def join_room
        stream_from(room_stream, coder: ActiveSupport::JSON) { |message| stream_insert(:messages, message) }
      end
    end
  end
end
