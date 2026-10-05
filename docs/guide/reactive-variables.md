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

For ActiveRecord models, any write to the record's attributes is tracked: setters, `[]=`, `update`, `toggle!`, `increment!`, `update_columns` and `reload`, including on a model read from a reactive Array or Hash with `[]`, `each` or an Array's `find`, but not one passed to the block of `map` or `select`. Changes through an association (`project.tasks.create!(...)`) and unsaved in-place edits to a JSON or serialized attribute are not; call `dirty(:project)` after those. A callback that writes an attribute while saving, such as a `before_validation` that normalises one, counts as a write too.

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

Values read back out of a reactive Array or Hash are tracked whether you reach them with `[]`, `find`, `detect`, `fetch`, `dig` or an Array's `first`, or iterate with `each`, `each_with_index`, `each_value` and the like. Other methods can hand back plain values, and changes made through those aren't tracked: the elements passed to the blocks of `map`, `select` and similar methods; the results of methods that don't wrap what they return, such as a Hash's `select`, `reject` and `slice`, or an Array's `second`, `values_at` and `partition`; and `to_a` and `to_h`. Make in-place changes inside `each` instead, or call `dirty(:data)` after a change LiveCable can't see.

In component code, an element kept in two reactive collections, as after `favorites << todos.find { ... }`, is tracked through the collection you change it through. If the other collection shows it too, call `dirty(:todos)` after the change. A child first given the element with `live(...)` once both collections hold it marks both; see [Accessing Reactive Variables in Views](#accessing-reactive-variables-in-views).

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

A shared name holds one value for every component on the connection that shares it, so the client can write it
only if **every** component class that shares that name declares it `writable: true`. If any class shares it
without `writable:` (or with `shared`), client writes are refused for all of them - otherwise a client could
subscribe the writable component just to set a value another component trusts.

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

Templates see the plain Array, Hash or model, just as on the first page load, so helpers such as `tag.span(class: classes)` and `class_names`, and checks like `case items when Array`, behave as they do in any Rails view. In a `.live.erb` template the same goes for what a component method returns, including an Array or Hash it builds from reactive values, such as `todos.each_slice(3).to_a`. Values a component method yields to a template block are still change-tracking wrappers, and so is anything reached through `component`, such as `component.items`.

Templates shouldn't change state. An Array or Hash changed in place in a template, or a model inside one, doesn't mark its variable dirty; a model held directly in a variable does, because it's watched on the record itself.

Passing a reactive value, an element of one, or a collection built from one to a child with `live(...)` keeps its change tracking, so the child's changes re-render this component too:

```erb
<% todos.each do |todo| %>
  <%= live('todo_card', id: todo[:id], todo:) %>
<% end %>
```

When `TodoCard` runs `todo[:done] = true`, the list re-renders as well. A child's tracking is set when it's created. A child created while two reactive collections hold its element, as after `pinned << todos.find { ... }`, marks both; one created before then marks only the collection it came from. A collection of plain values, such as `todos.map { |todo| todo[:id] }`, is passed as is.

In your component's Ruby code, reactive Arrays, Hashes and models are change-tracking wrappers once the component is connected, and plain values during the HTTP prerender of the first page load. ActiveRecord's `where(column: value)` accepts either, but `case` and `is_a?(Hash)`, `where(hash)` and assigning a model to an association don't see through the wrapper. Pass `items.to_a`, `settings.to_h` or `LiveCable::Delegator.unwrap(user)` to those. Each works in both cases and returns the underlying value itself, so in-place changes to an Array or Hash made through it aren't tracked.

## Default Values from Rendering

You can pass default values when rendering a component:

```erb
<%# Set initial count to 10 %>
<%= live('counter', id: 'my-counter', count: 10) %>

<%# Load user data %>
<%= live('profile', id: "profile-#{@user.id}", user_id: @user.id) %>
```

These defaults are only applied when the component is first created, not on subsequent renders.

Defaults travel through the page and come back from the browser when the
component subscribes. LiveCable signs them, so the browser can't change them,
but doesn't encrypt them, so don't pass anything secret. They come back as
JSON, so pass JSON-safe values (an id rather than a record), and expect nested
hashes back with string keys. See
[Writable Variables and Defaults](/guide/architecture#writable-variables-and-defaults).

A Turbo visit to a page that renders the component with different defaults
builds it again from them. Keep defaults to what identifies the component's
subject: one that changes on every render, such as `Time.current`, rebuilds
the component on every visit.

## Next Steps

- [Handle user actions](/guide/actions-events)
- [Use lifecycle callbacks](/guide/lifecycle-callbacks)
- [Learn about the architecture](/guide/architecture)
