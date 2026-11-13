# Changelog

All notable changes to this project are documented in this file.

The Ruby gem (`live_cable`) and the npm package (`@isometriks/live_cable`) are
released together and share a single version number. Entries below note which
side of the pair a change affects when it isn't both.

## 0.8.0 - 2026-11-12

### Upgrading from 0.7

Upgrade the gem and the npm package together: collection streams rely on row
op rules the 0.7 client doesn't follow, and a component that declares one
turns a 0.7 page away.

- The `live-stream` attribute and `live_stream_for` now belong to collection
  streams. A `.live.erb` template with an element carrying `live-stream` that
  isn't a stream's container, or that calls `stream(:name).each` (or any
  method on `stream(:name)`), now fails to compile with a message naming the
  fix: rename the attribute or the method. `live_stream_for` called from a
  `.html.erb` view raises. (gem)
- A page whose JavaScript is older than 0.8, such as a tab left open across
  the deploy, now shows "This page is out of date. Reload to continue." in
  place of a component that declares collection streams, because it would
  misapply the stream's row ops. The 0.8 client sends a protocol version when
  it subscribes; components without streams don't check it.

### Added

- **Components can stream a collection: add, update and remove single rows
  without re-rendering, re-sending or keeping the list on the server.**
  `stream :messages, ->(chat) { ... }` declares one, with `dom_id:` for a
  row's key and `limit:` for the most rows the page keeps, and a template
  renders it with `<%= live_stream_for :messages do |message| %>` inside an
  element with `live-stream="messages"`. `stream_insert` (at the end or the
  start), `stream_update`, `stream_delete` and `stream_reset` queue changes
  for the next render that reaches the page. They raise, naming the fix, on
  the prerender, after a disconnect, while rendering and outside the
  connection's lock. `live_update { ... }` runs a block under that lock and
  sends what it changed, for code on threads of your own. A render that only
  carries row ops runs none of the template's code, and the server keeps no
  rows between renders. On the page, such a frame changes only the rows it
  names, in the stream's container, without rebuilding or morphing the
  component, and `limit:` trims the rows the page keeps. A frame that changes
  other markup too morphs the rest of the component around the container and
  still touches only the rows it names. Outside production,
  `config.verify_stream_items` raises for a declared stream the template
  doesn't render and for a row whose own `id` isn't its key. See
  [Collection Streams](https://livecable.io/guide/collection-streams).
- **`LiveCable::Testing` can read a collection stream as the page holds it.**
  `stream_ids(:messages)` returns the keys of its rows in order, and
  `stream_ops(:messages)` the row ops sent since the last `clear_broadcasts`.
  See the testing guide's
  [Collection Streams](https://livecable.io/guide/testing#collection-streams).
  (gem)

### Fixed

- **A `reactive` or `shared` default written as `lambda(&:method)`, or as a
  lambda with a splat, raised instead of being given the component.** Only a
  lambda with a positive arity was passed the component, and these have a
  negative one. Any lambda with parameters is now given it, as the guide
  says. RuboCop's `Style/SymbolProc` rewrites `->(c) { c.method }` to the
  first form. (gem)
- **Reading a connection identifier such as `current_user` on the page load
  raised a bare NameError that didn't say why.** The prerendered component
  has no ActionCable connection to read it from. It now raises a
  `LiveCable::Error` that says so and points to `subscribed?`, and the
  lifecycle and collection streams guides show how to read the value on the
  page load. (gem)
- **A frame that inserted a row into a keyed loop and also changed other
  markup took focus from a field in another row.** Typing into a row's field
  while such a frame arrived, a new row at the top of the list and a changed
  count say, left focus on the page's body. The morph of the whole component
  moves the rows it keeps past the new one, and moving an element blurs what
  it holds; only a frame of row ops alone put focus back. The client now
  restores focus and the selection after the morph too. (npm)
- **A component's render rebuilt and morphed every child it renders inline,
  however little had changed.** For each child placeholder the client built
  the child's whole HTML from what it last rendered and morphed it, so a
  render cost more the more its children held. A child the render sends
  nothing for, whose element shows its last render, is now left out of the
  morph. So a change a script made inside such a child stays until the child
  renders again, where the parent's render used to undo it. (npm)
- **A component kept its inline children's last rendered HTML in memory until
  it rendered again.** The render context a component keeps between renders
  held every child result its last render sent. It now lets them go once they
  are in the frame. (gem)

## 0.7.0 - 2026-11-12

### Upgrading from 0.6

Upgrade the gem and the npm package together.

- A `.live.erb` partial rendered from a component template with a literal path
  is now compiled into the template instead of raising. Rendered any other
  way, from a path in a variable or from a `.html.erb` view, it still raises,
  with a message that says how to render it; the `LiveCable::Error` now
  arrives wrapped in an `ActionView::Template::Error`, so rescue that and read
  its `cause`. If a component template renders a partial that exists as both
  `_name.html.erb` and `_name.html.live.erb`, which used to render the
  `.html.erb` one, the template now fails to compile: rename or remove one of
  them.
- A reactive write in `after_render` now renders on the connection's next
  update (any action or `stream_from` callback on any of its components)
  instead of being dropped by the next message. An unconditional write there
  re-renders the component on every update; derive state in `before_render`
  instead. Marks made before a component's first render (defaults,
  `after_connect`) are consumed by that render. A shared variable first
  written during a cycle's renders, as in `before_render`, settles in that
  cycle only when every component sharing it rendered; otherwise all its
  sharers render it again on the next update. A shared variable written again
  while it is still pending in the same cycle does not re-render sharers that
  rendered earlier in that cycle. A component whose `before_render` throws
  `:abort` keeps its changes pending, so its render callbacks run again on
  each update until a render goes through.
- An inline child whose `after_connect` writes reactive state now renders
  again when it subscribes, where 0.6 dropped the write, so an unconditional
  write there costs one extra render per child on every page load; set state
  that doesn't need the connection in `before_render`, or write only when the
  value changes.
- In `LiveCable::Testing`, a child that a parent rendered inline is no longer
  rendered on its own until it subscribes. A spec that expected such a child
  to render, or that connected one by hand with
  `child.connect(TestChannel.new)`, should call
  `parent.subscribe_child(live_id)`. That sends the child's `_status` frame,
  or its render if anything changed for it since its parent rendered it: call
  `clear_broadcasts` on the child before asserting on what a later action
  sends.

### Added

- **Live partials: a component template can be split into
  `_name.html.live.erb` partials that read the component's state.** A plain
  partial only sees its locals, so splitting a template meant passing every
  reactive value in by hand, and passing `component:` instead left the partial
  stale because reads through it aren't tracked. A `.live.erb` partial
  rendered with a literal path (`render 'live/chat/badge', label:`, or
  `partial:` with `locals:`, `object:`, `as:` or `collection:`) is now copied
  into the template when it compiles. It reads component state by name, its
  reads are tracked like the template's own, and inside a control block its
  markup diffs like markup written there, so a change sends only the values
  that changed. A collection renders as a loop, keyed by the partial's `id` or
  `live-key`. Locals are declared with Rails' strict-locals comment,
  `t('.key')` uses the partial's path, and anything that can't be copied
  faithfully is an error when the template compiles, naming the file, the line
  and the fix. See
  [Live Partials](https://livecable.io/guide/partial-rendering#live-partials).
- `TestComponent#subscribe_child(live_id)` in `LiveCable::Testing` subscribes
  a child a component rendered inline, as its controller does in the browser.
  `live_mount` now connects and first renders under the connection lock, as
  production does, and `unmount` disconnects under it (gem).

### Fixed

- **A reactive write in `after_render` or `after_connect`, an inline child's
  defaults, or a shared default from a component that mounted later could be
  lost before anything sent them.** Changesets were reset when the next client
  message or `stream_from` callback started, whether or not anything had
  rendered them. So a sharer that rendered before a later mount kept the old
  shared value, and an action that raised after writing its component's own
  reactive state sent a `_refresh` after its `_error`. Now a render consumes
  the names that were pending in its own component when it started. A sharer
  that didn't render keeps the shared names in its own changeset and picks
  them up on the connection's next update. A shared name that sharers derive
  in `before_render` is settled in the cycle that wrote it once every sharer
  has rendered it. An error clears the failing component's own changeset, so
  only the `_error` goes out for its own writes; a shared write before the
  error still renders every sharer, the failing one included (gem).
- **Changes for a child component that hadn't subscribed yet were rendered
  into a frame nobody received, and never reached the page.**
  `broadcast_changeset` now skips components without a subscription, and they
  keep their changes. A child that subscribes after its parent rendered it
  gets its render when something changed for it since, and only its status
  otherwise. A component whose subscribe render a `before_render` halts now
  gets its status too, so the client settles and flushes queued events; it got
  nothing before (gem).
- **In `LiveCable::Testing`, a parent's `rendered` left out updates its inline
  children sent on their own channels.** It replayed only the parent's own
  frames, so a subscribed child appeared as the parent last rendered it. The
  harness now keeps one render state per live id on each connection, as the
  client does, and every channel applies its frames to it (gem).
- **When a loading state ended, a `live-disable-with` element went back to the
  label and disabled state it had when the message went out, over anything the
  server had rendered into it meanwhile.** A render that reached a pending
  element, such as a parent's render carrying the child's, was reverted: "Like
  (4)" went back to "Like (3)". Each element `live-disable-with` disables now
  carries a `live-disabled` marker, which a render from the server drops, and
  the restore leaves an element without it as the server rendered it (npm).

## 0.6.0 - 2026-11-12

### Upgrading from 0.5

Upgrade the gem and the npm package together. A control block in a `.live.erb`
template now arrives as a structure rather than an HTML string, and a 0.5
client cannot render one. To deploy the gem ahead of the client, set
`config.structured_blocks = false` until both are out. The client gains
`@isometriks/live_cable/tree` and `@isometriks/live_cable/rows` modules, which
the gem's importmap pins and `package.json` exports; an app that pins
LiveCable's modules by hand must pin them too.

Inside a control block, a non-output tag that writes to the buffer itself
(`<% concat 'x' %>`, `<% safe_concat ... %>`) no longer adds to the page: its
output is dropped and LiveCable logs a warning. Use an output tag instead.

A control block that re-runs but renders the same values is no longer sent.
If nothing else in the template changed, the action is answered with an
`_ack`, so a test that expected a `_refresh` should expect
`broadcasts(:_ack)`. A test that reads a `_refresh`'s parts itself, as
`broadcasts(:_refresh).last[:_refresh][:p]`, finds a Hash where a control
block used to be an HTML string, and later renders send diffs of it; read
`rendered` or `rendered_html` instead.

- Every component now has a public `refresh(*names)`, for reactive queries.
  A bare `refresh` in a template calls it ahead of a view helper of that
  name, and `actions :refresh` with no `refresh` method of the component's
  own calls it with the action's params, which raises `Invalid reactive
  query`. Rename the helper or the action, or define `refresh` on the
  component.
- Upgrade the npm package with the gem to get a rebuilt component's children
  built again with it; the fix waited for 0.6 rather than 0.5.1 because it
  needs both. A 0.6 gem with a 0.5 client still fixes the Turbo Drive case,
  but after a Turbo Frame navigation or Turbo Stream replace that rebuilds a
  parent, its children answer every action with a destroy and stop
  responding until the page reloads, with or without
  `config.structured_blocks = false`.
- Disconnecting a component, when the client unsubscribes it or through
  `LiveCable::Testing`'s `unmount`, now disconnects the children it renders
  too, running their `disconnect` callbacks.
- A child given an Array or Hash with `live(...)` now re-renders when its
  parent changes that value, or a record inside it, in place and renders the
  `live(...)` call again. If you worked around the stale child with `dirty` or
  by passing a revision counter, you can drop the workaround. A record counts
  as changed when it is written through an attribute writer, `update` or the
  like. An in-place change to a serialized or JSON attribute shows only once
  the record is saved.
- A `live-value-*` param reaches the action exactly as the template wrote it.
  On 0.5 the browser JSON-parsed it first, so `"1.50"` arrived as `"1.5"`,
  `"[1,2]"` as `"1,2"` and `" 5 "` as `"5"`; an action that relied on that
  should normalise the value itself. The `data-live-*-param` attribute
  LiveCable writes now holds the value as a JSON string (`'"5"'`), so a
  selector or script that reads it must expect the quotes.
- An action whose first positional argument is optional or a named splat,
  such as `def reload(full = false)` or `def search(*args)`, is now called
  with the message's `ActionController::Parameters`, which is truthy even
  when empty, instead of its default. Give an action the client calls a
  required `params` argument, or none, and keep optional arguments for
  methods only Ruby code calls. Forwarders keep their 0.5 behaviour: an
  action defined with `delegate` or served by `method_missing` is still
  called with no arguments, and a prepended wrapper or an RSpec stub is
  called with the params only when the method it wraps takes them.
- A top-level component's Hash default reaches it with its keys sorted at
  every level, on page load and after it connects, so code that iterates a
  nested Hash default sees its keys in sorted order rather than the order
  they were built in. An inline child's defaults still come from its
  parent's template as written.
- Socket renders no longer read `ApplicationController.renderer`'s defaults.
  Their host, protocol and script name come from the socket's request. A
  cable server on a host of its own should set `default_url_options` on
  `ApplicationController`. One with no session middleware in front of it has
  no session over the socket, so its forms still render without an
  authenticity token. A socket opened before a sign-in that rotates the
  token, as Devise's does, renders the old one until it reopens: put
  `live_cable_identity_tag` in the layout. `LiveCable::Testing` renders for
  `http://test.host`, not `http://example.org`.
- Upgrade the npm package with the gem. A 0.5 client sends no page path, so
  over the socket `request.path` stays blank and `url_for(page: 2)` still
  raises. Over the socket `params` now holds the page's query and route
  parameters. The client is the one that says which page it is on, so
  authorize from the session, not from `params` or `request.path`. A
  component kept across a Turbo visit keeps the path it subscribed on.
  `live_mount` takes a new `at:` keyword, so a default named `at` can no
  longer be passed through it.
- What one socket render writes to `flash.now`, `request.env`,
  `request.variant`, the cookie jar or response headers is no longer seen by
  later renders or by other components on the socket. The flash still starts
  empty, as in 0.5.
- A component whose socket the server refuses now reads
  `data-live-status-value="refused"` instead of staying `disconnected`. If you
  styled `disconnected` as "loading", style `refused` too, and listen for
  `live:refused` to reload or show a signed-out notice. Guard a reload so it
  happens at most once a minute or so per tab: if your cable refuses a session
  your HTTP authentication accepts, an unguarded reload loops forever. You can
  delete a workaround that patched `Subscriptions.prototype.notifyAll`.
- A component whose subscription a `before_subscribe` of yours rejects now
  reads `data-live-status-value="rejected"` and dispatches `live:rejected`
  from its root, and the client forgets it, so a page that renders it again
  subscribes it again. Style `rejected` if you style the other statuses.
- Until every client is on 0.6, a component that calls `refuse!` shows a 0.5
  client the error box ("An error occurred" in production), since it doesn't
  know `_refused`. The server stops the component either way.
- A `before_connect` that throws `:abort` now refuses the component, as
  `refuse!` does: it takes the `refused` status and a `live:refused` event
  with a `null` reason, and a 0.5 client shows the error box. Before, the
  prerendered HTML stayed on the page unconnected while its actions still
  ran. To keep the component on the page and refuse only its messages, throw
  `:abort` in `before_dispatch` instead. A message sent to a component whose
  `before_connect` raised now gets an `_error` instead of being dispatched,
  and a component whose subscribe failed before it connected no longer runs
  its `disconnect` callbacks when the client unsubscribes it. `live_mount`
  returns a component whose connect halted without raising, and
  `refused?` reports it.
- A component a Turbo Frame render or Turbo Stream action takes off the page
  is now disconnected on the server, running its `disconnect` callbacks. One a
  later response brings back is built afresh instead of picking up the old
  instance's state; one the same stream response puts back, as a `remove`
  followed by an `append` does, keeps it. A component your own JavaScript
  takes off the page is left alone until the next Drive visit, as before.
- The `turbo-cache-control` no-cache tag LiveCable adds now also comes off
  when a frame render or stream action takes the last live component off the
  page, so Turbo caches that page again, and a page that gets its first
  component from a frame or stream gets the tag.
- Turbo no longer morphs a live component's root element or anything inside
  it: LiveCable cancels `turbo:before-morph-element` for it, so a listener of
  your own sees the event's `defaultPrevented` set. A component a morph gives
  other defaults is replaced by the new markup rather than morphed into it.
- A model held in a reactive variable, or read from a reactive Array or
  Hash, is the record itself instead of a `LiveCable::Delegator`, in
  component code and through `component.x`. Drop any `__getobj__` call on
  one, which now raises `NoMethodError`; `LiveCable::Delegator.unwrap` still
  returns it. A model read from a reactive collection keeps marking that
  collection when it's written after being taken out of it.
  `LiveCable::Delegation::Model` is gone, and
  `LiveCable::Delegator.supported?` is false for a model.

### Changed

- **Control blocks send only the values that changed.** An `if`, `unless`,
  `case`, `for`, `while` or `until` at the top of a `.live.erb` template, and
  a block that iterates (`each`, `times`, `find_each`...), compiles to static
  markup plus values instead of one HTML string. Statics are sent once per
  component, and each render sends a diff against what the client already
  holds: renaming one row of a list sends its new title, adding a row sends
  the row and the key it goes after, and removing one sends its key. Rows are
  keyed by the `id` or `live-key` of the element the loop body renders. On a
  20-row todo list, an update went from about 11 KB to 120-450 bytes.
  See [Control Blocks](https://livecable.io/guide/partial-rendering#control-blocks).
  The server does more work for it. Measured with `LiveCable::Testing`, a
  one-row update to a 200-row list took about 2.4 ms to render instead of
  1.4 ms, and 10 ms instead of 6 ms at 1,000 rows, while sending 113 bytes
  instead of 109 KB. A page of 200 inline children takes about a quarter
  longer to render than on 0.5.1, with `config.structured_blocks = false` too,
  and a template's first render after boot compiles for longer (29 ms against
  6 ms for the 200-row list).
- When all a render changes is rows of keyed loops, the client adds, moves,
  removes and morphs those rows' elements instead of rebuilding and morphing
  the whole component, so its cost follows the rows that changed rather than
  the length of the list. See
  [Patching Rows in Place](https://livecable.io/guide/partial-rendering#patching-rows-in-place)
  (npm).
- Block helpers (`form_with`, `content_for`, `cache`...), `begin`/`rescue`,
  and blocks that use `next`, `break` or `return` are still rendered to HTML.

### Added

- `config.structured_blocks` (default `true`) to send control blocks as HTML
  strings, as before.
- **`reactive_query`, so a component that queries on render re-renders when
  the rows change.** Dependency tracking sees a method that only runs a query
  as depending on nothing, so its parts were skipped after a write unless the
  component bumped a counter by hand, and caching the result per counter kept
  every row in memory until the next bump.
  `reactive_query :entries, -> { relation } { |relation| ... }` declares a
  reader that runs the query and the optional block once per render and
  keeps nothing afterwards but the query's fingerprint: an SQL digest and
  `cache_key_with_version`, taken from the records just loaded where Rails
  can. `refresh(:entries)` runs one aggregate query and re-renders the parts
  that read `entries` only if the fingerprint changed; `dirty(:entries)`
  re-renders them without checking. A change to the query's SQL, such as a
  reactive variable the lambda reads, re-renders it with no database query.
  Writes that skip `updated_at` and changes to associated rows aren't seen;
  `dirty` covers those. A component that already defines `refresh` keeps its
  own method (gem).
- **`refuse!(reason)` stops a component when the person may no longer use
  it.** Call it from an action, a `before_dispatch`, a `stream_from` callback,
  a connect callback, a `rescue_from` handler or a render over the socket. It
  raises `LiveCable::Refused`, which is never offered to `rescue_from` and
  isn't reported to `Rails.error`. The server disconnects the component at
  once: its owned children are destroyed and disconnected with it, its streams
  stop, the rest of the message batch is skipped, and nothing the client sends
  it afterwards runs. A child rendered inline is refused on its own, even when
  it refuses while its parent renders it, and while the parent keeps rendering
  it, the parent's renders keep it as the page last showed it instead of
  building it again. The client keeps the component's markup, sets `refused`,
  ends its loading state, unsubscribes, and dispatches a bubbling
  `live:refused` from the component's root with `detail.reason`, so one
  handler covers refused sockets and refused components. A render that refuses
  during the HTTP prerender fails the page, as any template error does. In the
  testing harness, a refusal is never re-raised, and `TestComponent#refused?`
  reports it. A 0.5 client doesn't know `_refused`. It shows the error box
  from the `_error` sent alongside and unsubscribes, as it does for any error.

### Fixed

- **A component built again from new defaults could leave its inline children
  garbled or keeping the previous defaults' state.** On a Turbo Drive visit,
  ActionCable could run the new parent's subscribe before some of its old
  children's unsubscribes, so the parent's render reused those
  still-registered instances and sent them without their static parts: they
  showed as bare text, with no controller, and stayed dead. A Turbo Frame
  navigation or Turbo Stream replace never closed the children at all, so they
  kept their old state while the parent showed the new defaults. Disconnecting
  a component on the server now takes the children it renders off the
  connection too, running their disconnect callbacks, and the client closes
  the children of a component whose element brings different defaults wherever
  that element comes from. `LiveCable::Testing`'s `unmount` disconnects the
  children it renders too, as the server does.
- **A child given an element of a reactive collection with `live(...)` never
  showed the parent's own changes to it.** After `columns.first[:name] = x`
  the parent re-rendered, but each child kept its old HTML, though its state
  already held the change. A sibling given the whole collection later in the
  template than a child that changed an element of it stayed stale the same
  way. When a connected parent renders a `live(...)` call again, the child now
  compares each Array or Hash it was given, and the records in it, with how
  they were when the parent last rendered the call, and re-renders what reads
  one that changed. The comparison is made once per collection per parent
  render, so siblings given the same collection share it. Children whose
  values didn't change still send nothing. The comparison costs about 15 us a
  child each time its parent renders it, some 3 ms a render on a page of 200
  children (gem).
- **A `live-value-*` param could reach the action changed.** Stimulus parses
  every param as JSON, so `live-value-id="12345678901234567890"` arrived as
  `"12345678901234567000"`, a different record, `"1.50"` as `"1.5"`, `"1e3"`
  as `"1000"`, `"[1,2]"` as `"1,2"` and a JSON object as `"[object Object]"`.
  Each value is now written into its `data-live-*-param` as a JSON string, so
  the action gets exactly the text the template wrote (npm).
- **An action with an optional or splat params argument never got its
  params.** An action was passed its params only when its method's arity was
  positive, so `def search(params = {})` and `def search(*args)` were called
  with no arguments, so the action never saw the client's params, and nothing
  was logged. An action is now called with the params whenever its method
  takes a required, optional or named splat positional argument; one that
  takes only keywords is still called with none. An anonymous splat is a
  forwarder, and so is a splat over another method: a prepended wrapper or an
  RSpec stub gets the params only when the method it wraps takes them, and a
  `delegate`d or `method_missing` action gets none, as before (gem).
- **Equal defaults whose nested hashes were built in a different order rebuilt
  the component on a Turbo visit.** Only the top-level keys were sorted before
  signing, so `{ filters: { a: 1, b: 2 } }` and `{ filters: { b: 2, a: 1 } }`
  signed to different `live-defaults` blobs, and the client, which compares
  blobs, closed the component and its inline children and built them again,
  losing their live state. Keys are now sorted at every level, including
  hashes inside arrays, and a prerendered root renders with the same sorted
  form (gem).
- **Forms rendered over the socket lost their authenticity token, and `*_url`
  helpers printed `http://example.org`.** Every socket render, the subscribe
  render the client morphs over the page's HTML included, ran on a request
  built from `ApplicationController.renderer`'s defaults, with no session.
  Once its component connected, a form posted without Turbo, such as an
  OmniAuth `button_to`, failed with `InvalidAuthenticityToken`. The session,
  cookies and anything Rack middleware such as Warden put on the request were
  missing too. A socket render's request is now made from the socket's own:
  its host, protocol, headers, cookies and session, under the application's
  script name. `LiveCable::Testing` renders with an empty session, so its
  forms carry a token when forgery protection is on (gem).
- **`url_for(page: 2)` broke a component once it connected, and
  `current_page?` was always false over the socket.** A socket render's
  request had no path. `request.path` was blank, `params` held nothing from
  the page, and `url_for` with only parameters, which pagination helpers
  call, raised `ActionController::UrlGenerationError` and put the component
  in the error box. The client now subscribes with the path and query of its
  page, or of the `turbo-frame` it was loaded into. Socket renders run on a
  request for that page, with the parameters of the route it matches,
  recognized once per page per connection. A route whose constraint raises
  or throws, as Devise's `authenticate` does with no one signed in, gives no
  route parameters. `live_mount` takes the page as `at:`, as in
  `live_mount('product_list', at: '/products?page=2')`.
- **Socket renders on one connection shared request state.** 0.5 built one
  request and response per connection. So what a render wrote to
  `request.env`, `request.variant`, `flash.now`, the cookie jar or response
  headers was seen by later renders and by every other component on the
  socket. Each socket render now gets its own request, response and empty
  flash, on a copy of an env the connection builds once per page. That costs
  about 13 us a render. The session is still the socket's, shared by every
  render on it (gem).
- **A socket the server refused left every component waiting in its
  disconnected state for a reconnect that never came.** Action Cable stops
  reconnecting once a handshake is refused, after a sign-out, a password
  change or a remote disconnect, but LiveCable ignored the
  `willAttemptReconnect: false` it passes. Components now take the `refused`
  status. Messages held for a reconnect are dropped, loading states end, and
  anything sent while refused is dropped too. A single bubbling `live:refused`
  event fires on `document` with `detail.reason` (the reason from the server's
  disconnect frame, such as `'unauthorized'`, or `null`) and
  `detail.components`. LiveCable doesn't reload the page itself. Works with a
  0.5 server (npm).
- **Signing in again in the same tab after a refused socket left components
  kept from the previous page dead.** `syncIdentity` only reopened a socket
  that was still active. It now also opens a socket the server refused, so
  every subscription still on the page resubscribes as the new session and
  leaves `refused` on its first render. What the components send once the
  socket is reopening, by `syncIdentity` or by a new subscription, is held for
  the resubscribe rather than dropped. A socket that is only reconnecting is
  still left to Action Cable (npm).
- **A component whose subscription the server rejected kept the status the
  page rendered it with, and held whatever it sent until it stalled.**
  LiveCable passed Action Cable no `rejected` callback. Rejected components
  now take the `rejected` status. What they held is dropped, their loading
  state ends, later sends are dropped, and a bubbling `live:rejected` fires
  from the root. The manager forgets the subscription, so a new page that
  renders the component subscribes it again. LiveChannel never rejects by
  itself; this is for an application that adds a `before_subscribe` that calls
  `reject` and `throw :abort` (npm).
- **A `before_connect` that throws `:abort` left a component on the page that
  never connected and never answered.** The callback skipped attaching the
  channel, so the subscribe render and every later reply were dropped, while
  the actions the client sent still ran. A halted connect now refuses the
  component, as a `refuse!` there does, with no reason: the server drops it
  from the connection without running its disconnect callbacks, and the
  client keeps its markup, sets `refused` and dispatches `live:refused`. A
  message for a component whose connect raised is answered with an `_error`
  and runs nothing, in production and in the test harness, and a component
  that never connected runs no disconnect callbacks when the client
  unsubscribes it. `before_connect` can now read connection identifiers such
  as `current_user`, since the channel is attached before the callbacks run
  (gem).
- **A component a Turbo Frame or Turbo Stream took off the page stayed
  subscribed.** Only a Turbo Drive visit closed subscriptions, so after a
  frame navigation or a stream `remove`, `replace` or `update` the components
  it removed, and the components they render inline, stayed on the server
  until the next Drive visit or the socket closed: their `stream_from`
  callbacks kept running, and a stream that added the same component again
  showed the old instance's state. After each frame render and stream action
  the client now closes the subscription of every component that was inside
  the frame or the action's targets and whose element has left the page. One
  the new markup renders again with the same id and defaults, or the same
  stream response puts back, keeps its state, as on a Drive visit (npm).
- **Back to a page whose live component arrived by a frame or stream restored
  a cached snapshot of it.** The `turbo-cache-control` no-cache tag was added
  only on page load, so a page that got its first live component from a
  Turbo Stream or frame was cached, and Back brought the component back from
  the snapshot without its defaults: a counter streamed in at 7 came back
  at 0. The tag is now checked again after every frame render and stream
  action (npm).
- **A Turbo morph reset a live component to its prerender and sent a child's
  clicks to its parent.** A morphing page refresh (`turbo_refreshes_with
  method: :morph`, `broadcasts_refreshes`) or a stream action with `method:
  :morph` morphed each component towards the HTTP prerender without Stimulus
  reconnecting it: the page showed the initial state, pending
  `live-disable-with` buttons were enabled again, and inline children lost
  their controllers, so their `live-action` buttons ran the parent's action.
  The client now cancels `turbo:before-morph-element` for a component's root
  element: one the new markup renders with the same id and defaults stays as
  it is, and one it renders with other defaults, or replaces, is swapped for
  the new markup and built again from it (npm).
- **Duplicating a record held in a reactive variable re-rendered its
  component.** ActiveRecord clears a copy's timestamps while duplicating it,
  and until then the copy carried the original's observers, so `todo.dup`
  marked the variable holding `todo` dirty. The copy's observers are now
  reset first (gem).
- **A model in a reactive variable wasn't the record in component code.** A
  model held in a variable, or read from a reactive Array or Hash, came back
  as a `LiveCable::Delegator` around the record, so `is_a?`, `instance_of?`
  and `case` failed, and assigning it to an association, as in
  `todo.update!(owner: user)`, raised `ActiveRecord::AssociationTypeMismatch`.
  Records are no longer wrapped: they are watched through their own write
  hooks, and one read from a reactive collection comes back as itself with
  the collection's observers attached (gem).

## 0.5.1 - 2026-11-12

### Upgrading from 0.5

The gem and the npm package work with each other at 0.5 in either
direction, but upgrade both to get every fix. A few fixes change behaviour an
application could notice:

- LiveCable runs on Rails 7.1 and 7.2 again, which 0.5.0 required 8.0 for.
  The gemspec allows them, and CI runs the suite on both.
- A child component its parent stops rendering is disconnected at the end of
  the parent's update, so its `disconnect` callbacks run then rather than when
  the client's unsubscribe arrives. A message the child sent before its
  destroy reached the client is not run.
- `cache` keys in component templates now include the template's digest, so
  those fragments start cold after the upgrade and the old entries are left
  to expire. A key written with `skip_digest: true` is unchanged.

### Fixed

- **Every render of a `.live.erb` template rebuilt its renderer, so delta
  renders took two to three times as long as they needed to.** (gem) The
  compiled template allocated a new `Partial` on every render: every part
  string and metadata hash, an anonymous renderer class and one `class_eval`
  per part. Each template's `Partial` is now built once and cached, keyed by
  the template and checked against a digest of its compiled source. An edited
  template replaces its entry, so development holds at most one per file.
- **`<%= x # note %>`, `<%= form_with ... do |f| # note %>` and heredocs
  inside `<%= %>` raised a SyntaxError in `.live.erb` templates.** (gem) The
  renderer closed the expression on the same line as its code, so a trailing
  comment swallowed the closing parenthesis or the rest of the block, and a
  heredoc never found its terminator. It now adds the newline Herb's own ERB
  engine adds after such code.
- **With several debounced fields pending at once, the client sent their
  updates in reverse order, so the older value could win.** (npm) The flush
  put each pending message in front of the last, leaving the oldest just
  before the action, and a debounce whose own timer fired went after the newer
  ones still pending. A slider and a number field bound to one variable could
  save the slider's older value. Pending messages now go in the order they
  were triggered, ahead of the message that flushes them, and a firing
  debounce keeps its own place among them.
- **A socket's messages could be applied out of order, so typing into a
  `live-reactive` field and pressing Enter could refill it with a stale
  value.** (gem) ActionCable runs each frame as its own job on the worker
  pool, and the connection lock kept those jobs from overlapping but not in
  order: a late keystroke could land after the action that cleared the field,
  and messages flushed after a reconnect could be reordered. LiveCable now
  queues a socket's `LiveChannel` frames as they are read and runs them in
  that order. The application's own channels are unaffected, and no client
  change is needed.
- **A keyed child moved to another parent in one update, or a child hidden and
  shown again before the first reply arrived, showed as bare text or
  vanished.** (gem) When a parent stopped rendering a child, the server sent
  the child a destroy but kept the instance registered until the client's
  unsubscribe arrived, and a `live()` call for the same id in the meantime
  reused it, rendering it without its static parts into a client that had
  already dropped its state. A dropped child is now destroyed at the end of
  the render cycle, unless another parent placed it during that cycle, and
  taken off the connection with its children, so a card moved between lists
  keeps its instance and state and a child shown again later is built afresh.
  Its disconnect callbacks run at that point rather than when the client's
  unsubscribe arrives, also for a child something destroyed earlier, and an
  error they raise is reported instead of failing the parent's render; a child
  that never subscribed is removed without running them. A message a destroyed
  child sent before the destroy reached it is not run, and is answered with
  another destroy.
- **Child components rendered as table rows showed above the `<table>` once
  the socket connected.** (npm) The client parsed a parent's HTML with each
  child still in its `<LiveCable>` placeholder, and the HTML parser moves an
  unknown element out of table markup (older `<select>` parsing drops it), so
  a child whose root is a `<tr>` landed before the table and left the
  `<tbody>` empty after every render. The client now turns each placeholder
  into a comment before parsing, which stays where the parent put it; what
  the server sends is unchanged. Under that `<select>` parsing a Turbo visit
  also closed the children inside a `<select>` of a component it kept, and
  these are now read from the placeholders' text.
- **`live-value-*` on a `live-form` element never reached the action.** (npm)
  The attribute was converted into a Stimulus param, but the form's message
  was built from its fields alone, on both the immediate and the debounced
  path. The form's `live-value-*` params are now sent along with its fields,
  with dashed names in snake case as `live-action` sends them.
- **An inline child's `data-live-status-value` went back to `disconnected`
  whenever its parent re-rendered without re-rendering it.** (npm) The child
  kept working, but CSS keyed on the status, like the loading-states guide's
  dimming recipe, treated it as offline. Its stored root was rendered before
  it subscribed, and the parent rebuilt it from that. The parent now applies
  each child's own subscription status to a child it rebuilds.
- **A focused `live-reactive` field without a value attribute, like the
  docs' `<input name="search" live-reactive>`, was emptied by the reply to
  its own update.** (npm) The field kept what had been typed only when the
  reply rendered the value it sent, so any reply that re-rendered a part
  cleared it, and with `live-debounce` the next update then sent `""`. A
  reply to the field's own update now also keeps what was typed when the
  template renders no value for the field: an input without a `value`
  attribute, or an empty textarea.
- **On Rails 7.1 and 7.2, every action that takes params raised NameError.**
  (gem) `Dispatch#params` built them with `ActionDispatch::ParamBuilder` and
  `ActionDispatch::QueryParser`, which only exist from Rails 8.0, so every
  `live-form` submit and every `def save(params)` action answered with an
  `_error`. When `ParamBuilder` isn't defined, params are now parsed with
  `Rack::Utils.parse_nested_query`, the parser Rails 7.x itself uses for query
  strings. Rails 8 parses them as before.
- **On Rails 7.1, rendering a component outside the socket raised
  NoMethodError (private method 'format').** (gem) `Component#render` with no
  live connection, and `render component` from a controller, mailer or Turbo
  `renderable:`, go through Rails 7.1's `Template::Renderable`, which calls
  `format` on the component, where 7.2 and later use `try(:format)`. A
  component only had Kernel's private `format`. Components now have a public
  `format` that returns nil when called with no arguments, as 7.2 and later
  already saw, and is Kernel's `format` otherwise, so `format('%.2f', x)` in
  component and template code is unchanged.
- **A write chained off `reload` or `lock!` on a model read from a reactive
  collection, as in `todos.first.reload.update!(done: true)`, didn't
  re-render.** (gem) The wrapper `todos.first` returns forwarded `reload`,
  `lock!` and `presence` and handed back the bare record, which has no
  observer of its own, so the write that followed was saved but the page
  stayed stale. A child passed the record had the same problem with
  `todo.reload.update!`, which re-rendered the child but not its parent's
  list. When a forwarded call returns the record itself, the wrapper now gives
  the record its observers. The call still returns the record.
- **Updating a model with a column named `method` through a reactive variable
  raised ArgumentError.** (gem) The wrapper called the methods it decorates as
  `record.method(name).call(...)`, and a `method` column's reader replaces
  Object#method, so `request.update(path: '/x')` on a reactive model, or on
  one read from a reactive collection, failed with "given 1, expected 0". The
  wrapper now calls them with `public_send`.
- **After `map!`, `fill`, `transform_values!` or a `merge!` block stored
  another reactive value, templates got a wrapper instead of the plain
  value.** (gem) Mutators unwrapped their arguments but not what their block
  returned, so the wrapper ended up inside the raw data, and
  `tag.b(class: todo[:classes])` rendered `class="[&quot;d&quot;, ...]"` over
  the socket. A mutator now unwraps its block's result.
- **With `raise_errors: false`, an action whose `rescue_from` handler raised
  let the error escape `perform` instead of broadcasting an `_error`.** (gem)
  `LiveCable::Testing`'s `perform` and `set_reactive` called the connection
  without the outer rescue `LiveChannel#receive` has, so the harness disagreed
  with production. They now hand such an error to `handle_error` as the
  channel does.
- **A stream callback that raised left other components it changed
  unrendered.** (gem) When no `rescue_from` took the error, the callback
  skipped broadcasting the changeset, so a write it made before raising, such
  as to a `shared: true` variable, never reached the other components that
  read it and stayed stale until the variable changed again. It now broadcasts
  the changeset however the callback ended, as a failed action does.
- **Calling `stream_from` twice with the same name ran its callback twice per
  broadcast.** (gem) Each call subscribed another ActionCable handler, and
  `stop_stream_from` stopped only the newest, so the first stayed subscribed
  for the life of the process. The test harness kept one callback per name, so
  specs passed. `stream_from` with a name the component already streams from
  now replaces the callback and keeps the ActionCable stream, so the newer
  callback runs once. With a different `coder:` it stops the stream and starts
  a new one, and the old stream's handler runs nothing even when ActionCable
  subscribes it after the stop, as it does when both calls run in one job.
- **Changes made while a `before_render` threw `:abort` never reached the page
  once rendering resumed.** (gem) The halted cycles' changesets were reset
  before the next render, which sent only its own cycle's changes. A halted
  render callback now makes the next completed render send every dynamic part,
  as a template switch does. This covers a child whose parent rendered it
  while it was halted.
- **An action or subscribe that raised a `ScriptError`, such as
  `NotImplementedError` or a `SyntaxError` from a reload, got no reply.**
  (gem) LiveCable rescued only `StandardError`, so these errors reached
  ActionCable, which only logs them: the button stayed loading until the stall
  timeout, a failed subscribe left the component disconnected with no error
  box, and `rescue_from` was never offered them. They now get the same
  `rescue_from` offer and `_error` as any other error.
- **A `cache` block around `live(...)` in a component template lost the child
  once the fragment was stored.** (gem) A cache hit skips the block, so the
  `live(...)` call never ran: over the socket the parent destroyed the child
  and sent no render for it, and a page loaded after a socket render printed
  an empty `<LiveCable>` placeholder in place of the child, for every
  visitor. A `cache` block that renders a component inline is now rendered
  every time and never stored; other fragments are cached as before. Clear
  fragments an earlier version cached around `live(...)`, or let them expire.
- **The `cache` helper in a component template left the template's digest
  out of its keys.** (gem) Parts run after ActionView has finished the
  template, so `cache` saw no template on the socket and the host page's on
  a page load. Two components using the same key, such as `cache(record)`,
  served each other's markup, and editing a component template never expired
  its fragments. Parts now run with the component's template as the view's
  current template, so keys carry its digest as in any Rails view, and page
  loads and socket renders share them. Keys change once on upgrade, so
  fragments cached by an earlier version are left to expire;
  `skip_digest: true` still writes the bare key.
- **An action added by a code reload or a deploy couldn't be called from a
  page that was already open.** (npm) The live controller defined its action
  and form handlers once, when it connected, and morphdom keeps the root
  element across the reconnect render, so a new action's button only logged
  Stimulus's "references undefined method" error. The handlers are now defined
  whenever the component's actions value changes.
- **In development, client writes to a shared variable stayed refused after a
  reload removed the declaration that guarded it.** (gem) Shared declarations
  are kept per class name, and a reload replaced an entry only when the
  reloaded class declared the same name again. A class that was deleted,
  renamed or stopped sharing the name kept refusing writes until the server
  restarted. Now an entry counts only while its class can still be found and
  still shares the name without declaring it writable. Entries for classes
  that can't be looked up by name still count.
- **Content set with `content_for` in one tag went blank or stale over the
  socket when only the tag that read it, or only the one that set it,
  re-rendered.** (gem) Each socket render uses a fresh view, and nothing
  tracked `content_for` between parts, so the unchanged one was skipped. A
  tag that calls `content_for`, `content_for?` or `provide` now always runs,
  as a tag that assigns a top-level local a later tag reads already does.

## 0.5.0 - 2026-11-12

### Upgrading from 0.4

The gem and the npm package work with each other at 0.4 in either
direction, but upgrade both to get every fix. A few fixes change behaviour an
application could notice:

- LiveCable now needs Rails 8.0 or later, and the gemspec says so. On Rails
  7.1 and 7.2, every action that takes params already failed on 0.4.
- A template that reads a local assigned inside an earlier block, with no
  component method or view helper of that name, now raises `NameError`
  instead of rendering nothing.
- An `<%= %>` tag, or an `if`/`case`/loop group, that assigns a top-level
  local that a later tag reads before assigning it itself (a second
  `for item in …` loop doesn't) now runs and is re-sent on every update, and
  so is every tag that reads it. Prefer a component method for anything
  costly.
- A component method named like a Kernel method (`open`, `test`, `select`, …)
  now wins over Kernel in its template; call it on `Kernel`, as in
  `Kernel.rand`, to reach Kernel's.
- A loading state now ends only on the component's own reply, and a nested
  component's pending elements wait for it through its parent's renders. A
  message held while the socket was down stays loading until it is answered.
  The events an action dispatches without sending a render of its own arrive
  on its `_ack`, where they used to come in a frame of their own before it.
  Frames captured by `LiveCable::Testing` carry `_reply`, and subscribe frames
  `_subscribed`, so a spec that compares whole frames needs those keys. An
  `_ack` for a component whose new render went out inside its parent's
  carries `_rendered: true`.
- A focused field keeps what the user typed through renders it didn't ask for,
  and through a reply that only echoes the value its own `live-reactive`
  update sent. To clear a field after a submit, bind it to a reactive variable
  and reset that in the action.
- `live_mount(..., raise_errors: false)` no longer raises when the first
  render or a `connect` callback fails; assert on `broadcasts(:_error)`
  instead.
- In component code, changing an element held in two reactive collections
  now marks the one you changed it through, not the one it was first read
  from. Call `dirty(...)` for the other if the page shows it there too.
- A template now gets the plain Array, Hash or model inside a reactive
  variable, and inside what a component method returns, so Rails helpers and
  `case` see the real value. An Array or Hash a template changes in place, or
  a model inside one, no longer marks its variable dirty; change it in the
  component. `component.x` in a template still returns the tracked wrapper.
- In component code, values reached through `fetch`, `dig`, `detect`, `at`,
  `min`/`max`, `min_by`/`max_by`, `sample`, `reverse_each`, a Hash's `find`
  and the `each_*` iterators such as `each_slice` and `each_cons` (including
  `Hash#each` and `each_value`) are tracked wrappers now, and a Hash's
  `values`, `values_at` and `fetch_values` return a wrapper when they hold
  nested Arrays, Hashes or models. Writes through them mark the variable
  dirty. Use `to_a`, `to_h` or `LiveCable::Delegator.unwrap(value)` where
  code needs the real value.
- A model stored directly in a reactive variable is watched on the record
  itself, so a write through any reference to it, a `reload` that brings in
  a change, or a validation that normalises an attribute marks the variable
  dirty and re-renders. A model in a reactive Array or Hash re-renders on
  any write made through the collection (`todos.first.title = x`,
  `toggle!`, `reload`), not only `update`.
- When a component re-renders, parts that read a non-reactive `shared`
  variable render again and are sent too, whether or not it changed.
- Defaults are signed in their `as_json` form, and a prerendered root renders
  with that form too, so a Symbol default is a String, and a nested Hash has
  String keys, on page load as well as after subscribe. In development and
  test, a default that changes on the way logs a warning.
- A top-level component's default that is or holds anything other than
  strings, symbols, numbers, booleans, `nil`, times and dates, in Arrays and
  Hashes, now raises `ArgumentError` on page load, in production too. That
  covers an ActiveRecord record or relation, and a `Struct`, `Set`, presenter
  or form object, whether or not it holds a record. On 0.4 the page loaded and
  the component got the object's `to_s` or `inspect` string, such as
  `"#<User:0x…>"`, once connected. Pass an id and load the record in the
  component.
- An error raised by an initial-value lambda goes through the error handling
  of the subscribe or render that first reads it instead of storing `nil`: a
  root's subscribe answers with an `_error`, and a failing child replaces its
  parent with the error box. An initial value other than a proc or `nil`
  raises `ArgumentError` when the class loads.
- A child its parent renders now runs its render callbacks on each of those
  renders. The first time a parent renders it, on page load or when an action
  first shows it, they run before its connect callbacks, without connection
  identifiers such as `current_user`; pass such values from the parent. A
  `before_render` that throws `:abort` on that first render leaves the child
  out of the page until the parent renders it again and the callback lets it
  through.
- A checkbox with `live-reactive` sends `true` or `false`, and a `<select
  multiple>` sends an Array of values, instead of the element's `value`.
- A render in which no part re-renders is no longer sent. An action whose
  changes no part of the template reads is answered with an `_ack`, so a test
  expecting a `_refresh` after one should expect `broadcasts(:_ack)`. Such an
  action also no longer resets its form: a field the server doesn't track
  keeps what was typed. To clear it, bind it to a reactive variable and reset
  that in the action. A part that reads a non-reactive `shared` variable or a
  local an earlier tag assigns re-renders whenever its component does, so a
  template with one still answers with a `_refresh`.
- A relative key such as `t('.title')` in a `.live.erb` template now looks
  up the template's own scope on page load, `live.counter.title` for
  `app/views/live/counter.html.live.erb`, instead of the page's, such as
  `home.index.title`. Move any such translations under the component's key.

### Security

- **A child component's id could inject markup that ran in the browser.**
  Over the socket a parent sends each child it renders inline as a
  `<LiveCable child-live-id="...">` placeholder, and the child's id went into
  that attribute unescaped. An id built from user input, such as
  `live('tag', id: tag.name)`, could close the attribute and add an element
  with an event handler, which ran when the client put the parent's render on
  the page. An id with a plain quote broke the placeholder, so that child
  never rendered. The id is now escaped in the placeholder, and the client
  and the test harness read it back decoded.

### Fixed

- **An inline child whose root element has an id broke on its first
  action after the page loaded.** The client threw `TypeError:
  rootNode.querySelectorAll is not a function` and the child didn't update.
  The parent's first render over the socket brings the child's template, and
  the client stored it with the element that render built. But the morph
  kept the page's own element, because its id matched, so when the child's
  controller connected on that element its subscription started empty. The
  server only confirmed the subscription, since it had already sent the
  template, and the child's first update arrived as a delta with nothing to
  apply it to. A subscription now takes the state its parent's render left
  for it, whichever element the controller connected on (npm).
- **A template local could render blank or stale.** Dependency tracking
  parsed each part of a `.live.erb` template on its own and ignored Ruby's
  block scopes. A local assigned inside a block leaked into later parts, so a
  later `<%= css %>` rendered blank instead of calling the component's `css`;
  a top-level local updated inside a block, as in
  `<% counts.each { |c| total += c } %>`, kept its earlier value in later
  parts; a local reassigned in an `if` that didn't run became `nil`; and a
  tag that read a local by hash shorthand (`total:`), or one set by multiple
  assignment, pattern matching or a named regex capture, never re-rendered.
  Block parameters also counted as dependencies, so a part re-rendered
  whenever a reactive variable of the same name changed. And only a lone
  `<% %>` tag always ran, so a local first assigned inside an `if`, `case` or
  `for`, or in an `<%= %>` tag, was `nil` in a later part that re-rendered
  while that tag was skipped. Each part is now parsed with the earlier parts'
  locals in scope, so names resolve as they would in a plain ERB template,
  and a part that assigns a top-level local a later tag reads always runs. Two
  templates behave differently: one that reads a block's local after the
  block, with no component method or view helper of that name, now raises
  `NameError`, as plain ERB does, instead of rendering nothing; and a local
  reassigned in a branch that doesn't run keeps its value instead of becoming
  `nil` (gem).
- **A block passed to a view helper that renders a partial landed above the
  partial.** A helper such as
  `def card(&) = render(layout: 'shared/card', &)`, used from a `.live.erb`
  template as `<%= card do %>`, wrote the block's content before the card and
  left stray escaped markup where the card yields. A presenter or any other
  object that renders a partial with the template's block did the same.
  0.4.0 fixed this only for `render` called by the template itself. A block
  in a `.live.erb` template now writes wherever the view is writing when it
  runs, as in plain ERB, so it lands where the partial yields. Helpers that
  capture their block, such as `form_with` and `content_tag`, work as before
  (gem).
- **The error for a `.live.erb` template rendered as a partial didn't say
  which template.** The message began "A .live.erb template", and the
  backtrace points into LiveCable rather than at the template. It now opens
  with the template's path, such as
  `app/views/shared/_live_card.html.live.erb` (gem).
- **Template names that Kernel or Object also define, like `open`, `select`
  or `test`, ran the Kernel method instead of the component's or the view
  helper's.** A `.live.erb` template resolves bare names to the component and
  then the view context, but names the renderer already had from Kernel or
  Object never got that far. A component with `reactive :open` and
  `<% if open %>` raised an `ArgumentError` on the page and on mount, the
  `select` form helper raised a `TypeError`, and `j` printed to standard
  output instead of escaping. These names now go to the component or the view
  context whenever either defines them. When neither does they still call the
  Kernel method, so `format`, `rand` and `lambda` work as before. A component
  method with such a name now wins in its template; call it on `Kernel`, as
  in `Kernel.rand`, to reach the Kernel method. Names the renderer used for
  its own state hid the component's in the same way: with `reactive :parts`,
  `<%= parts %>` printed the compiled template, and with `reactive :changes`,
  `changes` returned the variables being re-rendered. Those now reach the
  component too (gem).
- **A child hidden after its parent re-rendered something else was never
  destroyed.** A parent only remembered the inline children of the parts its
  last render had run, so after a render that skipped a child's part it no
  longer knew it had that child. That happened on any change the part doesn't
  depend on, and whenever the parent was re-rendered inline by its own parent
  with nothing changed. Hiding the child later, a render error in the parent,
  or the parent's own destroy then left the child subscribed, with its
  `stream_from` streams running, until the socket closed. A compound component
  that switched to a variant with fewer parts leaked the children of the parts
  that went away in the same way. A parent now keeps the children of the parts
  a render skipped, and destroys any its new template no longer renders (gem).
- **A `stream_from` callback could still run after `stop_stream`.**
  ActionCable runs each broadcast as its own job on its worker pool, and
  stopping a stream can't take back a job already queued. A chat that
  switched rooms with `stop_stream` and a new `stream_from` could still run a
  callback for the old room after the switch. With a reactive array, the old
  room's message was appended to the new room's list and stayed there. A
  callback now checks, under the connection lock, that its stream is still
  running, so once `stop_stream` returns none of its callbacks run. Stopping a
  stream and starting it again under the same name still delivers what was
  already queued. `stop_stream` also kept every name it had stopped, a list
  that grew with each switch. The new `stop_stream_from(name)` stops one
  stream and leaves the component's others running (gem).
- **Another user's broadcast re-enabled a `live-disable-with` button whose own
  message was still in flight.** The client ended a component's loading state
  on every `_refresh`, including renders it never asked for - a `stream_from`
  callback's, or one caused by another component's action - and a parent's
  re-render rebuilt a nested component's pending button, so someone else's
  chat message could re-enable your Send button and invite a double submit. A
  nested component re-rendered only inside its parent's render got no reply at
  all, and stalled after 30 seconds. The server now marks the render that
  answers a message with `_reply`, or sends an `_ack` when the component sent
  no render of its own, marked `_rendered` when its new render went out inside
  its parent's. The client ends a loading state only on a reply, an `_ack` or
  an `_error`. A render an action pushes with `broadcast_render` before it
  returns isn't the reply. An `_ack` carries the events its message
  dispatched, so their handlers run once the loading state has ended and the
  component has caught up. Pending elements, and the `live-loading` on a
  nested component's root, keep their state through other renders, even a
  parent's render that carries the nested component's own, and catch up when
  the loading state ends, whether by the answer, the socket closing, a
  re-subscribe, a stall or a parent's render that moves the nested component,
  as reordering a list does. An `_ack` now also turns a `stalled` status back
  to `subscribed`, as a `_refresh` did. Frames captured by
  `LiveCable::Testing` carry the new `_reply`, `_subscribed` and `_rendered`
  keys. A message held while the socket was down now stays loading until its
  own reply, and one lost with the socket stops when it closes or the
  component re-subscribes.
  Either side works with the other at 0.4.0.
- **Typing in a focused field was undone by renders that arrived while the
  user typed.** Every refresh is morphed in from HTML rebuilt from the
  component's stored parts, which set each field back to the last value the
  server rendered. In a chat with a debounced `live-reactive` draft, an
  incoming `stream_from` message, a render caused by another component, or the
  reply to the draft's own last update dropped what had been typed since that
  update, and the debounced send that followed sent what was left. A focused
  field - a textarea, or any input a user types into or sets with a picker or
  slider, such as text, number, date or range - now keeps what has been
  entered unless the server changed its value. A re-render that answers the
  field's own form or action still applies the server's value, so an input
  cleared after a submit is still cleared, but a reply that only echoes the
  value the field's own `live-reactive` update sent keeps what has been typed
  since. Unfocused fields, checkboxes, radios and selects behave as before. A
  focused field that isn't bound to a reactive variable is no longer cleared
  by a render it didn't ask for; to clear it after a submit, bind it and reset
  the variable in the action (npm).
- **A Turbo Drive visit removed the inline children of a component that stayed
  on the page.** Before Turbo renders a new page, LiveCable closes the
  subscription of every component that isn't on it. The HTTP prerender gives a
  live id only to the root component, so a child rendered inline by its parent
  looked like it was leaving, even when the parent (a layout component, say)
  was staying. The child was torn down on the server, and the parent had
  nothing to rebuild it from, so it disappeared from the page. A component
  that stays on the page with the same defaults now also keeps the children it
  renders with `.live.erb` templates, and theirs, with their subscriptions and
  live state. One the new page renders with different defaults is still built
  again from them, and its children with it, unless it is in a
  `data-turbo-permanent` element that Turbo carries over: Turbo keeps the
  element already on the page, so the component and its children keep their
  state (npm).
- **`live_mount(..., raise_errors: false)` still raised when the first render
  or a `connect` callback failed.** `live_mount` ran `connect` and the first
  render with no rescue, so an error in either still raised, while production
  sends it through the connection's error handling and transmits an `_error`.
  `live_mount` now handles those errors the same way `LiveChannel#subscribed`
  does. With `raise_errors: false` it returns the component with the `_error`
  in its broadcasts, so a spec that expected it to raise now needs to assert
  on `broadcasts(:_error)` instead. The default, `raise_errors: true`, still
  raises (gem).
- **`component.x` and `self.x` in a template didn't re-render when `x`
  changed.** Dependency tracking only recorded bare names, so a part that read
  a reactive variable as `component.theme` or `self.theme` was skipped when
  `theme` changed and kept showing the old value. `self.x` also ran Kernel's
  method of that name when there was one, so `self.open` raised. Both forms
  now count as reads of the component (gem).
- **A call to a helper or component method rendered a template local of the
  same name instead.** After `<% t = Time.current %>`, a later
  `<%= t('.title') %>` printed the time, and after `<% count = 99 %>`,
  `count()` and `self.count` printed 99 instead of calling the component's
  `count`. A local is now read only by its bare name, as in plain ERB (gem).
- **`items.each.with_index` raised `LocalJumpError` on reactive arrays.** A
  reactive array's `each` always yielded, so calling `each` without a block
  failed, and so did `each.with_index`, `each.with_object` and `each.lazy`. In
  a template this meant the prerender worked, because it sees the raw array,
  but every socket render failed and the component never went live. `each`
  without a block now returns an enumerator, and elements yielded through it
  are tracked like those from `each` with a block (gem).
- **`self.tags = tags.dup` stopped all later change tracking for `tags`.**
  `dup` dropped the wrapper's tracking modules, so the assignment rendered
  once and every later `tags << x` or nested change went unnoticed. A
  duplicated reactive value now keeps its tracking. `clone(freeze: false)` on
  a reactive value or an ActiveRecord model raised `ArgumentError` and now
  works (gem).
- **Changing an element moved into another reactive collection marked the
  wrong variable.** After `done << todos.find { ... }` (or `self.done =
  [item]`, `done + [item]`, `selection[:item] = item`), changing the element
  through `done` marked `todos` instead. That included a child component given
  the element with `live(...)`, so the `done` part never re-rendered. Reactive
  collections now store the plain element rather than the tracked wrapper it
  was read through, and an element read back is tracked through the collection
  it was read from. In component code, an element kept in both collections is
  tracked through the one it is changed through, so a change through `done` no
  longer marks `todos`; call `dirty(:todos)` if both show it. An element read
  from a reactive collection and passed back to one of its mutators, as in
  `todos.delete(todos.find { ... })` on a list of models, is now found. An
  Array or Hash you pass in is copied only when it holds such a wrapper
  (gem).
- **After connecting, reactive Arrays and Hashes rendered wrongly in Rails tag
  helpers, and `where(id: reactive_array)` matched nothing.** A tracked value
  isn't an `Array` or `Hash` to `case` or `===`. On socket renders,
  `tag.span(class: classes)` printed `class="[&quot;btn&quot;,
  &quot;primary&quot;]"` where the prerender printed `class="btn primary"`,
  and `where(id: ids)` compiled to `id = NULL`. Templates now see the plain
  value, also inside an Array or Hash a component method builds from reactive
  values (`[todos.first, todos.last]`), so helpers and `case` behave as in any
  Rails view, and `where(column: value)`, `where(association: records)`,
  `in_order_of` and Arel's `in` and `not_in` accept reactive values instead of
  matching nothing. A child given one of these with `live(...)` still shares
  its change tracking, so the parent re-renders when the child changes it.
  That covers a reactive value, an element of one, and a collection built from
  one in the template or a component method. A child first rendered while two
  reactive collections hold an element marks both. An Array or Hash changed in
  place in a template, or a model inside one, no longer marks its variable
  dirty. A variable's first read now returns the tracked value like later
  reads, so changes made through it are tracked. `find`, `destroy` and
  `update` given a reactive list of ids act on every id instead of one.
  Component code sees plain values during the HTTP prerender and wrappers once
  connected, so for `case`, `where(hash)` and association assignment it needs
  `to_a`, `to_h` or `LiveCable::Delegator.unwrap(value)`, which work in both
  (gem).
- **Some common ways of changing a reactive Array or Hash didn't re-render.**
  Change tracking only knew the method names it listed, so aliases and
  ActiveSupport bang methods went straight through untracked. That covered
  `append`, `prepend`, `filter!`, `collect!`, `compact_blank!` and `extract!`,
  and on hashes `store`, `replace`, `slice!`, `with_defaults!`,
  `deep_symbolize_keys!` and others. Nested values read through `detect`,
  `fetch`, `dig`, `at`, `min_by`, `each_with_index`, `each_with_object`,
  `reverse_each`, `each_slice`, `values`, `each_value` or `Hash#each` came
  back untracked. So `todos.detect { ... }[:done] = true` answered with an
  `_ack` and left the page stale. All of these are now tracked, and a spec
  fails if a bang method, or an alias of a tracked one, is left out. Values
  these methods return or yield are now tracked wrappers, like the ones
  `each` already yielded, so in component code `is_a?(Hash)` on them is
  false. The elements passed to the blocks of `map`/`select`, the results of
  methods that don't wrap what they return (a Hash's `select` or `slice`, an
  Array's `second` or `partition`) and `to_a`/`to_h` are still untracked; see
  *Nested Structures* in the reactive variables guide (gem).
- **`where(commentable: record)` with a reactive record dropped the
  `commentable_type` condition and returned other models' rows.** ActiveRecord
  finds a polymorphic association's type with `is_a?(ActiveRecord::Base)`,
  which the wrapper answers false, so the query became
  `WHERE commentable_id = 1` and matched rows of every model with that id;
  `where.not` hid them instead. A plain Array holding reactive records, as in
  `where(id: [first, last])`, matched nothing. The predicate builder now
  unwraps reactive values, including those inside an Array, before
  ActiveRecord expands the hash (gem).
- **ActiveRecord models read from a reactive variable never compared equal.**
  Two reads of the same record, or a raw record and a wrapped one, compared
  unequal. So `list.delete(found)` on a plain Array left the record in it,
  `include?`, `index` and `todos - [found]` missed it, and `t == selected` in
  a template never matched. Equality now compares the records themselves.
  Unsaved records still compare unequal, as ActiveRecord intends (gem).
- **Many changes to ActiveRecord models in reactive variables didn't
  re-render.** A model reached through a reactive Array or Hash
  (`todos.first.title = x`, `todos.find { ... }.toggle!(:done)`, setters
  inside `todos.each`) was only tracked for `update` and `assign_attributes`.
  Even a model stored directly missed `[]=`, `write_attribute`, `increment!`,
  `update_column(s)`, `reload` and saved in-place JSON changes, so the
  streaming guide's `document.reload` example never refreshed the page. All of
  these writes are now tracked, at any depth. A replaced record no longer
  keeps marking the variable it was removed from. A `reload` re-renders only
  when the record's columns changed, so reloading to check a record before
  writing costs nothing; validations that normalize attributes re-render even
  when nothing visible changed.
  Association changes and unsaved in-place edits still need `dirty(:name)`
  (gem).
- **Writes through the `clone` of a model in a reactive variable didn't
  re-render.** ActiveRecord's `clone` shares the original's attributes, so
  `todo.clone.title = 'b'` changed the stored record, but the copy dropped
  the original's change tracking and the page kept the old title. A clone of
  a tracked model, held directly or read from a reactive Array or Hash, now
  marks the same variables; a `dup` is still a separate, untracked record
  (gem).
- **A part that passed a reactive variable with hash shorthand (`render
  'badge', page:`) or called it with empty parentheses (`count()`) never
  re-rendered.** The dependency analysis only recognised a bare `page`, so
  these forms (`tag.span(data: { page: })`, `items_path(page:)`) were left
  out and the part kept its first-render HTML. Any receiverless call with no
  arguments and no block now counts as a read (gem).
- **A component method's dependencies were lost when another def in the same
  file had the same name.** The method analyzer parses the component's whole
  file and the last def with a given name won, so a `def self.title`, a
  `class << self` method, a method in a nested class or `Struct.new` block, or
  a method of a second class in the file could leave every part calling
  `title` stale. Same-named defs now merge their dependencies, and singleton
  methods are ignored. Affected parts may now re-render where they were
  previously skipped (gem).
- **Parts reading a non-reactive `shared` variable in a `.live.erb` template
  never re-rendered.** They kept their first-render value even when the
  component re-rendered for its own reasons, including in an action that also
  wrote the variable, so the guide's FilterPanel badge example showed a stale
  count. Whenever a component re-renders, parts that read its `shared`
  variables, directly or through a component method, now re-render too. A
  change to a `shared` variable on its own still does not trigger a render of
  the components that declare it with `shared`. These parts are now sent on
  every re-render of the component (gem).
- **The guide's `reactive :user, ->(c) { User.find(c.defaults[:user_id]) }`
  raised `NoMethodError`.** `Component#defaults` was private, and an initial
  lambda gets the component as an explicit receiver. So the prerender failed,
  `live_mount` raised, and a real subscribe sent an `_error` and rendered
  without the default. `defaults` is now public. As a side effect, a bare
  `defaults` in a `.live.erb` template now resolves to the component's hash
  (gem).
- **A top-level component could render one way on page load and another once
  connected.** Its defaults come back from the browser as JSON on subscribe,
  but the prerender used the raw Ruby values. A Symbol came back as a String
  and nested hash keys as Strings. Since signing in 0.4.0 used plain
  `JSON.generate`, a `Time` came back as its `to_s` and a record as
  `"#<User:0x…>"`. LiveCable now signs each default's `as_json` form, as 0.3's
  unsigned attribute did, and prerenders a top-level component with that same
  form, so both renders agree: `status: :open` is now `"open"` on page load
  too. The defaults are signed, not encrypted, and a record's JSON form is
  every one of its attributes, and a plain object's is its instance variables,
  so a top-level component given anything other than strings, symbols,
  numbers, booleans, `nil`, times and dates, in Arrays and Hashes, now raises
  `ArgumentError` on page load in every environment. That covers a record or
  relation, and a `Struct`, `Set` or presenter holding one. Pass its id and
  load the record in the component. In development and test, a Symbol, Time or
  other default that comes back changed logs a warning. Children rendered by a
  parent and `live_mount` defaults are unchanged (gem).
- **An exception in a reactive variable's initial lambda was swallowed and the
  variable stuck at `nil` (or `true`).** On a connected component the error
  was reported, and then `handle_error`'s return value was stored as the
  variable. That was `nil` for a child rendered inline and `true` for a
  component with a channel, and the lambda never ran again. A child whose
  lambda failed rendered blank, with nothing sent to the client, and a failed
  shared variable stayed broken for every later sharer. The error now goes
  through the error handling of the subscribe or render that first reads it,
  and nothing is stored, so the next read retries. A top-level component's
  subscribe now sends just the `_error` (no trailing `_refresh`). A child's
  failing initial value now replaces its parent with the error box. An initial
  value other than a proc or `nil` now raises `ArgumentError` when the class
  loads (gem).
- **Initial lambdas ran again on every read during the HTTP prerender.** With
  no connection, the reactive getter never kept the value, so a `.live.erb`
  template ran the lambda once per reference, plus once for the render locals.
  A query read three times ran four times, and `-> { SecureRandom.hex }` gave
  a label's `for` and its input's `id` different values on the same page. The
  value is now kept for the rest of that prerender (gem).
- **`before_render` and `after_render` never ran for a child rendered by its
  parent.** Render callbacks ran only when a component broadcast its own
  render. A child rendered inside a connected parent was never rendered that
  way: on page load its subscription found it already rendered and only
  confirmed its status. So state a child derived in `before_render` showed its
  initial value and went stale every time the parent rendered it again. A
  child's render callbacks now run each time a connected parent renders it,
  and an error in one replaces the parent with the error box. A
  `before_render` that throws `:abort` keeps the child as it last rendered, or
  leaves it out the first time the parent renders it, until the parent renders
  it again and the callback lets it through. A grandchild that changed along
  with its grandparent, or a child whose parent subscribed again, is no longer
  also rendered on its own in the same update, so its callbacks run once. When
  a callback halts a parent's own render, a child that changed now renders on
  its own instead of being skipped. The first time a connected parent renders
  a child, on page load or when an action first shows it, the child hasn't
  subscribed yet, so its render callbacks run before its connect callbacks,
  without connection identifiers such as `current_user`. A child whose
  `before_render` uses one will now error its parent the first time the parent
  renders it. Render callbacks still don't run during the HTTP prerender,
  which the lifecycle guide now says (gem).
- **A checkbox with `live-reactive` could never be unchecked, and a `<select
  multiple>` kept only its first choice.** `live-reactive` always sent the
  input's `value`. For a checkbox that is its `value` attribute ("on" by
  default), whether the box is checked or not. For a multiple select it is
  only the first selected option. A checkbox now sends `true` or `false`, and
  a `<select multiple>` sends an Array of the selected values. Radios, single
  selects and text inputs still send their value as a String. If you were
  reading "on" (or a custom `value` attribute) from a checkbox, you now get a
  boolean (npm).
- **A `live-disable-with` button lost the markup in its label when an `_ack`
  answered its message.** The label was saved and restored as text, which
  flattened an icon or a `<span>` inside it. A `_refresh` reply rebuilds the
  button from the stored render and hid that, but an `_ack` leaves the page
  alone, and since a render in which no part re-renders is no longer sent,
  more actions are answered with one: an icon in a click counter's button was
  gone after the first click. The label is now saved and restored as HTML
  (npm).
- **Every action on a component with `reactive :method` raised
  `ArgumentError`.** The action was looked up with the component's `method`,
  which the reactive variable's getter replaces. It is now looked up with
  Kernel's `method`, so a reactive variable named `method` works (gem).
- **`t('.key')` in a component template raised over the socket and used the
  page's scope on page load.** Rails scopes a relative key by the template
  being rendered, but it only knows that while the template's compiled method
  runs, and a `.live.erb` template's parts run after it returns. Over the
  socket there was no template at all, so the lookup raised "Cannot use
  t(".key") shortcut because path is not available"; on page load it used
  the page's path, so `t('.title')` looked up `home.index.title`. Each
  render of a component template now runs its parts with that template's
  path, so a relative key resolves to the template's own scope, such as
  `live.counter.title`, in a child component and in each template of a
  compound component too (gem).

### Changed

- **The gemspec allowed Rails 7.1 and 7.2, where every action that takes
  params raised `NameError`.** LiveCable parses action params with
  `ActionDispatch::ParamBuilder` and `ActionDispatch::QueryParser`, which
  Rails 8.0 added. The gem now requires Rails 8.0 or later, and the
  installation guide, which said 7.1, says so (gem).
- **A render that changed nothing on the page was still sent.** When a
  reactive variable changed but no part of the template showed it - a shared
  variable updated by another component, say - the component still sent a
  `_refresh` with every part empty, and the client rebuilt and morphed it for
  no visible change. A render in which no part re-renders is now skipped: its
  events still go out, its render callbacks still run, and the message it
  answers gets an `_ack`, which carries the events of the component that sent
  the message. An action answered this way no longer resets its form: a field
  the server doesn't track keeps what was typed. A part that reads a
  non-reactive `shared` variable or a local an earlier tag assigns re-renders
  whenever its component does, so a template with one still sends a
  `_refresh` (gem).
- **Every render over the socket went through a full controller render.**
  `Component#render` used `ApplicationController.renderer`, which builds a
  controller, request and response and renders through `render_to_string`
  each time, about a sixth of the time of an action on a small component. A
  connection now builds the request and response once, from the renderer's
  current defaults, and each render calls the component's `render_in` on a
  fresh controller and view, so nothing one render sets or memoizes on them
  carries over to the next. A component with a public `format` method no
  longer fails every socket render with `ArgumentError` (Invalid formats). The
  HTTP prerender is unchanged (gem).

## 0.4.0 - 2026-09-29

### Upgrading from 0.3

Upgrade the gem and the npm package together. Defaults are now signed, and
the client forwards them as an opaque string; a 0.3 client sends them as an
object, which the server treats as no defaults at all, so every component
would mount without them.

Pages rendered before the upgrade carry unsigned defaults too. They mount with
no defaults until reloaded, so deploy at a quiet moment, or expect components
on open tabs to come up empty.

A component already live on the page is now built again when a Turbo visit
renders it with different defaults. One whose defaults differ on every
render - a timestamp, a random token - is therefore rebuilt on every visit
instead of keeping its state; keep defaults to what the component is about,
such as a record or an account.

A shared variable is now writable from the client only if every component
class that shares the name declares it `writable: true`. An application that
shares a name as writable in one component and server-only in another will
see `live-reactive` writes to it refused.

### Security

- **Defaults could set reactive variables that weren't writable.** Defaults
  passed to `live(...)` are written into the page and sent back by the browser
  when the component subscribes, and they were applied to any reactive
  variable, writable or not. Anyone could edit the `live-defaults` attribute,
  or send the subscribe frame by hand, and set a variable meant to be
  server-only - a record id, a price, a tenant key - bypassing the check
  `live-reactive` writes go through. Defaults are now signed with a key
  derived from `secret_key_base` and bound to the component's `live_id`; an
  edited, unsigned or borrowed blob applies no defaults
  (`LiveCable::DefaultsSigner`). `LiveCable::Testing#live_mount` still takes a
  plain hash.
- **A component could keep acting for the previous page's defaults after a
  Turbo visit.** When the new page rendered a component with the same id as
  one already live, the client kept the existing subscription and never sent
  the new page's defaults. A component whose id didn't include the account
  stayed bound to the account it was first rendered for, and its actions ran
  against that account under a URL for another. The client now compares the
  signed defaults and, when they differ, replaces the subscription so the
  server builds the component from the new ones; equal defaults keep today's
  behaviour, state included. A Turbo preview of a cached page is ignored.
  Defaults are signed with their keys sorted, so the same defaults always
  produce the same blob.
- **A client could write a shared variable that a component treats as
  server-only.** Shared variables are one value per connection, but a
  `live-reactive` write was checked only against the class it was sent
  through. Because a client can subscribe any component, it could mount one
  that shares `:account_id` as `writable: true` and set the value another
  component shares without `writable:` (or with plain `shared`). A client may
  now write a shared name only if every class that shares it declares it
  `writable: true`. Other writes are refused with `Forbidden`. Apps that mix
  writable and server-only declarations of the same shared name will see those
  writes refused. In development with lazy loading, a class that hasn't loaded
  yet doesn't count toward the rule (gem).

### Fixed

- **An action and a `stream_from` callback could run at the same time on one
  connection.** ActionCable runs each message and each stream broadcast as a
  separate job on a worker pool shared by the whole server, with nothing
  keeping two jobs for one socket apart, and LiveCable's per-connection state
  was read and written from both. An action that saved a record and then
  pushed it onto a reactive array could have the save's own broadcast reload
  the array in between, and the record appeared twice. Each connection's work
  is now serialised by a re-entrant lock, held across an action or callback
  and its render. A job waiting on a busy connection holds a worker while it
  waits; see *Concurrency* in the architecture guide (gem).
- **A click while the socket was down left its button disabled for good.**
  ActionCable drops a message sent on a closed socket, and one sent after a
  reconnect but before the re-subscribe is confirmed, and the loading state
  had already started. Messages are now held until the subscription is
  confirmed and sent in order, and the component reads
  `data-live-status-value="disconnected"` meanwhile (npm).
- **A loading state waited for ever when no reply came** - the server
  stopping mid-message, on a deploy. After `LoadingState.timeout` (30 seconds)
  with nothing heard it gives up, restores the DOM, drops any messages still
  held for a reconnect, sets the status to `stalled` and dispatches a
  `live:stalled` event. Messages still held when a component's element is
  replaced, by a Turbo navigation say, keep their loading state on the new
  element (npm).
- **Events dispatched by a child rendered inline by its parent were dropped.**
  Such a child has no channel of its own yet; its events were flushed and then
  discarded. They now wait for the child's own subscription (gem).
- **Component names that collide with a top-level constant failed obscurely.**
  `instance_from_string` used `const_defined?`, which inherits, so a name like
  `"string"` slipped past the "not found" guard and raised `NoMethodError`
  instead of `LiveCable::Error` (gem).
- **A `stream_from` callback re-sent whatever the last message had changed.**
  Changesets were reset only when a client message arrived. Variables dirtied
  by the last message, or by the defaults applied at subscribe, stayed dirty,
  and every later stream callback on the socket re-rendered them, whichever
  component of the connection they belonged to. In a chat whose input is a
  component of its own, as in the streaming guide, each incoming message
  re-rendered the input with its last-sent `live-reactive` value, and the
  morph overwrote whatever had been typed since the last debounce. A stream
  callback now resets the changesets before it runs, as a message does, so it
  sends only what it changed (gem).
- **Grandchild components went missing from the page.** A refresh replaced
  the `<LiveCable>` placeholders in its own markup but not the ones inside a
  child it had just built or rebuilt, so a grandchild reached the morph as an
  empty element: a tree nested three deep lost its third level as soon as the
  page connected, and a grandchild added by its parent's own refresh was torn
  out the next time its grandparent re-rendered. Placeholders are now
  replaced until none remain. A component that turns up twice in one refresh
  keeps its first appearance and logs a console error, and a child with
  nothing to rebuild from is left empty instead of abandoning the refresh
  (npm).
- **Rendering a partial with a block from a `.live.erb` template failed.**
  The block was dropped on its way to the view, so
  `<%= render layout: 'shared/card' do %>` raised `ArgumentError`, and
  `<%= render 'shared/card' do %>` rendered the partial with nothing where it
  yields. The block is now passed on and renders where the partial yields (gem).
- **Rendering a `.live.erb` template as a partial put
  `#<LiveCable::Rendering::Partial:0x...>` in the page.** A `.live.erb`
  template compiles to an object only a component knows how to render, so
  `<%= render 'shared/card' %>` on a `_card.html.live.erb`, or
  `render template:` on one, wrote that object's escaped name into the HTML.
  It now raises `LiveCable::Error`, saying to render the component with
  `live(...)` or `render(component)`, or to make the partial a `.html.erb`
  template (gem).
- **A `stream_from` broadcast that arrived as its component disconnected
  raised in ActionCable's worker.** ActionCable runs each broadcast as its own
  job, so one queued before the stream was stopped still ran the callback
  against the departed component; broadcasting its changes then raised
  `NoMethodError` on the missing connection, and the rescue meant to report
  that raised again, so the error escaped to ActionCable's log. Such a
  callback is now ignored (gem).
- **The test harness's `rendered` forgot the initial render after
  `clear_broadcasts`.** It was rebuilt from the `_refresh` payloads still in
  the broadcast log, so after a clear and an action it held only the parts
  that action changed, and any inline child rendered earlier was missing.
  Renders are now kept apart from the broadcast log, so `rendered` and
  `rendered_html` reflect every render whatever has been cleared.
  `broadcasts` and `dispatched_events` still start over after a clear (gem).
- **The test harness's `rendered` left out grandchildren.** The results
  for inline children at every depth arrive together in the root's refresh,
  but a child's placeholders were resolved against a set of children of its
  own, which was always empty. A component rendered inline by an inline child
  came out blank. Placeholders now resolve at any depth (gem).
- **Two components that subscribed at the same moment could end up on
  different connections.** A socket's `LiveCable::Connection` is created the
  first time it is needed, and ActionCable runs each subscribe as its own job
  on its worker pool, so two components on one page subscribing together could
  each create one. A component left on the losing one had its actions answered
  with an `_ack` and no re-render, and shared reactive variables weren't
  shared. The connection is now created under a lock (gem).
- `MethodAnalyzer` no longer raises for a component class with no Ruby source
  location, such as one built with `Class.new`. With no methods to analyze,
  every part that calls one of the component's methods re-renders on each
  change (gem).
- `insert_root_attributes` builds a new string instead of mutating the
  rendered part, so a frozen part can't raise `FrozenError`, and its "no root
  element" error now shows the start of the offending output (gem).
- **A component destroyed while a message was in flight stayed loading.**
  `destroy` unsubscribes the component on the client, so the reply to the
  message that caused it never arrived and its `live-disable-with` button
  stayed disabled. The loading state is now cleared when the server destroys
  the component (npm).

### Added

- **`rescue_from` in components.** `ActiveSupport::Rescuable` was included but
  never consulted. An error raised by an action, a `live-reactive` write or a
  `stream_from` callback is now offered to the component's `rescue_from`
  handlers first; a handled error still answers the message, so the loading
  state clears, and anything the handler set is re-rendered. Failures while
  subscribing or rendering still get the default error markup, as does a
  message asking for an action the component doesn't expose or a write to a
  variable that isn't `writable:` - those raise `LiveCable::Forbidden`, a
  `LiveCable::Error`, and are never offered to `rescue_from` (gem).
- **`before_dispatch` callbacks.** Authorizing every client message meant
  wrapping each action, keeping its arity, catching methods defined after
  `actions`, and wrapping every writable variable's setter - which then also
  ran for the component's own writes. `before_dispatch` runs before each
  action call and `live-reactive` write the client sends, and before nothing
  else: not server-side assignments, the defaults applied at subscribe, or
  `stream_from` callbacks. `current_dispatch` says what is being dispatched
  (`kind`, `name`, `params` or `value`). `throw :abort` skips the message and
  still answers it, so the loading state clears; an error raised goes to
  `rescue_from` like one raised by an action. Callbacks are inherited, so an
  `ApplicationComponent` can declare one for every component (gem).
- **`live_cable_identity_tag`, so a sign-in or sign-out in a tab moves its
  socket on.** A socket is identified once, at its handshake, and Turbo keeps
  it open across sign-in, sign-out and impersonation, all ordinary form
  submissions; after user A signed out and user B signed in, every component
  in the tab kept acting as A. The helper renders a meta tag carrying a keyed
  digest of whatever the application identifies sockets by; when a Turbo
  visit brings a different one, the client closes the socket and opens a new
  one before the new page's components subscribe, and they come back as the
  new session. Other tabs, and access revoked by someone else, are the
  application's to handle with ActionCable's
  `remote_connections.where(...).disconnect`; the architecture guide's
  *Sign-in, Sign-out and Revocation* shows the Devise wiring.

### Changed

- Framework warnings - a component rendered without a `.live.erb` template, a
  missing `app/live` directory - go through the Rails logger once per process,
  instead of `Kernel#warn` to stderr on every render (gem).
- RuboCop now fails CI.

## 0.3.0 - 2026-09-26

### Upgrading from 0.2

Upgrade the gem and the npm package together. The 0.3 client no longer sends
the `_csrf_token` field that the 0.2 gem checks on every message, so a newer
client talking to an older gem has every action refused.

If your `ApplicationCable::Connection` follows the 0.2 installation guide,
delete both LiveCable lines from it. LiveCable now attaches `live_connection`
to every connection itself.

```ruby
# app/channels/application_cable/connection.rb - delete these
identified_by :live_connection

def connect
  self.live_connection = LiveCable::Connection.new(request)
end
```

Delete them together. Without `identified_by` there is no `live_connection=`
for `connect` to call and every handshake fails. Without the `connect` override
the identifier shadows the `live_connection` LiveCable attaches with a nil one,
and every subscribe fails with a `LiveCable::Error` that says so. Leaving both
in place keeps working, at the cost described under *Changed*.

### Fixed

- **A message could be refused with no answer, leaving the component stuck in
  its loading state.** `LiveChannel#receive` had no rescue of its own, so
  anything raised before an action's own rescue — a component that failed to
  subscribe, the CSRF check — went to ActionCable, which only logs it. The
  client holds `live-loading` and `live-disable-with` until it hears back, so
  the button stayed disabled until a reload. Every batch is now answered with a
  `_refresh`, `_ack` or `_error`. A subscribe that fails at any point transmits
  an `_error` too, and the client's unsubscribe then removes the half-built
  component from the connection rather than leaving it for the next subscribe
  to resurrect (gem).

### Changed

- `live_connection` is attached to every `ActionCable::Connection` by LiveCable
  itself, so the connection no longer declares it. As an identifier, the
  per-socket `LiveCable::Connection` became part of the connection's identity,
  which `ActionCable.server.remote_connections` has to match in full, so an
  application could never disconnect its users' sockets on sign-out. See
  *Upgrading from 0.2* above (gem).

### Removed

- The per-message CSRF token check, and with it the `_csrf_token` field the
  client sent with every batch. A WebSocket is protected at its handshake by
  ActionCable's origin check and the `SameSite=Lax` session cookie, and the
  check added nothing on top of those except a way to wedge a socket: it ran
  against the session captured at the handshake, and a socket never sees
  cookies set afterwards, so once the session's token rotated — Devise does
  this on every sign-in — every message on that socket was refused until the
  socket reconnected. A socket that outlives a sign-in is handled as for any
  other channel, by the application disconnecting it; see the architecture
  guide (gem + npm).

## 0.2.1 - 2026-08-13

### Removed

- `Component#channel_name` and `Connection#channel_name`. A component no longer
  subscribes to a stream of its own now that payloads are written straight to its
  channel, so the name identified a stream nothing published to or read from.
  Subscribing to external streams with `stream_from` is unaffected (gem).

### Fixed

- **The opening payload from `LiveChannel#subscribed` could be dropped.**
  Payloads were published through the pubsub adapter, but ActionCable registers
  `stream_from` asynchronously — so the initial render could be published before
  the subscription it targets existed, and pubsub delivers only to subscribers
  present at that moment, with no buffering or retry. The component was left
  showing `data-live-status-value="disconnected"`, with no cached render on the
  client for a Turbo reattach to replay, until some later action happened to
  produce a refresh. When a subscribe render raised, the `_error` payload was
  lost outright and the failure never surfaced in the browser at all. A
  component's stream belongs to exactly one connection, so payloads are now
  written straight to that connection rather than published, which removes the
  race along with a pubsub round trip (gem).
- **Components not reattaching after a Turbo Drive navigation.** Navigating to a
  page containing a component that is already subscribed deliberately keeps the
  existing subscription, so `LiveChannel#subscribed` does not run again and the
  server sends nothing. The newly rendered element was left with its
  server-rendered status of `disconnected` and never received the component's
  current state. A reconnecting controller now re-syncs the subscription's status
  and replays the last render into the new element (npm).
- Building DOM from a server render used iterator helpers
  (`childNodes.values().find(...)`), an ES2025 feature, which raised
  `TypeError: ... .find is not a function` on runtimes that do not implement them
  — Node 20 and earlier, and browsers older than Chrome 122 / Firefox 131 /
  Safari 18.4. Rewritten with `Array.from` (npm).

## 0.2.0

The gem and npm package versions are realigned in this release. The npm package
jumps from 0.1.1 straight to 0.2.0, skipping 0.1.2, which was published for the
gem only.

### Added

- **Server-dispatched DOM events.** Components can queue browser events with
  `dispatch_event`, delivered with the next broadcast and fired after the DOM has
  been morphed, so handlers observe the updated markup. Events are bubbling
  `CustomEvent`s dispatched from the component root (or from `window` with
  `window: true`), so they can be wired up with plain Stimulus `data-action`
  syntax. (`LiveCable::Component::Events`)
- **Loading states.** While a message is in flight, a `live-loading` attribute is
  added to the component's root element and to the element that triggered the
  message, so pending feedback can be styled with plain CSS. `live-disable-with`
  on a button or submit button swaps its label and disables it for the duration
  of the round trip; form values are serialized before anything is disabled.
  Reactive inputs (`live-reactive`) receive `live-loading` but are never
  disabled, so typing is not interrupted.
- **Component test harness.** `LiveCable::Testing` can be included in specs to
  mount and drive components without a browser, via `live_mount`.
- `./loading` subpath export for the new loading module (npm).
- Gemspec `homepage_uri`, `documentation_uri`, and `bug_tracker_uri` metadata.

### Changed

- Minimum Rails version raised from 7.0 to 7.1 (`actioncable`, `actionview`,
  `activemodel`, `activesupport`) (gem).
- Herb upgraded from `~> 0.8.10` to `~> 0.10.2`, and `prism >= 1.0` added as an
  explicit dependency (gem).
- Gem homepage now points at https://livecable.io rather than the RubyGems page.
- The `Live` namespace for user components moved out of `lib/live_cable.rb` into
  its own `lib/live.rb`, required explicitly and ignored by the gem's Zeitwerk
  loader (gem).
- Dev dependencies updated: Vitest 2.x to 4.x, happy-dom 15.x to 20.x (npm).

### Fixed

- Template compiler: block sentinel tokens now carry a newline value so Herb's
  whitespace helpers (`at_line_start?`, `preceding_token_ends_with_newline?`)
  treat them as a line boundary instead of raising on a `nil` value.
- Template compiler: the closing `end` of an output block is emitted as plain
  code instead of going through Herb's paren-balancing block-end helper, since
  escaping is delegated to Rails' output buffer.

## 0.1.2 - 2026-03-25

Gem only; no corresponding npm release.

### Added

- JavaScript assets packaged so they can be consumed from package managers as
  well as through the asset pipeline.

## 0.1.1 - 2026-03-25

### Added

- Component generator.

### Changed

- Herb pinned to `0.8.*`, and other library versions pinned.

### Fixed

- `render` inside a live template.
- Generator no longer creates `app/live` when the directory does not exist.

## 0.1.0

Initial public release.
