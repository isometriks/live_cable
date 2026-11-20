# frozen_string_literal: true

module Live
  class ReplyParent < LiveCable::Component
    reactive :hidden, -> { [] }, shared: true
    reactive :tick, -> { 0 }, shared: true
    reactive :explode, -> { false }, shared: true
    reactive :own, -> { 0 }

    actions :bump_own

    def bump_own
      self.own += 1
    end
  end
end
