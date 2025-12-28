import { Controller } from "@hotwired/stimulus"
import SubscriptionManager from "live_cable_subscriptions"

export default class extends Controller {
  static values = {
    defaults: Object,
    status: String,
    component: String,
    id: String,
  }

  #subscription
  #formDebounce
  #reactiveDebounce
  #reactiveDebouncedMessage

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
  }

  disconnect() {
    this.element.removeEventListener("call", this.#callActionCallback)
  }

  call({ params }) {
    this.sendCall(params.action, params)
  }

  sendCall(action, params = {}) {
    this.#subscription.send(
      this.#unshiftDebounced(this.#callMessage(params, action))
    )
  }

  #callMessage(params, action) {
    return {
      _action: action,
      params: new URLSearchParams(params).toString(),
    }
  }

  reactive({ target }) {
    this.sendReactive(target)
  }

  sendReactive(target) {
    this.#subscription.send(
      this.#unshiftDebounced(this.#reactiveMessage(target))
    )
  }

  #reactiveMessage(target) {
    return {
      _action: '_reactive',
      name: target.name,
      value: target.value,
    }
  }

  #unshiftDebounced(message) {
    const messages = [message]

    if (this.#reactiveDebouncedMessage) {
      messages.unshift(this.#reactiveDebouncedMessage)
      this.#reactiveDebouncedMessage = null
    }

    return { messages, _csrf_token: this.#csrfToken }
  }

  reactiveDebounce(event) {
    clearTimeout(this.#reactiveDebounce)
    this.#reactiveDebouncedMessage = this.#reactiveMessage(event.target)

    this.#reactiveDebounce = setTimeout(() => {
      this.#reactiveDebouncedMessage = null
      this.reactive(event)
    }, event.params.debounce || 200)
  }

  form({ currentTarget, params: { action } }) {
    this.sendForm(action, currentTarget)
  }

  sendForm(action, formEl) {
    // Clear reactive debounce so it doesn't fire after form
    clearTimeout(this.#reactiveDebounce)
    clearTimeout(this.#formDebounce)

    const formData = new FormData(formEl)
    const params = new URLSearchParams(formData).toString()

    this.#subscription.send(
      this.#unshiftDebounced(this.#callMessage(params, action))
    )
  }

  formDebounce(event) {
    clearTimeout(this.#formDebounce)
    this.#formDebounce = setTimeout(() => {
      this.form(event)
    }, event.params.debounce || 200)
  }

  get #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
  }
}
