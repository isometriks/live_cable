# frozen_string_literal: true

module Live
  class LpDynamic < LiveCable::Component
    reactive :path, -> { 'shared/live_card' }
  end
end
