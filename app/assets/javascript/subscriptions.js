/**
 * LiveCable Subscription Manager
 *
 * This module implements subscription persistence for LiveCable components.
 * Instead of creating new ActionCable subscriptions every time a Stimulus controller
 * connects/disconnects, we maintain a single subscription per component instance
 * (identified by liveId) and simply update the controller reference.
 *
 * Architecture:
 * - SubscriptionManager: Singleton that manages all active subscriptions
 * - Subscription: Wraps an ActionCable subscription and handles morphdom updates
 * - Controller reconnection: When a controller disconnects/reconnects (e.g., due to
 *   Turbo navigation), the subscription persists and just updates its controller reference
 *
 * Benefits:
 * - Reduces WebSocket churn
 * - Maintains server-side state across page transitions
 * - Eliminates race conditions from rapid connect/disconnect cycles
 */

import { createConsumer } from "@rails/actioncable"
import morphdom from "morphdom"
import DOM from "live_cable_dom"

const consumer = createConsumer()

/**
 * Manages all LiveCable subscriptions across the application.
 * Ensures that each component (identified by liveId) has at most one
 * active ActionCable subscription at any time.
 */
class SubscriptionManager {
  /** @type {Object.<string, Subscription>} */
  #subscriptions = {}

  /**
   * Subscribe to or reconnect to a LiveCable component.
   * If a subscription already exists for this liveId, updates the controller
   * reference instead of creating a new subscription.
   *
   * @param {string} id - Raw ID for the component (e.g., "room-1")
   * @param {string} component - Component class name (e.g., "chat/chat_room")
   * @param {Object} defaults - Default values for reactive variables
   * @param {Object} controller - Stimulus controller instance
   * @returns {Subscription} The subscription instance
   */
  subscribe(id, component, defaults, controller) {
    const liveId = `${component}/${id}`

    if (!this.#subscriptions[liveId]) {
      this.#subscriptions[liveId] = new Subscription(id, component, defaults, controller)
    }

    this.#subscriptions[liveId].controller = controller

    return this.#subscriptions[liveId]
  }

  /**
   * Remove a subscription from the manager.
   * Called when the server sends a 'destroy' status, indicating the
   * component instance should be permanently removed.
   *
   * @param {string} liveId - Unique identifier for the component instance
   */
  unsubscribe(liveId) {
    delete this.#subscriptions[liveId]
  }
}

/**
 * Represents a single ActionCable subscription to a LiveCable component.
 * Handles receiving updates from the server and applying them to the DOM
 * via morphdom.
 */
class Subscription {
  /** @type {string} */
  #id
  /** @type {string} */
  #component
  /** @type {Object} */
  #defaults
  /** @type {Object|null} */
  #controller
  /** @type {Object} */
  #subscription

  #parts
  /**
   * Creates a new subscription to a LiveCable component.
   *
   * @param {string} id - Raw ID for the component (e.g., "room-1")
   * @param {string} component - Component class name (e.g., "chat/chat_room")
   * @param {Object} defaults - Default values for reactive variables
   * @param {Object} controller - Stimulus controller instance
   */
  constructor(id, component, defaults, controller) {
    this.#id = id
    this.#component = component
    this.#defaults = defaults
    this.#controller = controller
    this.#parts = []
    this.#subscribe()
  }

  /**
   * Update the controller reference.
   * Called when a Stimulus controller reconnects to an existing subscription.
   *
   * @param {Object} controller - Stimulus controller instance
   */
  set controller(controller) {
    this.#controller = controller
  }

  /**
   * Send a message to the server through the ActionCable subscription.
   *
   * @param {Object} message - Message to send (e.g., action calls, reactive updates)
   */
  send(message) {
    this.#subscription.send(message)
  }

  /**
   * Create the underlying ActionCable subscription.
   * @private
   */
  #subscribe() {
    this.#subscription = consumer.subscriptions.create({
      channel: "LiveChannel",
      id: this.#id,
      component: this.#component,
      defaults: this.#defaults,
    }, {
      received: this.#received,
    })
  }

  /**
   * Handle incoming messages from the server.
   * Processes status updates and DOM refreshes.
   *
   * @param {Object} data - Data received from the server
   * @param {string} [data._status] - Status update (e.g., 'subscribed', 'destroy')
   * @param {string} [data._refresh] - HTML to morph into the DOM
   * @private
   */
  #received = (data) => {
    // Handle destroy status - permanently remove this subscription
    if (data['_status'] === 'destroy') {
      this.#subscription.unsubscribe()
      const liveId = `${this.#component}/${this.#id}`
      subscriptionManager.unsubscribe(liveId)
    }

    // If no controller is attached, we can't update the DOM
    if (!this.#controller) {
      return
    }

    // Update connection status
    if (data['_status']) {
      this.#controller.statusValue = data['_status']
    }
    // Apply DOM updates via morphdom
    else if (data['_refresh']) {
      const refresh = this.#createRefresh(data['_refresh'])

      morphdom(this.#controller.element, this.#prepareRefresh(refresh), {
        // Preserve elements marked with live-ignore attribute
        onBeforeElUpdated(fromEl, toEl) {
          return fromEl.hasAttribute && !fromEl.hasAttribute('live-ignore')
        },
        // Use stable keys for better morphing performance and state preservation
        getNodeKey(node) {
          if (!node) {
            return
          }

          if (node.getAttribute) {
            const liveKey = node.getAttribute('live-key')
            const id = node.getAttribute('id') || node.id

            if (liveKey) {
              return liveKey
            }

            if (id) {
              return id
            }

            // Combine live-component and live-id for unique component identification
            const liveComponent = node.getAttribute('data-live-component-value')
            const liveId = node.getAttribute('data-live-id-value')

            if (liveComponent && liveId) {
              return `${liveComponent}/${liveId}`
            }
          }
        }
      })
    }
  }

  #createRefresh(json) {
    const parts = JSON.parse(json)

    // First render
    if (this.#parts.length === 0) {
      this.#parts = parts
    } else {
      // Replace non null parts
      for (let i = 0; i < parts.length; i++) {
        if (parts[i] !== null) {
          this.#parts[i] = parts[i]
        }
      }
    }

    console.log(this.#parts)
    return this.#parts.join('')
  }

  #prepareRefresh(html) {
    const rootNode = this.#cleanComments(html)

    // Root node will be a component
    DOM.mutate(rootNode)

    // Check for child components
    rootNode.querySelectorAll('[live-id]').forEach(child => {
      DOM.mutate(child)
    })

    return rootNode
  }

  #cleanComments(html) {
    const template = document.createElement('template')
    template.innerHTML = html

    // Find a node that isn't a comment, since template annotations are comments
    const node = template.content.childNodes
      .values()
      .find(n => n.nodeName !== '#comment')

    if (node) {
      return node
    }

    return template.content.childNodes[0]
  }
}

const subscriptionManager = new SubscriptionManager()

export default subscriptionManager
