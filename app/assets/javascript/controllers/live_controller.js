import { Controller } from "@hotwired/stimulus"
import SubscriptionManager from "@isometriks/live_cable/subscriptions"
import LoadingState from "@isometriks/live_cable/loading"

export default class extends Controller {
  static values = {
    // Opaque signed blob produced by the server; forwarded verbatim to the
    // channel on subscribe, where it is verified and decoded.
    defaults: String,
    status: String,
    component: String,
    actions: Array,
    id: String,
  }

  #subscription
  #debounces = new Map()
  #loading

  #callActionCallback = (event) => {
    event.stopPropagation()

    const { action, params } = event.detail

    this.sendCall(action, params, event.target)
  }

  connect() {
    this.#loading = new LoadingState(this.element)
    this.element.addEventListener("call", this.#callActionCallback)

    this.#subscription = SubscriptionManager.subscribe(
      this.idValue,
      this.componentValue,
      this.defaultsValue,
      this
    )

    // Create callbacks for each action or form
    this.actionsValue.forEach((action) => {
      this[`action_$${action}`] = ({ params, currentTarget }) => {
        this.sendCall(action, this.#convertKeysToSnakeCase(params), currentTarget)
      }

      this[`form_$${action}`] = (event) => {
        this.#form(action, event)
      }
    })
  }

  disconnect() {
    this.element.removeEventListener("call", this.#callActionCallback)
  }

  sendCall(action, params = {}, trigger = null) {
    this.#loading.start(trigger)
    this.#subscription.send(
      this.#flushDebounced(this.#callMessage(params, action))
    )
  }

  // Called by the subscription when the server answers a message
  // (refresh, ack, or error). Restores any live-loading / live-disable-with
  // state once all in-flight messages have been answered.
  finishLoading() {
    this.#loading?.finish()
  }

  // Whether any message is still awaiting a server response
  get isLoading() {
    return this.#loading?.active ?? false
  }

  // Called by the subscription when the component is being torn down.
  resetLoading() {
    this.#loading?.reset()
  }

  #callMessage(params, action) {
    return {
      _action: action,
      params: new URLSearchParams(params).toString(),
    }
  }

  #convertKeysToSnakeCase(params) {
    return Object.fromEntries(
      Object.entries(params).map(([key, value]) => [
        key.replace(/([A-Z])/g, '_$1').toLowerCase(),
        value
      ])
    )
  }

  reactive({ target, params }) {
    const debounce = params?.debounce

    if (debounce) {
      this.#setDebounce(target, debounce, () => {
        this.sendReactive(target)
      }, this.#reactiveMessage(target))
    } else {
      this.sendReactive(target)
    }
  }

  sendReactive(target) {
    this.#clearDebounce(target)
    // Never disable reactive inputs while in flight - it would drop focus
    this.#loading.start(target, { disable: false })
    this.#subscription.send(
      this.#flushDebounced(this.#reactiveMessage(target))
    )
  }

  #reactiveMessage(target) {
    return {
      _action: '_reactive',
      name: target.name,
      value: target.value,
    }
  }

  #form(action, { currentTarget, params }) {
    const debounce = params.debounce

    if (debounce) {
      const formData = new FormData(currentTarget)
      const formParams = new URLSearchParams(formData).toString()

      this.#setDebounce(currentTarget, debounce, () => {
        this.sendForm(action, currentTarget)
      }, this.#callMessage(formParams, action))
    } else {
      this.sendForm(action, currentTarget)
    }
  }

  sendForm(action, formEl) {
    this.#clearDebounce(formEl)

    // Serialize before starting the loading state - disabled controls
    // (live-disable-with) are excluded from FormData
    const formData = new FormData(formEl)
    const params = new URLSearchParams(formData).toString()

    this.#loading.start(formEl)

    this.#subscription.send(
      this.#flushDebounced(this.#callMessage(params, action))
    )
  }

  #setDebounce(source, delay, callback, message) {
    // Clear existing debounce for this source
    this.#clearDebounce(source)

    // Set new debounce
    const timeout = setTimeout(callback, delay)
    this.#debounces.set(source, { timeout, message })
  }

  #clearDebounce(source) {
    const debounce = this.#debounces.get(source)
    if (debounce) {
      clearTimeout(debounce.timeout)
      this.#debounces.delete(source)
    }
  }

  #flushDebounced(message) {
    const messages = [message]

    // Add all pending debounced messages to be sent immediately
    for (const [source, { timeout, message: debouncedMessage }] of this.#debounces) {
      clearTimeout(timeout)
      messages.unshift(debouncedMessage)
    }
    this.#debounces.clear()

    return { messages, _csrf_token: this.#csrfToken }
  }

  get #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
  }
}
