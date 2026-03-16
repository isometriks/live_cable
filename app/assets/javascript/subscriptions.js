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
 * Create a DOM element from HTML string, skipping comment nodes.
 * @param {string} html - HTML to build DOM from
 * @returns {HTMLElement}
 */
function createDOMFromHTML(html) {
  const template = document.createElement('template')
  template.innerHTML = html

  // Find a node that isn't a comment
  const node = template.content.childNodes
    .values()
    .find(n => n.nodeName !== '#comment')

  if (node) {
    DOM.mutate(node)
    return node
  }

  return template.content.childNodes[0]
}

/**
 * Manages all LiveCable subscriptions across the application.
 * Ensures that each component (identified by liveId) has at most one
 * active ActionCable subscription at any time.
 */
class SubscriptionManager {
  /** @type {Object.<string, Subscription>} */
  #subscriptions = {}
  /** @type {Object.<string, ComponentState>} */
  #componentStates = {}

  /**
   * Register a component state before subscription is created.
   * Used when a child component is rendered before its controller connects.
   *
   * @param {string} liveId - Unique identifier for the component instance
   * @param {HTMLElement} element - The DOM element created from initial render
   * @param {Object} refreshData - Initial refresh data with parts and template
   * @returns {ComponentState} The component state instance
   */
  registerComponent(liveId, element, refreshData) {
    if (!this.#componentStates[liveId]) {
      this.#componentStates[liveId] = new ComponentState(liveId, element, refreshData)
    }
    return this.#componentStates[liveId]
  }

  /**
   * Subscribe to or reconnect to a LiveCable component.
   * If a subscription already exists for this liveId, updates the controller
   * reference instead of creating a new subscription.
   * If a ComponentState exists and the controller element matches, reuses it.
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
      const componentState = this.#componentStates[liveId]

      // Check if we have a pre-existing component state and if the element matches
      if (componentState && componentState.element === controller.element) {
        // Create subscription with existing state
        this.#subscriptions[liveId] = new Subscription(id, component, defaults, controller, componentState)
        // Clean up component state
        delete this.#componentStates[liveId]
      } else {
        // Create new subscription normally
        this.#subscriptions[liveId] = new Subscription(id, component, defaults, controller)
      }
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

  /**
   * Unsubscribe components not present in the new page body.
   * Called before Turbo Drive renders a new page so that only components
   * truly leaving the page are cleaned up — components that persist across
   * pages (e.g. nav widgets) keep their subscriptions and server-side state.
   *
   * Because pages with live components are prevented from being cached (via
   * the turbo-cache-control meta tag), back/forward navigation always triggers
   * a fresh server fetch, so components are always pre-rendered before their
   * ActionCable subscription connects — no cold re-render needed.
   *
   * @param {HTMLElement} newBody - The incoming page body element from turbo:before-render
   */
  prune(newBody) {
    const newLiveIds = this.#extractLiveIds(newBody)

    Object.entries(this.#subscriptions).forEach(([liveId, subscription]) => {
      if (!newLiveIds.has(liveId)) {
        subscription.unsubscribe()
      }
    })

    Object.keys(this.#componentStates).forEach(liveId => {
      if (!newLiveIds.has(liveId)) {
        delete this.#componentStates[liveId]
      }
    })
  }

  /**
   * Extract the set of live IDs present in a body element.
   * Handles both fresh server renders (live-id attributes, not yet mutated)
   * and Turbo cache restores (data-live-id-value attributes, already mutated).
   *
   * @param {HTMLElement} body
   * @returns {Set<string>}
   */
  #extractLiveIds(body) {
    const ids = new Set()

    body.querySelectorAll('[live-id]').forEach(el => {
      const id = el.getAttribute('live-id')
      const component = el.getAttribute('live-component')
      if (id && component) ids.add(`${component}/${id}`)
    })

    body.querySelectorAll('[data-live-id-value]').forEach(el => {
      const id = el.getAttribute('data-live-id-value')
      const component = el.getAttribute('data-live-component-value')
      if (id && component) ids.add(`${component}/${id}`)
    })

    return ids
  }

  /**
   * Get component state by liveId.
   * Returns the state from either a subscription or a standalone component state.
   * @param {string} liveId - Unique identifier for the component instance
   * @returns {ComponentState|undefined}
   */
  getComponentState(liveId) {
    return this.#subscriptions[liveId]?.componentState || this.#componentStates[liveId]
  }
}

