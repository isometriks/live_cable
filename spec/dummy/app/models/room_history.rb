# frozen_string_literal: true

# Messages sent to each room, as the JSON payloads broadcast for them,
# standing in for a query by room
module RoomHistory
  @lock = Mutex.new

  class << self
    def reset!
      @lock.synchronize do
        @rooms = Hash.new { |rooms, room_id| rooms[room_id] = [] }
        @last_id = 0
      end
    end

    def for(room_id) = @lock.synchronize { @rooms[room_id].dup }

    def add(room_id, text)
      @lock.synchronize do
        { 'id' => @last_id += 1, 'text' => text }.tap { |message| @rooms[room_id] << message }
      end
    end

    def broadcast(room_id, message) = ActionCable.server.broadcast("lobby_#{room_id}", message)
  end

  reset!
end
