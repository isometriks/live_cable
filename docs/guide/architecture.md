# Architecture

Understanding LiveCable's architecture helps you build better components and debug issues effectively.

## High-Level Overview

```
Browser                    Server
┌─────────────────┐       ┌──────────────────────┐
│  Stimulus       │       │  LiveCable           │
│  Controller     │◄─────►│  Component           │
│                 │ Cable │                      │
│  - UI Events    │       │  - State             │
│  - DOM Updates  │       │  - Business Logic    │
└─────────────────┘       │  - Rendering         │
                          └──────────────────────┘
```

## Component Lifecycle

### 1. Initial Render (Server-Side)

When a page loads:

```
User Request → Rails Controller → View renders `live` helper
                                 → Component instantiated
                                 → Component rendered to HTML
                                 → HTML sent to browser
```

At this stage, the component has no live connection yet. It's just plain HTML with Stimulus data attributes.

### 2. WebSocket Connection

When the page loads in the browser:

```
Stimulus Controller connects → ActionCable subscription created
                             → Server creates or retrieves component
                             → before_connect callbacks run
                             → Channel attached, stream started
                             → after_connect callbacks run
                             → Component broadcasts current state
```

### 3. User Interaction

When the user interacts with the component:

```
User clicks button → Stimulus dispatches action
                  → ActionCable sends message to server
                  → Server calls whitelisted action method
                  → Action updates reactive variables
                  → Container marks variables as dirty
                  → before_render callbacks run
                  → Component re-renders
                  → after_render callbacks run
                  → HTML broadcasted to client
                  → morphdom updates DOM
```

### 4. Stimulus Reconnection (Within a Page)

When Stimulus disconnects and reconnects a controller on the same page — for example during a parent component re-render that morphs the DOM, or when a list is sorted — the subscription is kept alive:

```
Stimulus controller disconnects → Subscription persists
                                → Server-side component kept alive

Stimulus controller reconnects  → Reuses existing subscription
                                → Component already exists on server
                                → Component broadcasts current state
```

### 5. Turbo Navigation

When the user navigates to a new page with Turbo Drive:

```
User navigates away → Subscriptions for components not on new page are closed
                    → Server-side components are disconnected and removed
                    → WebSocket connection itself stays open
                    → Components present on both pages keep their subscriptions

User navigates back → Page is freshly fetched from the server (not from cache)
                    → Components are re-rendered in the HTTP response
                    → Stimulus controllers connect and create new subscriptions
                    → Server finds components from the HTTP render
                    → Components broadcast current state
```

LiveCable adds `<meta name="turbo-cache-control" content="no-cache">` to any page with live components, preventing Turbo from restoring a stale snapshot on back/forward navigation.

## Core Components

### LiveCable::Component

The base class for all live components.

**Responsibilities:**
- Define reactive variables and shared state
- Whitelist callable actions
- Implement business logic
- Render views

**Key Methods:**
- `reactive` - Define reactive variables
- `actions` - Whitelist action methods
- `broadcast_render` - Trigger a render and broadcast

### LiveCable::Connection

Manages the lifecycle of components for a single WebSocket connection.

**Responsibilities:**
- Store component instances
- Manage containers (state storage)
- Route actions to components
- Coordinate rendering

**Key Methods:**
- `add_component` - Register a new component
- `get` / `set` - Read/write reactive variables
- `dirty` - Mark variables as changed
- `broadcast_changeset` - Render all dirty components

### LiveCable::Container

Stores reactive variable values for a component.

**Responsibilities:**
- Store variable values
- Track which variables are dirty
- Wrap values in Delegators for change tracking
- Attach observers to track mutations

**Key Features:**
- Hash subclass for simple key-value storage
- Automatic wrapping of Arrays, Hashes, and ActiveRecord models
- Changeset tracking for efficient re-rendering

### LiveCable::Delegator

Transparent proxy for Arrays, Hashes, and ActiveRecord models.

**Responsibilities:**
- Intercept mutating method calls
- Notify observers when changes occur
- Support nested structures

**Example:**
```ruby
# When you do this:
items << 'new item'

# Behind the scenes:
delegator = Delegator::Array.new(['item1'])
delegator.add_live_cable_observer(observer, :items)
delegator << 'new item'  # Calls observer.notify(:items)
```

