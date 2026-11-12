# frozen_string_literal: true

module Live
  class Guest < LiveCable::Component
    reactive :pings, -> { 0 }
    reactive :revoked, -> { false }

    actions :ping, :leave

    def ping
      self.pings += 1
    end

    def leave
      refuse!('left')
    end
  end
end
