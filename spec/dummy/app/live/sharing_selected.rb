# frozen_string_literal: true

module Live
  class SharingSelected < LiveCable::Component
    reactive :todos, -> { [{ id: 1, done: false }, { id: 2, done: false }] }
    reactive :selected, ->(component) { component.todos.to_a.first }
    reactive :aliased, ->(component) { component.todos.to_a }
  end
end
