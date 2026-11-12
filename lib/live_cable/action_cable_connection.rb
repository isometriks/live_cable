# frozen_string_literal: true

module LiveCable
  # Prepended to ActionCable::Connection::Base by the engine, so every socket
  # carries its LiveCable::Connection without the application declaring
  # anything.
  #
  # Deliberately not an identifier. The identified_by values make up a
  # connection's identity, which remote_connections.where(...) has to match in
  # full to disconnect a socket, and a per-socket object can never be named
  # there. Keeping LiveCable off the identifiers leaves that mechanism working
  # for the application's own, such as current_user.
  module ActionCableConnection
    LOCK = Mutex.new

    def initialize(...)
      super
      @live_commands = Thread::Queue.new
      @live_commands_lock = Mutex.new
    end

    # @return [LiveCable::Connection]
    def live_connection
      # A socket's subscribes run as concurrent jobs on ActionCable's worker pool
      @live_connection || LOCK.synchronize { @live_connection ||= LiveCable::Connection.new(request) }
    end

    # Called in the order the client sent, on the thread reading the socket;
    # the pool jobs start in any order, so each runs the oldest frame queued.
    def receive(websocket_message)
      return super unless live_channel_command?(websocket_message)

      @live_commands << websocket_message
      send_async :dispatch_live_command
    end

    private

    def dispatch_live_command
      @live_commands_lock.synchronize { dispatch_websocket_message(@live_commands.pop) }
    end

    def live_channel_command?(websocket_message)
      return false unless websocket_message.include?('LiveChannel')

      ActiveSupport::JSON.decode(decode(websocket_message)['identifier'])['channel'] == 'LiveChannel'
    rescue StandardError
      false
    end
  end
end
