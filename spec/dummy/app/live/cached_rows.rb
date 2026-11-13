# frozen_string_literal: true

module Live
  class CachedRows < LiveCable::Component
    reactive :rows, -> { %w[a b] }

    actions :add

    def add
      rows << 'c'
    end
  end
end
