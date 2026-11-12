# Collection Streams

A collection stream is a list whose rows the server doesn't keep. You add,
update and remove one row at a time, from an action or a `stream_from`
callback, and the page changes only that row. The list itself is never
re-rendered, re-sent or held in the server's memory between renders, so a
chat, an activity feed or a log costs the same per message whether it shows
fifty rows or five thousand.

## Streams or a Keyed Loop?

A `.live.erb` template already sends only the rows that changed when it loops
over a list with keys (see [Control Blocks](/guide/partial-rendering#control-blocks)),
and a [`reactive_query`](/api/component#reactive-query-name-scope-transform)
re-runs its query only when what it reads changes. Use those when the list is
bounded and fits in the server's memory, and when its rows should re-render
whenever the component's state changes: a cart, a todo list, a filtered table.

Use a stream when:

- the list is unbounded or grows one way, such as messages, notifications or
  log lines;
- holding the list for every viewer would cost too much memory;
- rows arrive one at a time from broadcasts, and should never cause the list
  to be queried again.

What you give up: rows render once, when they're inserted or updated, so they
can read only their own row and the component, and they don't re-render when
the component's state changes. Use `stream_update` for one row and
`stream_reset` for all of them.

## A First Stream

```ruby
# app/live/chat.rb
module Live
  class Chat < LiveCable::Component
    reactive :room_id
    reactive :expanded, -> { true }

    stream :messages, ->(chat) { Message.where(room_id: chat.room_id).order(:id).last(50) }

    actions :toggle

    after_connect do
      stream_from("chat_room_#{room_id}", coder: ActiveSupport::JSON) { |payload| receive(payload) }
    end

    def toggle
      self.expanded = !expanded
    end

    private

    def receive(payload)
      return stream_delete(:messages, "messages_message_#{payload['id']}") if payload['event'] == 'deleted'

      message = Message.find_by(id: payload['id']) or return
      payload['event'] == 'created' ? stream_insert(:messages, message) : stream_update(:messages, message)
    end
  end
end
```

```erb
<%# app/views/live/chat.html.live.erb %>
<div class="chat">
  <% if expanded %>
    <ul class="messages" live-stream="messages">
      <%= live_stream_for :messages do |message| %>
        <li class="message"><strong><%= message.author_name %></strong> <%= message.body %></li>
      <% end %>
    </ul>
  <% else %>
    <button live-action="toggle">Show chat</button>
  <% end %>
</div>
```

The page load renders the last fifty messages from the stream's lambda. Each
broadcast then sends the page one row op, about 130 bytes, which the page
applies to the `<ul>` directly: the rest of the component isn't rebuilt or
morphed. `<li>` gets `id="messages_message_42"` without you writing it.

## Declaring a Stream

```ruby
stream :messages, ->(chat) { Message.where(room_id: chat.room_id).order(:id).last(50) },
       dom_id: ->(message) { dom_id(message, :messages) },   # the default
       limit: nil                                            # no limit, the default
```

- **The lambda** returns the rows of a full render: the page load, the first
  render over the socket, a render after `stream_reset`, and a render that
  shows the stream again after hiding it. A lambda that takes an argument is
  given the component. Its result goes through `to_a` and isn't kept, so bound
  the query yourself. Leave it out for a stream that starts empty.
- **`dom_id:`** returns a row's key, which is also its element's `id`. It runs
  on the component, where `dom_id` and `dom_class` are available. The default,
  `dom_id(row, name)`, gives `messages_message_42`. It needs a model with an
  id, so declare `dom_id:` for a Hash, a `Data` or an unsaved record. A key
  must be a String with no whitespace. A Hash decoded from a broadcast has
  String keys and one built in Ruby usually has Symbols: `"message-#{m['id']}"`
  gives every Symbol-keyed row the same key, so each replaces the last.
- **`limit:`** is the most rows the page keeps (see [Limits](#limits)).

The lambda doesn't track what it reads: changing `room_id` doesn't refill the
stream. Call `stream_reset` where what the lambda reads changes, as a
[room switch](#switching-rooms) does.

The stream's name can't also be a reactive variable, a shared variable, a
`reactive_query` or a method. Its reader, `messages`, raises: a stream holds no
rows to read, count or enumerate. The full list of arguments is in the
[Component API](/api/component#stream-name-initial-nil-dom-id-nil-limit-nil).

## The Template

```erb
<ul class="messages <%= density %>" live-stream="messages">
  <%= live_stream_for :messages do |message| %>
    <li class="message"><%= message.body %></li>
  <% end %>
</ul>
```

`live_stream_for` is compiled into the template, so the compiler checks its
rules and names the file, the line and the fix when one is broken:

- **The call** is an output tag (`<%=`), with the stream's name as a Symbol and
  a `do` block taking one parameter, the row.
- **The container** is the element the call sits directly in. It carries a
  static `live-stream` attribute equal to the stream's name and holds nothing
  but the call, whitespace and ERB comments. Its other attributes, `id`
  included, may be dynamic. An element with `live-stream` and no call is an
  error too.
- **Not every element can be a container.** Use a `<tbody>`, not a `<table>`,
  because the browser moves rows out of a table; a `<div>`, not a `<p>`; and
  nothing inside `<svg>` or `<math>`. Write one open tag for the container, with
  a dynamic class if it must differ, rather than
  `<% if a %><ul …><% else %><ul …><% end %>`.
- **One call per stream per template**, counting the live partials it renders.
  A compound component's variants are separate templates, and each may render
  the stream once.
- **The row renders exactly one element.** Whitespace, ERB comments and
  non-output `<% %>` tags may sit around it. The element may come from a
  [live partial](/guide/partial-rendering#live-partials):
  `<%= render 'live/chat/message', message: %>` naming
  `_message.html.live.erb`, whose content is one element. A plain `.html.erb`
  partial, a helper call or bare text as the whole row is an error: write the
  row's root element in the template and render the partial inside it, or make
  the partial a live partial.

### Row Ids

The row element's `id` is its key. Leave `id` off and LiveCable adds
`id="<key>"` as the element's first attribute, which the page fills in from
the key the row is sent with, so the key travels once. If you write one, it
must read only the row, and outside production
[`verify_stream_items`](/api/configuration#verify-stream-items) checks that
each row renders its key there:

```erb
<%# With stream :messages, dom_id: ->(message) { dom_id(message) } %>
<li id="<%= dom_id(message) %>" class="message"><%= message.body %></li>
```

A static `id`, which every row would share, is a compile error, and so is an
`id` that reads anything other than the row.

### Whitespace and Empty States

The whitespace around a row's element is dropped when the template compiles,
so a row is exactly its element. The whitespace between the container's tags
and the call is kept, so `:empty` never matches the container. Style an empty
state with `:has(> *)` instead:

```css
.messages:has(> *) + .empty-state { display: none; }
```

## Where a Stream Can Go

A stream's position in the page is fixed when the template compiles, so it
must sit where the compiler can see its path:

| Placement | |
|---|---|
| The template's top level, inside the root element | Yes |
| Inside `if`, `unless`, `elsif`, `else`, `case`, `when` or `in`, at any depth | Yes. Hiding and showing follow the branch |
| Inside a live partial rendered with a literal path | Yes |
| Inside a loop (`each`, `times`, `for`, `while`), including another stream's row | No: a stream has one container |
| Inside a block helper (`form_with`, `tag.section do`, `content_tag … do`, `turbo_frame_tag do`, `link_to … do`), `content_for`, `capture` or `cache` | No: block helpers render to one HTML string. Use a plain element, `<form live-form="…">` instead of `form_with`, or `<section class="…">` instead of `tag.section do` |
| Inside `begin`/`rescue` | No. Rescue in a component method |
| In a block that uses `next`, `break`, `return`, `redo`, `retry` or `throw`, in the block or the row | No. Remove them |
| In a conditional used as a value (`x = if …`) | No. Write the conditional as its own tag |
| In a block that opens the template, before any other output | No. Put the template's content in a root element |
| In a plain `.html.erb` partial, a helper or an `.html.erb` component | No: `live_stream_for` raises there |
| With `config.structured_blocks = false` | No: streams need structured blocks |

A component that declares a stream needs a `.live.erb` template: one with an
`.html.erb` template raises when it renders. Outside production, a component
whose template doesn't render a stream it declares raises at its first render.
Compound components are exempt, since a variant may leave a stream out.

## What a Row Can Read

A row renders on its own, when its op is sent, without the rest of the
template running. So a row may read:

- its parameter, and locals it assigns itself;
- the component's methods and reactive variables;
- view helpers, as the rest of the template does.

It may not read the template's locals: those assigned by earlier tags, by the
tag around the stream, or a live partial's locals. Each would silently be
something else when the row renders alone, so the compiler rejects them:

```
app/views/live/chat.html.live.erb:4: the row of stream :messages reads `label`, a template local.
Rows render on their own when ops arrive, so they can read only `message` and the component: use a
component method, or compute it from `message`
```

A row also can't render a live component, with `live(...)` or
`render(SomeComponent.new(...))`, because nothing would own it once the row
had rendered. Render the component outside the stream. Nor can it call
`content_for` or `provide`, or read instance variables. A helper that reaches
`live` from a row raises when the row renders.

Everything else a template can hold works in a row: `if` and `case`, loops,
block helpers such as `link_to … do`, plain partials, other objects that
respond to `render_in` (ViewComponent or Phlex components), `t('.key')`
(scoped to the template or live partial the row is written in), `live-action`
buttons and forms.

Two consequences of rows rendering on their own:

- **A reactive variable read in a row doesn't re-render the rows already
  shown.** Reading `density` in a row renders new rows with the current value;
  call `stream_reset` to render them all again.
- **Rows don't know about each other.** `cycle`, counters and grouping across
  rows don't work. Use CSS (`:nth-child`), or compute what you need from the
  row.

## Changing a Stream

| Method | What the page does |
|---|---|
| `stream_insert(:messages, message)` | Appends the row. A row whose key the page shows is replaced where it is |
| `stream_insert(:messages, message, at: :start)` | Prepends the row, with the same rule |
| `stream_update(:messages, message)` | Replaces the row where it is. A page that doesn't show its key ignores it |
| `stream_delete(:messages, message)` | Removes the row. A String is taken as the key. A page that doesn't show it ignores it |
| `stream_reset(:messages)` | Drops what was queued so far, and refills the stream from its lambda |

Each call queues an op for the next render that reaches the page. The key is
computed at once, so a bad `dom_id:` raises in your action, where `rescue_from`
sees it; the row's markup is rendered when the op is sent, from the row as it
is then. Ops apply in the order they were queued, and for one key the last one
wins. Ops queued after a `stream_reset` are applied to the refilled rows, all
in one frame.

Inserting a row the page already shows replaces it in place instead of moving
it, and updating or deleting one it doesn't show does nothing. So a duplicate
or late broadcast is harmless: the sender's own insert followed by its
broadcast of the same message shows it once.

Call them where LiveCable holds the connection's lock: actions, `stream_from`
callbacks, `before_connect`, `after_connect`. A call changes the stream of the
component you call it on, and another component on the same connection can be
changed too: its ops go out in its own frame, in the same update. Each raises
`LiveCable::Error`, with the fix in the message:

- with no live connection: on the page load, where the stream's rows come from
  its lambda, and after the component disconnects;
- while rendering, in a template, a helper or a render callback;
- on a thread that doesn't hold the lock;
- for a stream the component doesn't declare.

### From a Thread of Your Own

`live_update` takes the connection's lock, runs the block and sends what it
changed, as the end of an action does:

```ruby
after_connect do
  Thread.new do
    Rails.application.executor.wrap do
      Import.each_entry { |entry| live_update { stream_insert(:log, entry) } }
    rescue LiveCable::Error
      # the component disconnected
    end
  end
end
```

Inside an action or a callback it only runs the block, and its changes go out
with the rest of that update. See [`live_update`](/api/component#live-update).

## Limits

`limit: 200` keeps at most 200 rows on the page. An insert at the end that adds
a row trims rows from the start, and an insert at the start trims from the
end. Replacing a row in place never trims, and a full render whose lambda
returns more rows keeps the last 200. The page applies the limit, so the
server keeps nothing for it.

It suits feeds that grow one way: logs, tickers, notifications. **Don't combine
it with paging the other way.** In a chat with "load older", prepending a page
would trim the newest messages, and the next append would trim the page just
loaded. A row the limit trimmed ignores later updates, and inserting its key
again adds it as a new row, at the end the insert names.

## Hiding and Showing

When the stream's branch is hidden, by `<% if expanded %>` turning false or a
compound component switching to a variant without the stream, its container
leaves the page with its rows. While it's hidden, its ops cause no render and
are dropped at the end of each update. Showing it again renders it in full
from its lambda.

An action may show a stream and fill it in one go, since ops queued in the
update that shows it are applied to the refilled rows:

```ruby
def search(params)
  self.query = params[:q]
  stream_reset :results
  hits.each { |hit| stream_insert :results, hit }
end
```

Rows that must survive hiding and showing must come from the lambda.

Hiding with CSS (a class or the `hidden` attribute set from a reactive
variable) keeps the stream on the page and its ops flowing, at no extra cost.

## Recipes

### Broadcasting from the Model

Have the model broadcast an event and an id after it commits, and look the
record up in the callback:

```ruby
class Message < ApplicationRecord
  after_create_commit { broadcast_chat('created') }
  after_update_commit { broadcast_chat('updated') }
  after_destroy_commit { broadcast_chat('deleted') }

  private

  def broadcast_chat(event)
    ActionCable.server.broadcast("chat_room_#{room_id}", { event:, id: })
  end
end
```

- Pass `coder: ActiveSupport::JSON` to `stream_from`. Without it, the callback
  gets the raw JSON String, and with it a Hash with String keys:
  `payload['id']`, not `payload[:id]`.
- Use `find_by`, not `find`: a message can be destroyed before a viewer's
  callback runs.
- Delete by key, since the record is gone: `stream_delete(:messages,
  "messages_message_#{payload['id']}")`.

### Switching Rooms

Stop the old room's broadcasts, start the new room's, and refill:

```ruby
def switch_room(params)
  stop_stream_from("chat_room_#{room_id}")
  self.room_id = params[:room_id].to_i
  stream_from("chat_room_#{room_id}", coder: ActiveSupport::JSON) { |payload| receive(payload) }
  stream_reset :messages
end
```

### Loading Older Messages

Keep a cursor in a reactive variable that the lambda reads, so that a full
render (a reveal, a reset) shows the pages already loaded, and prepend each
older page newest first, since prepending one row at a time reverses the
order:

```ruby
PAGE = 50

reactive :room_id
reactive :oldest_id
reactive :has_older, -> { true }

stream :messages, ->(chat) { chat.window }

actions :load_older

def window
  scope = Message.where(room_id:).order(:id)
  oldest_id ? scope.where(id: oldest_id..) : scope.last(PAGE)
end

def load_older(_params)
  self.oldest_id ||= window.first&.id
  return unless oldest_id

  page = Message.where(room_id:, id: ...oldest_id).order(id: :desc).limit(PAGE).to_a
  page.each { |message| stream_insert :messages, message, at: :start }
  self.oldest_id = page.last.id if page.any?
  self.has_older = page.size == PAGE
end
```

Don't give such a stream a `limit:`. Its window starts again from the last
page when the socket reconnects, because a reconnect builds the component
again.

## Ordering and Delivery

- On one connection, frames reach the page in the order the server sends them,
  and a frame's ops apply in the order they were queued. Every full render
  restores the lambda's order.
- There is no ordering across broadcasts: ActionCable runs each as a separate
  job, so two messages committed close together can arrive in either order.
  Sort in the lambda, and a full render puts them right.
- Duplicate deliveries are harmless, as an insert of a key the page holds
  replaces that row.
- **The subscribe window.** A broadcast sent after the lambda's query but
  before the `stream_from` subscription is live is in neither the rows nor an
  op. It is missing until the next full render.

## Page Loads, Reconnects and Turbo

- **Two queries per page load.** The page load renders the stream from its
  lambda, and so does the first render over the socket, on a new instance of
  the component. The second render's rows are morphed onto the first by id, so
  the elements are kept.
- **Reconnects** build the component again and render the stream in full: rows
  missed while the socket was down appear, deleted ones go, and the window
  starts again from the lambda.
- **Turbo Drive.** A component on both pages keeps its subscription, and the
  page shows its rows as the client holds them, including any that arrived
  during the visit.
- **`live-ignore`.** A stream inside a `live-ignore` element is never updated.
  The same goes for a [Turbo Frame inside a component](/api/helpers#live-ignore),
  which you should `live-ignore`.
- Rows are in the client's copy of the component's render, so a morph of the
  whole component, for a change elsewhere in it, renders them as they are.

## Loading States and Focus

Rows are patched with the same rules as a morph of the whole component:

- a button in a row that is awaiting its reply keeps its `live-loading` or
  `live-disable-with` state when the row is updated, and catches up once the
  reply arrives;
- a focused field in a row keeps what was typed unless the server changed its
  value;
- `live-ignore` elements inside a row are left alone.

Inserting and deleting rows doesn't move focus, but deleting the row that has
it drops it. If that matters, move focus first, from a handler for an event
you send with [`dispatch_event`](/guide/server-events).

## Building a Chat

A few things make a stream read well as a chat:

```erb
<ol class="messages" live-stream="messages" role="log" aria-live="polite">
  <%= live_stream_for :messages do |message| %>
    <li class="message"><%= message.body %></li>
  <% end %>
</ol>
```

- `role="log"` and `aria-live="polite"` announce new messages to screen
  readers. Set `aria-busy` on the container from a reactive variable while a
  page of older messages loads.
- `overflow-anchor: auto` on the scrolling element keeps the reader's place
  when rows are prepended above it.
- To stick to the bottom, send an event with the insert and scroll in its
  handler. Events are dispatched after the frame's rows are on the page:

```ruby
stream_insert :messages, message
dispatch_event 'chat:message-received'
```

```js
document.addEventListener('chat:message-received', () => {
  const list = document.querySelector('.messages')
  list.scrollTop = list.scrollHeight
})
```

- Put things that change often, such as a typing indicator, in a child
  component. A frame that changes anything besides rows rebuilds and morphs
  the whole component, rows included, which costs more the longer the list.

## Child Components

A component rendered inline by a parent can have streams of its own. Its ops
ride in the parent's frame when the parent renders it, and otherwise go out in
its own frame once it has subscribed. Until it subscribes they wait; past
1,000 ops the stream is refilled from its lambda instead, with a warning in the
log. A parent and a child may both have a stream called `messages`: each
container belongs to its own component.

## Errors

An exception in the lambda or in a row is a render error: the component is
replaced with the error message, and its queued ops are dropped. An exception
in an action or a callback goes to `rescue_from` first; if a handler handles
it, the ops queued before the raise are still sent. A `before_render` that
throws `:abort` keeps the ops, and the next render refills the stream and
applies them; past 1,000 ops it drops them, since the refill shows them
anyway.

## Testing

`LiveCable::Testing` reads a stream as the page holds it, with `stream_ids`,
and the ops sent for it, with `stream_ops`:

```ruby
chat = live_mount('chat', room_id: 1)
expect(chat.stream_ids(:messages)).to eq(%w[messages_message_1 messages_message_2])

chat.clear_broadcasts
chat.receive_stream('chat_room_1', { 'event' => 'created', 'id' => 3 })

expect(chat.stream_ops(:messages).map(&:first)).to eq(%w[a])
expect(chat.rendered).to have_css('li#messages_message_3')
```

See [Collection Streams](/guide/testing#collection-streams) in the testing
guide.

## Migrating from a Reactive Array

A list in a reactive variable that broadcasts append to:

```ruby
reactive :messages, ->(chat) { Message.where(room_id: chat.room_id).last(50) }

stream_from("chat_room_#{room_id}", coder: ActiveSupport::JSON) do |payload|
  messages << Message.find(payload['id'])
end
```

```erb
<ul>
  <% messages.each do |message| %>
    <li id="<%= dom_id(message) %>"><%= message.body %></li>
  <% end %>
</ul>
```

becomes a stream:

```ruby
stream :messages, ->(chat) { Message.where(room_id: chat.room_id).last(50) }

stream_from("chat_room_#{room_id}", coder: ActiveSupport::JSON) do |payload|
  message = Message.find_by(id: payload['id'])
  stream_insert(:messages, message) if message
end
```

```erb
<ul live-stream="messages">
  <%= live_stream_for :messages do |message| %>
    <li><%= message.body %></li>
  <% end %>
</ul>
```

- Code that read the list (`messages.size`, `messages.last`) needs its own
  state or a query: the stream has no rows to read.
- Template locals the rows read become component methods or are computed from
  the row.
- Ids change from `dom_id(message)` to `dom_id(message, :messages)` unless you
  declare `dom_id:`; update CSS and JavaScript that select rows by id.

## Upgrading

Upgrade the gem and the npm package together. A page whose JavaScript is
older than 0.8, such as a tab left open across the deploy, shows "This page is
out of date. Reload to continue." in place of a component that declares
streams, since it would misapply the stream's ops. Components without streams
aren't affected.

## Next Steps

- [Broadcasts with `stream_from`](/guide/streaming)
- [Partial Rendering](/guide/partial-rendering)
- [Component API](/api/component)
- [Testing](/guide/testing#collection-streams)
