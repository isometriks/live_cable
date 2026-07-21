# Testing Components

LiveCable ships with a test harness for unit testing components without a browser or a real ActionCable connection. Tests run in milliseconds, and because actions are dispatched through the real message pipeline, they exercise exactly what production runs: action whitelisting, parameter parsing, writability checks, change tracking, and re-rendering.

## Setup

Include `LiveCable::Testing` in your specs:

```ruby
# spec/rails_helper.rb (or a support file)
RSpec.configure do |config|
  config.include LiveCable::Testing, type: :component

  config.define_derived_metadata(file_path: %r{spec/components}) do |metadata|
    metadata[:type] = :component
  end
end
```

Or include it directly in a spec:

```ruby
RSpec.describe Live::Counter do
  include LiveCable::Testing
end
```

## Mounting a Component

`live_mount` mirrors what happens when a component subscribes in production: it registers the component on a connection, applies defaults, runs `connect` lifecycle callbacks, and broadcasts the initial render.

```ruby
counter = live_mount('counter')                    # by name
counter = live_mount(Live::Counter)                # by class
counter = live_mount('counter', id: 'sidebar')     # custom id
counter = live_mount('counter', count: 10, step: 5) # with defaults
```

The returned object delegates to the component, so reactive variables and component methods are readable directly:

```ruby
counter.count       # => 10
counter.live_id     # => "counter/test"
counter.component   # the underlying Live::Counter instance
```

## Performing Actions

`perform` dispatches an action exactly as `live-action` or `live-form` would from the browser. Params go through a query-string round trip, so your action receives `ActionController::Parameters` with **string values** — just like production:

```ruby
counter.perform(:increment)

form.perform(:update_form, user: { name: 'Alice', email: 'alice@example.com' })
```

Actions that aren't whitelisted with `actions` raise `LiveCable::Error`, so a forgotten declaration fails loudly in your tests.

## Reactive Updates from the Client

`set_reactive` simulates a `live-reactive` input update. Non-writable variables raise, so you can verify your `writable:` declarations:

```ruby
counter.set_reactive(:step, '5')   # step is writable: true

expect do
  counter.set_reactive(:count, '999')
end.to raise_error(LiveCable::Error, /Non-writable/)
```

## Asserting on Rendered HTML

`rendered` returns the component's current HTML as a `Capybara::Node::Simple`, reconstructed from render broadcasts the same way the JavaScript client builds the DOM — partial rendering included:

```ruby
counter.perform(:increment)

expect(counter.rendered).to have_css('[data-testid="counter-value"]', text: '1')
expect(counter.rendered_html).to include('live-action="increment"')
```

## Asserting on Broadcasts

Everything the component broadcasts is captured. Filter by payload key:

```ruby
counter.broadcasts             # all broadcasts, oldest first
counter.broadcasts(:_refresh)  # re-renders
counter.broadcasts(:_error)    # error payloads
counter.clear_broadcasts       # forget the mount's initial render
```

This makes "did it re-render?" testable directly:

```ruby
counter.clear_broadcasts
counter.perform(:noop)

expect(counter.broadcasts(:_refresh)).to be_empty
```

## Errors

By default, errors raised inside actions, rendering, or stream callbacks are re-raised so tests fail with the real exception and backtrace. To test production error behavior instead, mount with `raise_errors: false` and assert on the `_error` broadcast:

```ruby
component = live_mount('checkout', raise_errors: false)

component.perform(:pay)

expect(component.broadcasts(:_error)).not_to be_empty
```

## Streams

Components that subscribe to ActionCable streams via `stream_from` can receive simulated broadcasts. Payloads go through the stream's coder round trip, so hashes arrive with string keys like real broadcasts:

```ruby
chat = live_mount('chat_room')

chat.receive_stream('chat_messages', { text: 'hello' })

expect(chat.messages.last).to eq('hello')
expect(chat.rendered).to have_content('hello')
```

## Shared State Across Components

Mount multiple components on the same connection to test `shared:` reactive variables:

```ruby
cart    = live_mount('cart_display')
filters = live_mount('filter_panel', connection: cart.connection)

cart.perform(:add_to_cart, item: 'book')

expect(filters.cart_items.size).to eq(1)
```

## Connection Identifiers

If your components use `identified_by` values from the ActionCable connection (like `current_user`), provide them at mount:

```ruby
profile = live_mount('user_profile', identifiers: { current_user: user })

expect(profile.current_user).to eq(user)
```

## Lifecycle

`unmount` disconnects the component, running `disconnect` callbacks and cleaning up streams and state — like a client unsubscribing:

```ruby
component = live_mount('dashboard')
component.unmount
```

## What Still Needs a Browser Test

The harness covers everything server-side. Client-side behavior — morphing, debouncing, loading states, focus preservation, Stimulus wiring — still belongs in system specs with a real browser.
