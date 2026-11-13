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
Default values are defined as lambdas to ensure each component instance gets its own copy of the value. Without lambdas, all instances would share the same object reference. A lambda that takes an argument is given the component, so it can read the component's defaults: `reactive :user, ->(c) { User.find(c.defaults[:user_id]) }`. Anything other than a proc or `nil` raises an `ArgumentError` when the class loads.
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

1. **Automatic Wrapping**: LiveCable wraps an Array or Hash in a transparent Delegator; a model is stored as the record itself
2. **Observer Attachment**: An Observer is attached to the wrapper or the record to track mutations
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

For ActiveRecord models, any write to the record's attributes is tracked: setters, `[]=`, `update`, `toggle!`, `increment!`, `update_columns` and a `reload` that brings in a change, including on a model read from a reactive Array or Hash with `[]`, `each` or an Array's `find` and on the record its `reload` or `lock!` returns, but not one passed to the block of `map` or `select`. A model read from a collection is the record itself, and from then on it marks that collection too, even after you take it out; at worst that's one re-render more than needed. So are writes through a tracked model's `clone`, which shares the original's attributes; a `dup` is a separate record. Changes through an association (`project.tasks.create!(...)`) and unsaved in-place edits to a JSON or serialized attribute are not; call `dirty(:project)` after those. Neither is `destroy`, which writes no attribute: remove the record from its Array, or call `dirty`. That holds for a record passed to a child with `live(...)` too: a child that destroys it doesn't re-render, and the parent still lists it. Saving nested attributes writes the associated records, not this one, so `update!(tasks_attributes: ...)` and `save` after `tasks_attributes=` need `dirty` too. `update` and `assign_attributes` mark the variable whatever they change, so `update(tasks_attributes: ...)` does re-render. A `reload` compares only the record's own columns, so a change to its associations made elsewhere needs `dirty` too, and a reload that finds nothing new doesn't re-render. A callback that writes an attribute while saving, such as a `before_validation` that normalises one, counts as a write too.

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

Values read back out of a reactive Array or Hash are tracked whether you reach them with `[]`, `find`, `detect`, `fetch`, `dig` or an Array's `first`, or iterate with `each`, `each_with_index`, `each_value` and the like. Other methods can hand back plain values, and changes made through those aren't tracked: the elements passed to the blocks of `map`, `select` and similar methods; the results of methods that don't wrap what they return, such as a Hash's `select`, `reject` and `slice`, or an Array's `second`, `values_at` and `partition`; and `to_a` and `to_h`. Make in-place changes inside `each` instead, or call `dirty(:data)` after a change LiveCable can't see. Methods that return the collection itself, such as `<<`, `push`, `merge!` and `each`, return the plain one, as `to_a` does, so only the first call in a chain like `done << a << b` is tracked; write `done << a` and `done << b` instead.

