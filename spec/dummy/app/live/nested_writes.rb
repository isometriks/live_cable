# frozen_string_literal: true

module Live
  class NestedWrites < LiveCable::Component
    reactive :todos, -> { [{ id: 1, done: false }, { id: 2, done: false }] }
    reactive :lists, -> { { open: [], done: [] } }
    reactive :tags, -> { %w[ruby] }

    actions :finish_first, :add_to_lists, :append_tag

    def finish_first
      todos.detect { |todo| todo[:id] == 1 }[:done] = true
    end

    def add_to_lists
      lists.each { |name, list| list << name }
    end

    def append_tag
      tags.append('rails')
    end
  end
end
