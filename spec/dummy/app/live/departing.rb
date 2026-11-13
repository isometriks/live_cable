# frozen_string_literal: true

module Live
  class Departing < LiveCable::Component
    DISCONNECTED = Concurrent::Array.new

    reactive :count, -> { 0 }
    reactive :nested, -> { false }

    actions :increment

    after_disconnect { DISCONNECTED << live_id }

    def increment
      self.count += 1
    end
  end
end
