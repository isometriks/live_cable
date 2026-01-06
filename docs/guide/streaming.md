# Streaming from ActionCable Channels

LiveCable components can subscribe to ActionCable channels using the `stream_from` method. This allows components to react to real-time broadcasts from anywhere in your application, making it easy to build collaborative features like chat rooms, live notifications, or shared dashboards.

## Basic Usage

Call `stream_from` in a connection callback to subscribe to a channel:

```ruby
module Live
  module Chat
    class ChatRoom < LiveCable::Component
      reactive :messages, -> { [] }, shared: true

      after_connect :subscribe_to_chat

      private

      def subscribe_to_chat
        stream_from("chat_messages", coder: ActiveSupport::JSON) do |data|
          messages << data
        end
      end
    end
  end
end
```

::: tip Callback Usage
Use `after_connect` to set up streams. Within a page, if Stimulus briefly disconnects and reconnects (e.g. during a parent re-render), the existing subscription is reused and `connect` does not fire again, so streams won't be recreated. When navigating to a new page with Turbo Drive, the subscription is closed and recreated, so `connect` will fire again on the new page.
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
2. You can update reactive variables inside the callback
3. LiveCable automatically detects the changes and broadcasts updates to all affected components
4. All components sharing the same reactive variables are re-rendered

## Complete Chat Example

This example splits the chat into two components — `ChatRoom` for displaying messages, and `ChatInput` for sending them. Both share the same `messages` and `typing_users` reactive variables via `shared: true`, so updates in one component are instantly reflected in the other.

### ChatRoom Component

```ruby
module Live
  module Chat
    class ChatRoom < LiveCable::Component
      reactive :messages, -> { [] }, shared: true
      reactive :typing_users, -> { [] }, shared: true
      
      after_connect :subscribe_to_streams
      
      private
      
      def subscribe_to_streams
        # Subscribe to chat messages
        stream_from("chat_messages", coder: ActiveSupport::JSON) do |data|
          messages << data
          
          # Keep only last 100 messages
          messages.shift if messages.size > 100
        end
        
        # Subscribe to typing indicators
        stream_from("chat_typing", coder: ActiveSupport::JSON) do |data|
          if data[:typing]
            typing_users << data[:user] unless typing_users.include?(data[:user])
          else
            typing_users.delete(data[:user])
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
    <div class="messages">
      <% messages.each do |message| %>
        <div class="message" live-key="<%= message[:id] %>">
          <strong><%= message[:user][:first_name] %></strong>
          <p><%= message[:text] %></p>
          <small><%= Time.at(message[:timestamp]).strftime('%I:%M %p') %></small>
        </div>
      <% end %>
    </div>

    <div class="typing-indicator <%= 'hidden' unless typing_users.any? %>">
      <%= typing_users.map { |u| u[:first_name] }.join(', ') %>
      <%= typing_users.size == 1 ? 'is' : 'are' %> typing...
    </div>
  </div>
</div>
```

### ChatInput Component

```ruby
module Live
  module Chat
    class ChatInput < LiveCable::Component
      reactive :message, -> { "" }
      
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
  <form live-form="send_message">
    <input type="text"
           name="message"
           value="<%= message %>"
           placeholder="Type a message..."
           live-reactive
           live-action="input->typing">
    <button type="submit">Send</button>
  </form>
</div>
```

## Use Cases

### Live Notifications

```ruby
module Live
  class NotificationCenter < LiveCable::Component
    reactive :notifications, -> { [] }
    
    after_connect :subscribe_to_notifications
    
    private
    
    def subscribe_to_notifications
      stream_from("user_notifications_#{current_user.id}", coder: ActiveSupport::JSON) do |notification|
        notifications.unshift(notification)
        
        # Keep only last 10 notifications
        notifications.pop if notifications.size > 10
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
        case data[:type]
        when 'content_updated'
          document.reload if data[:user][:id] != current_user.id
        when 'user_joined'
          active_users << data[:user] unless active_users.any? { |u| u[:id] == data[:user][:id] }
        when 'user_left'
          active_users.reject! { |u| u[:id] == data[:user][:id] }
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
        metrics.merge!(data[:metrics])
        
        if data[:alert]
          alerts.unshift(data[:alert])
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
# ✅ User-scoped - only this user's component receives it
stream_from("notifications_#{current_user.id}", coder: ActiveSupport::JSON) do |data|
  notifications.unshift(data)
end

# ❌ Global - every connected component receives it
stream_from("notifications", coder: ActiveSupport::JSON) do |data|
  notifications.unshift(data)
end
```

Similarly, when broadcasting from anywhere in your app, make sure only authorized callers can trigger the broadcast (e.g., background jobs that verify ownership before calling `ActionCable.server.broadcast`).

## Key Features

- **Automatic re-rendering**: Changes to reactive variables inside stream callbacks trigger re-renders
- **Shared state**: Combine with `shared: true` reactive variables to sync state across multiple component instances
- **Connection-scoped**: Each user's component instances receive broadcasts independently
- **Coder support**: Use `coder: ActiveSupport::JSON` to automatically decode JSON payloads
- **Multiple streams**: Components can subscribe to multiple streams simultaneously
- **Automatic cleanup**: Streams are automatically stopped when the component disconnects

## Best Practices

### Do

✅ Always scope channel names with a user or resource identifier
✅ Use descriptive channel names that indicate the data type
✅ Use JSON coder for structured data
✅ Clean up or limit collection sizes to prevent memory bloat
✅ Use `live-key` attributes for list items to preserve identity

### Don't

❌ Don't use global channel names — every component subscribing to that name will receive the broadcast
❌ Don't broadcast sensitive data without verifying the caller is authorized
❌ Don't subscribe to broad channels that send unnecessary updates
❌ Don't perform expensive operations inside stream callbacks

## Next Steps

- [Understand the architecture](/guide/architecture)
- [Learn about lifecycle callbacks](/guide/lifecycle-callbacks)
- [Read the Component API](/api/component)
