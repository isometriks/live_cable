# frozen_string_literal: true

module Live
  class SameNameDefs < LiveCable::Component
    reactive :count, -> { 0 }

    actions :increment

    def increment
      self.count += 1
    end

    def title
      "title=#{count}"
    end

    def self.title
      'class-level'
    end
  end
end
