# Loading States

Every LiveCable interaction is a round trip to the server, and on a slow connection that round trip is visible to the user. Loading states give you immediate visual feedback while a message is in flight: spinners, dimmed content, and disabled buttons that can't be double-clicked.

LiveCable tracks in-flight messages automatically. While a component is waiting for a server response, it exposes that state in the DOM so you can style it with plain CSS — no JavaScript required.

## The `live-loading` Attribute

When a component sends an action, form submission, or reactive update to the server, LiveCable adds a `live-loading` attribute to:

- The **component's root element**
- The **element that triggered** the message (the button, form, or input)

The attribute is removed as soon as the server responds — whether that response is a re-render, an error, or an acknowledgement that nothing changed.

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
   - a **re-render** (`_refresh`) if reactive variables changed,
   - an **acknowledgement** (`_ack`) if nothing changed, or
   - an **error** (`_error`) if the action raised.
3. When the response arrives, the counter is decremented. Once all in-flight messages are answered, the `live-loading` attributes are removed and disabled elements are restored — immediately before the new HTML is morphed in, so the server-rendered state always wins.

If several messages are in flight at once (for example, two different buttons clicked in quick succession), the loading state is only cleared after **all** of them have been answered.

::: info Server-pushed updates
A re-render triggered from outside the normal request cycle — such as a `stream_from` broadcast or a shared variable changed by another component — also counts as a response and can clear the loading state early. This is harmless: the morph restores the correct DOM either way.
:::