### LiveCable::Observer

Notifies containers when delegated values change.

**Responsibilities:**
- Receive change notifications from Delegators
- Mark variables as dirty in containers

## Change Tracking System

### How Mutations Trigger Re-renders

1. **Reactive variable is set:**
   ```ruby
   self.items = []
   ```

2. **Container wraps value in Delegator:**
   ```ruby
   container[:items] = Delegator.create_if_supported([], :items, observer)
   ```

3. **User mutates the value:**
   ```ruby
   items << 'new item'
   ```

4. **Delegator notifies observer:**
   ```ruby
   def <<(value)
     result = super
     notify_observers
     result
   end
   ```

5. **Observer marks variable dirty:**
   ```ruby
   def notify(variable)
     container.mark_dirty(variable)
   end
   ```

6. **Container adds to changeset:**
   ```ruby
   def mark_dirty(*variables)
     @changeset |= variables
   end
   ```

7. **After action completes, broadcast changeset:**
   ```ruby
   def broadcast_changeset
     components.each do |component|
       if container_changed? || shared_variables_changed?
         component.broadcast_render
       end
     end
   end
   ```

## Subscription Persistence

Traditional ActionCable subscriptions are destroyed whenever a Stimulus controller disconnects. LiveCable keeps them alive across Stimulus disconnects that happen within the same page — for example when a parent component re-renders and morphs its children, or when a sortable list reorders its items.

### Without Persistence (Standard ActionCable)
```
Stimulus disconnects → Subscription destroyed
Stimulus reconnects  → New subscription → Full reconnection overhead
```

### With Persistence (LiveCable)
```
Stimulus disconnects → Subscription persists → Server component kept alive
Stimulus reconnects  → Reuses subscription  → No reconnection overhead
```

**Benefits:**
- No WebSocket churn during parent re-renders or DOM sorts
- No race conditions from rapid connect/disconnect cycles
- Server-side state survives within-page Stimulus reconnects

**Turbo Drive navigations are handled separately.** When navigating to a new page, subscriptions for components that do not appear on the new page are closed and their server-side instances removed. The underlying WebSocket connection stays open. Components that appear on both pages — such as a persistent nav widget — keep their subscriptions.

**Implementation:**
The subscription manager tracks subscriptions by `live_id`. On each Turbo navigation it compares the current subscriptions against the incoming page's components and only closes those that are truly leaving.

## Rendering Pipeline

LiveCable's rendering pipeline has two modes depending on whether you use `.live.erb` templates:

### Standard Rendering (.html.erb)

**Simple but less efficient:**

1. **Component renders to complete HTML string**
2. **Full HTML sent over WebSocket**
3. **morphdom diffs against current DOM**
4. **Changed elements are updated**

This works fine but sends redundant static HTML on every update.

### Partial Rendering (.live.erb)

**Advanced and highly efficient:** See [Partial Rendering Guide](/guide/partial-rendering) for complete details.

#### How It Works

1. **Template compiled into parts** at boot time
2. **Dependencies tracked** using static analysis
3. **Only changed parts sent** over WebSocket
4. **Client reconstructs HTML** from partial updates

**Performance:** Up to 90% bandwidth reduction!

#### Child Component Optimization

The partial rendering system also solves the "double-render" problem with child components:

- **Before:** Child rendered in parent HTML, then re-rendered when its controller connected
- **After:** Child HTML included in parent's render result, reused when controller connects
- **Result:** No redundant renders!

### morphdom Integration

Once HTML is assembled (from parts or full render), morphdom updates the DOM:

1. **New HTML created** from parts or full render
2. **morphdom diffs** against current DOM
3. **Only changed elements updated**
4. **Event listeners and component state preserved**

### Special Attributes

- **`live-ignore`**: Skip updating this element and its children
- **`live-key`**: Identity hint for list items (preserves DOM elements during reordering)

Example:
```erb
<% items.each do |item| %>
  <li live-key="<%= item.id %>">
    <%= item.name %>
  </li>
<% end %>
```

When items are reordered, morphdom uses `live-key` to move existing elements instead of destroying and recreating them.