/**
 * Stores component state before subscription is active.
 * Used when a child component is rendered in parent's HTML before
 * the child's Stimulus controller connects and creates subscription.
 */
class ComponentState {
  /** @type {string} */
  #liveId
  /** @type {Object} - Map of template_id to parts array */
  #partsByTemplate
  /** @type {string|null} - Last template ID received */
  #lastTemplate
  /** @type {HTMLElement} - The DOM element for this component */
  #element

  /**
   * Creates component state from initial render data.
   *
   * @param {string} liveId - Unique identifier for the component instance
   * @param {HTMLElement} element - The DOM element created from initial render
   * @param {Object} refreshData - Initial refresh data with parts and template
   */
  constructor(liveId, element, refreshData) {
    this.#liveId = liveId
    this.#element = element
    this.#partsByTemplate = {}
    this.#lastTemplate = null

    // Store initial render data
    if (refreshData) {
      const [template, parts] = [refreshData['h'], refreshData['p']]
      const tid = template || 'default'
      this.#lastTemplate = tid
      this.#partsByTemplate[tid] = parts
    }
  }

  /**
   * Get the stored DOM element.
   * @returns {HTMLElement}
   */
  get element() {
    return this.#element
  }

  /**
   * Create a DOM element from stored state.
   * @param {Object} refresh - Optional refresh data to update state
   * @returns {HTMLElement}
   */
  createRefresh(refresh) {
    // If no refresh data provided, use the last rendered template
    if (!refresh) {
      const tid = this.#lastTemplate || 'default'
      const html = this.#partsByTemplate[tid].join('')
      return this.#buildRefreshDOM(html)
    }

    const [template, parts] = [refresh['h'], refresh['p']]

    // Use a default template ID for backward compatibility
    const tid = template || this.#lastTemplate || 'default'
    this.#lastTemplate = tid

    // First render for this template
    if (!this.#partsByTemplate[tid]) {
      this.#partsByTemplate[tid] = parts
    } else {
      // Replace non-null parts
      for (let i = 0; i < parts.length; i++) {
        if (parts[i] !== null) {
          this.#partsByTemplate[tid][i] = parts[i]
        }
      }
    }

    const html = this.#partsByTemplate[tid].join('')
    return this.#buildRefreshDOM(html)
  }

