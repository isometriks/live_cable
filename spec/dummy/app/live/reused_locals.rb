# frozen_string_literal: true

module Live
  class ReusedLocals < LiveCable::Component
    reactive :filter, -> { '' }
    reactive :items, -> { %w[a b] }
    reactive :tags, -> { %w[x] }
    reactive :admin, -> { false }
    reactive :owner, -> { false }

    actions :type

    def type
      self.filter += 'x'
    end
  end
end
