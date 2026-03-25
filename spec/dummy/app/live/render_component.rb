# frozen_string_literal: true

module Live
  class RenderComponent < LiveCable::Component
    reactive :count, -> { 1 }

    actions :increment

    def badge
      Live::Badge.new('badge', label: "Count: #{count}")
    end

    def increment
      self.count += 1
    end
  end
end
