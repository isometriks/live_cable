# frozen_string_literal: true

module Live
  class PropCards < LiveCable::Component
    reactive :cards, -> { [] }
  end
end
