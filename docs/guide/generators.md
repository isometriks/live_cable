# Generators

LiveCable provides a Rails generator to quickly scaffold new components.

## Usage

```bash
bin/rails generate live_cable:component NAME [options]
```

This creates:
- A component class in `app/live/`
- A view template in `app/views/live/`

## Basic Component

```bash
bin/rails generate live_cable:component counter
```

Generates:

**`app/live/counter.rb`**:
```ruby
module Live
  class Counter < LiveCable::Component
  end
end
```

**`app/views/live/counter.html.live.erb`**:
```erb
<div>
</div>
```

## Options

### `--reactive`

Define reactive variables with optional types. Supported types: `integer`, `string`, `boolean`, `array`, `hash`. Unrecognized or omitted types default to `nil`.

```bash
bin/rails generate live_cable:component counter --reactive count:integer name:string active:boolean items:array data:hash other
```

Generates:

```ruby
module Live
  class Counter < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :name, -> { "" }
    reactive :active, -> { false }
    reactive :items, -> { [] }
    reactive :data, -> { {} }
    reactive :other, -> { nil }
  end
end
```

### `--actions`

Define action methods with stubs:

```bash
bin/rails generate live_cable:component counter --actions increment decrement
```

Generates:

```ruby
module Live
  class Counter < LiveCable::Component
    actions :increment, :decrement

    def increment
    end

    def decrement
    end
  end
end
```

### `--compound`

Generate a [compound component](/guide/compound-components) with a directory-based template structure:

```bash
bin/rails generate live_cable:component wizard --compound
```

This creates the view at `app/views/live/wizard/component.html.live.erb` instead of `app/views/live/wizard.html.live.erb`, and adds the `compound` declaration to the component class.

## Combining Options

Options can be combined to scaffold a full component in one command:

```bash
bin/rails generate live_cable:component counter --reactive count:integer step:integer --actions increment decrement reset --compound
```

Generates:

```ruby
module Live
  class Counter < LiveCable::Component
    compound
    reactive :count, -> { 0 }
    reactive :step, -> { 0 }

    actions :increment, :decrement, :reset

    def increment
    end

    def decrement
    end

    def reset
    end
  end
end
```

## Namespaced Components

Use a slash-separated name to generate namespaced components:

```bash
bin/rails generate live_cable:component chat/message --reactive body:string
```

Generates:

**`app/live/chat/message.rb`**:
```ruby
module Live
  module Chat
    class Message < LiveCable::Component
      reactive :body, -> { "" }
    end
  end
end
```

**`app/views/live/chat/message.html.live.erb`**:
```erb
<div>
</div>
```
