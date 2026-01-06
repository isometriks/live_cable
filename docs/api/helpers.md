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

## `live_component`

Wraps component content with necessary Stimulus attributes and setup.

**Signature:**
```ruby
live_component(**html_options, &block)
```

**Parameters:**
- `**html_options` (Hash) - HTML attributes for the wrapper div
- `&block` - Content block to render

**Returns:** String (HTML)

### Examples

**Basic usage:**
```erb
<%= live_component do %>
  <h2>Counter: <%= count %></h2>
  <button <%= live_action(:increment) %>>+</button>
<% end %>
```

**With CSS classes:**
```erb
<%= live_component(class: "card p-4 shadow-lg") do %>
  <h2>Counter: <%= count %></h2>
<% end %>
```

**With additional Stimulus controllers:**
```erb
<%= live_component(data: { controller: "dropdown tooltip" }) do %>
  <%# Renders as: data-controller="live dropdown tooltip" %>
  <h2>Counter: <%= count %></h2>
<% end %>
```

**With ARIA attributes:**
```erb
<%= live_component(id: "my-counter",
                   aria: { label: "Counter widget", live: "polite" }) do %>
  <h2>Counter: <%= count %></h2>
<% end %>
```

**With custom data attributes:**
```erb
<%= live_component(data: {
                     controller: "sortable",
                     sortable_handle_value: ".drag-handle"
                   }) do %>
  <ul>
    <% items.each do |item| %>
      <li><span class="drag-handle">⋮</span> <%= item.name %></li>
    <% end %>
  </ul>
<% end %>
```

### HTML Attributes

The wrapper div receives:
- All `html_options` as HTML attributes
- `data-controller` with "live" prepended
- `data-live-id-value` with the component ID
- `data-live-component-value` with the component string

### Controller Appending

When passing `data: { controller: "..." }`, the controller name is **appended** to "live":

```erb
<%# Input %>
<%= live_component(data: { controller: "dropdown" }) do %>
  ...
<% end %>

<%# Output %>
<div data-controller="live dropdown" ...>
  ...
</div>
```

This allows you to combine LiveCable with other Stimulus controllers on the same element.

## `live_action`

Generates Stimulus action attributes for calling component actions.

**Signature:**
```ruby
live_action(action, event = nil)
```

**Parameters:**
- `action` (Symbol) - The name of the component action to call
- `event` (Symbol, optional) - The DOM event to bind to. If omitted, uses Stimulus default events (click for buttons, submit for forms, etc.)

**Returns:** String (HTML attributes)

### Examples

**Default event (click for buttons):**
```erb
<button <%= live_action(:save) %>>Save</button>
<!-- Generates: data-action='live#call' data-live-action-param='save' -->
```

**Custom event:**
```erb
<input <%= live_action(:search, :input) %> />
<!-- Generates: data-action='input->live#call' data-live-action-param='search' -->
```

**On forms (submit event):**
```erb
<form <%= live_action(:submit, :submit) %>>
  <input type="text" name="title">
  <button type="submit">Submit</button>
</form>
```

**With additional parameters:**
```erb
<button <%= live_action(:delete) %> data-live-id-param="<%= item.id %>">
  Delete
</button>
```

### Benefits

The `live_action` helper reduces boilerplate and makes your templates cleaner compared to manually writing data attributes:

```erb
<!-- With live_action helper -->
<button <%= live_action(:increment) %>>+</button>

<!-- Without helper (manual) -->
<button data-action="live#call" data-live-action-param="increment">+</button>
```

## Helper Usage in Components

### Accessing Reactive Variables

Reactive variables are automatically available as local variables in your views:

```erb
<%= live_component do %>
  <p>Count: <%= count %></p>
  <p>Message: <%= message %></p>
  <p>Items: <%= items.size %></p>
<% end %>
```

### Accessing Connection Identifiers

Connection identifiers (like `current_user`) are also available:

```erb
<%= live_component do %>
  <p>Welcome, <%= current_user.name %></p>
<% end %>
```

### Special Variables

These variables are always available:
- `component` - The component instance itself

```erb
<%= live_component do %>
  <p>Component ID: <%= component.live_id %></p>
  <p>Component class: <%= component.class.name %></p>
<% end %>
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

## Integration with Rails Helpers

LiveCable helpers work seamlessly with Rails view helpers:

```erb
<%= live_component(class: "mb-4") do %>
  <%= form_with model: @user, data: { action: "submit->live#form:prevent", 
                                       live_action_param: "save" } do |form| %>
    <%= form.text_field :name, class: "form-control" %>
    <%= form.submit "Save", class: "btn btn-primary" %>
  <% end %>
<% end %>
```

## Next Steps

- [Component API](/api/component)
- [Learn about components](/guide/components)
- [Learn about actions](/guide/actions-events)
