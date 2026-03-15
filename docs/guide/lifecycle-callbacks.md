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
  class NotificationBell < LiveCable::Component
    reactive :notifications, -> { [] }
    reactive :unread_count, -> { 0 }

    actions :mark_all_read

    # Load data when the component first connects
    after_connect :load_notifications

    # Compute derived state before every render
    before_render :update_unread_count

    # Record when the user last viewed notifications
    before_disconnect :save_last_seen

    def mark_all_read
      notifications.each { |n| n[:read] = true }
    end

    private

    def load_notifications
      self.notifications = current_user.notifications
                                       .order(created_at: :desc)
                                       .limit(20)
                                       .as_json
    end

    def update_unread_count
      self.unread_count = notifications.count { |n| !n[:read] }
    end

    def save_last_seen
      current_user.update(notifications_last_seen_at: Time.current)
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
- Loading initial data from the database
- Setting up resources that should persist across navigations

## Common Use Cases

### Loading Data on Connection

```ruby
after_connect :load_user_preferences

private

def load_user_preferences
  prefs = UserPreference.find_by(user_id: current_user.id)
  return unless prefs

  self.theme = prefs.theme
  self.notifications_enabled = prefs.notifications_enabled
end
```

### Cleaning Up Resources

```ruby
after_disconnect :cleanup_resources

private

def cleanup_resources
  Rails.cache.delete("component_cache_#{live_id}")
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
end
```

### Subscribing to ActionCable Streams

Use `after_connect` when setting up streams so they're only created once. Streams registered via `stream_from` are automatically stopped when the component disconnects — no cleanup needed.

```ruby
after_connect :subscribe_to_updates

private

def subscribe_to_updates
  stream_from("updates_#{current_user.id}", coder: ActiveSupport::JSON) do |data|
    notifications.unshift(data)
  end
end
```

## Best Practices

### Do

✅ Use `after_connect` for one-time setup (loading data, subscribing to streams)
✅ Use `before_render` for deriving state from reactive variables
✅ Use `before_disconnect` to clean up resources and save state
✅ Keep callback methods focused and single-purpose
✅ Use `around_*` callbacks for wrapping behavior (timing, logging)

### Don't

❌ Don't perform expensive operations in `before_render` (it runs on every render)
❌ Don't mutate reactive variables in `after_render` (causes another render)
❌ Don't rely on `disconnect` callbacks for critical data saving (connections can drop)
❌ Don't use callbacks for business logic that should be in action methods

## Next Steps

- [Handle actions and events](/guide/actions-events)
- [Stream from ActionCable channels](/guide/streaming)
- [Learn about compound components](/guide/compound-components)
