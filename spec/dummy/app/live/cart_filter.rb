# frozen_string_literal: true

module Live
  class CartFilter < LiveCable::Component
    shared :cart_items, -> { [] }
    reactive :filter, -> { 'all' }

    actions :set_filter, :add_and_filter, :add_only

    def set_filter
      self.filter = 'recent'
    end

    def add_and_filter
      cart_items << 'own'
      self.filter = 'own'
    end

    def add_only
      cart_items << 'quiet'
    end

    def badge_count
      cart_items.size
    end
  end
end