In component code, an element kept in two reactive collections, as after `favorites << todos.find { ... }`, is tracked through the collection you change it through. If the other collection shows it too, call `dirty(:todos)` after the change. A child first given the element with `live(...)` once both collections hold it marks both; see [Accessing Reactive Variables in Views](#accessing-reactive-variables-in-views).

## Primitive Values

LiveCable only wraps Arrays and Hashes in change-tracking Delegators, and watches ActiveRecord models on the record itself. Other values — including Strings, Integers, Floats, Booleans, and Symbols — are not tracked for in-place mutation. You must reassign them to trigger updates:

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

## Query-Backed State

A method like `products` above re-renders when `page` or `category` changes,
but not when the rows change: dependency tracking sees a method that only runs
a query as depending on nothing. `reactive_query` declares a query whose
result re-renders when it changes, without holding the rows between renders:

```ruby
module Live
  class Timesheet < LiveCable::Component
    reactive :day, -> { Date.current }

    reactive_query :entries, -> { Entry.where(spent_on: day).includes(:project).order(:created_at) } do |relation|
      relation.sort_by { |entry| [entry.user_id == current_user.id ? 0 : 1, entry.created_at] }
    end

    actions :stop, :next_day

    after_connect { stream_from("entries_#{current_user.account_id}") { refresh(:entries) } }

    def total_hours
      entries.sum(&:hours)
    end

    def stop(params)
      Entry.find(params[:id]).update!(stopped_at: Time.current)
      refresh(:entries)
    end

    def next_day
      self.day = day + 1
    end
  end
end
```

The lambda runs on the component and must return an `ActiveRecord::Relation`;
an association such as `-> { current_user.entries }` counts. Each read builds
a fresh relation from it, so an association already loaded on the record, or
a relation the lambda returns already loaded, is queried again rather than
reused. The optional block runs on the component too and receives the relation; with
no block, `entries` returns the loaded relation. Templates call `entries` like
any component method, and a part that reads it, directly or through a method
in the component's file such as `total_hours`, re-renders when it changes.
In a plain `.html.erb` template, call `component.entries`: a query isn't a
template local the way a reactive variable is.

- **One query per render.** The first read in a render runs the query and the
  block, and later reads in that render get the same result. Nothing is kept
  after the render: outside one, such as in an action, each read runs the
  query again.
- **What's kept is a fingerprint**: a digest of the query's SQL and its
  `cache_key_with_version`, the row count and latest `updated_at`. A render
  takes it from the records it just loaded, without another query. A relation
  whose records Rails can't count as rows (`eager_load`, or `includes` with
  `references`, `select`, `group` or `distinct`), or one the block doesn't
  load (such as `relation.count`), costs one `COUNT(*)`/`MAX(updated_at)`
  query per render instead.
- **`refresh(:entries)`** runs that aggregate query and re-renders the parts
  that read `entries` only if the fingerprint changed, so a stream whose
  messages mostly concern other rows doesn't re-render for them. `refresh`
  with no names checks every query on the component. Call it in an action or
  a `stream_from` callback, after a write you want shown; it raises during a
  render. Nothing polls: a write nobody refreshes for isn't shown until a
  `refresh`, a `dirty`, or a change to something else the part reads.
- **A changed query re-renders without a database query.** When the component
  re-renders for any reason, each query's SQL digest is compared with the
  stored one, so `next_day` re-renders `entries` even though the lambda isn't
  a method dependency tracking can follow.
  The block isn't checked this way: a reactive variable only the block reads
  doesn't re-render the query's parts when it changes. Read it in the lambda,
  so it changes the SQL, or call `dirty(:entries)` where it's set.
- **`dirty(:entries)`** re-renders the parts that read `entries` without
  checking, for a write the fingerprint can't see.

The fingerprint only sees what changes the row count or `updated_at`:

- Writes that skip `updated_at`: `update_columns`, `update_column`,
  `update_all`, `insert_all`, `upsert_all`, or SQL run directly. Call
  `dirty(:entries)` after those, or set `updated_at` yourself.
- Changes to included or preloaded associations, such as a project renamed,
  unless the association has `touch: true`. Declare a second
  `reactive_query` for the associated rows and read it in the same part, or
  call `dirty`.
- Two edits to the same row within the timestamp's precision look like one.
- The table needs an `updated_at` column; reading a query on a model without
  one raises `LiveCable::Error`.

Only relations have a fingerprint. A value from an API, or a query that
doesn't return a relation (`pluck`, `find_by`), stays a plain method or a
reactive variable.

A query belongs to its component: there is no `shared:` option (passing one
raises `ArgumentError`), since the lambda reads the component's own state. Components that show the same rows
each declare the query and refresh it, for example from a stream they all
listen to.

Defining your own `refresh` method in a component replaces this one, so a
component that already has one and then declares a `reactive_query` calls its
own method instead: rename it, or call `super` from it. It isn't an action
unless you list it in `actions`.

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

