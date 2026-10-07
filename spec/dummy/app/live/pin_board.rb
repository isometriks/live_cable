# frozen_string_literal: true

module Live
  class PinBoard < LiveCable::Component
    reactive :todos, -> { [{ id: 1 }, { id: 2 }] }
    reactive :pinned, -> { [] }

    actions :pin

    def pin
      pinned << todos.find { |todo| todo[:id] == 1 }
    end
  end
end
