# frozen_string_literal: true

module Live
  class UnreadLocals < LiveCable::Component
    reactive :filter, -> { '' }
    reactive :items, -> { %w[a b] }
    reactive :admin, -> { false }
    reactive :hidden, -> { 0 }

    actions :type, :bump_hidden

    def type
      self.filter += 'x'
    end

    def bump_hidden
      self.hidden += 1
    end
  end
end
