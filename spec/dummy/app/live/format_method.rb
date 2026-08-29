# frozen_string_literal: true

module Live
  class FormatMethod < LiveCable::Component
    reactive :count, -> { 0 }

    actions :bump

    def bump
      self.count += 1
    end

    def format
      'long'
    end
  end
end
