# Changelog

All notable changes to this project are documented in this file.

The Ruby gem (`live_cable`) and the npm package (`@isometriks/live_cable`) are
released together and share a single version number. Entries below note which
side of the pair a change affects when it isn't both.

## Unreleased

### Fixed

- **`items.each.with_index` raised `LocalJumpError` on reactive arrays.** A
  reactive array's `each` always yielded, so calling `each` without a block
  failed, and so did `each.with_index`, `each.with_object` and `each.lazy`. In
  a template this meant the prerender worked, because it sees the raw array,
  but every socket render failed and the component never went live. `each`
  without a block now returns an enumerator, and elements yielded through it
  are tracked like those from `each` with a block (gem).
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
  fails if a mutating method is missed. Values yielded by these methods are
  now tracked wrappers, like the ones `each` already yielded, so `is_a?(Hash)`
  on them is false. The blocks of `map`/`select` and the results of
  `to_a`/`to_h` are still untracked; see *Nested Structures* in the reactive
  variables guide (gem).
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
  it was read from. An Array or Hash you pass in is copied only when it holds
  such a wrapper (gem).
- **ActiveRecord models read from a reactive variable never compared equal.**
  Two reads of the same record, or a raw record and a wrapped one, compared
  unequal. So `todos.delete(todos.find { ... })` left the record in the list,
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
- **After connecting, reactive Arrays and Hashes rendered wrongly in Rails tag
  helpers, and `where(id: reactive_array)` matched nothing.** A tracked value
  isn't an `Array` or `Hash` to `case` or `===`. On socket renders,
  `tag.span(class: classes)` printed `class="[&quot;btn&quot;,
  &quot;primary&quot;]"` where the prerender printed `class="btn primary"`,
  and `where(id: ids)` compiled to `id = NULL`. Templates now see the plain
  value, so helpers and `case` behave as in any Rails view, and `where(column:
  value)` accepts reactive values. A child given one of these with `live(...)`
  still shares its change tracking, so the parent re-renders when the child
  changes it. That covers a reactive value, an element of one, and a
  collection built from one in the template, such as `todos.reject { ... }`. A
  template that mutates a reactive value no longer marks it dirty. A
  variable's first read now returns the tracked value like later reads, so
  changes made through it are tracked. In component code, `case`,
  `where(hash)` and association assignment still need `to_a`, `to_h` or
  `__getobj__` (gem).
- **A part that passed a reactive variable with hash shorthand (`render
  'badge', page:`) or called it with empty parentheses (`count()`) never
  re-rendered.** The dependency analysis only recognised a bare `page`, so
  these forms (`tag.span(data: { page: })`, `items_path(page:)`, a shorthand
  of a template local set in an earlier part) were left out and the part kept
  its first-render HTML. Any receiverless call with no arguments and no block
  now counts as a read. (gem)
- **A component method's dependencies were lost when another def in the same
  file had the same name.** The method analyzer parses the component's whole
  file and the last def with a given name won, so a `def self.title`, a `class
  << self` method, a method in a nested class or `Struct.new` block, or a
  method of a second class in the file could leave every part calling `title`
  stale. Same-named defs now merge their dependencies, and singleton methods
  are ignored. Affected parts may now re-render where they were previously
  skipped. (gem)
- **Parts reading a non-reactive `shared` variable in a `.live.erb` template
  never re-rendered.** They kept their first-render value even when the
  component re-rendered for its own reasons or wrote the variable itself, so
  the guide's FilterPanel badge example showed a stale count. Whenever a
  component re-renders, parts that read its `shared` variables, directly or
  through a component method, now re-render too. A change to a `shared`
  variable on its own still does not trigger a render. These parts are now
  sent on every re-render of the component. (gem)

## 0.4.0 - 2026-09-29

### Upgrading from 0.3

Upgrade the gem and the npm package together. Defaults are now signed, and
the client forwards them as an opaque string; a 0.3 client sends them as an
object, which the server treats as no defaults at all, so every component
would mount without them.

Pages rendered before the upgrade carry unsigned defaults too. They mount with
no defaults until reloaded, so deploy at a quiet moment, or expect components
on open tabs to come up empty.

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
  location, such as one built with `Class.new`; it falls back to no analyzable
  dependencies (gem).
- `insert_root_attributes` builds a new string instead of mutating the
  rendered part, so a frozen part can't raise `FrozenError`, and its "no root
  element" error now shows the start of the offending output (gem).

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
