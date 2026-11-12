# Broadcasts (stream_from)

LiveCable components can subscribe to ActionCable channels using the `stream_from` method. This allows components to react to real-time broadcasts from anywhere in your application, making it easy to build collaborative features like chat rooms, live notifications, or shared dashboards.

::: tip Lists that grow
A broadcast that adds to a list, such as a chat message or a notification, is best sent to a [collection stream](/guide/collection-streams): the page gets only the new row, and the server keeps none of the list. A reactive Array that every message appends to is held in memory for every viewer, and its loop runs over the whole list whenever it changes.
:::

## Basic Usage

Call `stream_from` in a connection callback to subscribe to a channel. This
chat inserts each message it is sent into a
[collection stream](/guide/collection-streams), so the page gets only the new
message:

```ruby
module Live
  module Chat
    class ChatRoom < LiveCable::Component
      stream :messages, dom_id: ->(message) { "message-#{message['id']}" }

      after_connect :subscribe_to_chat

      private

      def subscribe_to_chat
        stream_from("chat_messages", coder: ActiveSupport::JSON) do |data|
          stream_insert :messages, data
        end
      end
    end
  end
end
```

```erb
<div>
  <ul live-stream="messages">
    <%= live_stream_for :messages do |message| %>
      <li><%= message['text'] %></li>
    <% end %>
  </ul>
</div>
```

A callback can also set reactive variables, as an action does, and the parts
of the template that read them render again.

::: tip Callback Usage
Use `after_connect` to set up streams. Within a page, if Stimulus briefly disconnects and reconnects (e.g. during a parent re-render), the existing subscription is reused and `connect` does not fire again, so streams won't be recreated. A component on both pages of a Turbo Drive visit keeps its subscription and its streams too; `connect` fires again only for a new component, one the new page renders with different defaults (unless Turbo carries it over in a `data-turbo-permanent` element), or after an identity change reopens the socket. See [Connection Persistence](/guide/lifecycle-callbacks#connection-persistence).
:::

## Broadcasting to Streams

Any part of your application can broadcast to the stream using ActionCable's broadcast API:

```ruby
module Live
  module Chat
    class ChatInput < LiveCable::Component
      reactive :message, -> { "" }
      
      actions :send_message

      def send_message(params)
        return if params[:message].blank?

        message_data = {
          id: SecureRandom.uuid,
          text: params[:message],
          timestamp: Time.now.to_i,
          user: current_user.as_json(only: [:id, :first_name, :last_name])
        }

        # Broadcast to the chat stream
        ActionCable.server.broadcast("chat_messages", message_data)

        # Clear the input
        self.message = ""
      end
    end
  end
end
```

## How It Works

When a broadcast is received:

1. The stream callback is executed with the broadcast payload
2. You can update reactive variables, or insert, update and delete a collection stream's rows, inside the callback
3. LiveCable automatically detects the changes and broadcasts updates to all affected components
4. All components sharing the same reactive variables are re-rendered

