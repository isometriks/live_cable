# frozen_string_literal: true

module Live
  class GatedChild < LiveCable::Component
    reactive :open, -> { false }, shared: true
    reactive :label, -> { '' }

    before_render { throw :abort unless open }
  end
end
