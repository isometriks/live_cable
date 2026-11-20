# frozen_string_literal: true

module Live
  class CommentTextLed < LiveCable::Component
    reactive :count, -> { 0 }

    actions :increment

    def increment
      self.count += 1
    end
  end
end
