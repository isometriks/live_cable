# frozen_string_literal: true

module Live
  class LockProbe < LiveCable::Component
    attr_reader :locked_on_connect

    after_connect { @locked_on_connect = live_connection.synchronized? }
  end
end
