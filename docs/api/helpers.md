# View Helpers

LiveCable provides view helpers for rendering components and their markup.

## `live`

Renders a live component in a view.

**Signature:**
```ruby
live(component_name, id:, **defaults)
```

**Parameters:**
- `component_name` (String) - Component path (e.g., `'counter'`, `'chat/room'`)
- `id` (String) - Unique identifier for the component instance
- `**defaults` (Hash) - Default values for reactive variables

**Returns:** String (HTML)

### Examples

**Simple usage:**
```erb
<%= live('counter', id: 'my-counter') %>
```

**With default values:**
```erb
<%= live('counter', id: 'header-counter', count: 10) %>
```

**Namespaced components:**
```erb
<%= live('chat/room', id: "room-#{@room.id}", room_id: @room.id) %>
```

### Rendering Component Instances

If you already have a component instance, use `render` directly instead:

```erb
<%
  @counter = Live::Counter.new('my-counter', count: 10)
%>
<%= render(@counter) %>
```

### Component Resolution

The helper converts string paths to component classes:
- `'counter'` → `Live::Counter`
- `'chat/room'` → `Live::Chat::Room`
- `'admin/dashboard'` → `Live::Admin::Dashboard`

### Default Values

Default values are only applied when the component is first created:

```erb
<%# First render: count will be 10 %>
<%= live('counter', id: 'my-counter', count: 10) %>

<%# After user navigates away and back: count retains its current value %>
<%= live('counter', id: 'my-counter', count: 10) %>
```

## Component Rendering

Component partials should start with a root element. LiveCable automatically injects the required attributes (`live-id`, `live-component`, `live-actions`, and `live-defaults`) into your root element and transforms them into Stimulus attributes.

### Basic Template Structure

```erb
<%# app/views/live/counter/component.html.erb %>
<div>
  <h2>Counter: <%= count %></h2>
  <button live-action="increment">+</button>
  <button live-action="decrement">-</button>
</div>
```

The root `<div>` will automatically receive:
- `live-id` - The component's unique ID
- `live-component` - The component class string
- `live-actions` - JSON array of whitelisted actions
- `live-defaults` - JSON object of default values (on first render only)

These attributes are then transformed by the DOM observer into Stimulus data attributes before the component connects.

### Adding Custom Attributes

You can add any HTML attributes to your root element:

```erb
<div class="card p-4 shadow-lg" data-controller="dropdown">
  <h2>Counter: <%= count %></h2>
</div>
```

### Multiple Stimulus Controllers

The LiveCable Stimulus controller is automatically added. You can combine it with other controllers:

```erb
<div data-controller="sortable dropdown">
  <%# This will have data-controller="live sortable dropdown" after transformation %>
  <ul>
    <% items.each do |item| %>
      <li><span class="drag-handle">⋮</span> <%= item.name %></li>
    <% end %>
  </ul>
</div>
```

## Template Variables

### Accessing Reactive Variables

Reactive variables are automatically available as local variables in your component templates:

```erb
<div>
  <p>Count: <%= count %></p>
  <p>Message: <%= message %></p>
  <p>Items: <%= items.size %></p>
</div>
```

### Accessing Connection Identifiers

Connection identifiers (like `current_user`) are also available:

```erb
<div>
  <p>Welcome, <%= current_user.name %></p>
</div>
```

### The `component` Local

The `component` variable gives you access to the component instance itself:

```erb
<div>
  <p>Component ID: <%= component.live_id %></p>
  <p>Component class: <%= component.class.name %></p>
</div>
```

You can use `component` to call methods for memory-efficient data fetching. See the [memory efficiency section](/guide/reactive-variables#using-the-component-local-for-memory-efficiency) in the reactive variables guide.

## HTML Attributes Reference

### `live-ignore`

Prevents LiveCable from updating an element and its children during re-renders.

**Usage:**
```erb
<div live-ignore>
  <%# This content won't be updated by LiveCable %>
  <iframe src="https://example.com"></iframe>
</div>
```

**Use cases:**
- Embedding iframes or third-party widgets
- Preserving manually manipulated DOM
- Preventing updates to specific sections

**Note:** Live component wrappers automatically have `live-ignore` to prevent parent components from overwriting child components.

### `live-key`

Provides identity hints for list items to preserve DOM elements during reordering.

**Usage:**
```erb
<ul>
  <% items.each do |item| %>
    <li live-key="<%= item.id %>">
      <%= item.name %>
    </li>
  <% end %>
</ul>
```

**When to use:**
- Lists that can be reordered
- Dynamic lists where items can be added/removed
- When you want to preserve input focus or other element state

**Best practices:**
- Use stable identifiers (database IDs, UUIDs)
- Don't use array indices
- Ensure keys are unique within the parent element

## Custom Attributes Reference

LiveCable provides several custom HTML attributes that are automatically transformed into Stimulus attributes.

### `live-action`

Triggers a component action when an event occurs.

**Syntax:**
- `live-action="action_name"` - Uses default event
- `live-action="event->action_name"` - Custom event
- `live-action="event1->action1 event2->action2"` - Multiple actions

**Example:**
```erb
<button live-action="increment">+</button>
<button live-action="mouseover->highlight">Hover</button>
```

### `live-form`

Serializes and submits a form to a component action.

**Syntax:**
- `live-form="action_name"` - Uses submit event
- `live-form="event->action_name"` - Custom event

**Example:**
```erb
<form live-form="save">
  <input type="text" name="title">
  <button type="submit">Save</button>
</form>
```

### `live-reactive`

Updates a reactive variable when an input changes.

**Syntax:**
- `live-reactive` - Uses default event (input)
- `live-reactive="event"` - Custom event

**Example:**
```erb
<input type="text" name="search" live-reactive>
<input type="text" name="query" live-reactive="keydown">
```

### `live-value-*`

Passes parameters to actions.

**Syntax:** `live-value-param-name="value"`

**Example:**
```erb
<button live-action="delete" live-value-id="<%= item.id %>">Delete</button>
```

### `live-debounce`

Adds debouncing to reactive/form updates.

**Syntax:** `live-debounce="milliseconds"`

**Example:**
```erb
<input type="text" name="search" live-reactive live-debounce="300">
```

For complete documentation, see [Actions & Events](/guide/actions-events).

## Next Steps

- [Component API](/api/component)
- [Learn about components](/guide/components)
- [Learn about actions](/guide/actions-events)
