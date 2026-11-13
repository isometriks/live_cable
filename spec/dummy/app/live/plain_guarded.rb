# frozen_string_literal: true

module Live
  class PlainGuarded < LiveCable::Component
    reactive :blocked, -> { false }, shared: true
    reactive :count, -> { 0 }

    actions :increment

    def increment
      self.count += 1
    end

    before_render { throw :abort if blocked }
  end
end
