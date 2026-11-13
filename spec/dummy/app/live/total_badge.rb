# frozen_string_literal: true

module Live
  class TotalBadge < LiveCable::Component
    reactive :total, -> { 0 }, shared: true
  end
end
