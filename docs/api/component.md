# Component API

`LiveCable::Component` is the base class for all live components.

## Class Methods

### `reactive(variable, initial_value, shared: false)`

Define a reactive variable that triggers re-renders when changed.

**Parameters:**
- `variable` (Symbol) - The variable name
- `initial_value` (Proc) - Lambda that returns the default value
- `shared` (Boolean) - Whether the variable is shared across all components on the connection

**Example:**
```ruby
reactive :count, -> { 0 }
reactive :messages, -> { [] }, shared: true
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

### `render_broadcast`

Manually trigger a render and broadcast.

**Example:**
```ruby
def refresh
  render_broadcast
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

### `template_state`

Override to return the template name for compound components.

**Returns:** String - Template name (without path or extension)

**Example:**
```ruby
def template_state
  current_step  # Renders app/views/live/wizard/current_step.html.erb
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

Components have access to `identified_by` values from the ActionCable connection:

```ruby
# In ApplicationCable::Connection
identified_by :current_user

# In your component
def some_action
  # Access current_user directly
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
    reactive :loading, -> { false }
    
    actions :add_task, :toggle_task, :remove_task, :change_filter, :load_tasks
    
    before_connect :fetch_tasks
    after_render :log_render_time
    
    def add_task(params)
      return if params[:title].blank?
      
      task = {
        id: SecureRandom.uuid,
        title: params[:title],
        completed: false,
        created_at: Time.current
      }
      
      tasks << task
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
    
    def template_state
      loading ? "loading" : "list"
    end
    
    private
    
    def fetch_tasks
      self.loading = true
      render_broadcast
      
      # Simulate async load
      sleep 0.5
      self.tasks = Task.where(user_id: current_user.id).as_json
      self.loading = false
    end
    
    def log_render_time
      @render_count ||= 0
      @render_count += 1
      Rails.logger.debug "TaskList rendered #{@render_count} times"
    end
  end
end
```

## Next Steps

- [View Helpers](/api/helpers)
- [Learn about lifecycle callbacks](/guide/lifecycle-callbacks)
- [Learn about reactive variables](/guide/reactive-variables)
