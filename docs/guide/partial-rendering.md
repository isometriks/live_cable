# Partial Rendering & Performance

LiveCable includes a powerful partial rendering system that dramatically improves performance by only sending the parts of your template that actually changed.

## Overview

When you use `.live.erb` templates, LiveCable automatically:

1. **Splits your template into parts** - Static HTML and dynamic Ruby code are separated
2. **Tracks dependencies** - Analyzes which reactive variables each part uses
3. **Sends only changes** - On subsequent renders, only sends the parts that changed
4. **Minimizes bandwidth** - Static HTML is sent once, then reused on the client

This is a major performance improvement over the default `.html.erb` templates, which send the entire HTML on every render.

## Using .live.erb Templates

### Basic Usage

Simply name your component view with `.live.erb` instead of `.html.erb`:

**Before:**
```
app/views/live/counter.html.erb
```

**After:**
```
app/views/live/counter.html.live.erb
```

That's it! LiveCable will automatically use the partial rendering system.

### How It Works

Let's look at a simple counter component:

```erb
<!-- app/views/live/counter.html.live.erb -->
<div>
  <h2>Counter</h2>

  <div class="count">
    <%= count %>
  </div>

  <button live-action="increment">+</button>
  <button live-action="decrement">-</button>
</div>
```

LiveCable compiles this into multiple parts:

1. **Static part 1:** `<div>\n  <h2>Counter</h2>\n  \n  <div class="count">\n    `
2. **Dynamic part:** The result of `count` (e.g., "5")
3. **Static part 2:** `\n  </div>\n  \n  <button live-action="increment">+</button>\n  <button live-action="decrement">-</button>\n</div>`

On first render, all parts are sent. On subsequent renders when `count` changes, only part 2 is sent.

### Performance Benefits

**Initial Render (all parts sent):**
```json
{
  "h": "a1b2c3d4e5f6",
  "p": [
    "<div>\n  <h2>Counter</h2>\n  <div class=\"count\">\n    ",
    "0",
    "\n  </div>\n  <button live-action=\"increment\">+</button>\n  <button live-action=\"decrement\">-</button>\n</div>"
  ]
}
```

**Subsequent Render (only changed part):**
```json
{
  "h": "a1b2c3d4e5f6",
  "p": [null, "1", null]
}
```

The bandwidth savings grow significantly with larger components!

## Dependency Tracking

LiveCable uses static analysis to track which reactive variables each part of your template depends on.

### Direct Dependencies

```erb
<div>
  <span><%= user_name %></span>
  <span><%= user_email %></span>
</div>
```

If only `user_name` changes, only the first `<span>` content is sent.

`component.user_name` and `self.user_name` count as reads of `user_name` too.

A part that reads a non-reactive `shared` variable re-renders whenever its
component does, since a change to it doesn't trigger a render on its own.

### Method Dependencies

LiveCable also tracks method calls and expands them to their reactive variable dependencies:

```ruby
module Live
  class Profile < LiveCable::Component
    reactive :first_name, -> { "John" }
    reactive :last_name, -> { "Doe" }

    def full_name
      "#{first_name} #{last_name}"
    end
  end
end
```

```erb
<h1><%= full_name %></h1>
```

When either `first_name` or `last_name` changes, the `full_name` part is re-rendered because LiveCable knows that `full_name` depends on both variables.

### How Method Analysis Works

