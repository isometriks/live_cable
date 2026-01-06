# Actions & Events

Actions allow you to call server-side methods from the frontend. LiveCable provides a secure, declarative API for handling user interactions.

## Defining Actions

Use the `actions` class method to whitelist which methods can be called from the frontend:

```ruby
module Live
  class TodoList < LiveCable::Component
    reactive :todos, -> { [] }
    reactive :filter, -> { "all" }
    
    actions :add_todo, :remove_todo, :toggle_todo, :change_filter
    
    def add_todo(params)
      todos << {
        id: SecureRandom.uuid,
        text: params[:text],
        completed: false
      }
    end
    
    def remove_todo(params)
      todos.reject! { |todo| todo[:id] == params[:id] }
    end
    
    def toggle_todo(params)
      todo = todos.find { |t| t[:id] == params[:id] }
      todo[:completed] = !todo[:completed] if todo
    end
    
    def change_filter(params)
      self.filter = params[:filter]
    end
  end
end
```

::: warning Security
Only methods explicitly listed in `actions` can be called from the frontend. This prevents unauthorized access to internal component methods.
:::

## Action Parameters

Action methods can optionally accept a `params` argument:

```ruby
# No parameters needed
def increment
  self.count += 1
end

# With parameters
def add_item(params)
  items << params[:item]
end
```

### Working with ActionController::Parameters

The `params` argument is an `ActionController::Parameters` instance, which means you can use strong parameters and all standard Rails parameter handling methods:

```ruby
module Live
  class UserProfile < LiveCable::Component
    reactive :user, -> { |component| User.find(component.defaults[:user_id]) }
    reactive :errors, -> { {} }

    actions :update_profile

    def update_profile(params)
      # Use params.expect (Rails 8+) or params.require/permit for strong parameters
      user_params = params.expect(user: [:name, :email, :bio])

      if user.update(user_params)
        self.errors = {}
      else
        self.errors = user.errors.messages
      end
    end
  end
end
```

You can also use `assign_attributes` if you want to validate before saving:

```ruby
def update_profile(params)
  user_params = params.expect(user: [:name, :email, :bio])

  user.assign_attributes(user_params)

  if user.valid?
    user.save
    self.errors = {}
  else
    self.errors = user.errors.messages
  end
end
```

This works seamlessly with form helpers:

```erb
<form live-form="update_profile">
  <div>
    <label>Name</label>
    <input type="text" name="user[name]" value="<%= user.name %>" />
    <% if errors[:name] %>
      <span class="error"><%= errors[:name].join(", ") %></span>
    <% end %>
  </div>

  <div>
    <label>Email</label>
    <input type="email" name="user[email]" value="<%= user.email %>" />
    <% if errors[:email] %>
      <span class="error"><%= errors[:email].join(", ") %></span>
    <% end %>
  </div>

  <div>
    <label>Bio</label>
    <textarea name="user[bio]"><%= user.bio %></textarea>
  </div>

  <button type="submit">Update Profile</button>
</form>
```

## Calling Actions from Views

LiveCable provides custom HTML attributes that are automatically transformed into Stimulus attributes by the DOM observer.

### The `live-action` Attribute

Use `live-action` to trigger component actions when an event occurs.

**Syntax:**
- `live-action="action_name"` - Uses Stimulus default event (click for buttons, submit for forms)
- `live-action="event->action_name"` - Custom event
- `live-action="event1->action1 event2->action2"` - Multiple actions

**Examples:**

```erb
<!-- Default event (click for buttons) -->
<button live-action="increment">Increment</button>

<!-- Custom event -->
<button live-action="mouseover->highlight">Hover Me</button>

<!-- Multiple actions -->
<button live-action="click->save focus->track_focus">Save and Track</button>
```

### Passing Parameters with `live-value-*`

Use `live-value-*` attributes to pass parameters to actions:

**Syntax:** `live-value-param-name="value"`

```erb
<!-- Single parameter -->
<button live-action="remove_todo" live-value-id="<%= todo[:id] %>">
  Delete
</button>

<!-- Multiple parameters -->
<button live-action="add_item"
        live-value-name="<%= product.name %>"
        live-value-price="<%= product.price %>">
  Add to Cart
</button>
```

### The `live-form` Attribute

Use `live-form` to serialize and submit entire forms.

**Syntax:**
- `live-form="action_name"` - Uses Stimulus default event (submit)
- `live-form="event->action_name"` - Custom event
- `live-form="event1->action1 event2->action2"` - Multiple actions

**Examples:**

