# frozen_string_literal: true

module Live
  class ContentForHeading < LiveCable::Component
    reactive :label, -> { 'Inbox' }
    reactive :count, -> { 0 }

    actions :increment, :rename

    def increment
      self.count += 1
    end

    def rename
      self.label = 'Outbox'
    end
  end
end
