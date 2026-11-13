# frozen_string_literal: true

module Live
  class SharingParent < LiveCable::Component
    reactive :todos, -> { [{ id: 1, done: false }, { id: 2, done: false }] }
    reactive :lists, ->(component) { { all: component.todos } }

    actions :add, :finish_first

    def add
      todos << { id: todos.size + 1, done: false }
    end

    def finish_first
      todos.first[:done] = true
    end

    def ends = [todos.first, todos.last]
  end
end
