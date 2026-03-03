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
Stimulus Controller connects → ActionCable subscription
                             → Server creates/retrieves component
                             → Component.mark_connected called (once)
                             → before_connect callbacks run
                             → Connection established
                             → after_connect callbacks run
                             → Component broadcasts initial state
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

### 4. Reconnection

When the user navigates away and back:

```
User navigates away → Stimulus controller disconnects
                    → Subscription persists (not destroyed)
                    → Component instance kept alive

User navigates back → Stimulus controller reconnects
                   → Reuses existing subscription
                   → Component already exists
                   → mark_connected returns early (already connected)
                   → Component broadcasts current state
```

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
- `render_broadcast` - Trigger a render and broadcast

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
         component.render_broadcast
       end
     end
   end
   ```

## Subscription Persistence

Traditional ActionCable subscriptions are destroyed when Stimulus controllers disconnect. LiveCable keeps them alive:

### Without Persistence (Standard ActionCable)
```
Page Load → Subscribe → Connected
Navigate Away → Disconnect → Subscription destroyed → WebSocket closed
Navigate Back → Subscribe → New connection → New WebSocket
```

### With Persistence (LiveCable)
```
Page Load → Subscribe → Connected
Navigate Away → Controller disconnects → Subscription persists
Navigate Back → Controller reconnects → Reuses subscription → Same component
```

**Benefits:**
- Reduced WebSocket overhead
- State preservation across navigation
- No race conditions from rapid connect/disconnect
- Better performance

**Implementation:**
The subscription manager (in the JavaScript controller) tracks subscriptions by `live_id` and only creates new subscriptions when needed.

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

LiveCable includes CSRF token validation on all WebSocket messages:

1. Token is embedded in the Stimulus controller
2. Token is sent with every action
3. Server validates token before processing
4. Invalid tokens are rejected

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

### Enable Logging

```ruby
# config/environments/development.rb
config.action_cable.log_level = :debug
```

### Inspect Component State

In browser console:
```javascript
// Get all LiveCable controllers
Stimulus.controllers.filter(c => c.identifier === 'live')

// Get component data
controller.element.dataset.liveId
```

### Check Changeset

Add logging to your components:
```ruby
after_render do
  Rails.logger.debug "Rendered #{self.class.name}"
  Rails.logger.debug "Changesets: #{live_connection.containers.inspect}"
end
```

## Next Steps

- [Read the Component API reference](/api/component)
- [Explore the view helpers](/api/helpers)
- [Learn about lifecycle callbacks](/guide/lifecycle-callbacks)
