# frozen_string_literal: true

module Live
  class Lanes < LiveCable::Component
    reactive :cards, lambda {
      [
        { id: 1, title: 'A', lane: 'todo' },
        { id: 2, title: 'B', lane: 'todo' },
        { id: 3, title: 'C', lane: 'doing' },
      ]
    }, shared: true
  end
end
