import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import morphdom from "morphdom"

// Create a shared consumer
const consumer = createConsumer()

export default class extends Controller {
  static values = {
    defaults: Object,
    status: String,
    component: String,
  }

  #subscription
  #formDebounce
  #reactiveDebounce
  #reactiveDebouncedMessage

  connect() {
    this.#subscription = consumer.subscriptions.create({
      channel: "LiveChannel",
      component: this.componentValue,
      defaults: this.defaultsValue,
    }, {
      received: (data) => {
        if (data['_status']) {
          this.statusValue = data['_status']
        } else if (data['_refresh']) {
          morphdom(this.element, '<div>' + data['_refresh'] + '</div>', {
            childrenOnly: true,
          })
        }
      },
    })
  }

  call({ params }) {
    this.#subscription.send(
      this.#unshiftDebounced(this.#callMessage(params, params.action))
    )
  }

  #callMessage(params, action) {
    return {
      _action: action,
      params: new URLSearchParams(params).toString(),
      _csrf_token: this.#csrfToken,
    }
  }

  reactive({ target }) {
    this.#subscription.send(
      this.#unshiftDebounced(this.#reactiveMessage(target))
    )
  }

  #reactiveMessage(target) {
    return {
      _action: '_reactive',
      name: target.name,
      value: target.value,
      _csrf_token: this.#csrfToken,
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
    // Clear reactive debounce so it doesn't fire after form
    clearTimeout(this.#reactiveDebounce)

    const formData = new FormData(currentTarget)
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
