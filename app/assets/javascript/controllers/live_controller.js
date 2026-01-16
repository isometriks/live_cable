import { Controller } from "@hotwired/stimulus"
import SubscriptionManager from "live_cable_subscriptions"

export default class extends Controller {
  static values = {
    defaults: Object,
    status: String,
    component: String,
    actions: Array,
    id: String,
  }

  #subscription
  #debounces = new Map()

  #callActionCallback = (event) => {
    event.stopPropagation()

    const { action, params } = event.detail

    this.sendCall(action, params)
  }

  connect() {
    this.element.addEventListener("call", this.#callActionCallback)

    this.#subscription = SubscriptionManager.subscribe(
      this.idValue,
      this.componentValue,
      this.defaultsValue,
      this
    )

    // Create callbacks for each action or form
    this.actionsValue.forEach((action) => {
      this[`action_$${action}`] = ({ params }) => {
        this.sendCall(action, this.#convertKeysToSnakeCase(params))
      }

      this[`form_$${action}`] = (event) => {
        this.#form(action, event)
      }
    })
  }

  disconnect() {
    this.element.removeEventListener("call", this.#callActionCallback)
  }

  sendCall(action, params = {}) {
    this.#subscription.send(
      this.#flushDebounced(this.#callMessage(params, action))
    )
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

    const formData = new FormData(formEl)
    const params = new URLSearchParams(formData).toString()

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
