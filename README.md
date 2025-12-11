# LiveCable

LiveCable is a Phoenix LiveView-style live component system for Ruby on Rails that tracks state server-side and allows
you to call actions from the frontend using Stimulus.

## Features

- **Server-side state management**: Component state is maintained on the server using ActionCable
- **Reactive variables**: Automatic UI updates when state changes with smart change tracking
- **Automatic change detection**: Arrays, Hashes, and ActiveRecord models automatically trigger updates when mutated
- **Subscription persistence**: WebSocket connections persist across page navigations for better performance
- **Action dispatch**: Call server-side methods from the frontend
- **Lifecycle hooks**: Hook into component lifecycle events
- **Stimulus integration**: Seamless integration with Stimulus controllers and blessings API

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'live_cable'
```

And then execute:

```bash
bundle install
```

## Configuration

To use LiveCable, you need to set up your `ApplicationCable::Connection` to initialize a `LiveCable::Connection`.

Add this to your `app/channels/application_cable/connection.rb`:

```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :live_connection

    def connect
      self.live_connection = LiveCable::Connection.new(self.request)
    end
  end
end
```

## JavaScript Setup

### 1. Register the LiveController

Register the `LiveController` in your Stimulus application (`app/javascript/controllers/application.js`):

```javascript
import { Application } from "@hotwired/stimulus"
import LiveController from "live_cable_controller"

const application = Application.start()
application.register("live", LiveController)
```

### 2. Enable LiveCable Blessing (Optional)

If you want to call LiveCable actions from your own Stimulus controllers, add the LiveCable blessing:

```javascript
import { Application, Controller } from "@hotwired/stimulus"
import LiveController from "live_cable_controller"
import LiveCableBlessing from "live_cable_blessing"

// Enable the blessing for all controllers
Controller.blessings = [
  ...Controller.blessings,
  LiveCableBlessing
]

const application = Application.start()
application.register("live", LiveController)
```

This adds the `liveCableAction(action, params)` method to all your Stimulus controllers:

```javascript
// In your custom controller
export default class extends Controller {
  submit() {
    // Dispatch an action to the LiveCable component
    this.liveCableAction('save', {
      title: this.titleTarget.value
    })
  }
}
```

The action will be dispatched as a DOM event that bubbles up to the nearest LiveCable component. This is useful when you need to trigger LiveCable actions from custom controllers or third-party integrations.

## Subscription Persistence

LiveCable maintains persistent WebSocket connections across page navigations, providing better performance and preserving server-side state.

### How It Works

Traditional ActionCable subscriptions are torn down when Stimulus controllers disconnect (e.g., during Turbo navigation). LiveCable's subscription manager keeps connections alive:

```
User visits page → Subscription created → WebSocket opened
User navigates away → Controller disconnects → Subscription persists
User navigates back → Controller reconnects → Reuses existing subscription
```

### Benefits

- **Reduced WebSocket churn**: No reconnection overhead during navigation
- **State preservation**: Server-side state persists across page transitions
- **Better performance**: Eliminates subscription setup/teardown cycles
- **No race conditions**: Avoids issues from rapid connect/disconnect

### Automatic Management

Subscription persistence is handled automatically. Components are identified by their `live_id`, and the subscription manager ensures each component has exactly one active subscription at any time.

When the server sends a `destroy` status, the subscription is permanently removed:

```ruby
def some_action
  # Component decides to permanently clean up
  destroy
end
```

For implementation details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Lifecycle Hooks

Note on component location and namespacing:

- Live components must be defined inside the `Live::` module so they can be safely loaded from a string name.
- We recommend placing component classes under `app/live/` (so `Live::Counter` maps to `app/live/counter.rb`).
- Corresponding views should live under `app/views/live/...` (e.g. `app/views/live/counter/component.html.erb`).
- When rendering a component from a view, pass the namespaced underscored path, e.g. `live/counter` (which camelizes to `Live::Counter`).

LiveCable provides four lifecycle hooks that you can override in your components to add custom behavior at different
stages of a component's lifecycle.

### Available Hooks

- **`connected`**: Called when the component is first subscribed to the channel, after initialization but before the initial render. Use for initializing timers, subscribing to external services, or loading additional data.

- **`disconnected`**: Called when the component is unsubscribed from the channel. Use for cleanup: stop timers, unsubscribe from external services, or save state before disconnection.

- **`before_render`**: Called before each render and broadcast, including the initial render. Use for preparing data, performing calculations, or validating state.

- **`after_render`**: Called after each render and broadcast. Use for triggering side effects or cleanup after the DOM has been updated.

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

## Basic Usage

### 1. Create a Component

```ruby
# app/components/live/counter.rb
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