LiveCable uses Prism (Ruby's parser) to analyze your component methods:

1. **At component load time**, all methods are parsed
2. **Dependencies are extracted** - Which reactive variables and other methods are called
3. **Transitive dependencies are computed** - Method calls are expanded recursively
4. **Results are cached** - Analysis only happens once per component class

This means zero runtime overhead!

### Local Variable Dependencies

LiveCable also tracks local variables within templates:

```erb
<% items.each do |item| %>
  <div><%= item.name %></div>
<% end %>
```

The whole `items.each` block, with everything nested in it, is one part. It
depends on `items` and re-runs on the server as a unit when `items` changes;
`item` is the block's own variable, not a dependency. Only the rows that
changed are sent: see [Control Blocks](#control-blocks).

### Locals Follow Ruby's Scopes

A local assigned at the top level of a `<% %>` tag is available to the tags
after it, as in one Ruby method:

```erb
<% total = items.sum(&:price) %>
<p><%= number_to_currency(total) %></p>
```

- A tag, or an `if`/`case`/loop group, that assigns a top-level local a later
  tag reads runs whenever the component re-renders, and so does every tag
  that reads it. Prefer a component method for anything costly; methods are
  tracked precisely.
- A tag that assigns a local before reading it, such as a second
  `for item in ...` loop, doesn't read the earlier value, so it doesn't make
  the earlier tag run.
- A local assigned inside a block exists only inside it. Reading it after the
  block raises a `NameError`, unless the component or a view helper has a
  method of that name.
- An assignment that doesn't run, such as one inside a false `if`, leaves the
  local with its earlier value.
- Unlike in one Ruby method, a lambda or block made in one tag keeps that
  tag's own copy of the locals. Called from a later tag, its writes don't
  reach the tags after it, and it doesn't see a value a later tag assigns.
  Make and call it in the same tag, or use a component method.

### How Names Resolve

A bare name in a `.live.erb` template is looked up in this order:

1. a local assigned at the top level of an earlier tag;
2. a public method of the component, reactive variables included;
3. a view helper.

A local is read only by its bare name, as in plain Ruby. After
`<% t = Time.current %>`, `t('.title')` still calls the helper, and with a
local `count`, `count()` and `self.count` still call the component's `count`.

A component method named like a Kernel or Object method (`open`, `test`,
`select`, `rand`) wins over Kernel's in its template; call it on `Kernel`, as
in `Kernel.rand`, to reach Kernel's.

A few names belong to the renderer that runs the template and never reach the
component: `component`, which is the component itself, `render`, which renders
through the view, and `render_changes`, `should_skip_part?`,
`expand_component_method_dependencies`, `mark_locals_dirty`, `store_local`,
`call_component`, `with_buffer`, `render_tree` and `bind_shadowed_names`.
Call a component method with one of these names as `component.name`.

## Code vs Expression Parts

### Code Parts (always run)

A standalone `<% %>` tag always runs, so the locals it assigns are current for
the tags after it. It sends nothing itself:

```erb
<% total = items.sum(&:price) %>
```

Unlike plain ERB, a standalone `<% %>` tag throws away anything it writes to
the page: `concat`, `safe_concat`, a helper that calls them, or a template
proc it calls. Write output from an `<%= %>` tag or a block instead:

```erb
<%# Renders nothing %>
<% items.each { |item| concat tag.li(item) } %>

<%= safe_join(items.map { |item| tag.li(item) }) %>
<% items.each do |item| %><li><%= item %></li><% end %>
```

### Expression Parts (can be skipped)

An `<%= %>` tag is skipped when nothing it reads has changed:

```erb
<%= count %>
```

If `count` hasn't changed, this part returns `nil` (skip) instead of rendering.

A control or block tag (`if`, `case`, `each`, ...), with everything nested in
it, is one expression part and re-runs as a unit:

```erb
<% if show_details %>
  <%= user.email %>
<% end %>
```

The `if` and everything inside it are skipped unless `show_details` or `user`
has changed. When it does re-run, only the values that changed are sent (see
[Control Blocks](#control-blocks)).

An expression part that assigns a top-level local a later tag reads always
runs, so that tag gets the current value. It is sent on every update, except
a control block, which sends only the values that changed.

Each update renders on a fresh view, so an expression part that calls
`content_for`, `content_for?` or `provide` also always runs. A
`<% content_for :heading do %>` block and the tag that reads
`content_for(:heading)` stay in step whichever of them changed.

## Control Blocks

An `if`, `unless`, `case`, `for`, `while` or `until` at the top of a template, and a block that iterates (`each`, `each_with_index`, `times`, `find_each` and the like), is compiled into a structure rather than an HTML string. Its markup is split at compile time into static strings, one list per branch and one per loop body, and the part carries only the values that fill the gaps:

```erb
<ul>
  <% todos.each do |todo| %>
    <li id="todo-<%= todo.id %>"><%= todo.title %></li>
  <% end %>
</ul>
```

```json
{
  "h": "a1b2c3d4e5f6",
  "p": ["<ul>\n  ", { "t": 0, "r": [["1", "Milk"], ["2", "Eggs"]], "k": ["todo-1", "todo-2"] }, "</ul>\n"],
  "s": { "0": ["    <li id=\"todo-", "\">", "</li>\n  "] }
}
```

- `t` names the static list (the scope) the values belong to. A branch carries its values in `d`, a loop carries one list per row in `r`, and a conditional with no branch taken is `{ "t": null }`.
- `s` carries the static lists. Each is sent once per component, the first time a render uses it.
- A value is either an HTML string or a nested structure, so branches inside loops and loops inside branches work the same way at any depth.

After the first render, a block's part is a diff against the structure the client already holds, so only what changed travels:

```json
{ "h": "a1b2c3d4e5f6", "p": [null, { "o": [["u", "todo-2", { "1": "Free-range eggs" }]] }, null] }
```

Renaming one todo sends its new title and nothing else. Adding one sends the new row and where it goes; removing one sends its key. A branch that flips sends the new branch's values, plus its statics if the client hasn't seen them yet.

### Row Ops

A keyed loop's diff is `{ "o": [...] }`, a list of row ops the client applies in order. Each op names the row it is about second:

| Op | Meaning |
|---|---|
| `["d", key, ...]` | Delete these rows. A key the client doesn't hold is ignored. |
| `["a", key, row]` | Append a row. |
| `["p", key, row]` | Prepend a row. |
| `["i", key, row, after]` | Insert a row after the row keyed `after`. |
| `["m", key, after]` | Move a row after `after`, or to the front when `after` is `null`. |
| `["s", key, ...]` | Sort: put these rows first, in this order. Keys the client doesn't hold are skipped, and rows it holds that aren't named follow, in their order. |
| `["u", key, change]` | Update a row: an object of the values that changed, by index, or a whole row. A key the client doesn't hold is ignored. |
| `["r"]` | Reset: drop every row. Ops after it start from an empty loop. |

A `row` is the list of values for one row, as in `r`. Inserting a key the client already holds replaces that row where it is, and inserting after a key it doesn't hold appends. A [collection stream](/api/component#stream-name-initial-nil-dom-id-nil-limit-nil) relies on these rules, since its server doesn't know which rows the page holds. A stream's loop also carries its name in `st` and, when it has one, its limit in `l`: an insert that adds a row past the limit drops the last row after a prepend and the first otherwise. When LiveCable gave the stream's rows their `id`, the loop carries `"ik": 1` and each row leaves that `id` out of its values, since it is the row's key: the client fills it in from `k` or from the op. Removing one todo from a list of 2,000 sends `{ "o": [["d", "todo-1000"]] }`; adding one at the top sends a `p` op with the new row.

LiveCable sends one `d` op for the rows that went, then works through the new order, inserting each new row after the one before it and moving only the rows that fell out of the longest run still in order. When those moves would take more bytes than the new order of the rows it kept, as when a table is re-sorted, it sends that order as one `s` op instead, so a re-sort of 2,000 rows costs about what the key list does. When no row is kept, as when a filter swaps one set of rows for another, it sends the whole loop instead.

A loop without keys sends its diff by position: `{ "n": 3, "r": { "2": [...] } }` gives the new row count, when it changed, and the rows that changed, whole or as a diff, by index.

The gem and the npm package must be the same version: a client from another release can't read these diffs.

### Patching Rows in Place

When everything a render changed in a component is row ops on keyed loops, the client applies them to the page directly instead of rebuilding the component's HTML and morphing all of it. Each row of a keyed loop renders one element, so the rows are a run of sibling elements: new rows are built from their values and inserted, removed rows are taken out, moved rows are moved, and only the rows that changed are morphed. Rows nobody touched, and the rest of the component, are left alone, so the client's work grows with the rows that changed rather than with the length of the list.

A collection stream's rows are the elements inside its `live-stream` container, so the client finds them through the container: an empty stream takes new rows the same way, rows its limit trims are removed, and only the rows the ops name are looked up on the page. A nested component's stream of the same name has its own container and is never touched.

Row patching keeps what a morph keeps. A changed row is morphed with the same rules as the whole component: `live-ignore` elements are left alone, elements awaiting a reply keep their loading state, a focused field keeps what was typed unless the server changed its value, and child components in the row are kept. A moved row keeps focus and the text selection of a field inside it. New rows are parsed so that table rows, cells and options land where they belong and rows inside an `<svg>` or `<math>` element are SVG or MathML elements, with their child components filled in.

A part that re-ran to the HTML the client already holds counts as unchanged. The client falls back to rebuilding and morphing the component when the render changed anything else, carried a child component's render, or when it can't place the rows exactly: the loop held no rows to place new ones by, the page no longer shows the rows the client holds (a script removed one, say), the loop is inside a `live-ignore` or loading element, a new or changed row doesn't render one element with its key, or another element of the component has the key its first row has (two loops over the same records, or a field inside a row whose `id` is the row's key). A stream falls back when its container is missing or its rows aren't the ones the client holds. The result is the same either way, except that a stream inside a `live-ignore` element isn't updated by either.

### Row Keys

Rows are matched by key when the loop body renders a single element with an `id` or `live-key` attribute that contains Ruby, as in the example above. The key is read before the row renders, so its Ruby may only read the loop's own variables: `todo.id`, `todo[:id]`, `"todo-#{todo.id}"` or `dom_id(todo)` all work, while something like `cycle('a', 'b')` or `n += 1` leaves the loop unkeyed. Without a key, rows are matched by position, which is still correct but sends every row after an insertion or removal. If two rows render the same key, that render matches by position.

### What Stays HTML

Some blocks are rendered to HTML instead, as they always were:

- **Block helpers** such as `<%= form_with do %>`, `<% content_for :x do %>` or `<% cache do %>`, because the helper decides what happens to what its body writes. Inside a control block, such a helper becomes a single HTML value of that block.
- **A block that leaves its body early** with `next`, `break`, `return`, `redo`, `retry` or `throw`, because the values would no longer line up with the statics. The whole top-level block is sent as HTML.
- **`begin` / `rescue`**, as a single HTML value.
- **A block that comes before any other output**, because it may hold the component's root element, which LiveCable adds its attributes to.

A non-output tag inside a control block that writes to the buffer itself (`<% concat 'x' %>`) has its output dropped, and LiveCable logs a warning. Use an output tag instead.

### Turning It Off

Structured blocks are on by default. To send each control block as one HTML string again, set this in an initializer; templates read it when they compile:

```ruby
LiveCable.configure do |config|
  config.structured_blocks = false
end
```

## Partials

### Live Partials

A partial named `_name.html.live.erb` is a live partial. When a component's
`.live.erb` template renders one with a literal path, LiveCable copies the
partial into the template as the template compiles, so the partial reads the
component's state directly and its reads are tracked like the template's own:

```erb
<%# app/views/live/chat.html.live.erb %>
<div class="chat">
  <h2><%= room_name %></h2>
  <%= render 'live/chat/messages' %>
  <%= render 'live/chat/composer', placeholder: 'Say something' %>
</div>
```

```erb
<%# app/views/live/chat/_composer.html.live.erb %>
<%# locals: (placeholder:) -%>
<input name="draft" value="<%= draft %>" placeholder="<%= placeholder %>" live-reactive>
<button live-action="send_message">Send</button>
```

The composer re-renders when `draft` changes, and `live-action` and
`live-reactive` in it go to the chat component, as if the markup were written
in the template. A live partial is still one part: it re-renders as a unit,
and sends only the values in it that changed, like a control block. Inside a
control block it is part of that block, so a live partial rendered in a loop
body sends per-row changes like markup written in the loop. Its rows are
matched by position, though, because the key is read from the loop body's own
element: use `collection:`, or put the `id` on an element around the
`render`, to key them. Split a large partial into several for finer updates.

In a live partial, a bare name is one of the partial's locals, then a local
the partial assigned earlier, then a component method, then a view helper.
The template's own locals are never visible: reading one is an error when the
template compiles. Pass the value as a local instead. `self.name` and
`name()` always reach the component.

`t('.key')` in a live partial looks the key up under the partial's own path,
as in Rails: `live.chat.composer.key` for the composer above.

#### Locals

Declare a live partial's locals with Rails' strict-locals comment as its first
line. A default can read the component's state, and that read is tracked:

```erb
<%# locals: (label:, tone: "info", count: unread_count) -%>
```

Unlike Rails, a live partial without the comment takes no locals. A missing
or unknown local is an error when the template compiles, whichever branch the
render is in. `local_assigns` holds the locals passed at the call site, as in
Rails.

#### How to Render One

Render a live partial with a path that includes its directory, as the whole of
an `<%= %>` tag:

```erb
<%= render 'live/chat/badge', label: title %>
<%= render partial: 'live/chat/badge', locals: { label: title } %>
<%= render partial: 'live/chat/author', object: message.author %>
<%= render partial: 'live/chat/message', collection: messages, as: :message %>
```

- The locals must be a literal Hash with Symbol keys, so they're known when the
  template compiles.
- `object:` binds the partial's name, or `as:`, as a local. Declare it.
- `collection:` renders the partial once per item, binding the item, and
  `message_counter` and `message_iteration` if the partial declares them. It
  is a loop in the template, so its rows are keyed by the partial's `id` or
  `live-key`, as described in [Row Keys](#row-keys).
- A bare name such as `render 'badge'` resolves against the controller's
  prefixes, which differ between a page and the socket, so it is an error when
  it reaches a live partial. Write the full path.

Everything else is an error when the template compiles, naming the template,
the line and the fix:

- A render that isn't the whole of its tag, such as `<%= render(...) if show %>`
  or `<% render ... %>`. Write `<% if show %><%= render ... %><% end %>`.
- A block, `layout:` or `spacer_template:`.
- `yield`, `return`, `cache` or an instance variable in the partial.
- A partial that renders itself, directly or through others. Use a child
  component or a `.html.erb` partial for a recursive structure.
- A partial that doesn't parse on its own, such as one with an unclosed tag.
- Both `_badge.html.erb` and `_badge.html.live.erb`.
- A request variant (`_badge.html+phone.live.erb`) or locale file of the
  partial when the template that renders it has none of its own: the template
  compiles once for every request, so it can't choose per request.

A live partial rendered any other way, with a path in a variable, from a
`.html.erb` view or a mailer, raises an error when it renders.

Live partials are found in `ApplicationController`'s view paths, which socket
renders use too. A `prepend_view_path` in another controller doesn't apply.
In development, editing a live partial takes effect on the next page load, as
any template edit does.

### Plain Partials

A `.live.erb` template can render ordinary Rails partials, with locals, with a
block, or as a layout:

```erb
<%= render 'shared/badge', count: %>

<%= render layout: 'shared/card' do %>
  <%= count %>
<% end %>
```

A block in a `.live.erb` template writes wherever the view is writing when it
runs, as in plain ERB. So a view helper, or any other object that passes your
block to a partial, such as `def card(&) = render(layout: 'shared/card', &)`,
renders it where the partial yields.

A plain partial only sees its locals, and renders as part of the template
part that calls it, so it re-renders when that part does: when an argument
changes.

### Which to Use

| | Plain partial (`.html.erb`) | Live partial (`.html.live.erb`) | Child component (`live(...)`) |
|---|---|---|---|
| Reads | Its locals | Its locals and the component's state | Its own state |
| Re-renders | When an argument changes | When anything it reads changes | On its own |
| Rendered from | Anywhere | A component template or live partial, with a literal path | Anywhere `live(...)` works |
| Recursion | Yes | No | Yes |

Use a live partial to split a component's template into files, or to share
markup over component state. Use a plain partial for markup that also
renders outside components, such as from Turbo Stream broadcasts or mailers.
Use a child component when the fragment owns state or actions of its own.

## Template Switching

For compound components with multiple templates, LiveCable handles template switches efficiently:

```ruby
class Wizard < LiveCable::Component
  compound

  reactive :step, -> { 1 }

  def variant
    "step_#{step}"
  end
end
```

```erb
<!-- app/views/live/wizard/step_1.html.live.erb -->
<div>Step 1 content...</div>

<!-- app/views/live/wizard/step_2.html.live.erb -->
<div>Step 2 content...</div>
```

When switching templates:

1. **Template hash changes** - Client detects the template switch
2. **All dynamic parts render** - Static parts from new template sent as needed
3. **State preserved** - Component state persists across template switches

The `:dynamic` render mode forces all dynamic parts to render while reusing static parts from the new template.

## Child Component Rendering

When using `.live.erb` templates, child components are rendered efficiently without redundant work.

When a parent component renders:

1. Parent HTML is sent with **`<LiveCable>` placeholders** for children
2. Child render results are included in the parent's JSON payload
3. JavaScript replaces placeholders with child HTML from the payload
4. When a child's Stimulus controller connects, it **reuses** the existing `ComponentState`

This avoids double rendering — each child is rendered once on the server and delivered as part of the parent's payload.

### How It Works

**Parent template:**
```erb
<!-- app/views/live/parent.html.live.erb -->
<div>
  <h1>Parent</h1>
  <%= live('child', id: 1) %>
</div>
```

**Rendered to client:**
```json
{
  "h": "abc123",
  "p": [
    "<div>\n  <h1>Parent</h1>\n  ",
    "<LiveCable child-live-id=\"child/1\"></LiveCable>",
    "\n</div>"
  ],
  "c": {
    "child/1": {
      "h": "def456",
      "p": ["<div>Child 1</div>"]
    }
  }
}
```

The JavaScript subscription manager:

1. Assembles the parent HTML, which contains `<LiveCable>` placeholders for children
2. Replaces each placeholder with the child's rendered HTML from the `c` payload
3. Stores the child's parts in a `ComponentState` before the child's Stimulus controller connects
4. When the child controller connects, it reuses the stored state — no redundant server render needed

The `c` map is flat: results for children at every depth, grandchildren included, sit side by side keyed by live id. A child's HTML can carry placeholders of its own, and those are replaced from the same map.

A child can render wherever its root element is valid HTML. A child whose root is a `<tr>` stays inside the parent's `<tbody>`, and one whose root is an `<option>` stays inside its `<select>`.

### ComponentState Class

The `ComponentState` JavaScript class stores:

- `#partsByTemplate` - Parts for each template (for compound components)
- `#lastTemplate` - Which template was last used
- `#element` - The DOM element reference

When a component subscribes, it can reuse existing `ComponentState` if the element matches.

## Fragment Caching

Rails' `cache` helper works in a `.live.erb` template, and page loads and socket renders share its fragments:

```erb
<div>
  <% cache ['header', account] do %>
    <h2><%= account.name %></h2>
  <% end %>
</div>
```

As in any Rails view, the key carries the component template's digest, so editing the template expires its fragments, and two components that use the same key keep separate fragments. Partials the template renders aren't part of that digest, live partials included, so put a version in the key when a cached block renders one. A live partial can't use `cache` itself.

A `cache` block that renders a component with `live(...)` is rendered every time and never stored. A stored copy would skip the `live(...)` call, so the parent would lose track of the child, and a page load would get a socket render's placeholder in place of the child's HTML. Cache inside the child's own template instead.

Collection caching (`render partial:, collection:, cached: true`) has no such check, so don't render components with `live(...)` from a partial rendered that way.

## Migration Guide

### Converting Existing Templates

1. Rename `.html.erb` to `.html.live.erb`
2. Test thoroughly - most templates work without changes
3. Watch the Rails log for this warning, logged once per template:

```
[LiveCable] live/counter was rendered without a .live.erb template; the full
template diff is sent on every change, which is less performant.
```

### Potential Gotchas

**Method calls to non-reactive data:**

```ruby
# This won't trigger re-renders when Time changes
def current_time
  Time.now.strftime("%H:%M")
end
```

```erb
<%= current_time %>
```

The method doesn't depend on reactive variables, so the part won't update. Solution: make it reactive!

```ruby
reactive :last_updated_at, -> { Time.now }

def current_time
  last_updated_at.strftime("%H:%M")
end
```

**Operator assignments with locals (`||=`, `&&=`, `+=`):**

Before a tag runs, LiveCable sets the locals it uses from earlier tags in the
same render, so operator assignments build on them:

```erb
<% count = 0 %>
<% count += 1 %>   <%# 1: count comes from the tag above %>
```

A name no earlier tag assigned starts as a fresh `nil` local, as in Ruby:
`<% items ||= [] %>` makes a local `items` equal to `[]`, and it hides a
reactive variable of the same name for the rest of the template.

**External state changes:**

If your method reads from the database or external sources, LiveCable can't track those dependencies. Use reactive variables for state that drives rendering, or declare a database query with [`reactive_query`](/guide/reactive-variables#query-backed-state) and `refresh` it after a write.

## Performance Tips

### 1. Prefer CSS Classes Over Conditional Wrapping

When you wrap content in large control statements, LiveCable cannot split it into smaller parts and must send the entire chunk. Instead, use CSS classes to show/hide content.

**Less efficient (entire chunk replaced):**
```erb
<% if tasks.present? %>
  <h1>You have <%= tasks.count %> remaining</h1>
  <div class="tabs tabs-boxed w-full mt-4">
    <a class="tab <%= filter == :all ? 'tab-active' : '' %>" live-action="filter_all">
      All
    </a>
    <a class="tab <%= filter == :active ? 'tab-active' : '' %>" live-action="filter_active">
      Active
    </a>
    <a class="tab <%= filter == :completed ? 'tab-active' : '' %>" live-action="filter_completed">
      Completed
    </a>
  </div>
<% end %>
```

**More efficient (only class updated):**
```erb
<div class="<%= 'hidden' unless tasks.present? %>">
  <h1>You have <%= tasks.count %> remaining</h1>
  <div class="tabs tabs-boxed w-full mt-4">
    <a class="tab <%= filter == :all ? 'tab-active' : '' %>" live-action="filter_all">
      All
    </a>
    <a class="tab <%= filter == :active ? 'tab-active' : '' %>" live-action="filter_active">
      Active
    </a>
    <a class="tab <%= filter == :completed ? 'tab-active' : '' %>" live-action="filter_completed">
      Completed
    </a>
  </div>
</div>
```

In the second example, when `tasks.present?` changes, only the wrapper div's `class` attribute is updated. The entire content block remains static and doesn't need to be re-sent. This is especially beneficial for large content blocks with many nested elements.

### 2. Hoist Unchanging Content

Put static content outside dynamic blocks when possible:

**Less efficient:**
```erb
<%= render_user_card(user) %>
```

**More efficient:**
```erb
<div class="user-card">
  <img src="<%= user.avatar_url %>">
  <h3><%= user.name %></h3>
  <p><%= user.bio %></p>
</div>
```

Now `avatar_url`, `name`, and `bio` can update independently.

### 3. Avoid Side Effects in Templates

```erb
<!-- BAD: Side effect in template -->
<% @view_count += 1 %>

<!-- GOOD: Side effects in lifecycle callbacks -->
```

Dependency tracking assumes templates are pure. Side effects can cause unexpected behavior.

## Debugging

### Inspecting Parts

You can see what parts are sent by watching the ActionCable messages in the browser's network tab (filter by WS or the cable URL). Each message contains a `_refresh` payload with an `h` (template hash) and `p` (parts) field, plus `s` (statics) the first time a control block's structure is used.

### Template Hashes

The `h` field in render results is a hash of the template path:

```json
{
  "h": "a1b2c3d4e5f6",  // First 12 chars of SHA256(template_path)
  "p": [...]
}
```

This helps debug template switching issues in compound components.

### Dependency Analysis

You can inspect method dependencies in the Rails console:

```ruby
Live::Profile.method_dependencies_analyzer.dependencies
# => {
#   full_name: {
#     methods: #<Set: {:first_name, :last_name}>,
#     reactive_vars: #<Set: {:first_name, :last_name}>
#   }
# }

Live::Profile.method_dependencies_analyzer.expanded_dependencies(:full_name)
# => #<Set: {:first_name, :last_name}>
```

## Limitations

### Herb Engine Required

`.live.erb` templates use the Herb gem (an HTML + ERB Parser).

### Static Analysis Limitations

Method dependency tracking uses static analysis, which has limitations:

- Can't track `method_missing` calls
- Can't track dynamic `send()` calls
- Can't track dependencies in lambdas/procs passed to other methods
- Only follows `def`s in the component's own file; methods from concerns or
  superclasses, `alias_method` and `delegate` aren't followed
- A component class with no source file, such as one built with `Class.new`,
  has no methods to analyse, so every part that calls one of its methods
  re-renders on every change

For these cases, manually trigger renders when needed.

## Summary

The partial rendering system is one of LiveCable's most powerful features:

✅ **Automatic** - Just use `.live.erb` templates
✅ **Smart** - Dependency tracking via static analysis
✅ **Fast** - Only changed parts sent over the wire
✅ **Efficient** - Child components no longer double-render

For maximum performance, always use `.live.erb` templates with LiveCable components!
