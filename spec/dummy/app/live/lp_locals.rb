# frozen_string_literal: true

module Live
  class LpLocals < LiveCable::Component
    reactive :tone, -> { 'comp' }
  end
end
