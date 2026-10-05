# frozen_string_literal: true

module Live
  class SharingList < LiveCable::Component
    reactive :todos, -> { [] }

    actions :add, :finish_first

    def add
      todos << { id: todos.size + 1, done: false }
    end

    def finish_first
      todos.first[:done] = true
    end
  end
end
