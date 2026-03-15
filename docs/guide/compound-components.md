# Compound Components

Compound components allow you to organize complex components with multiple views into a directory structure, and dynamically switch between different templates based on component state.

## Basic Compound Components

By default, components render the partial at `app/views/live/component_name.html.live.erb`. Mark a component as `compound` to organize templates in a directory:

```ruby
module Live
  class Checkout < LiveCable::Component
    compound
    
    reactive :step, -> { "cart" }
    reactive :items, -> { [] }
    
    actions :proceed_to_shipping
    
    def proceed_to_shipping
      self.step = "shipping"
    end
  end
end
```

With `compound`, the component looks for templates in `app/views/live/checkout/`. By default, it renders `app/views/live/checkout/component.html.live.erb`.

## Dynamic Templates with `template_state`

Override the `template_state` method to dynamically switch between different templates:

```ruby
module Live
  class Wizard < LiveCable::Component
    compound
    
    reactive :current_step, -> { "account" }
    reactive :form_data, -> { {} }
    
    actions :next_step, :previous_step
    
    def template_state
      current_step  # Renders app/views/live/wizard/{current_step}.html.live.erb
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
- `app/views/live/wizard/account.html.live.erb`
- `app/views/live/wizard/billing.html.live.erb`
- `app/views/live/wizard/confirmation.html.live.erb`
- `app/views/live/wizard/complete.html.live.erb`

When templates switch, LiveCable's partial rendering system handles it efficiently by rendering all dynamic parts with the new template while reusing static parts when possible. See the [Partial Rendering Guide](/guide/partial-rendering#template-switching) for details.

## Example: Checkout Flow

A 2-step checkout that collects shipping details and confirms the order.

### Component Class

```ruby
module Live
  class Checkout < LiveCable::Component
    compound

    reactive :step, -> { "shipping" }
    reactive :shipping, -> { {} }
    reactive :errors, -> { {} }

    actions :confirm, :place_order, :back

    def template_state
      step
    end

    def confirm(params)
      if params[:name].blank? || params[:address].blank?
        self.errors = { base: "Name and address are required" }
        return
      end

      self.shipping = params.slice(:name, :address, :city, :postcode).to_h
      self.errors = {}
      self.step = "confirmation"
    end

    def place_order
      Order.create!(shipping: shipping, user: current_user)
      self.step = "complete"
    end

    def back
      self.step = "shipping"
    end
  end
end
```

### Templates

**Shipping** (`app/views/live/checkout/shipping.html.live.erb`):
```erb
<div class="checkout">
  <h2>Shipping Details</h2>

  <% if errors[:base] %>
    <p class="error"><%= errors[:base] %></p>
  <% end %>

  <form live-form="confirm">
    <div>
      <label>Full Name</label>
      <input type="text" name="name" value="<%= shipping[:name] %>">
    </div>
    <div>
      <label>Address</label>
      <input type="text" name="address" value="<%= shipping[:address] %>">
    </div>
    <div>
      <label>City</label>
      <input type="text" name="city" value="<%= shipping[:city] %>">
    </div>
    <div>
      <label>Postcode</label>
      <input type="text" name="postcode" value="<%= shipping[:postcode] %>">
    </div>
    <button type="submit">Review Order</button>
  </form>
</div>
```

**Confirmation** (`app/views/live/checkout/confirmation.html.live.erb`):
```erb
<div class="checkout">
  <h2>Confirm Your Order</h2>

  <div class="shipping-summary">
    <p><strong>Shipping to:</strong></p>
    <p><%= shipping[:name] %></p>
    <p><%= shipping[:address] %>, <%= shipping[:city] %> <%= shipping[:postcode] %></p>
  </div>

  <div class="actions">
    <button live-action="back">Back</button>
    <button live-action="place_order">Place Order</button>
  </div>
</div>
```

**Complete** (`app/views/live/checkout/complete.html.live.erb`):
```erb
<div class="checkout">
  <h2>Order Placed!</h2>
  <p>Thanks <%= shipping[:name] %>, your order is on its way.</p>
  <a href="/orders">View your orders</a>
</div>
```

## Use Cases

Compound components are ideal for:

- **Multi-step forms**: Wizards, onboarding flows, checkout processes
- **State machines**: Components with distinct states (loading, success, error, empty)
- **Modal dialogs**: Different content based on the modal's purpose
- **Tabs**: Switch between different content areas
- **Dashboard widgets**: Different views based on data availability

## Best Practices

### Do

✅ Use compound components for complex, multi-state components  
✅ Keep template names descriptive and reflective of the state  
✅ Use `template_state` to return a simple string or symbol  
✅ Organize shared partials in the component's directory  
✅ Keep state transitions clear and documented

### Don't

❌ Don't use compound components for simple components  
❌ Don't make `template_state` logic complex  
❌ Don't forget to create all referenced templates  
❌ Don't use compound when a single template with conditionals would suffice

## Next Steps

- [Stream from ActionCable channels](/guide/streaming)
- [Understand the architecture](/guide/architecture)
- [Learn about lifecycle callbacks](/guide/lifecycle-callbacks)
