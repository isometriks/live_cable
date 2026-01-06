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
Use `after_connect` to set up streams. The `connect` callback only fires once per component lifecycle, so streams won't be recreated on reconnections.
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

**View** (`app/views/live/chat/chat_room.html.erb`):
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

    <% if typing_users.any? %>
      <div class="typing-indicator">
        <%= typing_users.map { |u| u[:first_name] }.join(', ') %>
        <%= typing_users.size == 1 ? 'is' : 'are' %> typing...
      </div>
    <% end %>
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

**View** (`app/views/live/chat/chat_input.html.erb`):
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
    reactive :document, -> { Document.find(params[:document_id]) }
    reactive :active_users, -> { [] }
    
    after_connect :subscribe_to_document
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
    
    def subscribe_to_document
      stream_from("document_#{document.id}", coder: ActiveSupport::JSON) do |data|
        case data[:type]
        when 'content_updated'
          # Update local state if change is from another user
          if data[:user][:id] != current_user.id
            document.reload
          end
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

## Key Features

- **Automatic re-rendering**: Changes to reactive variables inside stream callbacks trigger re-renders
- **Shared state**: Combine with `shared: true` reactive variables to sync state across multiple component instances
- **Connection-scoped**: Each user's component instances receive broadcasts independently
- **Coder support**: Use `coder: ActiveSupport::JSON` to automatically decode JSON payloads
- **Multiple streams**: Components can subscribe to multiple streams simultaneously

## Best Practices

### Do

✅ Use descriptive channel names that indicate the data type  
✅ Include relevant identifiers in channel names (user_id, document_id, etc.)  
✅ Use JSON coder for structured data  
✅ Clean up or limit collection sizes to prevent memory bloat  
✅ Use `live-key` attributes for list items to preserve identity

### Don't

❌ Don't broadcast sensitive data without authorization checks  
❌ Don't subscribe to broad channels that send unnecessary updates  
❌ Don't perform expensive operations inside stream callbacks  
❌ Don't forget to unsubscribe or clean up when needed  
❌ Don't broadcast the same data to all components if only some need it

## Next Steps

- [Understand the architecture](/guide/architecture)
- [Learn about lifecycle callbacks](/guide/lifecycle-callbacks)
- [Read the Component API](/api/component)
