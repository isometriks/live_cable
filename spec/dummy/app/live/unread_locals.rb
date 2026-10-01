# frozen_string_literal: true

module Live
  class UnreadLocals < LiveCable::Component
    reactive :filter, -> { '' }
    reactive :items, -> { %w[a b] }
    reactive :admin, -> { false }

    actions :type

    def type
      self.filter += 'x'
    end
  end
end
