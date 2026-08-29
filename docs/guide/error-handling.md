# Error Handling

When an unhandled exception is raised inside a component, LiveCable replaces the component in the DOM with an error message and cleans up the server-side component and all of its children.

## Where Errors Are Caught

LiveCable catches errors in three places:

- **Actions** — unhandled exceptions raised inside action methods
- **Streaming callbacks** — exceptions raised inside `stream_from` blocks
- **Subscribe** — exceptions raised while the component is being set up (before the first render)

## Default Behaviour

In development and test environments (`verbose_errors` is `true` by default), the error message shows the component class name, the exception class and message, and a full backtrace:

```
MyComponent - RuntimeError: something went wrong
  app/live/my_component.rb:12:in 'do_something'
  ...
```

In production (`verbose_errors` defaults to `false`), a generic message is shown with no internal details:

```
An error occurred
```

All errors are also reported via `Rails.error.report`, so they will appear in your configured error tracker (Sentry, Honeybadger, etc.) regardless of the `verbose_errors` setting.

## Configuration

Override the default in an initializer:

```ruby
# config/initializers/live_cable.rb
LiveCable.configure do |config|
  config.verbose_errors = false  # never show details
  # or
  config.verbose_errors = true   # always show details (not recommended in production)
end
```

## Cleanup Behaviour

When an error is broadcast:

1. All child components are destroyed first, so their `_status: destroy` messages arrive before the error.
2. The error HTML is sent to the client via a `_error` broadcast.
3. The client replaces the component element with the error HTML and unsubscribes.
4. The unsubscribe triggers `LiveChannel#unsubscribed`, which calls `disconnect` on the server-side component to complete cleanup.

## Best Practices

Unhandled errors are a last resort. Where possible, handle expected error cases gracefully inside the component:

```ruby
def submit(params)
  result = MyService.call(params)

  if result.success?
    self.status = :done
  else
    self.error_message = result.error
  end
rescue MyService::NetworkError => e
  self.error_message = "Service temporarily unavailable"
  Rails.logger.warn("MyService failed: #{e.message}")
end
```

## Handling Errors with `rescue_from`

For error handling that spans multiple actions, components support
`rescue_from` (from `ActiveSupport::Rescuable`, the same API used by
`ActionController::Base`). Declare a handler for an exception class and, when a
matching exception is raised anywhere LiveCable catches errors (actions,
streaming callbacks, or subscribe), the component handles it instead of being
replaced with the default error markup:

```ruby
module Live
  class Dashboard < LiveCable::Component
    reactive :error_message, -> { nil }

    rescue_from MyService::NetworkError do |error|
      self.error_message = "Service temporarily unavailable"
      Rails.logger.warn("MyService failed: #{error.message}")
    end

    actions :refresh

    def refresh
      self.data = MyService.fetch # may raise MyService::NetworkError
    end
  end
end
```

Any reactive state the handler changes is re-rendered in the same cycle, so the
component stays alive and shows your error UI rather than the fallback `_error`
message. If no handler matches, LiveCable falls back to the default behaviour
described above. Handlers can be a block or a method name, exactly as in a
controller:

```ruby
rescue_from ActiveRecord::RecordNotFound, with: :redirect_home
```

## Next Steps

- [Actions & Events](/guide/actions-events)
- [Streaming](/guide/streaming)
