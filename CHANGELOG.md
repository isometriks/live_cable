# Changelog

All notable changes to this project are documented in this file.

The Ruby gem (`live_cable`) and the npm package (`@isometriks/live_cable`) are
released together and share a single version number. Entries below note which
side of the pair a change affects when it isn't both.

## Unreleased

### Performance

- **No-op renders are no longer broadcast.** When a reactive variable changed but
  no rendered template part depended on it, the component still rendered and sent
  a `_refresh` whose parts were all empty, costing a WebSocket message and a full
  client-side rebuild + morph for no visible change. This was common when a shared
  reactive variable updated but a given component didn't display it. Such renders
  are now detected and skipped; queued events are still delivered and the client
  still receives an `_ack` (gem).
- **The view context is reused per connection.** `Component#render` went through
  `ActionController::Renderer`, which built a fresh controller, request, and view
  context on every render — roughly 38% of render time in a head-to-head
  benchmark. On the WebSocket path none of that per-request state is meaningful,
  so a single view context is now built per connection and reused (renders are
  already serialized by the connection lock). The initial page pre-render is
  unchanged (gem).

### Security

- **Signed reactive-variable defaults.** Defaults set on the server by the
  `live(...)` helper are emitted into the page and re-sent by the client on
  subscribe. Because that value round-trips through the browser, a user could
  edit it (or craft the subscribe frame) to set reactive variables that were
  deliberately not marked `writable:` — a record id, price, or tenant key. The
  `_reactive` message path enforced writability; this path did not. Defaults are
  now signed with `secret_key_base`, bound to the component's `live_id`, and
  verified before they are applied, so a tampered or replayed blob yields no
  defaults (`LiveCable::DefaultsSigner`). The JS forwards the now-opaque blob
  verbatim, so this is gem-side; the npm package is unchanged and compatible
  (gem).
- **`config.require_csrf_token`.** CSRF validation was silently skipped when the
  session carried no token, with no way to require one. Setting this option (off
  by default) rejects any message that lacks a verifiable token (gem).

### Added

- **`rescue_from` in components.** Components can now declare `rescue_from` (from
  `ActiveSupport::Rescuable`, which was included but never consulted) to handle
  their own errors instead of being replaced with the default error markup. Any
  reactive state the handler sets is re-rendered in the same cycle (gem).

### Changed

- Framework warnings (a component rendered without a `.live.erb` template, a
  missing `app/live` directory) now go through the Rails logger at most once per
  message per process, instead of `Kernel#warn` to stderr on every render (gem).

### Fixed

- **Client-message actions and reactive updates on a shared connection could
  race.** A single `LiveCable::Connection` is shared by every component
  subscription on one socket, and ActionCable dispatches that connection's
  commands — and stream-broadcast callbacks — on a shared worker-thread pool.
  The shared component/container state was mutated from those threads without
  synchronization. Access is now serialized per connection with a re-entrant
  lock (gem).
- **Component names that collide with a top-level constant failed obscurely.**
  `instance_from_string` used `const_defined?`, which inherits, so a name like
  `"string"` (`::String`) slipped past the "not found" guard and raised a
  confusing `NoMethodError` — which made `LiveChannel#subscribed` fail silently.
  It now raises the intended `LiveCable::Error` (gem).
- **Events dispatched by a child rendered inline by its parent were dropped.**
  Such a child has no channel of its own yet; its queued events were flushed and
  then discarded. They now stay queued and are delivered when the child's own
  subscription connects (gem).
- `MethodAnalyzer` no longer raises for a component class with no Ruby source
  location (an anonymous class, or one built with `Class.new`); it falls back to
  no analyzable dependencies (gem).
- `insert_root_attributes` builds a new string instead of mutating the rendered
  part in place, so a frozen part can't raise `FrozenError`, and its "no root
  element" error now includes a preview of the offending output (gem).

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
