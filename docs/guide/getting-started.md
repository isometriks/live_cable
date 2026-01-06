# Getting Started

LiveCable is a Phoenix LiveView-style component system for Ruby on Rails that tracks state server-side and allows you to call actions from the frontend using Stimulus.

## What is LiveCable?

LiveCable brings the power of server-side rendered, real-time components to Rails applications. Instead of managing state on the client with JavaScript frameworks, LiveCable maintains component state on the server and uses ActionCable to automatically sync changes to the browser.

## Key Concepts

### Server-Side State
Component state lives on the server, not in the browser. When state changes, the component automatically re-renders and updates the DOM.

### Reactive Variables
Define reactive variables that automatically trigger re-renders when they change. LiveCable tracks mutations to Arrays, Hashes, and ActiveRecord models automatically.

### Actions
Call server-side methods from the frontend using Stimulus data attributes. Actions have access to the full Rails environment.

### Persistent Connections
WebSocket connections persist across page navigations, maintaining state and avoiding reconnection overhead.

## Quick Example

Here's a simple counter component to demonstrate LiveCable's capabilities:

**Component** (`app/live/counter.rb`):
```ruby
module Live
  class Counter < LiveCable::Component
    reactive :count, -> { 0 }
    
    actions :increment, :decrement
    
    def increment
      self.count += 1
    end
    
    def decrement
      self.count -= 1
    end
  end
end
```

**View** (`app/views/live/counter/component.html.erb`):
```erb
<div class="counter">
  <h2>Count: <%= count %></h2>
  <button live-action="increment">+</button>
  <button live-action="decrement">-</button>
</div>
```

**Usage** (in any view):
```erb
<%= live 'counter', id: 'my-counter' %>
```

## Next Steps

- [Installation](/guide/installation) - Set up LiveCable in your Rails application
- [Components](/guide/components) - Learn how to create components
- [Reactive Variables](/guide/reactive-variables) - Understand state management
- [Actions & Events](/guide/actions-events) - Handle user interactions
