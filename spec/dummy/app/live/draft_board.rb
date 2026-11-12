# frozen_string_literal: true

module Live
  class DraftBoard < LiveCable::Component
    reactive :todos, -> { [{ id: 1, classes: %w[a b] }, { id: 2, classes: %w[c] }] }
    reactive :draft, -> { { id: 1, classes: %w[d e] } }

    actions :save_draft

    def save_draft
      todos.map! { |todo| todo[:id] == draft[:id] ? draft : todo }
    end
  end
end
