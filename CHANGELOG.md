# Changelog

All notable changes to this project are documented in this file.

The Ruby gem (`live_cable`) and the npm package (`@isometriks/live_cable`) are
released together and share a single version number. Entries below note which
side of the pair a change affects when it isn't both.

## Unreleased

### Fixed

- **A message could be refused with no answer, leaving the component stuck in
  its loading state.** `LiveChannel#receive` had no rescue of its own, so
  anything raised before an action's own rescue — the CSRF check, a component
  that failed to subscribe — went to ActionCable, which only logs it. The
  client holds `live-loading` and `live-disable-with` until it hears back, so
  the button stayed disabled until a reload. Every batch is now answered with a
  `_refresh`, `_ack`, `_error` or `_reconnect`, and a subscribe that cannot
  build a component transmits an `_error` instead of failing silently (gem).
- **Every message on a socket was refused once the session's CSRF token
  rotated.** Tokens are verified against the session the socket captured at its
  handshake, and a socket never sees cookies set after it opened. Devise rotates
  the token on every sign-in (`clean_up_csrf_token_on_authentication`), so a
  sign-in in another tab — or in the same tab, after the session expired — left
  every page rendered from then on carrying a token the socket could not verify,
  until the socket itself reconnected. The server now answers such a batch with
  `_reconnect` instead of an error. The client re-opens the socket so the new
  handshake carries the current cookie; while re-subscribing, the server hands
  each component a token minted from the fresh socket's session, which the
  client puts on the page's meta tag and replays the refused batch with. No
  HTTP request or re-render is involved. Nothing in a refused batch ran, so the
  replay cannot double-apply it, and the loading state stays up until the
  replay is answered. Nothing is ever reloaded: should the replay be refused
  as well, the client clears the loading state, leaves the DOM as it is, and
  dispatches a `live:rejected` event from the component (gem + npm).

### Added

- `LiveChannel#subscribed` transmits `_csrf_token`, a token for the socket's
  session, when the handshake came from the application's own origin or one
  in `allowed_request_origins`. LiveCable checks the origin itself, so the
  token is as hard to obtain as the page's meta tag even where
  `disable_request_forgery_protection` is set (gem).
- `live:rejected`, a bubbling DOM event dispatched from a component's root
  element when a message batch could not be delivered even after reconnecting;
  `event.detail.messages` holds the batch (npm).

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
