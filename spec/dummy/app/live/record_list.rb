# frozen_string_literal: true

module Live
  class RecordList < LiveCable::Component
    reactive :todos, -> { RecordTodo.order(:id).to_a }

    actions :finish_first

    def finish_first
      todos.first.reload.update!(done: true)
    end
  end
end