When several components on a page stream from the same channel, each gets the
broadcast in a callback of its own, run by ActionCable as a separate job. On
one connection they run one at a time, each followed by its render, but in no
order you can rely on; usually it is the order the components subscribed. If
what one does with a broadcast depends on another, such as a notification
bell that shouldn't count what an open feed is already showing, don't depend
on which runs first: have the feed set a
[shared variable](/guide/reactive-variables#shared-variables) ahead of time,
such as in its `after_connect`, for the bell's callback to read. One the feed
sets in its own callback races the same way.

## Stopping Streams

Streams stop by themselves when the component disconnects, including when a Turbo Frame render or Turbo Stream action takes it off the page (see [Subscription Persistence](/guide/architecture#subscription-persistence)). To stop one sooner, call `stop_stream_from` with its name, or `stop_stream` to stop every stream the component has started. A chat that moves between rooms stops the old room's stream and starts the new one's:

```ruby
module Live
  module Chat
    class ChatRoom < LiveCable::Component
      reactive :room_id, -> { 1 }

      stream :messages, dom_id: ->(message) { "message-#{message['id']}" }

      actions :switch_room

      after_connect :join_room

      def switch_room(params)
        stop_stream_from(room_stream)

        self.room_id = params[:room_id].to_i
        stream_reset :messages

        join_room
      end

      private

      def room_stream
        "chat_room_#{room_id}"
      end

      def join_room
        stream_from(room_stream, coder: ActiveSupport::JSON) do |data|
          stream_insert :messages, data
        end
      end
    end
  end
end
```

`stream_reset` empties the list, or refills it from the stream's lambda when it
has one; see [Switching Rooms](/guide/collection-streams#switching-rooms) for a
room whose messages are saved.

Once `stop_stream` or `stop_stream_from` returns, no callback for that stream runs. ActionCable runs each broadcast as a job of its own on its worker pool and can't take one back once it is queued, so a message for the old room can still be on its way while the room switches; LiveCable drops it rather than insert it into the new room's list. Stopping a stream and starting it again under the same name still delivers a broadcast that was already on its way.

Calling `stream_from` with a name the component already streams from, such as from both `after_connect` and an action, replaces the callback and keeps the stream, so each broadcast runs the newer callback once. With a different `coder:` it stops the stream and starts a new one; a broadcast already on its way to the old one is dropped.

This holds wherever LiveCable calls your code: actions, lifecycle callbacks and stream callbacks all run under the connection's lock. From a thread of your own, stop streams inside `live_connection.synchronize { ... }` (see [Concurrency](/guide/architecture#concurrency)).

## Complete Chat Example

This example splits the chat into two components — `ChatRoom` for displaying messages, and `ChatInput` for sending them. They share no state: `ChatInput` broadcasts messages and typing changes to the `chat_messages` and `chat_typing` streams, and `ChatRoom` streams from both, inserting each message into its `messages` [collection stream](/guide/collection-streams) and keeping who is typing in its `typing_users` reactive variable, so every open chat room updates, the sender's included.

### ChatRoom Component

```ruby
module Live
  module Chat
    class ChatRoom < LiveCable::Component
      stream :messages, dom_id: ->(message) { "message-#{message['id']}" }, limit: 100
      reactive :typing_users, -> { [] }

      after_connect :subscribe_to_streams

      private

      def subscribe_to_streams
        # Subscribe to chat messages
        stream_from("chat_messages", coder: ActiveSupport::JSON) do |data|
          stream_insert :messages, data
        end

        # Subscribe to typing indicators
        stream_from("chat_typing", coder: ActiveSupport::JSON) do |data|
          if data['typing']
            typing_users << data['user'] unless typing_users.include?(data['user'])
          else
            typing_users.delete(data['user'])
          end
        end
      end
    end
  end
end
```

**View** (`app/views/live/chat/chat_room.html.live.erb`):
```erb
<div>
  <div class="chat-room">
    <div class="messages" live-stream="messages">
      <%= live_stream_for :messages do |message| %>
        <div class="message">
          <strong><%= message['user']['first_name'] %></strong>
          <p><%= message['text'] %></p>
          <small><%= Time.at(message['timestamp']).strftime('%I:%M %p') %></small>
        </div>
      <% end %>
    </div>

    <div class="typing-indicator <%= 'hidden' unless typing_users.any? %>">
      <%= typing_users.map { |u| u['first_name'] }.join(', ') %>
      <%= typing_users.size == 1 ? 'is' : 'are' %> typing...
    </div>
  </div>
</div>
```

The stream has no initial lambda, so the room starts empty and shows the messages sent while it is open, at most the last 100: `limit:` trims the oldest as new ones arrive. Each message's `id` is its row's key, and each broadcast sends the page that one row, so the typing indicator changing doesn't re-send the messages. A chat whose messages are saved would read the latest ones in the stream's lambda and broadcast ids from the model; see [Broadcasting from the Model](/guide/collection-streams#broadcasting-from-the-model).

### ChatInput Component

```ruby
module Live
  module Chat
    class ChatInput < LiveCable::Component
      reactive :message, -> { "" }, writable: true
      
      actions :send_message, :typing
      
      def send_message(params)
        return if message.blank?
        
        ActionCable.server.broadcast("chat_messages", {
          id: SecureRandom.uuid,
          text: message,
          timestamp: Time.now.to_i,
          user: current_user.as_json(only: [:id, :first_name, :last_name])
        })
        
        # Clear typing indicator
        ActionCable.server.broadcast("chat_typing", {
          user: current_user.as_json(only: [:id, :first_name]),
          typing: false
        })
        
        self.message = ""
      end
      
      def typing(params)
        ActionCable.server.broadcast("chat_typing", {
          user: current_user.as_json(only: [:id, :first_name]),
          typing: params[:message].present?
        })
      end
    end
  end
end
```

**View** (`app/views/live/chat/chat_input.html.live.erb`):
```erb
<div>
  <form live-form="submit->send_message input->typing">
    <input type="text"
           name="message"
           value="<%= message %>"
           placeholder="Type a message..."
           live-reactive>
    <button type="submit">Send</button>
  </form>
</div>
```

`live-reactive` writes each keystroke to `message`, which is why it is declared `writable: true`, and resetting `message` in `send_message` clears the field. The form's `input->typing` sends the form's fields with every keystroke, so `typing` reads the current text from `params[:message]`.

## Use Cases

### Live Notifications

```ruby
module Live
  class NotificationCenter < LiveCable::Component
    # Newest first, keeping the last 10
    stream :notifications, dom_id: ->(notification) { "notification-#{notification['id']}" }, limit: 10

    after_connect :subscribe_to_notifications

    private

    def subscribe_to_notifications
      stream_from("user_notifications_#{current_user.id}", coder: ActiveSupport::JSON) do |notification|
        stream_insert :notifications, notification, at: :start
      end
    end
  end
end
```

Broadcast notifications from anywhere:

```ruby
# In a background job, controller, or model callback
ActionCable.server.broadcast(
  "user_notifications_#{user.id}",
  {
    id: notification.id,
    title: "New message",
    body: "You have a new message from #{sender.name}",
    timestamp: Time.now.to_i
  }
)
```

### Collaborative Editing

```ruby
module Live
  class DocumentEditor < LiveCable::Component
    reactive :document, -> { nil }
    reactive :active_users, -> { [] }

    after_connect :load_document
    after_disconnect :leave_document

    actions :update_content

    def update_content(params)
      document.update(content: params[:content])

      ActionCable.server.broadcast("document_#{document.id}", {
        type: 'content_updated',
        content: params[:content],
        user: current_user.as_json(only: [:id, :name])
      })
    end

    private

    def load_document
      self.document = Document.find(defaults[:document_id])
      subscribe_to_document
    end

    def subscribe_to_document
      stream_from("document_#{document.id}", coder: ActiveSupport::JSON) do |data|
        case data['type']
        when 'content_updated'
          document.reload if data['user']['id'] != current_user.id
        when 'user_joined'
          active_users << data['user'] unless active_users.any? { |u| u['id'] == data['user']['id'] }
        when 'user_left'
          active_users.reject! { |u| u['id'] == data['user']['id'] }
        end
      end

      # Announce presence
      ActionCable.server.broadcast("document_#{document.id}", {
        type: 'user_joined',
        user: current_user.as_json(only: [:id, :name, :avatar_url])
      })
    end

    def leave_document
      ActionCable.server.broadcast("document_#{document.id}", {
        type: 'user_left',
        user: current_user.as_json(only: [:id])
      })
    end
  end
end
```

Rendered with the document ID as a default:

```erb
<%= live('document_editor', id: "doc-#{@document.id}", document_id: @document.id) %>
```

### Live Dashboards

```ruby
module Live
  class Dashboard < LiveCable::Component
    reactive :metrics, -> { {} }
    reactive :alerts, -> { [] }
    
    after_connect :subscribe_to_metrics
    
    private
    
    def subscribe_to_metrics
      stream_from("dashboard_metrics", coder: ActiveSupport::JSON) do |data|
        metrics.merge!(data['metrics'])
        
        if data['alert']
          alerts.unshift(data['alert'])
          alerts.pop if alerts.size > 5
        end
      end
    end
  end
end
```

Update from background jobs:

```ruby
class MetricsUpdateJob < ApplicationJob
  def perform
    metrics = {
      active_users: User.active.count,
      revenue: Order.today.sum(:total),
      pending_orders: Order.pending.count
    }
    
    ActionCable.server.broadcast("dashboard_metrics", {
      metrics: metrics,
      timestamp: Time.now.to_i
    })
  end
end
```

## Channel Authorization

LiveCable does not enforce who can receive a broadcast — that's your responsibility. Always scope channel names to the appropriate user or resource so broadcasts only reach the right people:

```ruby
stream :notifications, dom_id: ->(notification) { "notification-#{notification['id']}" }

# ✅ User-scoped - only this user's component receives it
stream_from("notifications_#{current_user.id}", coder: ActiveSupport::JSON) do |data|
  stream_insert :notifications, data, at: :start
end

# ❌ Global - every connected component receives it
stream_from("notifications", coder: ActiveSupport::JSON) do |data|
  stream_insert :notifications, data, at: :start
end
```

Similarly, when broadcasting from anywhere in your app, make sure only authorized callers can trigger the broadcast (e.g., background jobs that verify ownership before calling `ActionCable.server.broadcast`).

## Key Features

- **Automatic re-rendering**: Changes to reactive variables inside stream callbacks trigger re-renders
- **Shared state**: Combine with `shared: true` reactive variables to sync state across multiple component instances
- **Connection-scoped**: Each user's component instances receive broadcasts independently
- **Coder support**: Use `coder: ActiveSupport::JSON` to automatically decode JSON payloads. Decoded hashes have string keys: read `data['user']`, not `data[:user]`
- **Multiple streams**: Components can subscribe to multiple streams simultaneously
- **Automatic cleanup**: Streams are automatically stopped when the component disconnects

## Best Practices

### Do

✅ Always scope channel names with a user or resource identifier
✅ Use descriptive channel names that indicate the data type
✅ Use JSON coder for structured data
✅ Insert into a [collection stream](/guide/collection-streams) for lists that grow with each broadcast
✅ Use `live-key` attributes for list items to preserve identity

### Don't

❌ Don't use global channel names — every component subscribing to that name will receive the broadcast
❌ Don't broadcast sensitive data without verifying the caller is authorized
❌ Don't subscribe to broad channels that send unnecessary updates
❌ Don't perform expensive operations inside stream callbacks

## Next Steps

- [Stream rows into a list](/guide/collection-streams)
- [Understand the architecture](/guide/architecture)
- [Learn about lifecycle callbacks](/guide/lifecycle-callbacks)
- [Read the Component API](/api/component)
