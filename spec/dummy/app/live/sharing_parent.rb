# frozen_string_literal: true

module Live
  class SharingParent < LiveCable::Component
    reactive :todos, -> { [{ id: 1, done: false }, { id: 2, done: false }] }
  end
end
