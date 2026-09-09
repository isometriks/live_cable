# frozen_string_literal: true

module LiveCable
  # Mixed into ActionCable::Connection::Base by the engine, so every socket
  # carries its LiveCable::Connection without the application declaring
  # anything.
  #
  # Deliberately not an identifier. The identified_by values make up a
  # connection's identity, which remote_connections.where(...) has to match in
  # full to disconnect a socket, and a per-socket object can never be named
  # there. Keeping LiveCable off the identifiers leaves that mechanism working
  # for the application's own, such as current_user.
  module ActionCableConnection
    # @return [LiveCable::Connection]
    def live_connection
      @live_connection ||= LiveCable::Connection.new(request)
    end
  end
end
