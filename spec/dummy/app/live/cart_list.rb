# frozen_string_literal: true

module Live
  class CartList < LiveCable::Component
    reactive :cart_items, -> { [] }, shared: true

    actions :add_item

    def add_item
      cart_items << 'item'
    end
  end
end
