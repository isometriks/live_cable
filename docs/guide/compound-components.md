# Compound Components

Compound components allow you to organize complex components with multiple views into a directory structure, and dynamically switch between different templates based on component state.

## Basic Compound Components

By default, components render the partial at `app/views/live/component_name.html.erb`. Mark a component as `compound` to organize templates in a directory:

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

With `compound`, the component looks for templates in `app/views/live/checkout/`. By default, it renders `app/views/live/checkout/component.html.erb`.

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
      current_step  # Renders app/views/live/wizard/{current_step}.html.erb
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

## Example: Multi-Step Wizard

### Component Class

```ruby
module Live
  class RegistrationWizard < LiveCable::Component
    compound
    
    reactive :current_step, -> { "personal_info" }
    reactive :personal_info, -> { {} }
    reactive :account_info, -> { {} }
    reactive :preferences, -> { {} }
    reactive :errors, -> { {} }
    
    actions :next_step, :previous_step, :submit
    
    def template_state
      current_step
    end
    
    def next_step(params)
      # Validate current step
      case current_step
      when "personal_info"
        if validate_personal_info(params)
          personal_info.merge!(params)
          self.current_step = "account_info"
          self.errors = {}
        end
      when "account_info"
        if validate_account_info(params)
          account_info.merge!(params)
          self.current_step = "preferences"
          self.errors = {}
        end
      end
    end
    
    def previous_step
      self.current_step = case current_step
        when "account_info" then "personal_info"
        when "preferences" then "account_info"
        else current_step
      end
    end
    
    def submit(params)
      preferences.merge!(params)
      
      # Create user
      user = User.create(
        personal_info.merge(account_info).merge(preferences)
      )
      
      if user.persisted?
        self.current_step = "success"
      else
        self.errors = user.errors.to_hash
      end
    end
    
    private
    
    def validate_personal_info(params)
      errors = {}
      errors[:first_name] = "can't be blank" if params[:first_name].blank?
      errors[:last_name] = "can't be blank" if params[:last_name].blank?
      errors[:email] = "is invalid" unless params[:email] =~ URI::MailTo::EMAIL_REGEXP
      
      self.errors = errors
      errors.empty?
    end
    
    def validate_account_info(params)
      errors = {}
      errors[:username] = "can't be blank" if params[:username].blank?
      errors[:password] = "must be at least 8 characters" if params[:password].to_s.length < 8
      
      self.errors = errors
      errors.empty?
    end
  end
end
```

### Templates

**Personal Info** (`app/views/live/registration_wizard/personal_info.html.erb`):
```erb
<div>
  <div class="wizard">
    <h2>Personal Information</h2>
    <div class="progress">Step 1 of 3</div>

    <form live-form="next_step">
      <div>
        <label>First Name</label>
        <input type="text" name="first_name" value="<%= personal_info[:first_name] %>">
        <% if errors[:first_name] %>
          <span class="error"><%= errors[:first_name] %></span>
        <% end %>
      </div>

      <div>
        <label>Last Name</label>
        <input type="text" name="last_name" value="<%= personal_info[:last_name] %>">
        <% if errors[:last_name] %>
          <span class="error"><%= errors[:last_name] %></span>
        <% end %>
      </div>

      <div>
        <label>Email</label>
        <input type="email" name="email" value="<%= personal_info[:email] %>">
        <% if errors[:email] %>
          <span class="error"><%= errors[:email] %></span>
        <% end %>
      </div>

      <button type="submit">Next</button>
    </form>
  </div>
</div>
```

**Account Info** (`app/views/live/registration_wizard/account_info.html.erb`):
```erb
<div>
  <div class="wizard">
    <h2>Account Information</h2>
    <div class="progress">Step 2 of 3</div>

    <form live-form="next_step">
      <div>
        <label>Username</label>
        <input type="text" name="username" value="<%= account_info[:username] %>">
        <% if errors[:username] %>
          <span class="error"><%= errors[:username] %></span>
        <% end %>
      </div>

      <div>
        <label>Password</label>
        <input type="password" name="password">
        <% if errors[:password] %>
          <span class="error"><%= errors[:password] %></span>
        <% end %>
      </div>

      <div class="actions">
        <button type="button" live-action="previous_step">
          Back
        </button>
        <button type="submit">Next</button>
      </div>
    </form>
  </div>
</div>
```

**Success** (`app/views/live/registration_wizard/success.html.erb`):
```erb
<div>
  <div class="wizard success">
    <h2>Registration Complete!</h2>
    <p>Your account has been created successfully.</p>
    <a href="/dashboard" class="button">Go to Dashboard</a>
  </div>
</div>
```

## Use Cases

Compound components are ideal for:

- **Multi-step forms**: Wizards, onboarding flows, checkout processes
- **State machines**: Components with distinct states (loading, success, error, empty)
- **Modal dialogs**: Different content based on the modal's purpose
- **Tabs**: Switch between different content areas
- **Dashboard widgets**: Different views based on data availability

## Generating Compound Components

Use the `--compound` flag with the generator:

```bash
bin/rails generate live_cable:component Wizard --compound current_step:string
```

This creates:
- `app/live/wizard.rb` with `compound` already set
- `app/views/live/wizard/component.html.erb` as the default template

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
