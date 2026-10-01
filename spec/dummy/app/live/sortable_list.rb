# frozen_string_literal: true

module Live
  class SortableList < LiveCable::Component
    reactive :order, -> { %w[one two three] }, shared: true
  end
end
