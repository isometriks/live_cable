# Component API

`LiveCable::Component` is the base class for all live components.

## Class Methods

### `reactive(variable, initial_value = nil, shared: false, writable: false)`

Define a reactive variable that triggers re-renders when changed.

**Parameters:**
- `variable` (Symbol) - The variable name
- `initial_value` (Proc) - Lambda that returns the default value. A lambda that takes an argument is given the component, as in `->(c) { User.find(c.defaults[:user_id]) }`. An error it raises is handled like one raised by the render that read the variable, and nothing is stored, so the next read runs it again. Anything other than a proc or `nil` raises `ArgumentError` when the class loads
- `shared` (Boolean) - Whether the variable is shared across all components on the connection
- `writable` (Boolean) - Whether the variable can be updated from the client via `live-reactive`. Defaults to `false` for security. A shared variable is writable from the client only if every component class that shares it declares it `writable: true`

**Example:**
```ruby
reactive :count, -> { 0 }
reactive :messages, -> { [] }, shared: true
reactive :search, -> { "" }, writable: true
```

### `shared(variable, initial_value)`

Define a shared non-reactive variable. Changing it doesn't re-render a
component that declares it with `shared`; a component that declares the same
name with `reactive ..., shared: true` still re-renders. A part that reads it,
directly or through a component method, re-renders whenever its component
re-renders for another reason, so it shows the latest value.

**Parameters:**
- `variable` (Symbol) — The variable name
- `initial_value` (Proc) — Lambda that returns the default value, with the same rules as `reactive`'s `initial_value`. A lambda that takes an argument is given the first component that reads the variable

**Example:**
```ruby
shared :config, -> { { theme: 'dark' } }
```

### `reactive_query(name, scope, &transform)`

