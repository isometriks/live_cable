# Component API

`LiveCable::Component` is the base class for all live components.

## Class Methods

### `reactive(variable, initial_value = nil, shared: false, writable: false)`

Define a reactive variable that triggers re-renders when changed.

**Parameters:**
- `variable` (Symbol) - The variable name
- `initial_value` (Proc) - Lambda that returns the default value
- `shared` (Boolean) - Whether the variable is shared across all components on the connection
- `writable` (Boolean) - Whether the variable can be updated from the client via `live-reactive`. Defaults to `false` for security

**Example:**
```ruby
reactive :count, -> { 0 }
reactive :messages, -> { [] }, shared: true
reactive :search, -> { "" }, writable: true
```

### `shared(variable, initial_value)`

Define a shared non-reactive variable.

**Parameters:**
- `variable` (Symbol) — The variable name
- `initial_value` (Proc) — Lambda that returns the default value

**Example:**
```ruby
shared :config, -> { { theme: 'dark' } }
```

### `actions(*names)`

Whitelist methods that can be called from the frontend.

**Parameters:**
- `names` (`Array<Symbol>`) - Method names to whitelist

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

## Lifecycle Callbacks

### Connection Callbacks

```ruby
before_connect :setup
after_connect :log_connection
around_connect :measure_time
```

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

Manually trigger a render and broadcast.

**Example:**
```ruby
def refresh
  broadcast_render
end
```

### `destroy`

Destroy the component and close the WebSocket connection.

**Example:**
```ruby
def close
  destroy
end
```

### `dirty(*variables)`

Manually mark variables as dirty (changed).

**Parameters:**
- `variables` (`Array<Symbol>`) - Variable names to mark dirty

**Example:**
```ruby
dirty(:count, :total)
```

### `stream_from(channel_name, callback = nil, coder: nil, &block)`

Subscribe to an ActionCable channel.

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

### `channel_name`

Returns the ActionCable channel name for this component.

**Returns:** String - The channel name

## Accessing Connection Identifiers

Components have access to `identified_by` values from the ActionCable connection via `method_missing` delegation. Add any identifiers you need alongside `:live_connection`:

```ruby
# In ApplicationCable::Connection
identified_by :live_connection, :current_user

def connect
  self.live_connection = LiveCable::Connection.new(request)
  self.current_user = find_verified_user
end

# In your component — current_user is available directly
def some_action
  messages << { user: current_user.name, text: "Hello" }
end
```

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

List of reactive variables that can be updated from the client via `live-reactive`.

**Type:** `Array<Symbol>`

### `shared_variables`

List of shared non-reactive variables.

**Type:** `Array<Symbol>`

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
      self.tasks = Task.where(user_id: current_user.id).as_json
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
