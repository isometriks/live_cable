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

This works seamlessly with Rails form helpers:

```erb
<%= live_component do %>
  <%= form_with(model: user, data: { action: "submit->live#form:prevent", live_action_param: "update_profile" }) do |f| %>
    <div>
      <%= f.label :name %>
      <%= f.text_field :name %>
      <% if errors[:name] %>
        <span class="error"><%= errors[:name].join(", ") %></span>
      <% end %>
    </div>

    <div>
      <%= f.label :email %>
      <%= f.email_field :email %>
      <% if errors[:email] %>
        <span class="error"><%= errors[:email].join(", ") %></span>
      <% end %>
    </div>

    <div>
      <%= f.label :bio %>
      <%= f.text_area :bio %>
    </div>

    <%= f.submit "Update Profile" %>
  <% end %>
<% end %>
```

## Calling Actions from Views

### The live_action Helper

To simplify writing Stimulus action attributes, use the `live_action` helper:

```erb
<!-- Default event (click for buttons, submit for forms) -->
<button <%= live_action(:save) %>>Save</button>
<!-- Generates: data-action='live#call' data-live-action-param='save' -->

<!-- Custom event -->
<input <%= live_action(:search, :input) %> />
<!-- Generates: data-action='input->live#call' data-live-action-param='search' -->

<!-- On forms -->
<form <%= live_action(:submit, :submit) %>>
  <input type="text" name="title">
  <button type="submit">Submit</button>
</form>
```

**Parameters:**
- `action` (required): The name of the component action to call
- `event` (optional): The DOM event to bind to. If omitted, uses Stimulus default events (click for buttons, submit for forms, etc.)

### Using the `call` Action

The most common way to call actions is using the `live#call` Stimulus action:

```erb
<button data-action="live#call" 
        data-live-action-param="increment">
  Increment
</button>

<button data-action="live#call" 
        data-live-action-param="remove_todo"
        data-live-id-param="<%= todo[:id] %>">
  Delete
</button>
```

Parameters are passed using data attributes with the pattern `data-live-{name}-param`:

```erb
<button data-action="live#call"
        data-live-action-param="add_item"
        data-live-name-param="<%= product.name %>"
        data-live-price-param="<%= product.price %>">
  Add to Cart
</button>
```

### Form Submissions

Use `live#form` to serialize and submit entire forms:

```erb
<form data-action="submit->live#form:prevent" 
      data-live-action-param="save">
  <input type="text" name="title">
  <input type="text" name="description">
  <button type="submit">Save</button>
</form>
```

The action method receives all form fields as parameters:

```ruby
def save(params)
  self.title = params[:title]
  self.description = params[:description]
  # ... save logic
end
```

## Reactive Inputs

Use `live#reactive` to sync input values with reactive variables:

```erb
<!-- Immediate update -->
<input type="text"
       name="username"
       value="<%= username %>"
       data-action="input->live#reactive">

<!-- Debounced update (reduces network traffic) -->
<input type="text"
       name="search_query"
       value="<%= search_query %>"
       data-action="input->live#reactive"
       data-live-debounce-param="300">
```

This automatically updates the reactive variable and triggers a re-render. Use `data-live-debounce-param` for search inputs or expensive operations to reduce network traffic.

## Stimulus API Reference

### `call`

Calls a specific action on the server-side component.

- **Usage**: `data-action="click->live#call"`
- **Required**: `data-live-action-param="action_name"`
- **Optional**: Any `data-live-*-param` for additional parameters

```html
<button data-action="click->live#call" 
        data-live-action-param="update" 
        data-live-id-param="123">
  Update Item
</button>
```

### `reactive`

Updates a reactive variable with the element's current value.

- **Usage**: `data-action="input->live#reactive"`
- **Optional**: `data-live-debounce-param="milliseconds"` - Debounce delay. If not specified, updates immediately.
- **Behavior**: Sends the input's `name` and `value` to the server

```html
<!-- Immediate update -->
<input type="text"
       name="username"
       value="<%= username %>"
       data-action="input->live#reactive">

<!-- Debounced update (reduces network traffic) -->
<input type="text"
       name="search_query"
       data-action="input->live#reactive"
       data-live-debounce-param="300">
```

### `form`

Serializes and submits an entire form.

- **Usage**: `data-action="submit->live#form:prevent"` or `data-action="change->live#form"`
- **Required**: `data-live-action-param="action_name"`
- **Optional**: `data-live-debounce-param="milliseconds"` - Debounce delay. If not specified, submits immediately.

```html
<!-- Immediate submission -->
<form data-action="submit->live#form:prevent"
      data-live-action-param="save">
  <input type="text" name="title">
  <button type="submit">Save</button>
</form>

<!-- Debounced submission (useful for auto-saving or filtering on change) -->
<form data-action="change->live#form"
      data-live-action-param="filter"
      data-live-debounce-param="500">
  <select name="category">...</select>
</form>
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