```erb
<!-- Default event (submit) -->
<form live-form="save">
  <input type="text" name="title">
  <input type="text" name="description">
  <button type="submit">Save</button>
</form>

<!-- On change event -->
<form live-form="change->filter">
  <select name="category">
    <option value="all">All</option>
    <option value="electronics">Electronics</option>
  </select>
</form>

<!-- Multiple actions -->
<form live-form="submit->save change->auto_save">
  <input type="text" name="content">
</form>
```

The action method receives all form fields as parameters:

```ruby
def save(params)
  self.title = params[:title]
  self.description = params[:description]
  # ... save logic
end

def filter(params)
  self.category = params[:category]
end
```

### The `live-reactive` Attribute

Use `live-reactive` to sync input values with reactive variables.

**Syntax:**
- `live-reactive` - Uses Stimulus default event (input for text fields)
- `live-reactive="event"` - Single event
- `live-reactive="event1 event2"` - Multiple events

**Examples:**

```erb
<!-- Default event (input) -->
<input type="text" name="username" value="<%= username %>" live-reactive>

<!-- Specific event -->
<input type="text" name="search" live-reactive="keydown">

<!-- Multiple events -->
<input type="text" name="query" live-reactive="keydown keyup">
```

### The `live-debounce` Attribute

Add debouncing to reactive and form updates to reduce network traffic.

**Syntax:** `live-debounce="milliseconds"`

**Examples:**

```erb
<!-- Debounced reactive input (300ms delay) -->
<input type="text" name="search" live-reactive live-debounce="300">

<!-- Debounced form submission (1000ms delay) -->
<form live-form="change->filter" live-debounce="1000">
  <select name="category">...</select>
</form>
```

## Complete Example

Here's a comprehensive example showing all the custom attributes:

```erb
<div>
  <h2>Search Products</h2>

  <!-- Reactive search with debouncing -->
  <input type="text"
         name="query"
         value="<%= query %>"
         live-reactive
         live-debounce="300">

  <!-- Form with multiple actions and parameters -->
  <form live-form="submit->filter change->auto_filter" live-debounce="500">
    <select name="category">
      <option value="all">All</option>
      <option value="electronics">Electronics</option>
    </select>
  </form>

  <!-- Action buttons with parameters -->
  <% products.each do |product| %>
    <div>
      <h3><%= product.name %></h3>
      <button live-action="add_to_cart"
              live-value-product-id="<%= product.id %>"
              live-value-quantity="1">
        Add to Cart
      </button>
    </div>
  <% end %>

  <!-- Multiple events -->
  <button live-action="click->save mouseover->preview">
    Save & Preview
  </button>
</div>
```

## Race Condition Handling

When a form action is triggered, LiveCable manages potential race conditions with pending reactive updates:

1. **Priority**: Any pending debounced `reactive` message is sent **immediately before** the form action message in the same payload
2. **Order**: This guarantees that the server applies the reactive update first, then the form action
3. **Debounce Cancellation**: Any pending debounced form or reactive submissions are canceled, ensuring only the latest state is processed

This prevents scenarios where a delayed reactive update (e.g., from typing quickly) could arrive after a form submission and overwrite the changes made by the form action.

## Calling Actions from Custom Stimulus Controllers

Use the LiveCable blessing to call actions from your own controllers:

```javascript
// Enable the blessing
import { Controller } from "@hotwired/stimulus"
import LiveCableBlessing from "live_cable_blessing"

Controller.blessings = [
  ...Controller.blessings,
  LiveCableBlessing
]
```

Then use `liveCableAction` in your controllers:

```javascript
export default class extends Controller {
  submit() {
    this.liveCableAction('save', {
      title: this.titleTarget.value,
      priority: 'high'
    })
  }
  
  cancel() {
    this.liveCableAction('reset')
  }
}
```

The action will be dispatched as a DOM event that bubbles up to the nearest LiveCable component.

## Error Handling

If an action raises an error, LiveCable displays it in the component:

```ruby
def divide(params)
  raise "Cannot divide by zero" if params[:divisor].to_i.zero?
  
  self.result = params[:dividend].to_f / params[:divisor].to_f
end
```

The error will be rendered in place of the component with a collapsible details element showing the exception message and backtrace.

## Best Practices

### Do

✅ Always whitelist actions using the `actions` class method  
✅ Use descriptive action names that indicate what they do  
✅ Validate parameters inside action methods  
✅ Keep action methods focused on a single task  
✅ Use debouncing for search inputs and auto-save features

### Don't

❌ Don't call private methods from the frontend (they won't work)  
❌ Don't perform long-running operations in action methods  
❌ Don't trust client input - always validate and sanitize  
❌ Don't forget to handle edge cases and errors

## Next Steps

- [Create compound components](/guide/compound-components)
- [Stream from ActionCable channels](/guide/streaming)
- [Understand the architecture](/guide/architecture)
