# frozen_string_literal: true

module Live
  class KanbanBoard < LiveCable::Component
    reactive :todos, -> { [{ id: 1 }, { id: 2 }] }
    reactive :done, -> { [] }

    actions :finish

    def finish
      todo = todos.find { |t| t[:id] == 1 }
      done << todo
      todos.delete(todo)
    end
  end
end
