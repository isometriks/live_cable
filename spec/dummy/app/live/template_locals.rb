# frozen_string_literal: true

module Live
  class TemplateLocals < LiveCable::Component
    reactive :flagged, -> { false }
    reactive :counts, -> { [1, 2, 3] }
    reactive :messages, -> { [{ body: 'Hello', css: 'message' }] }

    actions :flag, :add_count

    def flag
      self.flagged = true
    end

    def add_count
      self.counts = counts + [4]
    end

    def css
      'message-list'
    end
  end
end
