# A refused socket: what happens now, and what LiveCable could do about it

*A note from the Sundial work, written against `release-0.5` (2e75dd3). A proposal; no code changes yet.*

## The problem

An application that authenticates its sockets refuses a handshake once the session behind it has gone. With Devise that is `reject_unauthorized_connection` in `connect`. That happens whenever a socket reconnects after:

- a sign-out in another tab;
- a password changed elsewhere;
- a session ended for any other reason the app checks (Sundial also ends sessions when two-factor codes go on or off);
- the app closing the user's sockets on purpose, as the guide's "Other tabs and devices" section recommends (`remote_connections.where(...).disconnect`). The client reconnects by itself, and the new handshake is then refused.

Action Cable's server answers the refused handshake with
`{"type":"disconnect","reason":"unauthorized","reconnect":false}`. The client
(`@rails/actioncable` 8.1, `actioncable.esm.js:255-259`) closes with
`allowReconnect: false`, which stops the connection monitor, and then
tells every subscription:

```js
subscriptions.notifyAll("disconnected", { willAttemptReconnect: false })   // :301-303
```

From then on nothing reconnects. The socket stays closed until something
calls `consumer.connection.open()`.

LiveCable doesn't look at that argument. `Subscription#disconnected`
(`app/assets/javascript/subscriptions.js:655`) handles it exactly like a
dropped connection:

- sets `#confirmed = false`;
- settles lost messages;
- calls `#handleStatus('disconnected')`.

So every component on the page goes into its "disconnected" state and waits
for a reconnect that will never come. Most applications style that state as
a loading or reconnecting panel. In Sundial it read "Loading the day…" and
stayed there, with nothing to say the user had been signed out.

Two related gaps:

1. **A subscription the server rejects is ignored.**
   - **What triggers it:** a channel `reject`, as opposed to a refused handshake. Action Cable answers it with `reject_subscription`, and the client calls the subscription's `rejected` callback (`actioncable.esm.js:406-411`).
   - **What LiveCable does:** `#subscribe()` (`subscriptions.js:614`) passes `connected`, `disconnected` and `received`, but no `rejected`. The component keeps its server-rendered markup, and its status never moves on from what the page rendered.
   - **When it bites:** only for an app whose channel rejects subscriptions. `LiveChannel` itself doesn't today, but `before_subscribe`-style checks might.
2. **Nothing brings a refused socket back.**
   - **The case:** the user signs in again in the same tab, through a Turbo form, so there is no full reload.
   - **What happens:** the identity tag changes, but `SubscriptionManager#syncIdentity` (`subscriptions.js:173-188`) only reopens a socket that is still active (`consumer.connection.isActive()`).
   - **Why it matters:** a refused socket isn't active, so the persistent subscriptions stay dead. That includes a navbar widget that survives the visit.
   - **What still recovers:** a component that subscribes fresh on the new page calls `ensureActiveConnection()` (`actioncable.esm.js:395`), which happens to open it. A page whose only components were kept from the last one gets nothing.

## What Sundial does today (the stopgap)

`app/javascript/refused_socket.js` in Sundial wraps Action Cable's shared
`Subscriptions.prototype.notifyAll`. That's the only place the flag is
visible, because the gem's consumer is private to its module. When it sees
`disconnected` with `willAttemptReconnect: false`, it reloads the page, with
two guards:

- only when a live component is on the page;
- at most once a minute per tab, through `sessionStorage`.

The reload hits the app's HTTP auth, which redirects to sign-in with a message. It works, but:

- **It patches a prototype** the gem doesn't own, and every consumer on the page shares it.
- **It can't tell the cases apart.** It sees "won't reconnect", not why: a server refusal, an app calling `consumer.disconnect()` on purpose, and Action Cable's "unsupported protocol" all look the same (`actioncable.esm.js:288-291`, `:471-474`).
- **A reload is the only answer it can give.** It can't show a signed-out banner in place, or keep what the user was typing.

## What LiveCable could add

Roughly in order of value. Items 1 to 3 together would let Sundial delete its workaround.

### 1. A `refused` status, distinct from `disconnected`

In `Subscription#disconnected`, read the argument Action Cable already passes:

```js
#disconnected = ({ willAttemptReconnect } = {}) => {
  this.#confirmed = false
  if (this.#settleLostMessages()) {
    this.catchUp()
  }
  this.#handleStatus(willAttemptReconnect === false ? 'refused' : 'disconnected')
}
```

What follows from that:

- `data-live-status-value="refused"` is a styling hook apps can use, the way `stalled` is.
- Messages held in `#pending` will never go. Drop them, as `#stalled` does (`discardPending()`), so a later reconnect doesn't send a click the page has given up on.
- In-flight loading states are already settled by `#settleLostMessages()`. With no reconnect coming, any `live-loading` left should be cleared too (`resetLoading()`, as `destroy` does).

### 2. A `live:refused` event, once per page, with the reason when known

Components shouldn't each decide to reload, so the event belongs at the
manager, not per component.

- `SubscriptionManager` dispatches a single bubbling `live:refused` on `document`.
- Its `detail` is `{ reason, components }`, where `components` is the count of live components on the page.
- The application then chooses: reload, show a banner, or `Turbo.visit(signInPath)`.

**The reason.** Action Cable reads `reason` off the `disconnect` frame but only logs it (`actioncable.esm.js:256`). LiveCable owns its consumer (`subscriptions.js:25`), so it can capture the reason without touching the shared prototype. Wrap its own connection's message handler once, at module load:

```js
const shared = consumer.connection.events   // Connection.prototype.events
consumer.connection.events = {
  ...shared,
  message(event) {
    try {
      const frame = JSON.parse(event.data)
      if (frame.type === 'disconnect') lastDisconnect = { reason: frame.reason, reconnect: frame.reconnect }
    } catch {}
    return shared.message.call(this, event)
  },
}
```

