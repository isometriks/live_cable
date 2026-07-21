# Server Events

Rendering isn't always enough. Some interactions need the client to *do* something after the server finishes: scroll a chat to the newest message, close a modal after a successful save, focus a field, show a toast, or poke a chart library. `dispatch_event` lets components trigger DOM events on the client.

## Dispatching Events

Call `dispatch_event` from actions, lifecycle callbacks, or `stream_from` callbacks:

```ruby
module Live
  class ChatRoom < LiveCable::Component
    reactive :messages, -> { [] }, shared: true

    actions :send_message

    def send_message(params)
      messages << { text: params[:text], user: current_user.name }

      dispatch_event('chat:message-sent')
    end
  end
end
```

The payload is available on the client as `event.detail`, and can be passed as keyword arguments or a hash:

```ruby
dispatch_event('toast:show', message: 'Profile saved', level: 'success')
dispatch_event('toast:show', { message: 'Profile saved' })  # equivalent
```

## Handling Events

On the client, each event fires as a **bubbling `CustomEvent` dispatched from the component's root element** — which means plain Stimulus `data-action` syntax handles it, with no LiveCable-specific JavaScript:

```erb
<div data-controller="chat" data-action="chat:message-sent->chat#scrollToBottom">
  <div data-chat-target="list">
    <% messages.each do |message| %>
      <p><%= message[:text] %></p>
    <% end %>
  </div>
</div>
```

```javascript
// chat_controller.js - ordinary Stimulus
export default class extends Controller {
  static targets = ['list']

  scrollToBottom() {
    this.listTarget.scrollTop = this.listTarget.scrollHeight
  }
}
```

Because events bubble, a handler anywhere above the component works too — a toast container on `<body>`, or a plain listener:

```javascript
document.addEventListener('toast:show', (event) => {
  showToast(event.detail.message, event.detail.level)
})
```

## Ordering: Events Fire After the Morph

Events dispatched during an action ride along with that action's render and fire **after the DOM has been morphed**. When your handler runs, the new state is already on the page — so scroll-to-bottom measures the right height, and a handler can safely query for elements the action just added.

If the action didn't change any state, the events are delivered on their own; either way, every `dispatch_event` call is delivered exactly once, in order.

## Window Events

For global listeners that live outside any component tree, dispatch on `window` instead:

```ruby
dispatch_event('analytics:tracked', window: true)
```

```javascript
window.addEventListener('analytics:tracked', handler)
```

If your event payload itself needs a `window` key, pass the detail as an explicit hash: `dispatch_event('resize:done', { window: 'main' })`.

## Events from Streams

`stream_from` callbacks can dispatch events too, which makes "new message arrived from another user" scroll behavior symmetrical with your own sends:

```ruby
after_connect :subscribe_to_chat

private

def subscribe_to_chat
  stream_from('chat_messages', coder: ActiveSupport::JSON) do |data|
    messages << data

    dispatch_event('chat:message-sent')
  end
end
```

## Testing

Server-side event dispatch is fully testable with the [testing harness](/guide/testing) — no browser needed:

```ruby
chat = live_mount('chat_room')

chat.perform(:send_message, text: 'hi')

expect(chat.dispatched_events).to include(
  hash_including(name: 'chat:message-sent')
)
```

`dispatched_events` returns every event the component dispatched, in order, whether it rode along with a render or was delivered on its own.

## Naming Conventions

Use a `namespace:event-name` format (e.g. `chat:message-sent`, `modal:close`). It reads naturally in Stimulus `data-action` attributes and avoids collisions with native DOM events.
