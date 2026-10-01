# frozen_string_literal: true

module Live
  class Room < LiveCable::Component
    reactive :room_id, -> { 1 }
    reactive :messages, -> { [] }

    actions :switch_room, :leave

    after_connect :join_room

    def switch_room(params)
      stop_stream_from(room_stream)
      self.room_id = params[:room_id].to_i
      self.messages = []
      join_room
    end

    def leave
      stop_stream
    end

    private

    def room_stream
      "room_#{room_id}"
    end

    def join_room
      stream_from(room_stream, coder: ActiveSupport::JSON) do |data|
        messages << data['text']
      end
    end
  end
end
