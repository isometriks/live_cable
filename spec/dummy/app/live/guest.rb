# frozen_string_literal: true

module Live
  class Guest < LiveCable::Component
    reactive :pings, -> { 0 }
    reactive :revoked, -> { false }

    actions :ping, :leave

    before_connect { throw :abort if id == 'barred' }

    def ping
      self.pings += 1
    end

    def leave
      refuse!('left')
    end
  end
end
