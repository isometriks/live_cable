/**
 * Loading state tracking for LiveCable components.
 *
 * Tracks in-flight messages for a single component and reflects them in the
 * DOM so users can style pending states with CSS:
 *
 * - The component root element gets a `live-loading` attribute while any
 *   message is awaiting a server response.
 * - The element that triggered the message (button, form, input) also gets
 *   a `live-loading` attribute.
 * - Elements with a `live-disable-with` attribute are disabled while the
 *   message is in flight. If the attribute has a value, the element's label
 *   (textContent, or value for inputs) is swapped for it.
 *
 * The state is cleared when the server responds with a refresh, an error,
 * or an ack (sent when an action didn't change any reactive variables).
 * Multiple in-flight messages are counted; the DOM is only restored once
 * all of them have been answered.
 *
 * If nothing is heard for `LoadingState.timeout` milliseconds while a message
 * is in flight, the state gives up: it resets and calls `onStalled`. That is
 * the backstop for a reply that is never coming - the server stopped while
 * running the message, say - which would otherwise leave a button disabled
 * until the page is reloaded.
 */
export default class LoadingState {
  /**
   * Milliseconds to wait for any reply before giving up. Long enough to
   * cover a reconnect after a deploy, since messages held for one count too.
   * Set it before components connect to change it everywhere.
   * @type {number}
   */
  static timeout = 30_000

  /** @type {HTMLElement} */
  #root
  /** @type {number} */
  #inFlight = 0
  /** @type {Set<Element>} - Elements marked with the live-loading attribute */
  #markedElements = new Set()
  /** @type {Map<Element, Object>} - Original state of disabled elements */
  #disabledElements = new Map()
  /** @type {Function|null} */
  #onStalled
  /** @type {number|null} */
  #timer = null

  /**
   * @param {HTMLElement} root - The component's root element
   * @param {Object} options
   * @param {Function} [options.onStalled] - Called after the state gives up
   *   waiting and resets itself
   */
  constructor(root, { onStalled = null } = {}) {
    this.#root = root
    this.#onStalled = onStalled
  }

  /**
   * Whether any message is currently awaiting a server response.
   * @returns {boolean}
   */
  get active() {
    return this.#inFlight > 0
  }

  /**
   * Mark the component as loading.
   * Called right before a message is sent to the server.
   *
   * @param {Element|null} trigger - The element that triggered the message
   * @param {Object} options
   * @param {boolean} options.disable - Whether to process live-disable-with
   *   elements. Disabled for reactive inputs so typing doesn't lose focus.
   */
  start(trigger = null, { disable = true } = {}) {
    this.#inFlight++
    this.#arm()

    this.#mark(this.#root)

    if (trigger instanceof Element && trigger !== this.#root) {
      this.#mark(trigger)

      if (disable) {
        this.#disableElements(trigger)
      }
    }
  }

  /**
   * Record a server response for this component.
   * Restores the DOM once all in-flight messages have been answered.
   *
   * @returns {boolean} true if the loading state was fully cleared
   */
  finish() {
    if (this.#inFlight === 0) {
      return false
    }

    this.#inFlight--

    if (this.#inFlight > 0) {
      // Still waiting on others, but the server is evidently answering
      this.#arm()
      return false
    }

    this.#disarm()
    this.#restore()
    return true
  }

  /**
   * Clear all loading state immediately, regardless of in-flight count.
   * Used when the component is being torn down (e.g. on error).
   */
  reset() {
    this.#inFlight = 0
    this.#disarm()
    this.#restore()
  }

  #arm() {
    this.#disarm()
    this.#timer = setTimeout(() => this.#stall(), LoadingState.timeout)
  }

  #disarm() {
    clearTimeout(this.#timer)
    this.#timer = null
  }

  #stall() {
    this.#timer = null
    this.reset()
    this.#onStalled?.()
  }

  #mark(element) {
    element.setAttribute('live-loading', '')
    this.#markedElements.add(element)
  }

  /**
   * Disable the trigger and/or its descendants marked with live-disable-with.
   * For a button the attribute lives on the button itself; for a form it
   * usually lives on the submit button(s) inside it.
   */
  #disableElements(trigger) {
    const elements = []

    if (trigger.hasAttribute('live-disable-with')) {
      elements.push(trigger)
    }

    elements.push(...trigger.querySelectorAll('[live-disable-with]'))

    elements.forEach(element => {
      // Already disabled by an earlier in-flight message
      if (this.#disabledElements.has(element)) {
        return
      }

      const text = element.getAttribute('live-disable-with')
      const isInput = element instanceof HTMLInputElement

      this.#disabledElements.set(element, {
        disabled: element.disabled,
        content: text ? (isInput ? element.value : element.textContent) : null,
      })

      element.disabled = true

      if (text) {
        if (isInput) {
          element.value = text
        } else {
          element.textContent = text
        }
      }
    })
  }

  #restore() {
    this.#markedElements.forEach(element => {
      element.removeAttribute('live-loading')
    })
    this.#markedElements.clear()

    this.#disabledElements.forEach(({ disabled, content }, element) => {
      element.disabled = disabled

      if (content !== null) {
        if (element instanceof HTMLInputElement) {
          element.value = content
        } else {
          element.textContent = content
        }
      }
    })
    this.#disabledElements.clear()
  }
}
