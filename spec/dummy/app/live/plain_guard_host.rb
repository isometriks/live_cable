# frozen_string_literal: true

module Live
  class PlainGuardHost < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :blocked, -> { false }, shared: true

    actions :block

    def block
      self.blocked = true
      self.count += 1
    end
  end
end
