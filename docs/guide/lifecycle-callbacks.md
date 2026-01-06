# Lifecycle Callbacks

LiveCable uses ActiveModel::Callbacks to provide lifecycle callbacks that allow you to hook into different stages of a component's lifecycle.

## Available Callbacks

LiveCable provides three lifecycle events you can hook into:

- **`connect`**: Triggered when the component is first subscribed to the channel (only once per component lifecycle)
- **`disconnect`**: Triggered when the component is unsubscribed from the channel
- **`render`**: Triggered around each render and broadcast, including the initial render

## Callback Methods

For each lifecycle event, you can define callbacks using standard ActiveModel callback methods:

- `before_connect`, `after_connect`, `around_connect`
- `before_disconnect`, `after_disconnect`, `around_disconnect`
- `before_render`, `after_render`, `around_render`

## Example Usage

```ruby
module Live
  class Timer < LiveCable::Component
    reactive :elapsed, -> { 0 }
    reactive :running, -> { false }

    actions :start, :stop, :reset

    # Connection callbacks
    before_connect :load_saved_state
    after_connect :log_connection
    around_connect :measure_connection_time

    # Disconnection callbacks
    before_disconnect :stop_timer
    after_disconnect :save_state

    # Render callbacks
    before_render :update_elapsed_time
    after_render :log_render

    def start
      return if running

      self.running = true
      @start_time = Time.current
    end

    def stop
      self.running = false
    end

    def reset
      self.elapsed = 0
      self.running = false
    end

    private

    def load_saved_state
      # Load state from database or cache
      saved = TimerState.find_by(user_id: current_user.id)
      self.elapsed = saved.elapsed if saved
    end

    def log_connection
      Rails.logger.info "Timer component connected for user #{current_user.id}"
    end

    def measure_connection_time
      start = Time.now
      yield
      Rails.logger.info "Connection took #{Time.now - start}s"
    end

    def stop_timer
      self.running = false
    end

    def save_state
      TimerState.upsert(
        { user_id: current_user.id, elapsed: elapsed },
        unique_by: :user_id
      )
    end

    def update_elapsed_time
      return unless running

      self.elapsed = (Time.current - @start_time).to_i
    end

    def log_render
      Rails.logger.debug "Timer rendered: #{elapsed}s"
    end
  end
end
```

## Callback Execution Order

### When a Component is Subscribed

1. Component is instantiated
2. `before_connect` callbacks run
3. Connection is established (only happens once per component lifecycle)
4. `after_connect` callbacks run
5. `before_render` callbacks run
6. Component is rendered and broadcast
7. `after_render` callbacks run

### On Subsequent Updates

When state changes (action calls, reactive variable mutations):

1. State changes occur
2. `before_render` callbacks run
3. Component is rendered and broadcast
4. `after_render` callbacks run

### When a Component is Unsubscribed

1. `before_disconnect` callbacks run
2. Disconnection occurs
3. `after_disconnect` callbacks run
4. Streams are stopped
5. Component is cleaned up

## Connection Persistence

::: info Important
The `connect` event only fires **once** when the component first establishes a WebSocket connection, even if the user navigates away and back to the page. This ensures setup code (like subscribing to ActionCable channels) only runs once per component lifecycle.
:::

This is particularly useful for:
- Subscribing to external ActionCable channels
- Setting up timers or intervals
- Loading initial data from the database
- Establishing connections to external services

## Common Use Cases

### Loading Data on Connection

```ruby
before_connect :load_user_preferences

private

def load_user_preferences
  prefs = UserPreference.find_by(user_id: current_user.id)
  self.theme = prefs.theme if prefs
  self.notifications_enabled = prefs.notifications_enabled if prefs
end
```

### Cleaning Up Resources

```ruby
after_disconnect :cleanup_resources

private

def cleanup_resources
  # Stop any background jobs
  @background_job&.cancel
  
  # Clear caches
  Rails.cache.delete("component_cache_#{live_id}")
  
  # Log disconnect
  Rails.logger.info "Component #{live_id} disconnected"
end
```

### Tracking Render Performance

```ruby
around_render :track_render_time

private

def track_render_time
  start = Time.now
  yield
  duration = Time.now - start
  
  if duration > 0.1
    Rails.logger.warn "Slow render: #{duration}s for #{self.class.name}"
  end
  
  # Track metrics
  Metrics.histogram('component.render.duration', duration, 
    tags: { component: self.class.name })
end
```

### Preparing Data Before Render

```ruby
before_render :calculate_derived_state

private

def calculate_derived_state
  # Update computed values that depend on reactive variables
  self.filtered_items = items.select { |item| item[:category] == selected_category }
  self.total_price = filtered_items.sum { |item| item[:price] }
end
```

### Logging and Monitoring

```ruby
after_connect :track_component_usage
after_disconnect :track_session_duration
after_render :increment_render_counter

private

def track_component_usage
  Analytics.track(
    user_id: current_user.id,
    event: 'component_connected',
    properties: { component: self.class.name }
  )
  @connected_at = Time.current
end

def track_session_duration
  return unless @connected_at
  
  duration = Time.current - @connected_at
  Analytics.track(
    user_id: current_user.id,
    event: 'component_session',
    properties: { 
      component: self.class.name,
      duration: duration
    }
  )
end

def increment_render_counter
  @render_count ||= 0
  @render_count += 1
end
```

## Best Practices

### Do

✅ Use `after_connect` for one-time setup that needs the WebSocket connection  
✅ Use `before_render` for deriving state from reactive variables  
✅ Use `before_disconnect` to clean up resources and save state  
✅ Keep callback methods focused and single-purpose  
✅ Use `around_*` callbacks for wrapping behavior (timing, logging, etc.)

### Don't

❌ Don't perform expensive operations in `before_render` (it runs on every render)  
❌ Don't mutate reactive variables in `after_render` (causes another render)  
❌ Don't rely on `disconnect` callbacks for critical data saving (connections can drop)  
❌ Don't use callbacks for business logic that should be in action methods

## Next Steps

- [Handle actions and events](/guide/actions-events)
- [Stream from ActionCable channels](/guide/streaming)
- [Learn about compound components](/guide/compound-components)
