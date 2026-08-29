# Loading States

Every LiveCable interaction is a round trip to the server, and on a slow connection that round trip is visible to the user. Loading states give you immediate visual feedback while a message is in flight: spinners, dimmed content, and disabled buttons that can't be double-clicked.

LiveCable tracks in-flight messages automatically. While a component is waiting for a server response, it exposes that state in the DOM so you can style it with plain CSS — no JavaScript required.

## The `live-loading` Attribute

When a component sends an action, form submission, or reactive update to the server, LiveCable adds a `live-loading` attribute to:

- The **component's root element**
- The **element that triggered** the message (the button, form, or input)

The attribute is removed when the server answers the message — with the component's own re-render, an error, or an acknowledgement.

Style loading states with CSS attribute selectors:

```css
/* Dim the triggering button while its action is in flight */
button[live-loading] {
  opacity: 0.5;
  cursor: wait;
}

/* Show a spinner inside the component while anything is in flight */
.spinner {
  display: none;
}

[live-loading] .spinner {
  display: inline-block;
}
```

```erb
<div>
  <h2>Search <span class="spinner">⏳</span></h2>

  <input type="text" name="query" value="<%= query %>" live-reactive live-debounce="300">

  <button live-action="refresh">Refresh</button>
</div>
```

::: tip
`live-loading` is a styling hook, not a directive — you never write it in your templates yourself. LiveCable adds and removes it at runtime.
:::

## The `live-disable-with` Attribute

For buttons that shouldn't be clicked twice, add `live-disable-with`. While the message is in flight, the element is disabled; when the server responds, it's restored:

```erb
<button live-action="checkout" live-disable-with>
  Checkout
</button>
```

Give the attribute a value to also swap the button's label while it's disabled:

```erb
<button live-action="checkout" live-disable-with="Processing...">
  Checkout
</button>
```

This works on `<button>` elements (swaps the text content) and on `<input type="submit">` elements (swaps the `value`).

### Forms

For forms, put `live-disable-with` on the submit button(s) inside the form. When the form is submitted, every marked element inside it is disabled until the response arrives:

```erb
<form live-form="save">
  <input type="text" name="title">

  <button type="submit" live-disable-with="Saving...">Save</button>
</form>
```

Form values are serialized *before* the buttons are disabled, so `live-disable-with` never affects the submitted data.

### Reactive Inputs

Reactive updates (`live-reactive`) set the `live-loading` attribute on the component root and the input, but never disable the input — disabling a focused text field would interrupt typing. Use the attribute selector if you want a subtle pending indicator:

```css
input[live-loading] {
  background-image: url("spinner.svg");
  background-position: right 8px center;
  background-repeat: no-repeat;
}
```

## How It Works

1. When the controller sends a message, it increments an in-flight counter, marks the root and trigger with `live-loading`, and processes any `live-disable-with` elements.
2. The server processes the message and responds with exactly one of:
   - its own **re-render** (`_refresh`) if a part of its template needs re-rendering,
   - an **acknowledgement** (`_ack`) if none does (nothing changed, or nothing the template reads), or if the component's re-render went out as part of its parent's, or
   - an **error** (`_error`) if the action raised.
3. When the response arrives, the counter is decremented. Once all in-flight messages are answered, the `live-loading` attributes are removed and disabled elements are restored — immediately before the new HTML is morphed in, so the server-rendered state always wins. An acknowledgement leaves the DOM as it is, unless a render of the component arrived while the message waited: the pending elements skipped it, so the acknowledgement morphs it in again.

If several messages are in flight at once (for example, two different buttons clicked in quick succession), the loading state is only cleared after **all** of them have been answered.

::: info Server-pushed updates
A re-render the component didn't ask for — a `stream_from` broadcast, or a shared variable changed by another component's action — is not a response. It is morphed in as usual, except for the elements awaiting a reply: they keep their `live-loading` and `live-disable-with` state, and catch up once the loading state ends, so another user's chat message can't re-enable your Send button before your own message has been answered. The same holds for a component nested in another: a re-render of the parent leaves the child's pending elements, and the `live-loading` on its root, alone until the child is answered.
:::

## While the Connection Is Down

A message sent while the WebSocket is closed - after a laptop wakes, during a
network blip, while a deploy restarts the server - isn't lost. LiveCable holds
it, keeps the loading state on, and sends it once ActionCable has reconnected
and the server has confirmed the component's subscription. Messages held this
way go out in the order they were sent.

While the socket is down the component's root carries
`data-live-status-value="disconnected"`, so you can say so. The page as the
server renders it carries `disconnected` too, until each component's
subscription is confirmed, so wait a moment before showing it, or every page
load will flash:

```css
@keyframes live-dim { to { opacity: 0.6; } }

[data-live-status-value="disconnected"] {
  animation: live-dim 0.2s 1s forwards;
}
```

Only a message the socket refused is held. One that was sent and simply never
answered - the server stopped while running it, or the socket closed first -
is not sent again, because there's no telling whether it ran. Its reply was
bound for the old socket and can't arrive, so its loading state ends when the
socket closes, or at the latest when the component re-subscribes. A held
message keeps its loading state until its own reply arrives.

## When No Reply Comes

If a component gets no reply for 30 seconds while a message is in flight, the
loading state gives up: it restores the DOM, morphs in any render that arrived
meanwhile, sets `data-live-status-value="stalled"`, and dispatches a bubbling
`live:stalled` event from the component's root. That covers a reply that is
never coming - the server stopped while running the message - which would
otherwise leave a button disabled until the page was reloaded. Messages still
held when a component's element is replaced, by a Turbo navigation say, keep
the loading state on the new element, and the 30 seconds start again from
there.

Anything still held for a reconnect is dropped at the same moment, so a
message the page has said didn't go through can't go through later. A message
that was already sent can't be recalled, and may have run; `event.detail.discarded`
is how many were dropped, so you can word it accordingly:

```javascript
document.addEventListener('live:stalled', (event) => {
  showNotice("That didn't go through. Check your connection and try again.")
})
```

Change the wait before any component connects:

```javascript
import LoadingState from "@isometriks/live_cable/loading"

LoadingState.timeout = 60_000
```

A reply that arrives after the component gave up is still applied - a
re-render morphs in as usual - it just no longer has a loading state to clear.

## Component Status

A component's root always carries one of these in `data-live-status-value`:

| Value | When |
|---|---|
| `disconnected` | The page as the server rendered it, until the component's subscription is confirmed; and whenever the socket is down |
| `subscribed` | The subscription is confirmed and the component is live |
| `stalled` | A message got no reply in time, as above |
| `destroy` | The server destroyed the component; it no longer sends or receives anything |