Define a reader for query-backed state that re-renders when the query's result
changes, keeping only its fingerprint between renders. See
[Query-Backed State](/guide/reactive-variables#query-backed-state).

**Parameters:**
- `name` (Symbol) - The reader's name. Templates and component methods call it like any method, and `refresh` and `dirty` take it
- `scope` (Proc) - Lambda, run on the component, that returns an `ActiveRecord::Relation`, such as a `has_many` association. Anything else, or a model without an `updated_at` column, raises `LiveCable::Error` when the reader runs
- `transform` (Block, optional) - Run on the component with the relation, once per render; the reader returns its result. Without it the reader returns the loaded relation

The first read in a render runs the query and the block, and later reads in
that render reuse the result; nothing is kept after the render. The component
stores the query's SQL digest and `cache_key_with_version`, taken from the
loaded records where Rails can, otherwise with one aggregate query. Each read
builds a fresh relation, so an association or a relation the lambda returns
already loaded is queried again rather than reused. A query has no `shared:`
option (passing one raises `ArgumentError`) and isn't settable from the client
or from defaults.

**Example:**
```ruby
reactive_query :entries, -> { Entry.where(spent_on: day).order(:created_at) }
reactive_query :week_total, -> { Entry.where(spent_on: week) } do |relation|
  relation.sum(:hours)
end
```

### `client_writable?(variable)`

Whether a client may set the variable via `live-reactive`: it must be declared `writable: true` and, if it's shared,
every class that shares it must declare it `writable: true` too.

**Returns:** Boolean

### `actions(*names)`

Whitelist methods that can be called from the frontend.

**Parameters:**
- `names` (`Array<Symbol>`) - Method names to whitelist

A method with a required, optional or named splat positional argument is called with the message's `ActionController::Parameters`; one with no positional arguments is called with none. A splat that wraps another method, such as a prepended `(*)` or `(...)` wrapper or an RSpec stub, takes what the method it wraps takes, and a `delegate`d or `method_missing` action is called with none. See [Action Parameters](/guide/actions-events#action-parameters).

**Example:**
```ruby
actions :increment, :decrement, :reset
```

### `compound`

Mark the component as compound, organizing templates in a directory.

**Example:**
```ruby
compound  # Templates in app/views/live/component_name/
```

### `rescue_from(*exceptions, with: nil, &block)`

From `ActiveSupport::Rescuable`. Handles an error raised by an action, a
`live-reactive` write, a `before_dispatch` callback or a `stream_from`
callback, instead of replacing the component with the error box. The message
is still answered, and anything the handler changes is re-rendered. Errors
while subscribing or rendering aren't offered to it, and neither is
`LiveCable::Forbidden`, raised for an action the component doesn't list or a
write to a variable that isn't writable.

**Example:**
```ruby
rescue_from ActiveRecord::RecordNotFound do
  self.notice = 'That record is gone.'
end
```

See [Error Handling](/guide/error-handling#handling-errors-with-rescue-from).

## Lifecycle Callbacks

### Connection Callbacks

```ruby
before_connect :setup
after_connect :log_connection
around_connect :measure_time
```

Connection identifiers such as `current_user` are available in all three. A `before_connect` that throws
`:abort` refuses the component, as [`refuse!`](/guide/error-handling#refusing-a-component) with no reason does. See
[Lifecycle Callbacks](/guide/lifecycle-callbacks#when-a-component-is-subscribed).

### Disconnection Callbacks

```ruby
before_disconnect :cleanup
after_disconnect :save_state
around_disconnect :log_duration
```

### Render Callbacks

```ruby
before_render :prepare_data
after_render :track_render
around_render :time_render
```

### Dispatch Callbacks

```ruby
before_dispatch :authorize!
```

Run before every action and `live-reactive` write sent by the client, and
nothing else. `throw :abort` skips the message. See
[Authorizing Every Message](/guide/architecture#authorizing-every-message).

## Instance Methods

### `broadcast(data)`

Send data directly to the client.

**Parameters:**
- `data` (Hash) - Data to broadcast

**Example:**
```ruby
broadcast({ _status: 'loading' })
```

### `broadcast_render`

Manually trigger a render and broadcast. A render in which no part re-renders
sends no `_refresh`; its events still go out and its render callbacks still
run. Returns whether a `_refresh` went out.

Actions and `stream_from` callbacks don't need it for their final state: what
they change is rendered when they return. Call it after changing state from a
thread of your own, holding the connection's lock (see
[Concurrency](/guide/architecture#concurrency)). `live_connection` is `nil`
once the component disconnects, so take it before the thread starts.

**Example:**
```ruby
after_connect do
  connection = live_connection

  Thread.new do
    Rails.application.executor.wrap do
      report = Report.build

      connection.synchronize do
        next unless live_connection # disconnected while it was building

        self.report = report
        broadcast_render
      end
    end
  end
end
```

Called during an action, for example to show progress before slow work, it
doesn't end the loading state of the message being handled; the reply sent
after the action does.

### `destroy`

Unsubscribe the component, and the children it rendered, from the client.
The element stays on the page as it was last rendered, its loading state is
cleared, and it sends no more messages. The WebSocket stays open for the
page's other components.

**Example:**
```ruby
def close
  destroy
end
```

### `refuse!(reason = nil)`

Stop the component because the person may no longer use it. Call it from an
action, a callback, a `stream_from` callback, a `rescue_from` handler or a
render over the socket; it raises `LiveCable::Refused`, which ends what was
running and is never offered to `rescue_from` or reported as an error. The
server disconnects the component at once: its streams stop, the rest of the
message batch is skipped, and nothing the client sends it afterwards runs.
The children it owns are destroyed and disconnected with it. The client
keeps the component's markup, sets `data-live-status-value="refused"`, ends
its loading state, unsubscribes, and dispatches a bubbling `live:refused` from
its root with `event.detail.reason` set to `reason`.

A child rendered inline that refuses, even while its parent renders it, is
refused on its own; its parent carries on. Until the parent stops rendering
it, the parent's renders keep the child as the page last showed it rather
than build it again.

During the HTTP prerender nothing catches it, so a render that refuses fails
the page like any other exception; check access for the page in its
controller.

A 0.5 client doesn't know a refusal and shows the error box instead.

**Example:**
```ruby
before_dispatch { refuse!('membership_ended') unless membership.active? }
```

See [Refusing a Component](/guide/error-handling#refusing-a-component).

### `current_dispatch`

The client message being dispatched, while `before_dispatch` callbacks and
the action or write run; `nil` otherwise. A `LiveCable::Dispatch` with `kind`
(`:action` or `:reactive`), `name`, `params` (actions) and `value` (reactive
writes).

### `dirty(*variables)`

Manually mark variables as dirty (changed).

**Parameters:**
- `variables` (`Array<Symbol>`) - Reactive variable or `reactive_query` names to mark dirty. A query marked dirty re-renders the parts that read it without checking its fingerprint

**Example:**
```ruby
dirty(:count, :total)
```

### `refresh(*names)`

Check `reactive_query` fingerprints and mark dirty, so their parts re-render,
only the queries whose result changed. Each name costs one
`COUNT(*)`/`MAX(updated_at)` query. With no names, checks every
`reactive_query` on the component. Call it in an action or a `stream_from`
callback; it raises `LiveCable::Error` during a render and for a name that
isn't a `reactive_query`. It doesn't see writes that skip `updated_at` or
changes to associated rows; use `dirty` for those. See
[Query-Backed State](/guide/reactive-variables#query-backed-state).

**Parameters:**
- `names` (`Array<Symbol>`) - `reactive_query` names to check

**Example:**
```ruby
stream_from("entries_#{account_id}") { refresh(:entries) }
```

### `dispatch_event(name, detail = nil, window: false)`

Fire a DOM event on the client: a bubbling `CustomEvent` dispatched from the
component's root element, or from `window` with `window: true`. It goes out
with the component's next broadcast and fires after any render it rides with
is morphed in. See [Server Events](/guide/server-events).

**Parameters:**
- `name` (String, Symbol) - The event name, e.g. `'chat:message-sent'`
- `detail` (Hash, optional) - JSON-serializable payload, available as `event.detail`. Pass it as keyword arguments, or as a Hash when it needs a `window` key
- `window` (Boolean) - Dispatch on `window` instead of the component's root

**Example:**
```ruby
def save(params)
  self.name = params[:name]

  dispatch_event('toast:show', message: 'Profile saved', level: 'success')
end
```

### `stream_from(channel_name, callback = nil, coder: nil, &block)`

Subscribe to an ActionCable channel. Calling it again with a name the
component already streams from replaces its callback and keeps the
ActionCable stream, so each broadcast runs only the newer callback. A
different `coder:` stops that stream and starts a new one.

**Parameters:**
- `channel_name` (String) - The channel name to subscribe to
- `callback` (Proc, optional) - Callback to execute when broadcast received
- `coder` (Object, optional) - Coder for decoding messages (e.g., `ActiveSupport::JSON`)
- `block` - Alternative to callback parameter

**Example:**
```ruby
after_connect :subscribe_to_updates

private

def subscribe_to_updates
  stream_from("updates_#{user.id}", coder: ActiveSupport::JSON) do |data|
    messages << data
  end
end
```

### `stop_stream_from(channel_name)`

Stop one stream the component started with `stream_from`. No callback for it
runs afterwards, including a broadcast that was already queued, unless the
stream is started again under the same name. Private, like `stream_from`.
See [Stopping Streams](/guide/streaming#stopping-streams).

### `stop_stream`

Stop every stream the component has started. Disconnecting does this already.
Private, like `stream_from`.

See [Stopping Streams](/guide/streaming#stopping-streams).

### `variant`

Override to return the template name for compound components.

**Returns:** String - Template name (without path or extension)

**Example:**
```ruby
def variant
  current_step  # e.g., returns "billing" → renders app/views/live/wizard/billing.html.live.erb
end
```

### `to_partial_path`

Returns the partial path for rendering.

**Returns:** String - The partial path

### `live_id`

Returns the component's unique identifier.

**Returns:** String - The component ID

### `defaults`

The defaults the component was rendered with, with Symbol keys. An initial value lambda can read them to seed a
variable the client can't write:

```ruby
reactive :user, ->(c) { User.find(c.defaults[:user_id]) }
```

For a top-level component the values are their JSON form, on page load and once connected: a Symbol or Time
arrives as a String and a nested Hash has String keys. A child created by its parent keeps the values the parent
passed; one the client subscribed to before its parent rendered it has none. See
[Writable Variables and Defaults](/guide/architecture#writable-variables-and-defaults).

**Returns:** Hash

## Accessing Connection Identifiers

Components have access to `identified_by` values from the ActionCable connection via `method_missing` delegation. LiveCable needs no identifier of its own, so declare only your application's:

```ruby
# In ApplicationCable::Connection
identified_by :current_user

def connect
  self.current_user = find_verified_user
end

# In your component — current_user is available directly
def some_action
  messages << { user: current_user.name, text: "Hello" }
end
```

## Reactive Values

### `LiveCable::Delegator.unwrap(value)`

Returns the plain Array, Hash or model inside a reactive value, with any
change-tracking wrappers nested inside it replaced too. Anything else comes
back unchanged, so it works during the HTTP prerender, where component code
already sees plain values, and once connected. In-place changes to an Array or
Hash it returns aren't tracked.

```ruby
task.update!(assignee: LiveCable::Delegator.unwrap(user))
```

**Returns:** the plain value

See [Accessing Reactive Variables in Views](/guide/reactive-variables#accessing-reactive-variables-in-views).

## Class Attributes

### `is_compound`

Whether the component is marked as compound.

**Type:** Boolean

### `reactive_variables`

List of component-specific reactive variables.

**Type:** `Array<Symbol>`

### `shared_reactive_variables`

List of shared reactive variables.

**Type:** `Array<Symbol>`

### `writable_reactive_variables`

List of reactive variables declared `writable: true`. A shared one is only updatable from the client if it is
[`client_writable?`](#client-writable-variable).

**Type:** `Array<Symbol>`

### `shared_variables`

List of shared non-reactive variables.

**Type:** `Array<Symbol>`

### `reactive_queries`

The component's `reactive_query` declarations, by name.

**Type:** `Hash{Symbol => Array(Proc, Proc or nil)}`

## Example: Complete Component

```ruby
module Live
  class TaskList < LiveCable::Component
    compound

    reactive :tasks, -> { [] }
    reactive :filter, -> { "all" }

    actions :add_task, :toggle_task, :remove_task, :change_filter

    after_connect :fetch_tasks
    after_render :log_render_time

    def add_task(params)
      return if params[:title].blank?

      tasks << {
        id: SecureRandom.uuid,
        title: params[:title],
        completed: false,
        created_at: Time.current
      }
    end

    def toggle_task(params)
      task = tasks.find { |t| t[:id] == params[:id] }
      task[:completed] = !task[:completed] if task
    end

    def remove_task(params)
      tasks.reject! { |t| t[:id] == params[:id] }
    end

    def change_filter(params)
      self.filter = params[:filter]
    end

    def variant
      tasks.empty? ? "empty" : "list"
    end

    private

    def fetch_tasks
      self.tasks = Task.where(user_id: current_user.id).map do |task|
        { id: task.id.to_s, title: task.title, completed: task.completed }
      end
    end

    def log_render_time
      @render_count ||= 0
      @render_count += 1
      Rails.logger.debug("TaskList rendered #{@render_count} times")
    end
  end
end
```

## Next Steps

- [View Helpers](/api/helpers)
- [Learn about lifecycle callbacks](/guide/lifecycle-callbacks)
- [Learn about reactive variables](/guide/reactive-variables)
