# Components

Components are the core building blocks of LiveCable applications. They encapsulate server-side state, behavior, and rendering logic.

## Component Structure

A LiveCable component consists of two parts:

1. **Component Class** - Ruby class that defines state and behavior
2. **Component View** - ERB template that renders the component

## Creating Components

### Using the Generator

The easiest way to create a component is using the generator:

```bash
bin/rails generate live_cable:component Counter count:integer
```

This generates:

```ruby
# app/live/counter.rb
module Live
  class Counter < LiveCable::Component
    reactive :count, -> { 0 }

    actions # Add your action methods here

    # Lifecycle callbacks (optional)
    # before_connect :setup
    # after_connect :log_connection
    # before_render :prepare_data
    # after_render :track_render

    private
    #
    # def setup
    #   # Called before connection
    # end
  end
end
```

```erb
<%# app/views/live/counter/component.html.erb %>
<div>
  <h2>Counter</h2>
  <p>Count: <%= count %></p>

  <%# Add your component markup here %>
</div>
```

### Manual Creation

You can also create components manually:

**Component Class** (`app/live/todo_list.rb`):
```ruby
module Live
  class TodoList < LiveCable::Component
    reactive :todos, -> { [] }
    reactive :new_todo, -> { "" }
    
    actions :add_todo, :remove_todo, :toggle_todo
    
    def add_todo(params)
      return if new_todo.blank?
      
      todos << {
        id: SecureRandom.uuid,
        text: new_todo,
        completed: false
      }
      self.new_todo = ""
    end
    
    def remove_todo(params)
      todos.reject! { |todo| todo[:id] == params[:id] }
    end
    
    def toggle_todo(params)
      todo = todos.find { |t| t[:id] == params[:id] }
      todo[:completed] = !todo[:completed] if todo
    end
  end
end
```

**Component View** (`app/views/live/todo_list/component.html.erb`):
```erb
<div class="todo-list">
  <h2>My Todos</h2>

  <form live-form="add_todo">
    <input type="text" name="new_todo" value="<%= new_todo %>" live-reactive>
    <button type="submit">Add</button>
  </form>

  <ul>
    <% todos.each do |todo| %>
      <li live-key="<%= todo[:id] %>">
        <input type="checkbox"
               <%= 'checked' if todo[:completed] %>
               live-action="change->toggle_todo"
               live-value-id="<%= todo[:id] %>">
        <span class="<%= 'completed' if todo[:completed] %>">
          <%= todo[:text] %>
        </span>
        <button live-action="remove_todo"
                live-value-id="<%= todo[:id] %>">
          Delete
        </button>
      </li>
    <% end %>
  </ul>
</div>
```

## Component Locations

::: info Component Namespacing
All LiveCable components **must** be defined inside the `Live::` module so they can be safely loaded from a string name.
:::

- Component classes go in `app/live/` (e.g., `Live::Counter` → `app/live/counter.rb`)
- Views go in `app/views/live/` (e.g., `app/views/live/counter.html.erb`)
- For namespaced components: `Live::Chat::Message` → `app/live/chat/message.rb` and `app/views/live/chat/message.html.erb`

## Rendering Components

### Basic Rendering

Use the `live` helper to render a component:

```erb
<%# Simple usage %>
<%= live('counter', id: 'my-counter') %>

<%# With default values %>
<%= live('counter', id: 'my-counter', count: 10) %>
```

### Component IDs

Each component instance needs a unique ID. The ID is used to:
- Persist component state across page navigations
- Maintain WebSocket connections
- Identify components for ActionCable streams

```erb
<%# Unique IDs for multiple instances %>
<%= live('counter', id: 'header-counter') %>
<%= live('counter', id: 'sidebar-counter') %>
```

### Rendering Component Instances Directly

If you already have a component instance, use `render` directly:

```erb
<%
  @counter = Live::Counter.new('my-counter', count: 10)
%>
<%= render(@counter) %>
```

### Component Templates

Component templates should start with a root element. LiveCable automatically injects the required attributes into your root element:

```erb
<div>
  <!-- Your component HTML here -->
</div>
```

The root element automatically receives:
- `live-id` - The component's unique ID
- `live-component` - The component class string
- `live-actions` - JSON array of whitelisted actions
- `live-defaults` - JSON object of default values (first render only)

You can add any HTML attributes to your root element:

```erb
<%# With CSS classes %>
<div class="p-4 bg-white rounded-lg shadow">
  <h2>Counter: <%= count %></h2>
</div>

<%# With additional Stimulus controllers %>
<div data-controller="dropdown">
  <%# This will have data-controller="live dropdown" after transformation %>
</div>

<%# With any HTML attributes %>
<div id="my-counter" class="flex items-center"
     aria-label="Counter widget">
  <h2>Counter: <%= count %></h2>
</div>
```

::: info Automatic Controller Addition
The LiveCable Stimulus controller is automatically added to the root element. If you specify `data-controller="dropdown"`, it becomes `data-controller="live dropdown"`.
:::

## Next Steps

- [Learn about reactive variables](/guide/reactive-variables)
- [Handle actions and events](/guide/actions-events)
- [Use lifecycle callbacks](/guide/lifecycle-callbacks)
- [Create compound components](/guide/compound-components)
