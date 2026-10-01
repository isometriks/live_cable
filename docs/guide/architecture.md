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
                    → Components present on both pages keep their subscriptions,
                      unless the new page renders them with different defaults

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

**Turbo Drive navigations are handled separately.** When navigating to a new page, subscriptions for components that do not appear on the new page are closed and their server-side instances removed. The underlying WebSocket connection stays open. Components that appear on both pages — such as a persistent nav widget — keep their subscriptions, and so do the components they render inline in their `.live.erb` templates.

A component on both pages keeps its subscription only if the new page renders it with the same defaults. Defaults are what a component is built from - an account, a record - so when they differ, the client closes the old subscription and the server builds the component again from the new page's defaults. The components it renders inline are closed and built again with it. Equal defaults always sign to the same `live-defaults` blob, which is what the client compares. A default that changes on every render, such as `Time.current`, therefore rebuilds the component on every visit; keep defaults to what identifies the component's subject. A Turbo preview of a cached page changes nothing - the page that follows it decides.

Turbo keeps an element marked `data-turbo-permanent` in place when the new page has a permanent element with the same `id`, and drops the new page's copy. A component in such an element keeps its subscription, and the components it renders inline keep theirs, whatever defaults the new page gives it.

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

### Writable Variables and Defaults

The client can set a reactive variable only if it is declared
`writable: true`; a `live-reactive` write to any other is refused. A shared
variable is writable only if every class that shares the name declares it
`writable: true`, since the client chooses which components to subscribe.

Defaults passed to `live(...)` travel through the page and come back from the
browser when the component subscribes, so they are signed: the `live-defaults`
attribute is an opaque blob, signed with a key derived from `secret_key_base`
and bound to the component's `live_id`. A blob that has been edited, was never
signed, or was issued to a different component applies no defaults at all.
That is what makes it safe to seed a non-writable variable from a default -
`reactive :user, ->(c) { User.find(c.defaults[:user_id]) }`.

Signing proves the server wrote the value, not that it is still true. A page
left open for a week subscribes with the defaults it was rendered with, and
rotating `secret_key_base` invalidates every page already rendered (they
subscribe with no defaults). Re-check anything that can change underneath a
page - a membership, a permission - when the component connects, rather than
trusting the default alone.

### Authorizing Every Message

`actions` and `writable: true` say what the client may call at all.
`before_dispatch` decides whether this client may, at this moment. It runs
before every action call and every `live-reactive` write the client sends,
after the checks above, and before nothing else: not before your own
assignments to a reactive variable, not before the defaults applied when a
component subscribes, and not before a `stream_from` callback. Declare it once
on a base class and every component inherits it:

```ruby
class ApplicationComponent < LiveCable::Component
  before_dispatch :authorize!

  private

  def authorize!
    throw :abort unless current_user&.member_of?(account)
  end
end
```

`current_dispatch` describes the message while the callbacks, and the action
or write itself, run:

| Method | Action | Reactive write |
|---|---|---|
| `kind` | `:action` | `:reactive` |
| `name` | the action, e.g. `:archive` | the variable, e.g. `:title` |
| `params` | the action's `ActionController::Parameters` | `nil` |
| `value` | `nil` | the value being written |

`before_dispatch` takes `if:` and `unless:` like any ActiveModel callback, so
`before_dispatch :authorize_admin!, if: -> { current_dispatch.name == :destroy_all }`
guards a single action.

A callback refuses a message in one of two ways:

- **`throw :abort`** skips the message quietly. The client still gets its
  reply, so its loading state clears, and anything the callback changed is
  re-rendered. A refused write leaves the input showing what was typed;
  `dirty(current_dispatch.name)` before the `throw` re-renders the variable's
  server value over it.
- **Raising** goes the way an error in an action goes: to the component's
  `rescue_from` handlers, or to the error box when none takes it (see
  [Error Handling](/guide/error-handling)).

What happens after a refusal is yours to choose. Re-render with a message, as
above; `destroy` the component to unsubscribe it; or, when the socket itself
should no longer be trusted, close it with
`channel.connection.close(reconnect: true)`. The client reconnects, and the new
handshake runs your connection's `connect` against the current session.

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

### Sign-in, Sign-out and Revocation

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
only LiveCable's. Reject anonymous handshakes with
`reject_unauthorized_connection` in `connect` if your components need a user,
and close sockets whose identity has changed, as below.

#### The tab where it happened

