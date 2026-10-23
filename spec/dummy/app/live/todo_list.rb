# frozen_string_literal: true

module Live
  # A todo list whose markup is mostly control blocks: an empty state, a keyed
  # loop, and a branch per row. Used to exercise structured parts.
  class TodoList < LiveCable::Component
    reactive :todos, -> { [] }
    reactive :filter, -> { 'all' }
    reactive :next_id, -> { 1 }

    actions :add, :toggle, :rename, :remove, :show, :clear_done

    def add(params)
      todos.unshift({ 'id' => next_id, 'title' => params[:title].to_s, 'done' => false })
      self.next_id += 1
    end

    def toggle(params)
      todo = find(params[:id])
      todo['done'] = !todo['done']
    end

    def rename(params)
      find(params[:id])['title'] = params[:title].to_s
    end

    def remove(params)
      todos.reject! { |todo| todo['id'] == params[:id].to_i }
    end

    def show(params)
      self.filter = params[:filter].to_s
    end

    def clear_done
      todos.reject! { |todo| todo['done'] }
    end

    def visible_todos
      case filter
      when 'active' then todos.reject { |todo| todo['done'] }
      when 'done' then todos.select { |todo| todo['done'] }
      else todos
      end
    end

    def remaining
      todos.count { |todo| !todo['done'] }
    end

    private

    def find(id)
      todos.find { |todo| todo['id'] == id.to_i }
    end
  end
end
