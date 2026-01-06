# Reactive Variables

Reactive variables are the heart of LiveCable's state management. When a reactive variable changes, the component automatically re-renders and broadcasts the updated HTML to connected clients.

## Defining Reactive Variables

Define reactive variables using the `reactive` class method with a lambda that provides the default value:

```ruby
module Live
  class ShoppingCart < LiveCable::Component
    reactive :items, -> { [] }
    reactive :discount_code, -> { nil }
    reactive :total, -> { 0.0 }
    
    actions :add_item, :apply_discount
  end
end
```

::: info Why Lambdas?
Default values are defined as lambdas to ensure each component instance gets its own copy of the value. Without lambdas, all instances would share the same object reference.
:::

## Setting Reactive Variables

Use the setter method (with `self.`) to update reactive variables:

```ruby
def add_item(params)
  items << { id: params[:id], name: params[:name], price: params[:price].to_f }
  self.total = calculate_total(items)
end

def apply_discount(params)
  self.discount_code = params[:code]
  self.total = calculate_total_with_discount(items, discount_code)
end
```

## Automatic Change Tracking

LiveCable automatically tracks changes to reactive variables containing **Arrays**, **Hashes**, and **ActiveRecord models**. You can mutate these objects directly without manual re-assignment:

```ruby
module Live
  class TaskManager < LiveCable::Component
    reactive :tasks, -> { [] }
    reactive :settings, -> { {} }
    reactive :project, -> { nil }

    actions :add_task, :update_setting, :update_project_name

    after_connect :load_project

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
      project.update(name: params[:name])
    end

    private

    def load_project
      self.project = Project.find(defaults[:project_id])
    end
  end
end
```

The component would be rendered with the project ID passed as a default:

```erb
<%= live('task_manager', id: "task-#{@project.id}", project_id: @project.id) %>
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

## Primitive Values

LiveCable only wraps Arrays, Hashes, and ActiveRecord models in change-tracking Delegators. Other values — including Strings, Integers, Floats, Booleans, and Symbols — are not tracked for in-place mutation. You must reassign them to trigger updates:

```ruby
reactive :count, -> { 0 }
reactive :name, -> { "" }

# ✅ This works (reassignment)
self.count = count + 1
self.name = "John"

# ❌ This won't trigger updates (not wrapped in a Delegator)
count + 1       # creates a new Integer but doesn't assign it
name.concat("!") # mutates the String but LiveCable doesn't detect it
```

## Prefer Methods Over Storing Large Datasets

You don't need to store everything in reactive variables. Component methods can be called directly from `.live.erb` templates, and LiveCable's dependency tracking will still re-render the relevant parts when the reactive variables they depend on change.

**Why this matters:** Reactive variables are held in memory on the server between renders. If you store 500 products in a reactive variable across 200 component instances, that's 100,000 product objects sitting in RAM at all times. Calling a method instead fetches the data fresh on each render and is immediately garbage collected afterwards.

**Best practice:** Use reactive variables for state (like page numbers, filters), but call methods to fetch data on-demand during rendering:

```ruby
module Live
  class ProductList < LiveCable::Component
    reactive :page, -> { 0 }
    reactive :category, -> { "all" }

    actions :next_page, :prev_page, :change_category

    def products
      # Fetched fresh on each render, not stored in memory
      Product.where(category_filter)
             .offset(page * 20)
             .limit(20)
    end

    def next_page
      self.page += 1
    end

    def prev_page
      self.page = [page - 1, 0].max
    end

    def change_category(params)
      self.category = params[:category]
      self.page = 0
    end

    private

    def category_filter
      category == "all" ? {} : { category: category }
    end
  end
end
```

In your `.live.erb` template, call `products` directly — LiveCable uses `method_missing` to forward the call to the component and tracks that it depends on `page` and `category`:

```erb
<div>
  <div class="products">
    <% products.each do |product| %>
      <div class="product">
        <h3><%= product.name %></h3>
        <p><%= product.price %></p>
      </div>
    <% end %>
  </div>

  <div class="pagination">
    <button live-action="prev_page">Previous</button>
    <span>Page <%= page + 1 %></span>
    <button live-action="next_page">Next</button>
  </div>
