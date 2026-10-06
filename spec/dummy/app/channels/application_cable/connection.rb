# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # LiveCable needs no identifier; this one exists so system specs can
    # exercise remote disconnection and identity changes. /sign_in sets the
    # cookie; without it every socket belongs to the same guest.
    def connect
      self.current_user = cookies[:dummy_user].presence || 'guest'
    end
  end
end
