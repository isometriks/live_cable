# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # LiveCable needs no identifier; this one exists so a system spec can
    # exercise remote disconnection. There is no sign-in, so every socket
    # belongs to the same guest.
    def connect
      self.current_user = 'guest'
    end
  end
end