Two things make this work:

- **It gets its own object.** `events` is defined on `Connection.prototype` (`actioncable.esm.js:240`), so it is shared by every consumer on the page. Assigning into it would patch them all, which is the same problem the stopgap has. Shadowing it on this one connection instance keeps the change to LiveCable's consumer.
- **It covers every socket.** `installEventHandlers` (`:225-230`) reads `this.events` and binds each handler when each socket opens. Setting it before the first open covers every socket this consumer opens.

With that:

- **`reason: 'unauthorized'`** is a refusal by the app.
- **No disconnect frame before the close** means the close came from the client: `consumer.disconnect()` by the app, or an unsupported protocol. LiveCable could report `reason: null` and let the app ignore it, or not dispatch at all.
- **Server-side reasons** (`'server_restart'`, `'remote'`, `'invalid_request'`, `'unauthorized'`) come from `ActionCable::INTERNAL[:disconnect_reasons]`.

**A built-in default would also do**, and is less code for every app. For example, `LiveCable.configure({ onRefused: 'reload' | 'event' | fn })`, defaulting to `'event'`. I'd keep the event as the primitive either way.

### 3. Recover when the identity changes, even if the socket is closed

In `syncIdentity()`, open a socket that isn't active, as well as reopening an active one:

```js
if (this.#identity && identity !== this.#identity) {
  consumer.connection.isActive() ? consumer.connection.reopen() : consumer.connection.open()
}
```

`open()` restarts the monitor, and the `welcome` frame runs `subscriptions.reload()` (`actioncable.esm.js:248-253`). Every kept subscription then resubscribes as the new identity, and each component leaves `refused` on its first render.

This is what makes the in-place banner possible: the user signs in again in the same tab, and the page comes back to life without a reload.

### 4. Handle `rejected`

Pass a `rejected` callback in `#subscribe()` that:

- sets a `rejected` status;
- settles loading states;
- removes the subscription from the manager, since Action Cable has already forgotten it (`actioncable.esm.js:408`);
- dispatches `live:rejected` on the component's element.

Today a rejected component sits on whatever the page rendered.

### 5. Docs

The guide's "Sign-in, Sign-out and Revocation" section should say what a
refused socket looks like on the client:

- the `refused` status;
- the event;
- the recommended handler: reload, or show "You've been signed out" with a sign-in link;
- that refusal is final until the page reloads or the identity tag changes.

It's the natural next paragraph after the remote-disconnect advice there, since that advice is what produces refusals.

## Tests (vitest, `test/subscriptions.test.js`)

- **The refused status:** `disconnected({ willAttemptReconnect: false })` gives status `refused`, discards pending messages and clears `live-loading`. `{ willAttemptReconnect: true }` and no argument give `disconnected`, as now.
- **One event per page:** a refusal with three components on the page dispatches `live:refused` once.
- **The reason:** a `disconnect` frame with `reason: 'unauthorized'` before the close puts `reason: 'unauthorized'` in `detail`. A close with no frame gives `reason: null`.
- **Recovery:** `syncIdentity()` with a new digest calls `open()` on an inactive connection and `reopen()` on an active one.
- **Rejection:** `rejected` sets status `rejected`, removes the subscription from the manager and dispatches `live:rejected`.

And a system spec in `spec/system`, if the dummy app can authenticate its
socket:

1. Sign in, and mount a component.
2. Disconnect the user's connections server-side, and invalidate the session so the reconnect is refused.
3. Assert the component reaches `refused`, and the event fires.

## What Sundial would do with it

- Delete `app/javascript/refused_socket.js`.
- Listen for `live:refused`:
  - with `reason === 'unauthorized'`, show the signed-out banner, which Sundial already renders over HTTP;
  - or `Turbo.visit` the sign-in page, which keeps the "back to this page" behaviour Devise's stored location gives.
- Style `[data-live-status-value=refused]` so components stop showing "Loading…".

## Open questions

- **Event or default?** Should the default be an event (the app decides), or a reload, so an app that does nothing still recovers? A reload is what most apps want, and a silent stuck page is the worst outcome. I lean towards event plus a one-line documented handler, with no default reload, because the gem can't know whether a reload would lose typed work.
- **Client-side closes:** should a `consumer.disconnect()` by the app itself raise `live:refused`? Probably not, or only with `reason: null`. An app that disconnects on purpose knows it did.
- **The 0.4 server:** none of this needs a server change. The gem and npm package stay compatible in both directions, as the 0.5 changelog promises.

## Addendum (2026-10-26): a component refused for lost access

Sundial pass 9 found a second shape of the same problem. A component whose `before_dispatch` (or a `stream_from` callback) raises, because the person's membership was deactivated, their impersonation ran out or the account was deleted while the page was open, goes through `Connection::ErrorHandling#handle_error`. In production that shows the bare "An error occurred" box (`error_handling.rb:54-66`).

Sundial now closes the whole connection with `reconnect: false` from `Live::Tenanted#authorize_account_or_close!` and lets `refused_socket.js` reload. That is a workaround. Two things the gem could offer instead:

- **An error-template hook:** `LiveCable.configure { |c| c.error_renderer = ->(component, error) { … } }`, so an app can render "You no longer have access to this account — reload" for `Authorized::Forbidden`/`RecordNotFound` and keep the default box for everything else.
- **A refusal primitive** for callbacks, such as `refuse!(reason)`. It would broadcast a `_refused` message rather than `_error`, set the `refused` status proposed above, and dispatch `live:refused` with that reason. The app's one `live:refused` handler would then cover both a refused handshake and a refused component.
