# Changelog

All notable changes to this project are documented in this file.

The Ruby gem (`live_cable`) and the npm package (`@isometriks/live_cable`) are
released together and share a single version number. Entries below note which
side of the pair a change affects when it isn't both.

## Unreleased

### Upgrading from 0.4

The gem and the npm package work with each other at 0.4 in either
direction, but upgrade both to get every fix. A few fixes change behaviour an
application could notice:

- A template that reads a local assigned inside an earlier block, with no
  component method or view helper of that name, now raises `NameError`
  instead of rendering nothing.
- An `<%= %>` tag, or an `if`/`case`/loop group, that assigns a top-level
  local that a later tag reads now runs and is re-sent on every update, and so
  is every tag that reads it. Prefer a component method for anything costly.
- A component method named like a Kernel method (`open`, `test`, `select`, …)
  now wins over Kernel in its template; call it on `Kernel`, as in
  `Kernel.rand`, to reach Kernel's.
- A loading state now ends only on the component's own reply, and a nested
  component's pending elements wait for it through its parent's renders. A
  message held while the socket was down stays loading until it is answered.
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
  `min_by`/`max_by`, a Hash's `find` and the `each_*` iterators (including
  `Hash#each` and `each_value`) are tracked wrappers now, and a Hash's
  `values`, `values_at` and `fetch_values` return a wrapper when they hold
  nested Arrays, Hashes or models. Writes through them mark the variable
  dirty. Use `to_a`, `to_h` or `LiveCable::Delegator.unwrap(value)` where
  code needs the real value.
- A model stored directly in a reactive variable is watched on the record
  itself, so a write through any reference to it, a `reload`, or a
  validation that normalises an attribute marks the variable dirty and
  re-renders. A model in a reactive Array or Hash re-renders on any write
  made through the collection (`todos.first.title = x`, `toggle!`,
  `reload`), not only `update`.

### Fixed

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
  returns isn't the reply. Pending elements, and the `live-loading` on a
  nested component's root, keep their state through other renders, even a
  parent's render that carries the nested component's own, and catch up when
  the loading state ends, whether by the answer, the socket closing, a
  re-subscribe or a stall. An `_ack` now also turns a `stalled` status back to
  `subscribed`, as a `_refresh` did. Frames captured by `LiveCable::Testing`
  carry the new `_reply`, `_subscribed` and `_rendered` keys. A message held
  while the socket was down now stays loading until its own reply, and one
  lost with the socket stops when it closes or the component re-subscribes.
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
  Rails view, and `where(column: value)` accepts reactive values. A child
  given one of these with `live(...)` still shares its change tracking, so the
  parent re-renders when the child changes it. That covers a reactive value,
  an element of one, and a collection built from one in the template or a
  component method. A child first rendered while two reactive collections hold
  an element marks both. An Array or Hash changed in place in a template, or a
  model inside one, no longer marks its variable dirty. A variable's first
  read now returns the tracked value like later reads, so changes made through
  it are tracked. Component code sees plain values during the HTTP prerender
  and wrappers once connected, so for `case`, `where(hash)` and association
  assignment it needs `to_a`, `to_h` or `LiveCable::Delegator.unwrap(value)`,
  which work in both (gem).
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
  keeps marking the variable it was removed from. `reload`, and validations
  that normalize attributes, now re-render even when nothing visible changed.
  Association changes and unsaved in-place edits still need `dirty(:name)`
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