### 2. Create a Partial

Component partials must be wrapped in a `live_component` block:

```erb
<%# app/views/live/counter/component.html.erb %>
<%= live_component(component) do %>
  <h2>Counter: <%= count %></h2>
  <button data-action="live#call" data-live-action-param="increment">+</button>
  <button data-action="live#call" data-live-action-param="decrement">-</button>
<% end %>
```

The `live_component` helper accepts HTML attributes that are passed to the wrapper `div`:

```erb
<%# With CSS classes %>
<%= live_component(component, class: "p-4 bg-white rounded-lg shadow") do %>
  <h2>Counter: <%= count %></h2>
<% end %>

<%# With additional Stimulus controllers %>
<%= live_component(component, data: { controller: "dropdown" }) do %>
  <%# This renders as: data-controller="live dropdown" %>
<% end %>

<%# With any HTML attributes %>
<%= live_component(component, id: "my-counter", class: "flex items-center", aria: { label: "Counter widget" }) do %>
  <h2>Counter: <%= count %></h2>
<% end %>
```

**Note**: When passing `data: { controller: "..." }`, the controller name is appended to the `live` controller, so `data: { controller: "widget" }` becomes `data-controller="live widget"`.

### 3. Use in Your View

Render components using the `live` helper method:

```erb
<%# Simple usage %>
<%= live 'counter', id: 'my-counter' %>

<%# With default values %>
<%= live 'counter', id: 'my-counter', count: 10, step: 5 %>

<%# Render an existing component instance %>
<%
  @counter = Live::Counter.new('my-counter')
  @counter.count = 10
%>
<%= live @counter %>
```

The `live` helper automatically:
- Creates component instances with unique IDs
- Wraps the component in proper Stimulus controller attributes
- Passes default values to reactive variables
- Reuses existing component instances when navigating back

## Reactive Variables

Reactive variables automatically trigger re-renders when changed. Define them with default values using lambdas:

```ruby
module Live
  class ShoppingCart < LiveCable::Component
    reactive :items, -> { [] }
    reactive :discount_code, -> { nil }
    reactive :total, -> { 0.0 }

    actions :add_item, :remove_item, :apply_discount

    def add_item(params)
      items << { id: params[:id], name: params[:name], price: params[:price].to_f }
      calculate_total
    end

    def remove_item(params)
      items.reject! { |item| item[:id] == params[:id] }
      calculate_total
    end

    def apply_discount(params)
      self.discount_code = params[:code]
      calculate_total
    end

    private

    def calculate_total
      subtotal = items.sum { |item| item[:price] }
      discount = discount_code ? apply_discount_rate(subtotal) : 0
      self.total = subtotal - discount
    end

    def apply_discount_rate(subtotal)
      discount_code == "SAVE10" ? subtotal * 0.1 : 0
    end
  end
end
```

## Automatic Change Tracking

LiveCable automatically tracks changes to reactive variables containing Arrays, Hashes, and ActiveRecord models. You can mutate these objects directly without manual re-assignment:

```ruby
module Live
  class TaskManager < LiveCable::Component
    reactive :tasks, -> { [] }
    reactive :settings, -> { {} }
    reactive :project, -> { Project.find_by(id: params[:project_id]) }

    actions :add_task, :update_setting, :update_project_name

    # Arrays - direct mutation triggers re-render
    def add_task(params)
      tasks << { title: params[:title], completed: false }
    end

    # Hashes - direct mutation triggers re-render
    def update_setting(params)
      settings[params[:key]] = params[:value]
    end

    # ActiveRecord - direct mutation triggers re-render
    def update_project_name(params)
      project.name = params[:name]
    end
  end
end
```

### Nested Structures

Change tracking works recursively through nested structures:

```ruby
module Live
  class Organization < LiveCable::Component
    reactive :data, -> { { teams: [{ name: 'Engineering', members: [] }] } }

    actions :add_member

    def add_member(params)
      # Deeply nested mutation - automatically triggers re-render
      data[:teams].first[:members] << params[:name]
    end
  end
end
```

### How It Works

When you store an Array, Hash, or ActiveRecord model in a reactive variable:

