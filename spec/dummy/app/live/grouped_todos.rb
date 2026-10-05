# frozen_string_literal: true

module Live
  class GroupedTodos < LiveCable::Component
    reactive :todos, -> { [{ id: 1, status: 'open', classes: %w[a b] }, { id: 2, status: 'done', classes: %w[c] }] }
    reactive :settings, -> { { theme: { classes: %w[dark wide] } } }

    def rows = todos.each_slice(2).to_a
    def by_status = todos.each_with_object({}) { |todo, groups| (groups[todo[:status]] ||= []) << todo }
    def themes = settings.each_value.to_a
    def ends = [todos.first, todos.last]
    def settings_kind = LiveCable::Delegator.unwrap(settings).class.name
  end
end
