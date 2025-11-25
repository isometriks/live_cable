# LiveCable

LiveCable is a Phoenix LiveView-style live component system for Ruby on Rails that tracks state server-side and allows 
you to call actions from the frontend using Stimulus.

## Features

- **Server-side state management**: Component state is maintained on the server using ActionCable
- **Reactive variables**: Automatic UI updates when state changes
- **Action dispatch**: Call server-side methods from the frontend
- **Lifecycle hooks**: Hook into component lifecycle events
- **Stimulus integration**: Seamless integration with Stimulus controllers

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'live_cable'
```

And then execute:

```bash
bundle install
```

## Lifecycle Hooks

LiveCable provides four lifecycle hooks that you can override in your components to add custom behavior at different 
stages of a component's lifecycle.

### Available Hooks

#### `connected`

Called when the component is first subscribed to the channel, after initialization but before the initial render.

**Use cases:**
- Initialize timers or intervals
- Subscribe to external services
- Load additional data
- Set up event listeners

**Example:**
```ruby
class CounterComponent < LiveCable::Component
  reactive :count, 0

  def connected
    # Start a timer that increments the counter every second
    @timer = Thread.new do
      loop do
        sleep 1
        self.count += 1
      end
    end
  end

  def disconnected
    @timer&.kill
  end
end
```

#### `disconnected`

Called when the component is unsubscribed from the channel, typically when a user navigates away or closes the 
connection.

**Use cases:**
- Clean up timers or intervals
- Unsubscribe from external services
- Save state before disconnection
- Release resources

**Example:**
```ruby
class ChatComponent < LiveCable::Component
  reactive :messages, -> { [] }

  def connected
    @subscription = MessageBus.subscribe("/chat") do |message|
      self.messages = messages + [message]
    end
  end

  def disconnected
    MessageBus.unsubscribe(@subscription)
  end
end
```

#### `before_render`

Called before each render and broadcast, including the initial render.

**Use cases:**
- Prepare data for rendering
- Perform calculations
- Validate state
- Log render events

**Example:**
```ruby
class DashboardComponent < LiveCable::Component
  reactive :stats, -> { {} }

  def before_render
    # Fetch latest stats before each render
    self.stats = {
      users: User.count,
      orders: Order.today.count,
      revenue: Order.today.sum(:total)
    }
  end
end
```

#### `after_render`

Called after each render and broadcast.

**Use cases:**
- Log render completion
- Trigger side effects
- Update analytics
- Clean up temporary data

**Example:**
```ruby
class NotificationComponent < LiveCable::Component
  reactive :notification, nil

  actions :dismiss

  def dismiss(params)
    self.notification = nil
  end

  def after_render
    # Log each render for debugging
    Rails.logger.debug "NotificationComponent rendered: #{notification.inspect}"
  end
end
```

### Hook Execution Order

When a component is subscribed:
1. Component is instantiated
2. `connected` is called
3. `before_render` is called
4. Component is rendered and broadcast
5. `after_render` is called

On subsequent updates (action calls, reactive variable changes):
1. State changes occur
2. `before_render` is called
3. Component is rendered and broadcast
4. `after_render` is called

When a component is unsubscribed:
1. `disconnected` is called
2. Streams are stopped
3. Component is cleaned up

### Best Practices

1. **Keep hooks lightweight**: Hooks are called synchronously, so avoid long-running operations
2. **Handle errors**: Use `rescue` blocks to prevent hook errors from breaking the component
3. **Clean up resources**: Always clean up in `disconnected` what you set up in `connected`
4. **Avoid rendering in hooks**: Don't call `render_broadcast` inside hooks to prevent infinite loops
5. **Thread safety**: If using threads or background jobs, ensure proper synchronization

### Example: Complete Component with Lifecycle Hooks

```ruby
class LiveClockComponent < LiveCable::Component
  reactive :current_time, -> { Time.current }
  reactive :timezone, -> { "UTC" }

  actions :change_timezone

  def connected
    Rails.logger.info "Clock connected for session #{_live_id}"
    start_timer
  end

  def disconnected
    Rails.logger.info "Clock disconnected for session #{_live_id}"
    stop_timer
  end

  def before_render
    # Update time before each render
    self.current_time = Time.current.in_time_zone(timezone)
  end

  def after_render
    # Could track render metrics here
  end

  def change_timezone(params)
    self.timezone = params[:timezone]
  end

  private

  def start_timer
    @timer = Thread.new do
      loop do
        sleep 1
        dirty(:current_time) # Mark as dirty to trigger re-render
      end
    end
  end

  def stop_timer
    @timer&.kill
    @timer = nil
  end
end
```

## Basic Usage

### 1. Create a Component

```ruby
# app/components/counter_component.rb
class CounterComponent < LiveCable::Component
  reactive :count, -> { 0 }

  actions :increment, :decrement

  def increment(params)
    self.count += 1
  end

  def decrement(params)
    self.count -= 1
  end
end
```

### 2. Create a Partial

```erb
<%# app/views/live/counter_component/component.html.erb %>
<div>
  <h2>Counter: <%= count %></h2>
  <button data-action="live#action" data-live-action-param="increment">+</button>
  <button data-action="live#action" data-live-action-param="decrement">-</button>
</div>
```

### 3. Use in Your View

```erb
<%= live_component "counter" %>
```

## Reactive Variables

Reactive variables automatically trigger re-renders when changed:

```ruby
class TodoComponent < LiveCable::Component
  reactive :todos, -> { [] }
  reactive :filter, -> { "all" }

  actions :add_todo, :toggle_filter

  def add_todo(params)
    self.todos = todos + [params[:text]]
  end

  def toggle_filter(params)
    self.filter = params[:filter]
  end
end
```

## Shared Reactive Variables

Shared reactive variables are shared across all instances of a component for the same connection:

```ruby
class ChatComponent < LiveCable::Component
  reactive :username, -> { "Guest" }
  reactive :messages, -> { [] }, shared: true

  actions :send_message

  def send_message(params)
    self.messages = messages + [{ user: username, text: params[:text] }]
  end
end
```

## Action Whitelisting

For security, explicitly declare which actions can be called from the frontend:

```ruby
class SecureComponent < LiveCable::Component
  actions :safe_action, :another_safe_action

  def safe_action(params)
    # This can be called from the frontend
  end

  def another_safe_action(params)
    # This can also be called
  end

  private

  def internal_method
    # This cannot be called from the frontend
  end
end
```

## License

This project is available as open source under the terms of the MIT License.
