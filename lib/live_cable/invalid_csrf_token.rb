# frozen_string_literal: true

module LiveCable
  # Raised when a message's CSRF token cannot be verified against the session
  # the connection captured at its WebSocket handshake.
  class InvalidCsrfToken < Error; end
end
