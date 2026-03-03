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
app/views/live/counter/component.html.erb
```

**After:**
```
app/views/live/counter/component.html.live.erb
```

That's it! LiveCable will automatically use the partial rendering system.

### How It Works

Let's look at a simple counter component:

```erb
<!-- app/views/live/counter/component.html.live.erb -->
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

### Method Dependencies

LiveCable also tracks method calls and expands them to their reactive variable dependencies:

```ruby
class Profile < LiveCable::Component
  reactive :first_name, -> { "John" }
  reactive :last_name, -> { "Doe" }

  def full_name
    "#{first_name} #{last_name}"
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

The `items` iteration depends on the `items` reactive variable, but the `item.name` part also depends on the local `item` variable. If `items` changes, all iteration parts re-render. If only internal item properties change, only those parts update.

## Code vs Expression Parts

LiveCable distinguishes between two types of dynamic parts:

### Code Parts (always execute)

Code parts define local variables or control flow that other parts need:

```erb
<% if show_details %>
  <%= user.email %>
<% end %>
```

The `if` condition is a code part that always executes because the `show_details` boolean determines if the inner parts should render.

### Expression Parts (can be skipped)

Expression parts output values and can be skipped if their dependencies haven't changed:

```erb
<%= count %>
```

If `count` hasn't changed, this part returns `nil` (skip) instead of rendering.

## Template Switching

For compound components with multiple templates, LiveCable handles template switches efficiently:

```ruby
class Wizard < LiveCable::Component
  compound

  reactive :step, -> { 1 }

  def template_state
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

One of the biggest improvements is how child components are handled.

### The Problem (Before)

Previously, when a parent component rendered:

1. Parent HTML sent to client
2. Child components rendered as full HTML inside parent
3. When child's Stimulus controller connected, it subscribed
4. Server re-rendered child and sent full HTML again ❌

This caused **double rendering** of every child component!

### The Solution (Now)

With `.live.erb` templates and `RenderResult`:

1. Parent HTML sent with **`<LiveCable>` placeholders** for children
2. Child render results included in parent's JSON payload
3. JavaScript replaces placeholders with child HTML from payload
4. When child's Stimulus controller connects, it **reuses** the ComponentState ✅

No more double renders!

### How It Works

**Parent template:**
```erb
<!-- app/views/live/parent/component.html.live.erb -->
<div>
  <h1>Parent</h1>
  <%= live(Live::Child, id: 1) %>
</div>
```

**Rendered to client:**
```json
{
  "h": "abc123",
  "p": ["<div>\n  <h1>Parent</h1>\n  ", null, "\n</div>"],
  "c": {
    "live/child/1": {
      "h": "def456",
      "p": ["<div>Child 1</div>"]
    }
  }
}
```

The JavaScript subscription manager:

1. Stores child's HTML in a `ComponentState` before subscription exists
2. When child controller connects, reuses the stored state
3. No redundant render needed!

### ComponentState Class

The `ComponentState` JavaScript class stores:

- `#partsByTemplate` - Parts for each template (for compound components)
- `#lastTemplate` - Which template was last used
- `#element` - The DOM element reference

When a component subscribes, it can reuse existing `ComponentState` if the element matches.

## Migration Guide

### Converting Existing Templates

1. Rename `.html.erb` to `.html.live.erb`
2. Test thoroughly - most templates work without changes
3. Watch for warnings in development:

```
[LiveCable Warning] live/counter/component was rendered without using a .live.erb template,
this will be less performant.
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

**External state changes:**

If your method reads from the database or external sources, LiveCable can't track those dependencies. Always use reactive variables for state that drives rendering.

## Performance Tips

### 1. Split Large Templates

Instead of one giant template:

```erb
<div>
  <header><%= header_content %></header>
  <main><%= main_content %></main>
  <footer><%= footer_content %></footer>
</div>
```

Use multiple smaller parts naturally:

```erb
<div>
  <header>
    <%= header_content %>
  </header>

  <main>
    <%= main_content %>
  </main>

  <footer>
    <%= footer_content %>
  </footer>
</div>
```

Each `<%= ... %>` becomes a separate part that can be skipped independently.

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

### 3. Use Methods for Expensive Computations

```ruby
def expensive_computation
  # This is only called when dependencies change
  some_reactive_var.map { |x| complex_transform(x) }
end
```

```erb
<%= expensive_computation %>
```

The method is only called when `some_reactive_var` changes, not on every render.

### 4. Avoid Side Effects in Templates

```erb
<!-- BAD: Side effect in template -->
<% @view_count += 1 %>

<!-- GOOD: Side effects in lifecycle callbacks -->
```

Dependency tracking assumes templates are pure. Side effects can cause unexpected behavior.

## Debugging

### Inspecting Parts

You can see what parts are sent in the browser console by enabling debug mode:

```javascript
// In browser console
DEBUG = true
```

Then watch the network tab for ActionCable messages.

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
Live::Counter.method_dependencies_analyzer.dependencies
# => {
#   :full_name => {
#     :methods => #<Set: {}>,
#     :reactive_vars => #<Set: {:first_name, :last_name}>
#   }
# }

Live::Counter.method_dependencies_analyzer.expanded_dependencies(:full_name)
# => #<Set: {:first_name, :last_name}>
```

## Limitations

### Herb Engine Required

`.live.erb` templates use the Herb gem (a Haml-like template engine). Most ERB features work, but some edge cases might behave differently.

### Static Analysis Limitations

Method dependency tracking uses static analysis, which has limitations:

- Can't track `method_missing` calls
- Can't track dynamic `send()` calls
- Can't track dependencies in lambdas/procs passed to other methods

For these cases, manually trigger renders when needed.

### No Partial Template Support Yet

Currently, `.live.erb` only works for component templates, not Rails partials (`_partial.html.erb`).

## Summary

The partial rendering system is one of LiveCable's most powerful features:

✅ **Automatic** - Just use `.live.erb` templates
✅ **Smart** - Dependency tracking via static analysis
✅ **Fast** - Only changed parts sent over the wire
✅ **Efficient** - Child components no longer double-render

For maximum performance, always use `.live.erb` templates with LiveCable components!