A shared value a component sets while it subscribes, from its defaults or in `after_connect`, reaches the components
that rendered before it on the connection's next update: the next action or `stream_from` callback on any of its
components.

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
FilterPanel can read the cart to show item count in a badge, but doesn't need to re-render every time an item is added—only when the filter changes. Whenever FilterPanel re-renders for its own reasons, parts that read `cart_items` (directly or through a method) re-render too, so the badge picks up the latest count.
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

Templates shouldn't change state. An Array or Hash changed in place in a template doesn't mark its variable dirty; a model can, because it's watched on the record itself.

Passing a reactive value, an element of one, or a collection built from one to a child with `live(...)` keeps its change tracking, so the child's changes re-render this component too:

```erb
<% todos.each do |todo| %>
  <%= live('todo_card', id: todo[:id], todo:) %>
<% end %>
```

When `TodoCard` runs `todo[:done] = true`, the list re-renders as well. The other direction works too: when the list runs `todos.first[:done] = true`, or another child changes an element the card shares, the list re-renders the part that renders the card, and the card re-renders with it. Each time the parent renders a `live(...)` call again, the child checks each Array or Hash it was given, and re-renders what reads one whose contents, or a record in them, changed since the parent last rendered the call. A change that doesn't re-render the call, such as one to a variable that part doesn't read, doesn't reach the child until it does. A collection built in the template stays the one the child was first given: changes to its elements show, but an element added to the source doesn't. A child's tracking is set when it's created. A child created while two reactive collections hold its element, as after `pinned << todos.find { ... }`, marks both; one created before then marks only the collection it came from. A collection of plain values, such as `todos.map { |todo| todo[:id] }`, is passed as is.

In your component's Ruby code, a reactive model is always the record itself, whether it's held in a variable or read from a reactive Array or Hash, so `==`, `is_a?`, `case`, `where(owner: user)` and assigning it to an association work as usual. Reactive Arrays and Hashes are change-tracking wrappers once the component is connected, and plain values during the HTTP prerender of the first page load. ActiveRecord's `where(column: value)`, `find`, `destroy` and `update` with a list of ids, `in_order_of` and Arel's `in` and `not_in` accept either, as does `where(association: records)` with a list of records, polymorphic or not, but `case` and `is_a?(Hash)`, `where(hash)` and bind values in a string condition such as `where('id IN (?)', ids)` don't see through the wrapper. Pass `items.to_a`, `settings.to_h` or `LiveCable::Delegator.unwrap(value)` to those. Each works in both cases and returns the underlying value itself, so in-place changes to an Array or Hash made through it aren't tracked.

## Default Values from Rendering

You can pass default values when rendering a component:

```erb
<%# Set initial count to 10 %>
<%= live('counter', id: 'my-counter', count: 10) %>

<%# Load user data %>
<%= live('profile', id: "profile-#{@user.id}", user_id: @user.id) %>
```

These defaults are only applied when the component is first created, not on subsequent renders.

A top-level component's defaults are signed into the page and sent back by the browser when it connects, so
they must be JSON-safe: strings, numbers, booleans, `nil`, and arrays or string-keyed hashes of those. A Symbol,
a `Time` or `Date`, or a Hash with Symbol keys arrives as its JSON form - `:open` as `"open"`, a `Time` as an
ISO 8601 string - and LiveCable logs a warning in development and test. A hash's keys arrive sorted, at every level, on page load and after connecting. Anything else raises an
`ArgumentError`, in every environment, wherever it sits in the defaults: a record's JSON form is every one of
its attributes, and a `Struct`, a `Set` or a presenter holding one would put them in the page too. Pass an id
and load the record in the component. The defaults are signed, not encrypted, so anyone viewing the page can
read them; don't pass secrets. See
[Writable Variables and Defaults](/guide/architecture#writable-variables-and-defaults).

A Turbo visit to a page that renders the component with different defaults
builds it again from them. Keep defaults to what identifies the component's
subject: one that changes on every render, such as `Time.current`, rebuilds
the component on every visit.

## Next Steps

- [Handle user actions](/guide/actions-events)
- [Use lifecycle callbacks](/guide/lifecycle-callbacks)
- [Learn about the architecture](/guide/architecture)
