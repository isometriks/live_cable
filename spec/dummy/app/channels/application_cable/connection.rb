# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :live_connection

    def connect
      self.live_connection = LiveCable::Connection.new(request)
    end
  end
end
