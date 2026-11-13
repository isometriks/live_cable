# frozen_string_literal: true

module Live
  class TagChip < LiveCable::Component
    reactive :label, -> { '' }
    reactive :hidden, -> { false }

    before_render { throw :abort if hidden }
  end
end
