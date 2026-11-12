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
- Keep a child and its state when another component renders it in the same update, as when a card moves from one list to another

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

An ID can be any string, including one built from user input such as a tag
name or a search term. LiveCable escapes it wherever it goes into the page, so
it can't add markup. Signed defaults are bound to the component name and ID
joined by a slash, though, so if one component's name is a namespace of
another's (`counter` and `counter/deep`), `counter` with ID `deep/1` and
`counter/deep` with ID `1` can take each other's defaults. Keep slashes out of
IDs built from user input, for example with `parameterize`.

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
- `live-defaults` - Default values as JSON, signed so the client can't alter them but readable by anyone viewing the page (first render only)

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

### Translations

A relative key such as `t('.title')` in a `.live.erb` template is scoped to
that template, as in any Rails view, on the page load and over the socket
alike. In `app/views/live/counter.html.live.erb` it looks up
`live.counter.title`, wherever the counter is rendered; a child component's
template uses its own scope, and each template of a
[compound component](/guide/compound-components) its own, such as
`live.wizard.billing.title`:

```yaml
en:
  live:
    counter:
      title: "Counter"
```

### Rendering Over the Socket

A component's template runs on the page load, in the page's own request, and
again over the socket: when the component subscribes, and each time it changes
after that. No HTTP request stands behind a socket render, so LiveCable builds
one from the request that opened the socket. A template can rely on:

- The page's host and protocol, under the application's script name, so
  `root_url` and the other `*_url` helpers print the same URLs as on the page.
- The socket's cookies, headers and session, as they were when the socket
  connected. Rack middleware that ran for the handshake, such as Warden, is
  there too.
- An authenticity token from that session in `form_with` and `button_to`, so
  a form posted without Turbo passes Rails' CSRF check. Devise rotates the
  token on sign-in, and a socket opened before a sign-in over Turbo keeps
  rendering the old one until it reopens, so put
  [`live_cable_identity_tag`](/api/helpers#live-cable-identity-tag) in the
  layout.
- The path and query of the page the component subscribed on, which the
  client sends when it subscribes: the `src` of the `<turbo-frame>` it was
  loaded into, or else the browser's address. `request.path`,
  `current_page?`, `params` (with the page's route parameters) and
  `url_for(page: 2)`, which pagination helpers call, work as they do on the
  page.
- A request, response and flash of its own. What one render writes to
  `request.env`, `request.variant`, `flash.now`, cookies or response headers
  isn't there in the next, or in another component's.

It can't rely on:

- Anything the page's controller did. Its `before_action`s don't run over the
  socket, and its instance variables aren't there.
- The page's path for anything but display. The client says which page it is
  on, and nothing checks it, so authorize from the session and the
  component's own state, not from `params` or `request.path`.
- The page the browser is on now, for a component that stays subscribed
  across a Turbo visit, such as one in the layout. It keeps the path it
  subscribed on. Give a component that shows which page is current an id
  that includes the path, as in `live('nav', id: request.path)`, so each page
  subscribes its own.
- Writes to the session, cookies, flash or response headers reaching the
  browser. No HTTP response follows a socket render. The flash starts empty
  each time, and the session is the socket's, so a value written to it is
  seen by later renders on that socket but never saved.

A cable server on a host of its own sees that host. Set
`default_url_options` with the page's host on `ApplicationController` and the
`*_url` helpers use it on the page and over the socket alike. It sees only
the middleware in front of it, too. With no session middleware, as when its
`config.ru` only runs `ActionCable.server`, a socket render has no session,
and Rails leaves the authenticity token out of its forms.

## Next Steps

- [Learn about reactive variables](/guide/reactive-variables)
- [Handle actions and events](/guide/actions-events)
- [Use lifecycle callbacks](/guide/lifecycle-callbacks)
- [Create compound components](/guide/compound-components)
