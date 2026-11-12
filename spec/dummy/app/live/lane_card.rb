# frozen_string_literal: true

module Live
  class LaneCard < LiveCable::Component
    reactive :card, -> { {} }
    reactive :notes, -> { 0 }

    actions :note, :advance

    def note
      self.notes += 1
    end

    def advance
      card[:lane] = card[:lane] == 'todo' ? 'doing' : 'todo'
    end
  end
end
