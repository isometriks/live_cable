# frozen_string_literal: true

module Live
  class TodoList < LiveCable::Component
    reactive :done, -> { [] }, shared: true

    def todos
      %w[write test ship]
    end
  end
end
