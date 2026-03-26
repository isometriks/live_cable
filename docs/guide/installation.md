# Installation

## Requirements

- Ruby on Rails 7.0+
- ActionCable configured and running
- Stimulus 3.0+

## Step 1: Add the Gem

Add LiveCable to your `Gemfile`:

```ruby
gem 'live_cable'
```

Then run:

```bash
bundle install
```

## Step 2: Configure ActionCable Connection

Update your `app/channels/application_cable/connection.rb` to initialize a `LiveCable::Connection`:

```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :live_connection

    def connect
      self.live_connection = LiveCable::Connection.new(self.request)
    end
  end
end
```

## Step 3: JavaScript Setup

LiveCable works with both **importmap-rails** (default for Rails 7+) and **JavaScript bundlers** (esbuild, Vite, webpack, Rollup via jsbundling-rails or vite_ruby).

### Using importmap-rails (default)

The gem automatically pins all necessary modules when you install it. No additional setup is needed — skip to "Register the LiveController" below.

### Using a JavaScript bundler (yarn/npm)

If your app uses jsbundling-rails, vite_ruby, or another bundler, install the npm package instead:

```bash
yarn add @isometriks/live_cable
# or
npm install @isometriks/live_cable
```

This will also install the required peer dependencies (`@rails/actioncable`, `@hotwired/stimulus`, and `morphdom`).

### Register the LiveController

Register the `LiveController` in your Stimulus application (`app/javascript/controllers/application.js`). The imports are the same regardless of whether you use importmap or a bundler:

```javascript
import { Application } from "@hotwired/stimulus"
import LiveController from "@isometriks/live_cable/controller"
import "@isometriks/live_cable" // Automatically starts DOM observer

const application = Application.start()
application.register("live", LiveController)
```

### Enable LiveCable Blessing (Optional)

If you want to call LiveCable actions from your own Stimulus controllers, add the LiveCable blessing:

```javascript
import { Application, Controller } from "@hotwired/stimulus"
import LiveController from "@isometriks/live_cable/controller"
import LiveCableBlessing from "@isometriks/live_cable/blessing"
import "@isometriks/live_cable" // Automatically starts DOM observer

// Enable the blessing for all controllers
Controller.blessings = [
  ...Controller.blessings,
  LiveCableBlessing
]

const application = Application.start()
application.register("live", LiveController)
```

This adds the `liveCableAction(action, params)` method to all your Stimulus controllers:

```javascript
// In your custom controller
export default class extends Controller {
  submit() {
    // Dispatch an action to the LiveCable component
    this.liveCableAction('save', {
      title: this.titleTarget.value
    })
  }
}
```

## Step 4: Create Your First Component

Create a component class at `app/live/counter.rb`:

```ruby
module Live
  class Counter < LiveCable::Component
    reactive :count, -> { 0 }

    actions :increment, :decrement

    def increment
      self.count += 1
    end

    def decrement
      self.count -= 1
    end
  end
end
```

Create a component view at `app/views/live/counter.html.live.erb`:

```erb
<div>
  <h2>Counter: <%= count %></h2>
  <button live-action="increment">+</button>
  <button live-action="decrement">-</button>
</div>
```

## Step 5: Use the Component

Add the component to any view:

```erb
<%= live('counter', id: 'my-counter', count: 0) %>
```

That's it! Your component is now live and reactive.

## Next Steps

- [Create your first component](/guide/components)
- [Learn about reactive variables](/guide/reactive-variables)
- [Handle user actions](/guide/actions-events)
