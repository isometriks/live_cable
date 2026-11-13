# frozen_string_literal: true

module Live
  class KanbanCard < LiveCable::Component
    reactive :todo, -> { {} }

    actions :star

    def star
      todo[:starred] = true
    end
  end
end
