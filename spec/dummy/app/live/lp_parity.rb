# frozen_string_literal: true

module Live
  class LpParity < LiveCable::Component
    reactive :title, -> { 'A & <B>' }
    reactive :count, -> { 2 }

    actions :bump

    def bump = self.count = count + 1
  end
end