1. **Automatic Wrapping**: LiveCable wraps the value in a transparent Delegator
2. **Observer Attachment**: An Observer is attached to track mutations
3. **Change Detection**: When you call mutating methods (`<<`, `[]=`, `update`, etc.), the Observer is notified
4. **Smart Re-rendering**: Only components with changed variables are re-rendered

This means you can write natural Ruby code without worrying about triggering updates:

```ruby
# These all work and trigger updates automatically:
tags << 'ruby'
tags.concat(%w[rails rspec])
settings[:theme] = 'dark'
user.update(name: 'Jane')
```

### Primitives (Strings, Numbers, etc.)

Primitive values (String, Integer, Float, Boolean, Symbol) cannot be mutated in place, so you must reassign them:

```ruby
reactive :count, -> { 0 }
reactive :name, -> { "" }

# ✅ This works (reassignment)
self.count = count + 1
self.name = "John"

# ❌ This won't trigger updates (mutation, but primitives are immutable)
self.count.+(1)
self.name.concat("Doe")
```

For more details on the change tracking architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Shared Variables

Shared variables allow multiple components on the same connection to access the same state. There are two types:

### Shared Reactive Variables

Shared reactive variables trigger re-renders on **all** components that use them:

```ruby
module Live
  class ChatMessage < LiveCable::Component
    reactive :messages, -> { [] }, shared: true
    reactive :username, -> { "Guest" }

    actions :send_message

    def send_message(params)
      messages << { user: username, text: params[:text], time: Time.current }
    end
  end
end
```

When any component updates `messages`, all components using this shared reactive variable will re-render.

### Shared Non-Reactive Variables

Use `shared` (without `reactive`) when you need to share state but don't want updates to trigger re-renders in the component that doesn't display that data:

```ruby
module Live
  class FilterPanel < LiveCable::Component
    shared :cart_items, -> { [] }  # Access cart but don't re-render on cart changes
    reactive :filter, -> { "all" }

    actions :update_filter

    def update_filter(params)
      self.filter = params[:filter]
      # Can read cart_items.length but changing cart elsewhere won't re-render this
    end
  end
end

module Live
  class CartDisplay < LiveCable::Component
    reactive :cart_items, -> { [] }, shared: true  # Re-renders on cart changes

    actions :add_to_cart

    def add_to_cart(params)
      cart_items << params[:item]
      # CartDisplay re-renders, but FilterPanel does not
    end
  end
end
```

**Use case**: FilterPanel can read the cart to show item count in a badge, but doesn't need to re-render every time an item is added—only when the filter changes.

## Action Whitelisting

For security, explicitly declare which actions can be called from the frontend:

```ruby
module Live
  class Secure < LiveCable::Component
    actions :safe_action, :another_safe_action

    def safe_action
      # This can be called from the frontend
    end

    def another_safe_action(params)
      # This can also be called with parameters
    end

    private

    def internal_method
      # This cannot be called from the frontend
    end
  end
end
```

**Note on `params` argument**: The `params` argument is optional. Action methods only receive `params` if you declare the argument in the method signature:

```ruby
# These are both valid:
def increment
  self.count += 1  # No params needed
end

def add_todo(params)
  todos << params[:text]  # Params are used
end
```

If you don't need parameters from the frontend, simply omit the `params` argument from your method definition.

## Stimulus API

The `live` controller exposes several actions to interact with your component from the frontend.

### `call`

Calls a specific action on the server-side component.

-   **Usage**: `data-action="click->live#call"`
-   **Parameters**:
    -   `data-live-action-param="action_name"` (Required): The name of the action to call.
    -   `data-live-*-param`: Any additional parameters are passed to the action method.

```html
<button data-action="click->live#call" 
        data-live-action-param="update" 
        data-live-id-param="123">
  Update Item
</button>
```

### `reactive`

Updates a reactive variable with the element's current value and marks it as dirty. Typically used on input fields.

-   **Usage**: `data-action="input->live#reactive"`
-   **Behavior**: Sends the input's `name` and `value` to the server.

```html
<input type="text" name="username" value="<%= username %>" data-action="input->live#reactive">
```

### `reactiveDebounce`

Same as `reactive`, but debounces the update to reduce network traffic.

-   **Usage**: `data-action="input->live#reactiveDebounce"`
-   **Parameters**:
    -   `data-live-debounce-param="500"` (Optional): Debounce delay in milliseconds (default: 200ms).

