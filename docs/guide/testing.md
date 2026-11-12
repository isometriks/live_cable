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
list = live_mount('product_list', at: '/products?page=2') # on a page
```

Defaults are applied as given. A top-level component gets them back from the
page as JSON, so a Symbol default arrives as a String; a child gets exactly
what its parent passes. Pass the values the component would receive.

Renders run on a request for `http://test.host` with an empty session, as a
socket's would (see
[Rendering Over the Socket](/guide/components#rendering-over-the-socket)).
`at:` is the path and query of the page the component is on, which the client
sends when it subscribes; without it, `request.path` is empty and
`url_for(page: 2)` raises, as it does for a client that sends none.

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

`set_reactive` simulates a `live-reactive` input update. Pass the value the browser would send: `true` or `false` for a checkbox, an Array of Strings for a `<select multiple>`, and a String for anything else. Non-writable variables raise, so you can verify your `writable:` declarations:

```ruby
counter.set_reactive(:step, '5')   # step is writable: true

expect do
  counter.set_reactive(:count, '999')
end.to raise_error(LiveCable::Error, /Non-writable/)
```

## Asserting on Rendered HTML

`rendered` returns the component's current HTML as a `Capybara::Node::Simple`, rebuilt from every render the component has sent, the same way the JavaScript client builds the DOM: partial rendering included, and children rendered inline at any depth filled in, with what a [subscribed child](#child-components) has since sent on its own channel. It reflects every render since the mount, whatever `clear_broadcasts` has cleared:

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
counter.broadcasts(:_ack)      # replies to messages that didn't re-render
counter.broadcasts(:_error)    # error payloads
counter.clear_broadcasts       # start the log over; rendered is unaffected
```

`clear_broadcasts` also starts `dispatched_events` over.

This makes "did it re-render?" testable directly:

```ruby
counter.clear_broadcasts
counter.perform(:noop)

expect(counter.broadcasts(:_refresh)).to be_empty
```

A `_refresh` that answers the component's own message carries `_reply: true`;
one it didn't ask for, from a stream callback or another component changing a
shared variable, carries `_reply: false`. The render and the status frame sent
when it subscribes carry `_subscribed: true`. An `_ack` carries
`_rendered: true` when the component's new render went out inside its parent's
`_refresh`.

A message a `before_dispatch` callback refuses with `throw :abort` is skipped
and answered with an `_ack`:

```ruby
doc = live_mount('document', role: 'viewer')
doc.clear_broadcasts

doc.perform(:archive)

expect(doc.broadcasts).to eq([{ _ack: true }])
expect(doc.archived).to be(false)
```

## Asserting on Dispatched Events

Events sent with `dispatch_event` are captured in order, whether they rode along with a render or an acknowledgement, or were delivered on their own:

```ruby
chat.perform(:send_message, text: 'hi')

expect(chat.dispatched_events).to include(
  hash_including(name: 'chat:message-sent')
)
```

## Errors

By default, errors raised inside actions, `rescue_from` handlers, rendering, `connect` callbacks, or stream callbacks are re-raised so tests fail with the real exception and backtrace. To test production error behavior instead, mount with `raise_errors: false` and assert on the `_error` broadcast:

```ruby
component = live_mount('checkout', raise_errors: false)

component.perform(:pay)

expect(component.broadcasts(:_error)).not_to be_empty
```

This covers mounting too: a component whose first render or a `connect` callback raises is still returned by `live_mount`, with the `_error` in its broadcasts. If the error came from a `connect` callback, the component never connected, so `perform` on it runs nothing and broadcasts another `_error`, as production answers the client.

A [`refuse!`](/guide/error-handling#refusing-a-component), or a `before_connect` that throws `:abort`, is never re-raised, whatever `raise_errors` says. Ask the component whether it refused, and read the reason from its broadcasts:

```ruby
board = live_mount('board', membership_active: false)

board.perform(:move_card)

expect(board).to be_refused
expect(board.broadcasts(:_refused).last[:_reason]).to eq('membership_ended')
```

## Streams

Components that subscribe to ActionCable streams via `stream_from` can receive simulated broadcasts. Payloads go through the stream's coder round trip, so hashes arrive with string keys like real broadcasts:

```ruby
chat = live_mount('chat_room')

chat.receive_stream('chat_messages', { text: 'hello' })

expect(chat.messages.last).to eq('hello')
expect(chat.rendered).to have_content('hello')
```

### Collection Streams

`stream_ids` returns the keys of a [collection stream](/api/component#stream-name-initial-nil-dom-id-nil-limit-nil)'s
rows as the page holds them, in order, and an empty list while the stream isn't shown. `stream_ops` returns the
row ops the component's renders sent for it since the last `clear_broadcasts`, with a render that sent the stream
whole as `["reset", keys]`:

```ruby
chat = live_mount('chat', room_id: 1)
expect(chat.stream_ids(:messages)).to eq(%w[messages_message_1 messages_message_2])

chat.clear_broadcasts
chat.receive_stream('chat_room_1', { 'event' => 'created', 'id' => 3 })

expect(chat.stream_ops(:messages).map(&:first)).to eq(%w[a])
expect(chat.stream_ids(:messages).last).to eq('messages_message_3')
```

Change a stream from the spec itself with `live_update`, as a thread of your own would:

```ruby
chat.live_update { chat.stream_delete(:messages, 'messages_message_1') }
```

`verify_stream_items` is on in the test environment, so a row whose own `id` isn't its key raises in your specs.

## Shared State Across Components

Mount multiple components on the same connection to test `shared:` reactive variables:

```ruby
cart    = live_mount('cart_display')
filters = live_mount('filter_panel', connection: cart.connection)

cart.perform(:add_to_cart, item: 'book')

expect(filters.cart_items.size).to eq(1)
```

## Child Components

A child the component renders inline with `live(...)` is on the same connection but hasn't subscribed: in
the browser its own controller subscribes once the parent's render reaches the page. Until then nothing is
rendered for it on its own, and what changes for it waits. `subscribe_child` subscribes it, sending its render
when anything changed for it since its parent rendered it, or only its status otherwise, and returns it to
test like a mounted component:

```ruby
list = live_mount('todo_list')
todo = list.subscribe_child('todo/write')
todo.clear_broadcasts

todo.perform(:complete)

expect(todo.broadcasts).to eq([{ _ack: true, _rendered: true }])
```

## Connection Identifiers

If your components use `identified_by` values from the ActionCable connection (like `current_user`), provide them at mount:

```ruby
profile = live_mount('user_profile', identifiers: { current_user: user })

expect(profile.current_user).to eq(user)
```

## Lifecycle

`unmount` disconnects the component and the children it renders, running their `disconnect` callbacks and cleaning up streams and state — like a client unsubscribing:

```ruby
component = live_mount('dashboard')
component.unmount
```

## What Still Needs a Browser Test

The harness covers everything server-side. Client-side behavior — morphing, debouncing, loading states, focus preservation, Stimulus wiring — still belongs in system specs with a real browser.
