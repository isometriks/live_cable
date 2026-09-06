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

### CSRF Protection

LiveCable validates a CSRF token on every WebSocket message batch, on top of
ActionCable's own origin check on the handshake:

1. The page's token (`<meta name="csrf-token">`) is sent with every batch
2. The server verifies it against the session the socket captured at its handshake
3. A batch whose token cannot be verified is not run

A socket never sees cookies set after it opened, so when the session's token
rotates behind an open socket — Devise does this on every sign-in, and
`reset_session` does too — pages rendered from then on carry a token the socket
cannot verify. Rather than failing those messages, the server answers with
`_reconnect` and the client recovers without reloading anything:

1. It re-opens the socket, so the new handshake carries the current cookie
   and the socket holds the current session. ActionCable re-subscribes every
   component.
2. While re-subscribing, the server hands each component a token minted from
   the fresh socket's session (`_csrf_token`), and the client puts it on the
   page's `<meta name="csrf-token">`. No HTTP request is made, so nothing is
   re-rendered and no GET with side effects can be triggered.
3. It replays the refused batch with that token. Nothing in a refused batch
   ran, so the replay cannot apply it twice, and the component's loading state
   stays up until the replay is answered.

A token is only ever issued over a socket whose handshake came from the
application's own origin, or one listed in `allowed_request_origins`.
Browsers put the opening page's origin on every WebSocket handshake and a
cross-site page cannot forge it, so the token is exactly as hard to obtain as
the meta tag it replaces. LiveCable applies this check itself, so it holds
even where `disable_request_forgery_protection` has switched off ActionCable's.

The token is used only for the replay after a reconnect. On an ordinary
subscribe — including one on a socket kept across a Turbo Drive navigation —
the page's own token stays in place, because a page token the socket cannot
verify is exactly what tells LiveCable the socket has outlived a sign-in. The
socket is re-opened rather than told the new token over the old one for the
same reason: its identity (`identified_by`) was established at the handshake,
and a socket kept alive across a sign-in must not carry on as the user it was
opened by.

Should the replay be refused as well, the client gives up rather than looping:
it clears the loading state, leaves the DOM untouched so nothing typed is
lost, and dispatches a bubbling `live:rejected` event from the component's
root element with the refused messages in `event.detail`, so the page can
tell the user.

Components are re-created from their defaults on the new socket, exactly as
they are after any dropped connection.

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