  /**
   * Build a DOM element from HTML.
   * @param {string} html - HTML to build DOM from
   * @returns {HTMLElement}
   * @private
   */
  #buildRefreshDOM(html) {
    return createDOMFromHTML(html)
  }

  /**
   * Set the DOM element reference.
   * @param {HTMLElement} element
   */
  set element(element) {
    this.#element = element
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
  /** @type {ComponentState} */
  #componentState
  /** @type {Object} */
  #subscription
  /** @type {string|null} */
  #currentStatus = null
  /**
   * Creates a new subscription to a LiveCable component.
   *
   * @param {string} id - Raw ID for the component (e.g., "room-1")
   * @param {string} component - Component class name (e.g., "chat/chat_room")
   * @param {Object} defaults - Default values for reactive variables
   * @param {Object} controller - Stimulus controller instance
   * @param {ComponentState} [existingState] - Optional existing component state to reuse
   */
  constructor(id, component, defaults, controller, existingState) {
    this.#id = id
    this.#component = component
    this.#defaults = defaults
    this.#controller = controller

    // Use existing state or create new one
    if (existingState) {
      this.#componentState = existingState
      // Update element reference to controller's element
      this.#componentState.element = controller.element
    } else {
      this.#componentState = new ComponentState(
        `${component}/${id}`,
        controller.element,
        null
      )
    }

    this.#subscribe()
  }

  /**
   * Get the component state.
   * @returns {ComponentState}
   */
  get componentState() {
    return this.#componentState
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
   * Unsubscribe from ActionCable and remove from the subscription manager.
   * Called when navigating away from this component's page, or when the
   * server sends a 'destroy' status.
   */
  unsubscribe() {
    this.#subscription.unsubscribe()
    const liveId = `${this.#component}/${this.#id}`
    subscriptionManager.unsubscribe(liveId)
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
   * @param {string} [data._error] - Raw error HTML to replace the component with
   * @private
   */
  #received = (data) => {
    if (data['_status']) {
      this.#handleStatus(data['_status'])
    } else if (data['_refresh']) {
      this.#handleRefresh(data['_refresh'])
    } else if (data['_error']) {
      this.#handleError(data['_error'])
    }
  }

  /**
   * Handle error messages from the server.
   * Replaces the component element with raw error HTML, then unsubscribes
   * to trigger server-side cleanup via LiveChannel#unsubscribed.
   * @param {string} html - Raw HTML error markup
   * @private
   */
  #handleError(html) {
    if (!this.#controller) {
      return
    }

    this.#controller.element.outerHTML = html
    this.unsubscribe()
  }

  /**
   * Handle status updates from the server.
   * Updates the controller's status and handles destroy status.
   * @param {string} status - Status update (e.g., 'subscribed', 'destroy')
   * @private
   */
  #handleStatus(status) {
    this.#currentStatus = status

    if (this.#controller) {
      this.#controller.statusValue = status
    }

    // Handle destroy status - permanently remove this subscription
    if (status === 'destroy') {
      this.unsubscribe()
    }
  }

  /**
   * Handle DOM refreshes from the server.
   * Updates the DOM using morphdom.
   * @param {Object} refresh - Refresh data from the server
   * @private
   */
  #handleRefresh(refresh) {
    // If we're getting a refresh we must be connected
    this.#handleStatus('subscribed')

    // If no controller is attached, we can't update the DOM
    if (!this.#controller) {
      return
    }

    morphdom(this.#controller.element, this.#buildRefreshDOM(refresh), {
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

  #buildRefreshDOM(refresh) {
    const rootNode = this.#componentState.createRefresh(refresh)

    // Apply stored status to root element
    if (this.#currentStatus && rootNode.setAttribute) {
      rootNode.setAttribute('data-live-status-value', this.#currentStatus)
    }

    // Root node will be a component
    DOM.mutate(rootNode)

    // Check for child components
    rootNode.querySelectorAll('[live-id]').forEach(child => {
      DOM.mutate(child)
    })

    // Replace Child Components
    const childResults = refresh?.c || {}
    rootNode.querySelectorAll('LiveCable').forEach(component => {
      const liveId = component.getAttribute('child-live-id')
      const childResult = childResults[liveId]

      const componentState = subscriptionManager.getComponentState(liveId)

      if (componentState) {
        // ComponentState already exists (either in subscription or standalone)
        component.replaceWith(
          componentState.createRefresh(childResult)
        )
      } else {
        // No state exists yet - create ComponentState
        const childElement = this.#buildChildElement(childResult)
        subscriptionManager.registerComponent(liveId, childElement, childResult)
        component.replaceWith(childElement)
      }
    })

    return rootNode
  }

  #buildChildElement(childResult) {
    if (!childResult) {
      return document.createTextNode('')
    }

    const [template, parts] = [childResult['h'], childResult['p']]
    const html = parts.join('')

    return createDOMFromHTML(html)
  }
}

const subscriptionManager = new SubscriptionManager()

export default subscriptionManager
