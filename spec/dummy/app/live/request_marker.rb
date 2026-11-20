# frozen_string_literal: true

module Live
  class RequestMarker < LiveCable::Component
    reactive :count, -> { 0 }

    actions :bump

    def bump
      self.count += 1
    end
  end
end