Put `live_cable_identity_tag` in your layout's `<head>`, passing what your
`connect` identifies by:

```erb
<%= live_cable_identity_tag(current_user) %>
```

It renders a meta tag carrying a digest of those values, keyed with
`secret_key_base`, so the page never shows them. It works like
`data-turbo-track="reload"`: when a Turbo visit brings a different digest from
the one the socket was opened under, the client closes the socket and opens a
new one before the new page's components subscribe. The new handshake runs
`connect` against the current session, and the components are built again
from their defaults, as the new identity, with no extra request. A signed-out
`current_user` is `nil`, which digests differently from any user, so signing
out counts too. A page without the tag changes nothing.

#### Other tabs and devices

The tag acts on Turbo visits in its own tab; other tabs keep their sockets
until they navigate. Close a user's sockets everywhere with ActionCable's own
API:

```ruby
ActionCable.server.remote_connections.where(current_user: user).disconnect
```

The client reconnects by itself, and the handshake runs `connect` again.
`where` has to be given every identifier your connection declares, each with
the value `connect` assigned: a connection `identified_by :current_user,
:true_user` is reached by `where(current_user: user, true_user: nil)` while
nobody is impersonating, and not by `where(current_user: user)` at all.
LiveCable declares no identifiers of its own - `live_connection` is attached to
the connection separately - so the identity is made of yours alone. A socket
whose identifiers are all `nil`, a signed-out visitor's, can't be named; the
identity tag is what moves that one on.

With Devise, one hook covers sign-out:

```ruby
# config/initializers/action_cable_sign_out.rb
# current_user: is whatever your connection's identified_by declares
Warden::Manager.before_logout do |user, _auth, _opts|
  ActionCable.server.remote_connections.where(current_user: user).disconnect if user
end
```

Sign-in needs no hook of its own: the tab that signed in has the identity tag,
and other tabs were signed out, so their sockets carry no identity to misuse.
Devise can sign a user in over another without signing the first out, and
then `before_logout` doesn't run - and Warden's `after_set_user` is given only
the new user, so it can't name the old one's sockets either. If your
application switches users that way (an admin "log in as"), call `sign_out`
before `sign_in`.

#### Revocation

Access can change without anyone signing in or out: a membership removed, a
role changed, an account suspended. LiveCable can't see that; only your
application knows, so disconnect the user's sockets where it makes the change:

```ruby
class Membership < ApplicationRecord
  after_destroy_commit do
    ActionCable.server.remote_connections.where(current_user: user).disconnect
  end
end
```

The user is still signed in, so the handshake succeeds; what refuses them is
your own checks running against the rebuilt components. A `before_dispatch`
that checks the membership refuses their next message even without the
disconnect, but until the socket closes their components keep showing what
they showed, and `stream_from` callbacks keep pushing updates into them.

## Performance Considerations

### Efficient Re-rendering

- Only components with dirty variables are re-rendered
- Changesets are reset before each message or stream callback is processed
- morphdom minimizes actual DOM manipulations

### Memory Management

- Components are cleaned up when connections close
- Containers are destroyed when components are removed
- Observers are detached when values are replaced

### Scalability

- Each WebSocket connection has its own component instances
- Shared variables use a single container per connection
- ActionCable handles WebSocket scaling natively

### Concurrency

ActionCable reads every socket on one thread, but it doesn't process them
there. Each incoming message, each subscribe and unsubscribe, and each
`stream_from` broadcast becomes a separate job on a worker pool
(`config.action_cable.worker_pool_size`, 4 by default) shared by the whole
server, and nothing keeps two jobs from the same socket apart. That suits a
channel that keeps no state between messages. A LiveCable connection does keep
state - its components and their reactive variables - so LiveCable serialises
the work itself: each of those jobs holds a per-connection lock for its whole
duration, action and render included.

What that guarantees: within one connection, an action runs start to finish
before a `stream_from` callback sees its component, and the reverse. A callback
that reloads a collection from the database can't land between an action's
save and the push that follows it.

What it costs: a job waiting on the lock holds a worker thread while it waits.
Different connections still run in parallel, so this only matters when one
connection is busy - a slow action and a stream of broadcasts to the same
socket. If your actions are slow, raise `worker_pool_size` (and the database
pool with it), or move the slow part to a job and let it broadcast back.

Work you start on threads of your own - a `Thread.new` in `after_connect`,
say - is outside all of this. Wrap anything it does to a component in
`live_connection.synchronize { ... }`.

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
