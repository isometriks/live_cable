# Error Handling

When an unhandled exception is raised inside a component, LiveCable replaces the component in the DOM with an error message and cleans up the server-side component and all of its children.

## Where Errors Are Caught

LiveCable catches errors in these places:

- **Actions** — unhandled exceptions raised inside action methods
- **`live-reactive` writes** — exceptions raised by a writable variable's setter
- **`before_dispatch` callbacks** — exceptions raised while authorizing a client message
- **Streaming callbacks** — exceptions raised inside `stream_from` blocks
- **Subscribe and render** — exceptions raised while the component is being set up, or while it renders

Exceptions here means every `StandardError`, and also a `ScriptError` such as `NotImplementedError`, or the
`SyntaxError` or `LoadError` raised when a component or model that a reload picked up fails to load.

Errors from the first four are offered to the component's
[`rescue_from`](#handling-errors-with-rescue-from) handlers before the error
box is shown. A message asking for an action the component doesn't list in
`actions`, or a write to a variable that isn't `writable: true`, raises
`LiveCable::Forbidden`, which is never offered to `rescue_from`. Neither is
[`refuse!`](#refusing-a-component), which stops a component without an error.

An exception from a reactive variable's initial lambda is raised by the render that first reads the variable. For a
component rendered inside a parent, that is the parent's render, so the parent is replaced with the error. A failed
initial value isn't stored, so the next read runs the lambda again.

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

Other components on the connection still render what a failed action or stream callback changed before it raised, such as a `shared: true` variable.

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
matching exception is raised by the component's own code - an action, a
`live-reactive` write, or a `stream_from` callback - the component handles it
instead of being replaced with the default error markup:

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
message. A handled error still answers the message, so the loading state clears
even when the handler changes nothing. If no handler matches, LiveCable falls
back to the default behaviour described above.

A failure while subscribing or rendering is not offered to `rescue_from`: there
is no working render to show your error UI in, so it always gets the default
error markup.
Neither is a message asking for an action the component doesn't expose, or a
write to a reactive variable that isn't `writable:` - those are rejected with
the default error markup whatever handlers you declare.

Handlers can be a block or a method name, exactly as in a controller:

```ruby
rescue_from ActiveRecord::RecordNotFound, with: :redirect_home
```

## Refusing a Component

Losing access while a page is open isn't an error: a membership ended, an
impersonation ran out, an account was deleted. Call `refuse!` where your
component finds out, instead of letting it raise:

```ruby
module Live
  class Board < LiveCable::Component
    before_dispatch :check_membership

    private

    def check_membership
      refuse!('membership_ended') unless membership.active?
    end
  end
end
```

`refuse!` raises `LiveCable::Refused`, which stops whatever was running. It is
never offered to `rescue_from`, even a `rescue_from StandardError`, and it
isn't reported to `Rails.error`. A `rescue_from` handler can call it too, to
turn an error into a refusal:

```ruby
rescue_from ActiveRecord::RecordNotFound do
  refuse!('not_found')
end
```

The server doesn't wait for the client: it disconnects the component at once,
running its disconnect callbacks and stopping its streams, skips the rest of
the message batch, and runs nothing the client sends it afterwards. The
children it owns are destroyed and disconnected with it. The client keeps the
component's markup as it was, sets `data-live-status-value="refused"`, ends
its loading state and unsubscribes. It then dispatches a bubbling
`live:refused` from the component's root, with the reason in
`event.detail.reason`.

A child its parent renders inline with `live(...)` is refused on its own,
including when it refuses in its template while the parent renders it: the
parent renders on without it, and its other children carry on. While the
parent keeps rendering it, the parent's renders don't build it again, and the
client keeps showing it refused, as it last rendered. Once the parent stops
rendering it, or the page is loaded again, it is built afresh. A child that
refuses the first time it renders over the socket can be left showing nothing.

A `refuse!` while rendering also runs during the HTTP prerender, where
nothing catches it, so the page fails as for any exception in a template.
Check access for the page in its controller, and refuse from the component
for what changes while the page is open.

That's the same event, and the same status, as for a
[refused socket](/guide/architecture#a-refused-socket), which fires on
`document`, so one handler covers both:

```javascript
document.addEventListener('live:refused', (event) => {
  showNotice("You no longer have access to this. Reload to continue.")
})
```

A 0.5 client doesn't know a refusal. It shows the error box instead, which in
production reads "An error occurred", and unsubscribes as for any error.

## Next Steps

- [Actions & Events](/guide/actions-events)
- [Streaming](/guide/streaming)
