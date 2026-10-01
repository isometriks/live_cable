# frozen_string_literal: true

module Live
  class SortableItem < LiveCable::Component
    reactive :order, -> { %w[one two three] }, shared: true

    actions :to_top

    def to_top(params)
      sleep 0.3
      order.unshift(order.delete_at(params[:from].to_i - 1))
    end
  end
end
