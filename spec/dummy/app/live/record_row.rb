# frozen_string_literal: true

module Live
  class RecordRow < LiveCable::Component
    reactive :todo

    actions :finish

    def finish
      todo.reload.update!(done: true)
    end
  end
end
