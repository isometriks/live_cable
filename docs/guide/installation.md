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

### Register the LiveController

Register the `LiveController` in your Stimulus application (`app/javascript/controllers/application.js`):

```javascript
import { Application } from "@hotwired/stimulus"
import LiveController from "live_cable_controller"

const application = Application.start()
application.register("live", LiveController)
```

### Enable LiveCable Blessing (Optional)

If you want to call LiveCable actions from your own Stimulus controllers, add the LiveCable blessing:

```javascript
import { Application, Controller } from "@hotwired/stimulus"
import LiveController from "live_cable_controller"
import LiveCableBlessing from "live_cable_blessing"

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

Generate a component using the generator:

```bash
bin/rails generate live_cable:component Counter count:integer
```

This creates:
- `app/live/counter.rb` - The component class
- `app/views/live/counter.html.erb` - The component view

## Step 5: Use the Component

Add the component to any view:

```erb
<%= live 'counter', id: 'my-counter', count: 0 %>
```

That's it! Your component is now live and reactive.

## Next Steps

- [Create your first component](/guide/components)
- [Learn about reactive variables](/guide/reactive-variables)
- [Handle user actions](/guide/actions-events)