### Performance Comparison

| Scenario | `.html.erb` | `.live.erb` |
|----------|-------------|-------------|
| **Initial render** | 1 KB HTML | 1 KB (all parts) |
| **Single variable change** | 1 KB HTML | ~100 bytes (one part) |
| **Template switch** | 1 KB HTML | ~500 bytes (dynamic parts only) |
| **10 rapid changes** | 10 KB | ~1 KB total |

**For detailed information, see the [Partial Rendering Guide](/guide/partial-rendering).**

## Security

### Action Whitelisting

Only explicitly declared actions can be called from the frontend:

```ruby
actions :safe_method, :another_safe_method

def safe_method
  # Callable from frontend
end

def internal_method
  # Not callable - will raise error
end
```

### Cross-Site Requests

LiveCable does not verify a CSRF token on messages. A WebSocket is protected
at its handshake, and Rails does that twice over:

- ActionCable only accepts a handshake whose `Origin` header is the
  application's own host, or one listed in
  `config.action_cable.allowed_request_origins`. Browsers set that header
  themselves, and a cross-site page cannot forge it.
- The session cookie is `SameSite=Lax` by default, and browsers do not send a
  Lax cookie on a cross-site WebSocket handshake at all.

Keep `config.action_cable.disable_request_forgery_protection` off in
production. It is the one setting that removes the first of those layers, and
every LiveCable action runs with whatever identity the handshake established.

### Sign-in and Sign-out

LiveCable needs no identifiers, and a connection without `identified_by` has
no identity that can go stale. The rest of this section is for applications
that authenticate their sockets.

If `connect` identifies who is on the other end — `identified_by :current_user`
is Devise's convention, but the name is yours — that happens once, at the
handshake, and the socket never sees the session again; it has no way to,
since a WebSocket receives no cookies after it opens. Turbo Drive keeps the
page's JavaScript, and so the socket, alive across navigations, which means a
socket outlives a sign-out or sign-in in the same tab and carries on with the
identity it was opened with. This is true of every channel on the socket, not
only LiveCable's, and the application owns it:

- Reject anonymous handshakes with `reject_unauthorized_connection` in
  `connect` if your components need a user.
- Disconnect a user's sockets when they sign out. The client reconnects by
  itself, the new handshake runs `connect` against the current cookie, and
  components are rebuilt from their defaults, exactly as after any dropped
  connection. With Devise, one hook does it:

```ruby
# config/initializers/action_cable_sign_out.rb
# current_user: is whatever your connection's identified_by declares
Warden::Manager.before_logout do |user, _auth, _opts|
  ActionCable.server.remote_connections.where(current_user: user).disconnect
end
```

`remote_connections.where` has to be given every identifier the connection
declares, which is why LiveCable stays off `identified_by`: the socket's
identity is made of your identifiers alone, and `live_connection` is attached
to the connection separately.

## Performance Considerations

### Efficient Re-rendering

- Only components with dirty variables are re-rendered
- Changesets are reset after each broadcast cycle
- morphdom minimizes actual DOM manipulations

### Memory Management

- Components are cleaned up when connections close
- Containers are destroyed when components are removed
- Observers are detached when values are replaced

### Scalability

- Each WebSocket connection has its own component instances
- Shared variables use a single container per connection
- ActionCable handles WebSocket scaling natively

## Debugging Tips

### Enable ActionCable Logging

ActionCable has its own logging that can be enabled in development:

```ruby
# config/environments/development.rb
config.action_cable.log_level = :debug
```

### Inspect Component State

In the browser console, Stimulus controllers can be inspected via your application instance:

```javascript
// Get all LiveCable controllers
application.controllers.filter(c => c.identifier === 'live')

// Get component data from a controller's element
controller.element.dataset.liveIdValue
controller.element.dataset.liveComponentValue
```

### Add Render Logging

Add logging to your components using lifecycle callbacks:

```ruby
after_render do
  Rails.logger.debug("Rendered #{self.class.name}")
end
```

## Next Steps

- [Read the Component API reference](/api/component)
- [Explore the view helpers](/api/helpers)
- [Learn about lifecycle callbacks](/guide/lifecycle-callbacks)
