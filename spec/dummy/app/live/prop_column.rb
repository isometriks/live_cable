# frozen_string_literal: true

module Live
  class PropColumn < LiveCable::Component
    reactive :column, -> { {} }
  end
end