```html
<input type="text" 
       name="search_query" 
       data-action="input->live#reactiveDebounce" 
       data-live-debounce-param="300">
```

### `form`

Serializes the enclosing form and submits it to a specific action.

-   **Usage**: `data-action="submit->live#form:prevent"` or `data-action="change->live#form"`
-   **Parameters**:
    -   `data-live-action-param="save"` (Required): The component action to handle the form submission.

```html
<form data-action="submit->live#form:prevent" data-live-action-param="save">
  <input type="text" name="title">
  <button type="submit">Save</button>
</form>
```

### `formDebounce`

Debounces a form submission. useful for auto-saving forms or filtering on change.

-   **Usage**: `data-action="change->live#formDebounce"`
-   **Parameters**:
    -   `data-live-debounce-param="1000"` (Optional): Debounce delay in milliseconds (default: 200ms).

```html
<form data-action="change->live#formDebounce" 
      data-live-action-param="filter" 
      data-live-debounce-param="500">
  <select name="category">...</select>
</form>
```

### Race Condition Handling

When a form action is triggered (via `form` or `formDebounce`), the controller manages potential race conditions with pending reactive updates:

1.  **Priority**: Any pending `reactiveDebounce` message is sent **immediately before** the form action message in the same payload.
2.  **Order**: This guarantees that the server applies the reactive update first, then the form action.
3.  **Debounce Cancellation**: Any pending debounced form submissions are canceled, ensuring only the latest form state is processed.

This mechanism prevents scenarios where a delayed reactive update (e.g., from typing quickly) could arrive after a form
submission and overwrite the changes made by the form action.

## HTML Attributes

LiveCable supports special HTML attributes to control how the DOM is updated.

### `live-ignore`

When `live-ignore` is present on an element, LiveCable (via morphdom) will skip updating that element's children during a re-render.

-   **Usage**: `<div live-ignore>...</div>`
-   **Behavior**: Prevents the element's content from being modified by server updates.
-   **Default**: Live components automatically have this attribute to ensure the parent component doesn't overwrite the child component's state.

### `live-key`

The `live-key` attribute acts as a hint for the diffing algorithm to identify elements in a list. This allows elements to be reordered rather than destroyed and recreated, preserving their internal state (like input focus or selection).

-   **Usage**: `<div live-key="unique_id">...</div>`
-   **Behavior**: Matches elements across renders to maintain identity.
-   **Notes**:
    -   The key must be unique within the context of the parent element.
    -   `id` attributes are also used as keys if `live-key` is not present, but `live-key` is preferred in loops to avoid ID collisions or valid HTML ID constraints.
    -   Do not use array indices as keys; use a stable identifier from your data (e.g., database ID). If you reorder or add / remove elements from your array the index will no longer match the proper component.

**Example:**

```erb
<% todos.each do |todo| %>
  <li live-key="<%= todo.id %>">
    ...
  </li>
<% end %>
```

## Compound Components

By default, components render the partial at `app/views/live/component_name.html.erb`. You can organize your templates differently by marking a component as `compound`.

```ruby
module Live
  class Checkout < LiveCable::Component
    compound
    # Component will look for templates in app/views/live/checkout/
  end
end
```

When `compound` is used, the component will look for its template in a directory named after the component. By default, it renders `app/views/live/component_name/component.html.erb`.

### Dynamic Templates with `template_state`

Override the `template_state` method to dynamically switch between different templates:

```ruby
module Live
  class Wizard < LiveCable::Component
    compound
    reactive :current_step, -> { "account" }
    reactive :form_data, -> { {} }

    actions :next_step, :previous_step

    def template_state
      current_step  # Renders app/views/live/wizard/account.html.erb, etc.
    end

    def next_step(params)
      form_data.merge!(params)
      self.current_step = case current_step
        when "account" then "billing"
        when "billing" then "confirmation"
        else "complete"
      end
    end

    def previous_step
      self.current_step = case current_step
        when "billing" then "account"
        when "confirmation" then "billing"
        else current_step
      end
    end
  end
end
```

This creates a multi-step wizard with templates in:
- `app/views/live/wizard/account.html.erb`
- `app/views/live/wizard/billing.html.erb`
- `app/views/live/wizard/confirmation.html.erb`
- `app/views/live/wizard/complete.html.erb`

## License

This project is available as open source under the terms of the MIT License.
