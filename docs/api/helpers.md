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
- `id` (String, ActiveRecord model) - Identifier for the component instance, unique within the component type. If an ActiveRecord model is passed, it is converted using `dom_id`. It can be built from user input: it is escaped wherever it goes into the page. Keep slashes out of such an id, since defaults are bound to the component name and id joined by a slash (see [Components](/guide/components))
- `**defaults` (Hash) - Default values for reactive variables. A top-level component's defaults are signed into the page as JSON, so pass JSON-safe values and no secrets. Passing it a record, or any other object that isn't JSON-native, raises `ArgumentError`; pass the record's id

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

**With an ActiveRecord model:**
```erb
<%= live('chat/room', id: @room, room_id: @room.id) %>
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

Default values are only applied when the component is first created. If the parent component re-renders and passes the same defaults again, the component's current state is left untouched:

```erb
<%# First render: count starts at 10 %>
<%= live('counter', id: 'my-counter', count: 10) %>

<%# Parent re-renders (e.g. a reactive variable changed): count keeps its current value, not reset to 10 %>
<%= live('counter', id: 'my-counter', count: 10) %>
```

A Turbo visit, frame navigation or stream action that renders the component with *different* defaults is the exception: the component, and the children it renders, are built again from the new defaults. See [Subscription Persistence](/guide/architecture#subscription-persistence).

A child its parent stops rendering is destroyed, and rendering it again later builds it anew from the defaults passed then. One that another component renders in the same update, such as a card moved from one list to another, keeps its instance and its state.

Passing a reactive value, an element of one, or a collection built from one keeps its change tracking, so the child's changes re-render the parent too. When the parent re-renders the `live(...)` call after changing that value in place, the child re-renders with it. See [Accessing Reactive Variables in Views](/guide/reactive-variables#accessing-reactive-variables-in-views).

## `live_cable_identity_tag`

Renders a `<meta name="live-cable-identity">` tag carrying a digest of who the
page was rendered for. Put it in your layout's `<head>`, passing what your
connection's `connect` identifies by:

```erb
<%= live_cable_identity_tag(current_user) %>
```

When a Turbo visit brings a different digest - after a sign-in, sign-out or
impersonation - the client reopens its socket, so components act for the new
session. It opens one the server [refused](/guide/architecture#a-refused-socket)
too. Records are identified by their GlobalID, anything else by `to_s`;
the digest is keyed with `secret_key_base` and never reveals the values. See
[Sign-in, Sign-out and Revocation](/guide/architecture#sign-in-sign-out-and-revocation).

## Component Rendering

Component partials must start with a root element. LiveCable automatically injects the required attributes (`live-id`, `live-component`, `live-actions`, and `live-defaults`) into your root element and transforms them into Stimulus attributes.

### Basic Template Structure

```erb
<%# app/views/live/counter.html.live.erb %>
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
- `live-defaults` - Default values as JSON, signed so the client can't alter them but readable by anyone viewing the page (on first render only)

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

You can use `component` to call methods for memory-efficient data fetching. See the [`component` local section](/guide/reactive-variables#the-component-local) in the reactive variables guide.

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
- Keeping a `<turbo-frame>` that Turbo navigates

Every re-render morphs the whole component from the HTML the server rendered, so markup other code changed inside it goes back to the server's on the component's next render, even one that changes nothing near it. That includes a Turbo Frame: after a link inside a `<turbo-frame>` the component renders loads new content into it, the next render puts the template's original frame back. Put `live-ignore` on the frame, or render it outside the component.

A component rendered inside another doesn't need `live-ignore`. The parent's render holds a placeholder where the child goes, and LiveCable fills it with the child's own latest render, so a parent's re-render shows each child as the child last rendered.

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

LiveCable provides several custom HTML attributes. `live-action`, `live-form`, `live-reactive`, `live-value-*` and `live-debounce` are transformed into Stimulus attributes; `live-disable-with` and `live-loading` stay as they are and are read or set by LiveCable's loading handling.

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

Updates a reactive variable when an input changes. The input's `name` must be a reactive variable declared with `writable: true`.

A checkbox sends `true` or `false`, a `<select multiple>` an Array of the selected values, and anything else its `value` as a String. See [The `live-reactive` Attribute](/guide/actions-events#the-live-reactive-attribute).

**Syntax:**
- `live-reactive` - Uses default event (input)
- `live-reactive="event"` - Custom event

**Example:**
```erb
<input type="text" name="search" live-reactive>
<input type="text" name="query" live-reactive="keydown">
<input type="checkbox" name="notify" live-reactive <%= 'checked' if notify %>>
```

### `live-value-*`

Passes parameters to the actions of a `live-action` or `live-form` element. On a form they are sent along with its fields. A dashed name arrives in snake case: `live-value-item-id` is `params[:item_id]`.

**Syntax:** `live-value-param-name="value"`

**Example:**
```erb
<button live-action="delete" live-value-id="<%= item.id %>">Delete</button>
<form live-form="rename" live-value-id="<%= item.id %>">
  <input type="text" name="title">
</form>
```

The action gets the value as the string written in the attribute, with no type conversion. `live-value-id="123"` becomes `data-live-id-param='"123"'`, a JSON string, so Stimulus's JSON typecasting can't turn `"1.50"` into `1.5` or round a long id.

### `live-debounce`

Adds debouncing to reactive/form updates.

**Syntax:** `live-debounce="milliseconds"`

**Example:**
```erb
<input type="text" name="search" live-reactive live-debounce="300">
```

For complete documentation, see [Actions & Events](/guide/actions-events).

### `live-disable-with`

Disables an element while the message it triggers waits for a reply; inside a `live-form`, while the form's submission does. A value also replaces the element's label for that time: a button's text, or an `<input type="submit">`'s value. `live-reactive` inputs are never disabled.

**Syntax:**
- `live-disable-with` - Disable only
- `live-disable-with="text"` - Disable and swap the label

**Example:**
```erb
<button live-action="checkout" live-disable-with="Processing...">Checkout</button>

<form live-form="save">
  <button type="submit" live-disable-with>Save</button>
</form>
```

See [The `live-disable-with` Attribute](/guide/loading-states#the-live-disable-with-attribute).

### `live-loading`

Set by LiveCable, not written in templates. While a message waits for a reply, the component's root element and the element that sent it carry `live-loading`, so CSS can style the pending state.

**Example:**
```css
button[live-loading] {
  opacity: 0.5;
}
```

See [The `live-loading` Attribute](/guide/loading-states#the-live-loading-attribute).

## Next Steps

- [Component API](/api/component)
- [Learn about components](/guide/components)
- [Learn about actions](/guide/actions-events)
