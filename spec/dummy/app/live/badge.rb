# frozen_string_literal: true

module Live
  class Badge < LiveCable::Component
    reactive :label, -> { '' }
  end
end
