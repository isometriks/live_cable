# frozen_string_literal: true

module Live
  class LpRows < LiveCable::Component
    reactive :todos, -> { [{ 'id' => 1, 'title' => 'Milk' }, { 'id' => 2, 'title' => 'Eggs' }] }
    reactive :heading, -> { 'Todos' }

    actions :add, :rename_first, :retitle

    def add = todos << { 'id' => todos.size + 1, 'title' => 'Bread' }
    def rename_first = self.todos = [todos[0].to_h.merge('title' => 'Oat milk'), *todos.to_a.drop(1)]
    def retitle = self.heading = 'Chores'
  end
end
