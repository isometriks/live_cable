# Components

Components are the core building blocks of LiveCable applications. They encapsulate server-side state, behavior, and rendering logic.

## Component Structure

A LiveCable component consists of two parts:

1. **Component Class** - Ruby class that defines state and behavior
2. **Component View** - ERB template that renders the component

## Creating Components

::: tip Generator
You can scaffold components quickly with the built-in generator: `bin/rails generate live_cable:component NAME`. See [Generators](/guide/generators) for details.
:::

**Component Class** (`app/live/todo_list.rb`):
```ruby
module Live
  class TodoList < LiveCable::Component
    reactive :todos, -> { [] }
    reactive :new_todo, -> { "" }

    actions :add_todo, :remove_todo, :toggle_todo

    def add_todo(params)
      return if params[:text].blank?

      todos << {
        id: SecureRandom.uuid,
        text: params[:text],
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

**Component View** (`app/views/live/todo_list.html.live.erb`):
```erb
<div class="todo-list">
  <h2>My Todos</h2>

  <form live-form="add_todo">
    <input type="text" name="text" value="<%= new_todo %>" placeholder="What needs to be done?">
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
- Views go in `app/views/live/` (e.g., `app/views/live/counter.html.live.erb`)
- For namespaced components: `Live::Chat::Message` → `app/live/chat/message.rb` and `app/views/live/chat/message.html.live.erb`

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

Each component instance needs an ID that is unique within its component type. The ID is combined with the component name to form the `live_id` (e.g., `"counter/my-counter"`), so the same ID can be safely reused across different component types without collisions.

The ID is used to:
- Identify the component's ActionCable stream
- Maintain WebSocket connections across Stimulus reconnects

```erb
<%# Unique IDs within the same component type %>
<%= live('counter', id: 'header-counter') %>
<%= live('counter', id: 'sidebar-counter') %>

<%# Same ID is fine across different component types %>
<%= live('counter', id: 'main') %>
<%= live('todo_list', id: 'main') %>
```

You can also pass an ActiveRecord model as the `id`, which will be converted using `dom_id`:

```erb
<%# These are equivalent %>
<%= live('chat/room', id: @room) %>
<%= live('chat/room', id: dom_id(@room)) %>
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

Component templates must start with a root element — LiveCable raises an error at render time if no opening tag is found. It automatically injects the required attributes into that root element:

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
