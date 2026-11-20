# frozen_string_literal: true

module Live
  # Renders a guest per id, for refusals inside a parent's render
  class GuestList < LiveCable::Component
    reactive :guests, -> { %w[a b] }
    reactive :ticks, -> { 0 }
    reactive :gone, -> { false }

    actions :tick, :revoke, :close, :drop, :restore

    def tick
      self.ticks += 1
    end

    def revoke(params)
      guest(params[:id]).revoked = true
      dirty(:guests)
    end

    def close
      guest('a').pings += 1
      self.ticks += 1
      self.gone = true
    end

    def drop(params)
      self.guests = guests.to_a - [params[:id]]
    end

    def restore(params)
      self.guests = guests.to_a | [params[:id]]
    end

    private

    def guest(id)
      live_connection.get_component("guest/#{id}")
    end
  end
end
