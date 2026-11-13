# frozen_string_literal: true

module Live
  class Shorthand < LiveCable::Component
    reactive :count, -> { 1 }

    actions :increment

    def increment
      self.count += 1
    end
  end
end