</div>
```

This approach:
- Keeps only `page` and `category` in memory (lightweight)
- Fetches the 20 products fresh on each render
- Prevents memory bloat when dealing with large datasets
- Still provides reactive updates when `page` or `category` changes

### The `component` local

A `component` local variable referencing the component instance is available in all templates. In `.live.erb` templates you don't need it — `method_missing` forwards method calls to the component automatically, and LiveCable can track dependencies for partial rendering.

If you use regular `.html.erb` templates or another templating language, you must use the `component` local to call component methods. Reactive variables are always available as template locals regardless of template type. Note that regular `.erb` templates do not support partial rendering — the entire template is re-rendered on every update.

```erb
<%# Regular .html.erb — reactive variables are locals, but methods need component %>
<div>
  <% component.products.each do |product| %>
    <div class="product">
      <h3><%= product.name %></h3>
    </div>
  <% end %>

  <span>Page <%= page + 1 %></span>
</div>
```

## Writable Reactive Variables

By default, reactive variables are **read-only from the client**. This prevents users from manipulating the DOM (e.g., via browser dev tools) to update variables that were never intended to be client-settable, such as a `user_id` or `total_price`.

To allow a reactive variable to be updated from the client via [`live-reactive`](/guide/actions-events#the-live-reactive-attribute), mark it as `writable:`:

```ruby
module Live
  class Counter < LiveCable::Component
    reactive :count, -> { 0 }                       # Server-only, cannot be set from the client
    reactive :step, -> { 1 }, writable: true         # Can be updated via live-reactive inputs

    actions :increment

    def increment
      self.count += step.to_i
    end
  end
end
```

If a client attempts to update a non-writable variable (e.g., by changing an input's `name` attribute in the browser), the server will reject the update and raise an error.

::: warning Security
Any reactive variable used with `live-reactive` in a template **must** be declared with `writable: true`. Without it, the client update will be rejected. This is a deliberate security measure — only opt in to client-writability for variables you explicitly intend to be user-controlled.
:::

The `writable:` option composes with other options:

```ruby
reactive :filter, -> { "all" }, writable: true                  # Writable local variable
reactive :search, -> { "" }, shared: true, writable: true       # Writable shared variable
```

## Shared Variables

Shared variables allow multiple components on the same connection to access the same state.

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

Use `shared` (without `reactive`) when you need to share state but don't want updates to trigger re-renders:

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

::: tip Use Case
FilterPanel can read the cart to show item count in a badge, but doesn't need to re-render every time an item is added—only when the filter changes.
:::

## Accessing Reactive Variables in Views

Reactive variables are automatically available as local variables in your component views:

```erb
<div>
  <div class="shopping-cart">
    <h2>Shopping Cart</h2>
    <p>Items: <%= items.size %></p>
    <p>Total: $<%= total %></p>

    <p class="discount <%= 'hidden' unless discount_code %>">
      Discount code: <%= discount_code %>
    </p>

    <ul>
      <% items.each do |item| %>
        <li><%= item[:name] %> - $<%= item[:price] %></li>
      <% end %>
    </ul>
  </div>
</div>
```

## Default Values from Rendering

You can pass default values when rendering a component:

```erb
<%# Set initial count to 10 %>
<%= live('counter', id: 'my-counter', count: 10) %>

<%# Load user data %>
<%= live('profile', id: "profile-#{@user.id}", user_id: @user.id) %>
```

These defaults are only applied when the component is first created, not on subsequent renders.

## Next Steps

- [Handle user actions](/guide/actions-events)
- [Use lifecycle callbacks](/guide/lifecycle-callbacks)
- [Learn about the architecture](/guide/architecture)
