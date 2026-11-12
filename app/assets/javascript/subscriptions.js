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
import DOM from "@isometriks/live_cable/dom"
import { applyPart, renderParts } from "@isometriks/live_cable/tree"
import { nodeAt, patchRows, rowOpLoops } from "@isometriks/live_cable/rows"

const consumer = createConsumer()

// Sent on subscribe: 3 and up apply row ops the way collection streams need
const PROTOCOL = 3

const CHILD_PLACEHOLDER = /<LiveCable child-live-id="([^"]+)"><\/LiveCable>/g
const CHILD_COMMENT = /^live-cable-child (.+)$/

/**
 * @param {string} escapedId - The id as escaped in the placeholder attribute
 * @returns {string}
 */
function decodeChildId(escapedId) {
  const decoder = document.createElement('textarea')
  decoder.innerHTML = escapedId

  return decoder.value
}

/**
 * Comment text keeps character references as written, so a placeholder's
 * escaped id is decoded here and carried URI-encoded.
 * @param {string} escapedId - The id as escaped in the placeholder attribute
 * @returns {string}
 */
function childComment(escapedId) {
  return `<!--live-cable-child ${encodeURIComponent(decodeChildId(escapedId))}-->`
}

/**
 * Create a DOM element from HTML string, skipping comment nodes.
 * @param {string} html - HTML to build DOM from
 * @returns {HTMLElement}
 */
function createDOMFromHTML(html) {
  const template = document.createElement('template')
  // The parser moves or drops an unknown element inside table or select
  // markup; a comment stays where it is
  template.innerHTML = html.replace(CHILD_PLACEHOLDER, (_, escapedId) => childComment(escapedId))

  // Find a node that isn't a comment
  const node = Array.from(template.content.childNodes)
    .find(n => n.nodeName !== '#comment')

  if (node) {
    DOM.mutate(node)
    return node
  }

  return template.content.childNodes[0]
}

const FOREIGN_ROOTS = {
  'http://www.w3.org/2000/svg': 'svg',
  'http://www.w3.org/1998/Math/MathML': 'math',
}

/**
 * Build a row, parsed inside an svg or math element when the rows it joins
 * are in that namespace.
 * @param {string} html
 * @param {string} namespace - The namespace of the row elements
 * @returns {Node|null} Null when the row is more than one node, comments aside
 */
function createRowFromHTML(html, namespace) {
  const root = FOREIGN_ROOTS[namespace]
  const row = root ? createDOMFromHTML(`<${root}>${html}</${root}>`).firstChild : createDOMFromHTML(html)
  const alone = Array.from(row?.parentNode?.childNodes ?? [])
    .every(node => node === row || node.nodeType === Node.COMMENT_NODE)

  if (!row || !alone) {
    return null
  }

  if (root) {
    row.remove()
  }

  return row
}

/**
 * The child component placeholders in a node, with the live id each holds.
 * @param {Node} node
 * @returns {Array<{placeholder: Comment, liveId: string}>}
 */
function childPlaceholders(node) {
  const walker = document.createTreeWalker(node, NodeFilter.SHOW_COMMENT)
  const found = []

  while (walker.nextNode()) {
    const liveId = walker.currentNode.data.match(CHILD_COMMENT)?.[1]

    if (liveId) {
      found.push({ placeholder: walker.currentNode, liveId: decodeURIComponent(liveId) })
    }
  }

  return found
}

const UNTYPED_INPUT_TYPES = new Set(['checkbox', 'radio', 'file', 'hidden', 'submit', 'reset', 'button', 'image'])

/**
 * Whether the user enters the element's value, by typing or with a picker or
 * slider.
 * @param {Element} element
 * @returns {boolean}
 */
function isTypedField(element) {
  return element instanceof HTMLTextAreaElement ||
    (element instanceof HTMLInputElement && !UNTYPED_INPUT_TYPES.has(element.type))
}

/**
 * Whether the template renders a value for the field.
 * @param {HTMLInputElement|HTMLTextAreaElement} field
 * @returns {boolean}
 */
function rendersValue(field) {
  return field instanceof HTMLTextAreaElement ? field.defaultValue !== '' : field.hasAttribute('value')
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
  /** @type {string|null} - Digest from live_cable_identity_tag the socket was opened under */
  #identity = null
  /** @type {boolean} - Whether the last socket closed for good, with no reconnect coming */
  #refused = false
  /** @type {string|null} - Why the server last said it was closing the socket */
  #disconnectReason = null
  /** @type {number} - Components the refusal being reported stopped */
  #refusedComponents = 0

  /**
   * ActionCable reads the reason off the server's disconnect frame and only
   * logs it. The handlers are shared on Connection.prototype by every
   * consumer on the page, so this connection gets its own copy; each socket
   * it opens binds them afresh.
   */
  constructor() {
    const { events } = consumer.connection
    const manager = this

    consumer.connection.events = {
      ...events,
      open(...args) {
        manager.#refused = false
        manager.#disconnectReason = null
        return events.open.apply(this, args)
      },
      message(event) {
        manager.#readDisconnectReason(event.data)
        return events.message.call(this, event)
      },
    }
  }

  /**
   * @param {string} data - A frame from the server
   */
  #readDisconnectReason(data) {
    if (typeof data !== 'string' || !data.includes('"disconnect"')) {
      return
    }

    try {
      const { type, reason } = JSON.parse(data)

      if (type === 'disconnect') {
        this.#disconnectReason = reason ?? null
      }
    } catch {
      // ActionCable's own handler reports a frame it can't read
    }
  }

  /**
   * Whether the socket closed for good, so a message sent now would never go.
   * @returns {boolean}
   */
  get refused() {
    return this.#refused
  }

  /**
   * A subscription heard that the socket closed with no reconnect coming:
   * the server refused it, or the client closed it. ActionCable tells every
   * subscription in turn, so the page hears about it once they all have.
   */
  socketRefused() {
    this.#refused = true

    if (this.#refusedComponents++ > 0) {
      return
    }

    queueMicrotask(() => {
      const detail = { reason: this.#disconnectReason, components: this.#refusedComponents }
      this.#refusedComponents = 0
      document.dispatchEvent(new CustomEvent('live:refused', { bubbles: true, detail }))
    })
  }

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
   * reference instead of creating a new subscription - unless the element
   * brings different defaults, in which case the old subscription is replaced
   * so the server builds the component again from them.
   * If a parent's render left a ComponentState for it, the subscription takes it.
   *
   * @param {string} id - Raw ID for the component (e.g., "room-1")
   * @param {string} component - Component class name (e.g., "chat/chat_room")
   * @param {string} defaults - Opaque signed defaults blob, forwarded to the server
   * @param {Object} controller - Stimulus controller instance
   * @returns {Subscription} The subscription instance
   */
  subscribe(id, component, defaults, controller) {
    const liveId = `${component}/${id}`

    if (this.#subscriptions[liveId] && this.#replaced(this.#subscriptions[liveId], defaults)) {
      // A frame render or stream action doesn't run prune, so close the
      // children here: the server builds them again with their parent
      const children = this.#extractLiveIds(this.#subscriptions[liveId].componentState.element)

      this.#subscriptions[liveId].unsubscribe()
      children.forEach((_, childId) => {
        this.#subscriptions[childId]?.unsubscribe()
        delete this.#componentStates[childId]
      })
    }

    if (!this.#subscriptions[liveId]) {
      // ActionCable opens a closed socket for a new subscription
      this.#refused = false
      const componentState = this.#componentStates[liveId]

      // Whichever element its controller connected on: a morph keeps a
      // prerendered root with an id in place of the one the parent's render built
      this.#subscriptions[liveId] = new Subscription(id, component, defaults, controller, componentState)
      delete this.#componentStates[liveId]
    }

    this.#subscriptions[liveId].controller = controller

    return this.#subscriptions[liveId]
  }

  /**
   * Only a page rendered over HTTP carries a defaults blob; an element rendered
   * over the socket has none and says nothing about them. Signing is
   * deterministic, so the same defaults always produce the same blob. A Turbo
   * preview shows a cached copy of the page, whose blob may be stale; the
   * page itself follows it.
   *
   * @param {Subscription} subscription
   * @param {string} defaults
   * @returns {boolean}
   */
  #defaultsChanged(subscription, defaults) {
    return this.#renderedByPage(defaults) && defaults !== subscription.defaults
  }

  /**
   * A refused component stays refused in its parent's renders, until a page
   * renders it again.
   *
   * @param {Subscription} subscription
   * @param {string} defaults
   * @returns {boolean}
   */
  #replaced(subscription, defaults) {
    return subscription.ended ? this.#renderedByPage(defaults) : this.#defaultsChanged(subscription, defaults)
  }

  /**
   * @param {string} defaults
   * @returns {boolean}
   */
  #renderedByPage(defaults) {
    return Boolean(defaults) && !document.documentElement.hasAttribute('data-turbo-preview')
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
   * Reopen the socket when the page was rendered for someone other than the
   * socket was opened for.
   *
   * A socket is identified once, at its handshake, and Turbo keeps it open
   * across a sign-in, sign-out or impersonation, so its components would
   * carry on as the previous identity. The live_cable_identity_tag meta tag
   * carries a digest of who each page was rendered for; Turbo merges the new
   * page's head before turbo:before-render, so this runs before the new
   * body's components subscribe. Reopening closes the socket, the server
   * drops its components, and they resubscribe on the new socket as the new
   * session. A socket the server refused is opened again, since a page kept
   * from before has nothing else to open it. A page without the tag, and a
   * Turbo preview of a cached page, say nothing.
   */
  syncIdentity() {
    if (document.documentElement.hasAttribute('data-turbo-preview')) {
      return
    }

    const identity = document.head.querySelector('meta[name="live-cable-identity"]')?.content

    if (!identity) {
      return
    }

    if (this.#identity && identity !== this.#identity) {
      if (consumer.connection.isActive()) {
        consumer.connection.reopen()
      } else if (this.#refused) {
        this.#refused = false
        consumer.connection.open()
      }
    }

    this.#identity = identity
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
    const newElements = this.#extractLiveIds(newBody)
    const newLiveIds = new Set(newElements.keys())
    const rebuilt = new Set()

    // A component built again from other defaults builds its children again,
    // including those a cached page still shows
    newElements.forEach((element, liveId) => {
      const subscription = this.#subscriptions[liveId]

      if (subscription && !this.#carriedOver(element) && this.#defaultsChanged(subscription, this.#defaultsOf(element))) {
        rebuilt.add(liveId)
        this.#extractLiveIds(element).forEach((_, childId) => newLiveIds.delete(childId))
      }
    })

    // Inline children have no live id on a rendered page; a component kept
    // with its defaults rebuilds them, and the set grows to take in grandchildren
    newLiveIds.forEach(liveId => {
      if (!rebuilt.has(liveId)) {
        this.getComponentState(liveId)?.childLiveIds.forEach(childId => newLiveIds.add(childId))
      }
    })

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
   * Whether the element Turbo would morph a live component's element into
   * renders the same component with the same defaults, so the live element
   * can stay as it is.
   *
   * @param {HTMLElement} element - A live component's element on the page
   * @param {HTMLElement} newElement - The element Turbo would morph it into
   * @returns {boolean}
   */
  keeps(element, newElement) {
    const liveId = this.#liveIdOf(element)
    const subscription = this.#subscriptions[liveId]

    return Boolean(subscription) && this.#liveIdOf(newElement) === liveId &&
      !this.#defaultsChanged(subscription, this.#defaultsOf(newElement))
  }

  /**
   * @param {HTMLElement} element
   * @returns {string|null} The live id of the component the element is the
   *   root of, rendered or already mutated
   */
  #liveIdOf(element) {
    const id = element.getAttribute('live-id') ?? element.getAttribute('data-live-id-value')
    const component = element.getAttribute('live-component') ?? element.getAttribute('data-live-component-value')

    return id && component ? `${component}/${id}` : null
  }

  /**
   * The live ids of the components, subscribed or only registered, whose
   * element is inside one of the given elements.
   *
   * @param {Iterable<HTMLElement>} elements - What a Turbo Frame render or
   *   Turbo Stream action is about to change
   * @returns {Set<string>}
   */
  liveIdsWithin(elements) {
    const containers = Array.from(elements)
    const within = (state) => state.element && containers.some(container => container.contains(state.element))
    const liveIds = new Set()

    Object.entries(this.#subscriptions).forEach(([liveId, subscription]) => {
      if (within(subscription.componentState)) liveIds.add(liveId)
    })

    Object.entries(this.#componentStates).forEach(([liveId, state]) => {
      if (within(state)) liveIds.add(liveId)
    })

    return liveIds
  }

  /**
   * Unsubscribe the given components whose element has left the page. A
   * Turbo Frame render or Turbo Stream action changes the page without a
   * visit, so prune never sees what it took away. Run it once Stimulus has
   * connected the controllers of what came in: a component rendered again
   * with the same defaults has moved its subscription to its new element by
   * then.
   *
   * @param {Iterable<string>} liveIds - From liveIdsWithin, taken before
   *   the change
   */
  pruneDetached(liveIds) {
    for (const liveId of liveIds) {
      const state = this.getComponentState(liveId)

      if (state && !state.element?.isConnected) {
        this.#subscriptions[liveId]?.unsubscribe()
        delete this.#componentStates[liveId]
      }
    }
  }

  /**
   * Extract the live IDs present inside an element, with the element each
   * belongs to. Handles both fresh server renders (live-id attributes, not
   * yet mutated) and Turbo cache restores (data-live-id-value attributes,
   * already mutated).
   *
   * @param {HTMLElement} body
   * @returns {Map<string, HTMLElement>}
   */
  #extractLiveIds(body) {
    const elements = new Map()

    body.querySelectorAll('[live-id]').forEach(el => {
      const id = el.getAttribute('live-id')
      const component = el.getAttribute('live-component')
      if (id && component) elements.set(`${component}/${id}`, el)
    })

    body.querySelectorAll('[data-live-id-value]').forEach(el => {
      const id = el.getAttribute('data-live-id-value')
      const component = el.getAttribute('data-live-component-value')
      if (id && component) elements.set(`${component}/${id}`, el)
    })

    return elements
  }

  /**
   * Whether Turbo will keep what is already on the page in place of this
   * element: it carries a [data-turbo-permanent] element over, with all it
   * holds, when the new page has a permanent element with the same id.
   *
   * @param {HTMLElement} element - An element in the incoming page
   * @returns {boolean}
   */
  #carriedOver(element) {
    const permanent = element.closest('[id][data-turbo-permanent]')

    return Boolean(permanent && document.getElementById(permanent.id)?.hasAttribute('data-turbo-permanent'))
  }

  /**
   * @param {HTMLElement} element
   * @returns {string} The signed defaults blob the element carries
   */
  #defaultsOf(element) {
    return element.getAttribute('live-defaults') ?? element.getAttribute('data-live-defaults-value') ?? ''
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

  /**
   * The status a component's subscription last received.
   * @param {string} liveId - Unique identifier for the component instance
   * @returns {string|null|undefined}
   */
  statusOf(liveId) {
    return this.#subscriptions[liveId]?.status
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
  /** @type {Object} - Map of template_id to the statics of its structured parts */
  #staticsByTemplate
  /** @type {string|null} - Last template ID received */
  #lastTemplate
  /** @type {HTMLElement} - The DOM element for this component */
  #element
  /** @type {number} */
  #renderCount = 0

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
    this.#staticsByTemplate = {}
    this.#lastTemplate = null

    // Store initial render data
    if (refreshData) {
      const [template, parts] = [refreshData['h'], refreshData['p']]
      const tid = template || 'default'
      this.#lastTemplate = tid
      this.#partsByTemplate[tid] = parts
      this.#mergeStatics(tid, refreshData['s'])
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
   * Whether a render has been received and cached, and can therefore be
   * replayed into a freshly attached element.
   * @returns {boolean}
   */
  get hasRender() {
    return this.#lastTemplate !== null && Boolean(this.#partsByTemplate[this.#lastTemplate])
  }

  /**
   * How many renders have been stored, counting those that arrived in a
   * parent's refresh.
   * @returns {number}
   */
  get renderCount() {
    return this.#renderCount
  }

  /**
   * Live ids of the child components placed in the last render.
   * @returns {string[]}
   */
  get childLiveIds() {
    const html = this.hasRender ? this.#html(this.#lastTemplate) : ''
    return Array.from(html.matchAll(CHILD_PLACEHOLDER), ([, escapedId]) => decodeChildId(escapedId))
  }

  /**
   * Create a DOM element from stored state.
   * @param {Object} refresh - Optional refresh data to update state
   * @returns {HTMLElement}
   */
  createRefresh(refresh) {
    if (refresh) {
      this.#apply(refresh)
    }

    return this.#buildRefreshDOM(this.#html(this.#lastTemplate || 'default'))
  }

  /**
   * Apply a refresh that carries nothing but row ops for keyed loops.
   * @param {Object} refresh
   * @returns {Array<{before: Object, after: Object, ops: Array}>|null} The
   *   loops it changed, or null, having applied nothing, for any other refresh
   */
  applyRowOps(refresh) {
    const tid = refresh['h'] || this.#lastTemplate || 'default'
    const stored = this.#partsByTemplate[tid]
    const children = refresh['c'] && Object.keys(refresh['c']).length > 0

    if (tid !== this.#lastTemplate || !stored || children) {
      return null
    }

    const loops = rowOpLoops(stored, refresh['p'], this.statics)

    if (loops) {
      this.#apply(refresh)
      loops.forEach(loop => { loop.after = nodeAt(stored, loop.path) })
    }

    return loops
  }

  /**
   * @returns {Object.<string, string[]>} The statics of the last template
   */
  get statics() {
    return this.#staticsByTemplate[this.#lastTemplate] ?? {}
  }

  /**
   * @param {Object} refresh
   * @private
   */
  #apply(refresh) {
    this.#renderCount++
    const [template, parts] = [refresh['h'], refresh['p']]

    // Use a default template ID for backward compatibility
    const tid = template || this.#lastTemplate || 'default'
    this.#lastTemplate = tid
    this.#mergeStatics(tid, refresh['s'])

    // First render for this template
    if (!this.#partsByTemplate[tid]) {
      this.#partsByTemplate[tid] = parts
    } else {
      // Apply non-null parts: an HTML string or a structured part replaces
      // what was held, a diff updates it
      const stored = this.#partsByTemplate[tid]

      for (let i = 0; i < parts.length; i++) {
        if (parts[i] !== null) {
          stored[i] = applyPart(stored[i], parts[i])
        }
      }
    }
  }

  /**
   * @param {string} tid - Template ID
   * @returns {string} The template's HTML from the parts held for it
   * @private
   */
  #html(tid) {
    return renderParts(this.#partsByTemplate[tid], this.#staticsByTemplate[tid] ?? {})
  }

  /**
   * Keep the statics a render brought for the template's structured parts.
   * @param {string} tid - Template ID
   * @param {Object|undefined} statics - Statics by scope id
   * @private
   */
  #mergeStatics(tid, statics) {
    if (statics) {
      this.#staticsByTemplate[tid] = { ...(this.#staticsByTemplate[tid] ?? {}), ...statics }
    }
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
 * The path and query of the page a component was rendered for: the src of the
 * turbo-frame it was loaded into, or the page's own.
 *
 * @param {Element} [element]
 * @returns {string}
 */
function pagePath(element) {
  const src = element?.closest('turbo-frame[src]')?.getAttribute('src')
  const url = new URL(src ?? location.href, location.href)

  return url.origin === location.origin ? url.pathname + url.search : location.pathname + location.search
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
  /** @type {string} */
  #defaults
  /** @type {string} - Path and query of the page the component subscribed on */
  #path
  /** @type {Object|null} */
  #controller
  /** @type {ComponentState} */
  #componentState
  /** @type {Object} */
  #subscription
  /** @type {string|null} */
  #currentStatus = null
  /** @type {boolean} - Whether the server has confirmed this subscription on the current socket */
  #confirmed = false
  /** @type {Array<Object>} - Messages held until the subscription is confirmed */
  #pending = []
  /** @type {number} - The render count when the first in-flight message was sent */
  #renderCountAtSend = 0
  /** @type {Map<string, *>} - The value last sent for each live-reactive name */
  #sentValues = new Map()
  /** @type {boolean} - Whether the server ended the subscription for good */
  #ended = false
  /** @type {boolean} - Whether ActionCable has been told to unsubscribe */
  #closed = false
  /**
   * Creates a new subscription to a LiveCable component.
   *
   * @param {string} id - Raw ID for the component (e.g., "room-1")
   * @param {string} component - Component class name (e.g., "chat/chat_room")
   * @param {string} defaults - Opaque signed defaults blob, forwarded to the server
   * @param {Object} controller - Stimulus controller instance
   * @param {ComponentState} [existingState] - Optional existing component state to reuse
   */
  constructor(id, component, defaults, controller, existingState) {
    this.#id = id
    this.#component = component
    this.#defaults = defaults
    this.#path = pagePath(controller?.element)
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
   * The signed defaults blob this subscription was created with.
   * @returns {string}
   */
  get defaults() {
    return this.#defaults
  }

  /**
   * Whether the server ended the subscription for good.
   * @returns {boolean}
   */
  get ended() {
    return this.#ended
  }

  /**
   * The status the server last gave this subscription.
   * @returns {string|null}
   */
  get status() {
    return this.#currentStatus
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
   * Called when a Stimulus controller reconnects to an existing subscription —
   * most importantly after a Turbo Drive navigation to a page that contains the
   * same component, where prune() deliberately keeps the subscription alive.
   *
   * In that case the ActionCable subscription is never recreated, so
   * LiveChannel#subscribed does not run again and the server sends nothing.
   * Without re-syncing here, the newly rendered element keeps the
   * server-rendered status of "disconnected" forever and never receives the
   * component's current state.
   *
   * @param {Object} controller - Stimulus controller instance
   */
  set controller(controller) {
    const previous = this.#controller

    this.#controller = controller
    this.#componentState.element = controller.element

    if (previous && previous !== controller) {
      this.#reattach()
    }
  }

  /**
   * Bring a freshly connected controller up to date with state this
   * subscription already holds.
   * @private
   */
  #reattach() {
    if (this.#currentStatus) {
      this.#controller.statusValue = this.#currentStatus
    }

    // Replay the last render into the new element. The server-side component
    // is the same instance, so the cached parts are its current state.
    if (this.#componentState.hasRender) {
      this.#handleRefresh(null)
    }
  }

  /**
   * Send a message to the server, or hold it until the subscription is
   * confirmed on an open socket.
   *
   * ActionCable drops a message sent while its socket is closed - after a
   * laptop wakes, a network blip, a deploy - and one sent after the socket
   * reopens but before the re-subscribe is confirmed can reach the server
   * before the subscription exists there, which drops it too. Either way the
   * component would wait in its loading state for a reply that is never
   * coming. Held messages go out, in order, once the server confirms the
   * subscription.
   *
   * @param {Object} message - Message to send (e.g., action calls, reactive updates)
   */
  send(message) {
    if (this.#ended || subscriptionManager.refused) {
      this.#controller?.finishLoading()
      return
    }

    if (this.#controller?.inFlight === 1) {
      this.#renderCountAtSend = this.#componentState.renderCount
    }

    // Only a reply to live-reactive updates alone can be an echo
    if (message.messages.every(({ _action }) => _action === '_reactive')) {
      message.messages.forEach(({ name, value }) => this.#sentValues.set(name, value))
    } else {
      this.#sentValues.clear()
    }

    if (!this.#confirmed || !this.#subscription.send(message)) {
      this.#pending.push(message)
    }
  }

  /**
   * How many messages are waiting for a connection.
   * @returns {number}
   */
  get pendingCount() {
    return this.#pending.length
  }

  /**
   * Drop any messages still waiting for a connection. Called when the loading
   * state gives up on them, so a message the page has said didn't go through
   * can't then go through after a reconnect.
   *
   * @returns {number} How many messages were dropped
   */
  discardPending() {
    const count = this.#pending.length
    this.#pending = []
    return count
  }

  /**
   * Unsubscribe from ActionCable and remove from the subscription manager.
   * Called when navigating away from this component's page, or when the
   * server sends a 'destroy' status.
   */
  unsubscribe() {
    this.#close()
    const liveId = `${this.#component}/${this.#id}`
    subscriptionManager.unsubscribe(liveId)
  }

  #close() {
    if (!this.#closed) {
      this.#closed = true
      this.#subscription.unsubscribe()
    }
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
      path: this.#path,
      protocol: PROTOCOL,
    }, {
      connected: this.#connected,
      disconnected: this.#disconnected,
      received: this.#received,
      rejected: this.#rejected,
    })
  }

  /**
   * The server rejected the subscription, and ActionCable has forgotten it,
   * so nothing will be sent or received again.
   * @private
   */
  #rejected = () => {
    this.#end('rejected')
    subscriptionManager.unsubscribe(`${this.#component}/${this.#id}`)
    this.#controller?.element.dispatchEvent(new CustomEvent('live:rejected', { bubbles: true }))
  }

  /**
   * The component's own code called refuse!. Its markup stays, as the page
   * last showed it, and the manager keeps it for a parent's renders.
   * @param {string|null} reason
   * @private
   */
  #handleRefused(reason) {
    this.#end('refused')
    this.#close()
    this.#controller?.element.dispatchEvent(new CustomEvent('live:refused', {
      bubbles: true,
      detail: { reason, components: 1 },
    }))
  }

  /**
   * Stop for good: drop what is held and anything sent from now on.
   * @param {string} status
   * @private
   */
  #end(status) {
    const loading = this.#controller?.isLoading
    this.#ended = true
    this.discardPending()
    this.#controller?.resetLoading()
    if (loading) {
      this.catchUp()
    }
    this.#handleStatus(status)
  }

  /**
   * The server confirmed the subscription - on first connect, or again after
   * a reconnect. Anything held while it wasn't goes out now.
   * @private
   */
  #connected = () => {
    this.#confirmed = true
    // ActionCable can replace a stale socket without calling disconnected
    if (this.#settleLostMessages()) {
      this.catchUp()
    }

    while (this.#pending.length > 0) {
      // The socket closed again mid-flush; the next confirmation resumes it
      if (!this.#subscription.send(this.#pending[0])) {
        this.#confirmed = false
        break
      }

      this.#pending.shift()
    }
  }

  /**
   * The socket closed. ActionCable reconnects and re-subscribes by itself;
   * until it has, sends are held and the component says so. When it won't
   * reconnect, nothing held would ever go.
   * @param {Object} [options]
   * @param {boolean} [options.willAttemptReconnect]
   * @private
   */
  #disconnected = ({ willAttemptReconnect } = {}) => {
    this.#confirmed = false

    if (willAttemptReconnect === false) {
      const loading = this.#controller?.isLoading
      this.discardPending()
      this.#controller?.resetLoading()
      if (loading) {
        this.catchUp()
      }
      this.#handleStatus('refused')
      subscriptionManager.socketRefused()
      return
    }

    if (this.#settleLostMessages()) {
      this.catchUp()
    }
    this.#handleStatus('disconnected')
  }

  /**
   * End the loading state of messages sent on a socket that has since
   * closed - their replies will never arrive. Held messages still will.
   * @returns {boolean} Whether that ended the loading state
   * @private
   */
  #settleLostMessages() {
    const lost = (this.#controller?.inFlight ?? 0) - this.#pending.length
    let settled = false

    for (let i = 0; i < lost; i++) {
      settled = this.#controller.finishLoading()
    }

    return settled
  }

  /**
   * Morph the last render in again if renders arrived after the first
   * in-flight message went out: the pending elements skipped them. For a
   * loading state that ended without a render to apply.
   */
  catchUp() {
    if (this.#componentState.renderCount !== this.#renderCountAtSend) {
      this.#handleRefresh(null)
    }
  }

  /**
   * Handle incoming messages from the server.
   * Processes status updates and DOM refreshes.
   *
   * @param {Object} data - Data received from the server
   * @param {string} [data._status] - Status update (e.g., 'subscribed', 'destroy')
   * @param {string} [data._refresh] - HTML to morph into the DOM
   * @param {string} [data._error] - Raw error HTML to replace the component with
   * @param {boolean} [data._reply] - Whether a _refresh answers this
   *   component's own message; absent from 0.4 servers, whose refreshes all
   *   count as replies
   * @param {boolean} [data._subscribed] - Marks the frame the server sends
   *   when it (re)subscribes the component
   * @param {boolean} [data._ack] - Answers a message that no re-render of the
   *   component's own answered, as when its render rode in its parent's
   *   refresh; clears the loading state
   * @param {boolean} [data._rendered] - Marks an _ack whose message's render
   *   of the component rode in its parent's refresh
   * @param {Array} [data._events] - Events to dispatch as CustomEvents; when
   *   attached to a _refresh they fire after the DOM has been morphed
   * @param {boolean} [data._refused] - The component called refuse!; the
   *   _error alongside is for 0.5 clients
   * @param {string|null} [data._reason] - Why it refused
   * @private
   */
  #received = (data) => {
    if (data['_refused']) {
      this.#handleRefused(data['_reason'] ?? null)
      return
    }

    // A re-subscribe render brings the component up to date; a status frame doesn't
    if (data['_subscribed'] && this.#settleLostMessages() && !data['_refresh']) {
      this.catchUp()
    }

    if (data['_status']) {
      this.#handleStatus(data['_status'])
    } else if (data['_refresh']) {
      const legacy = !('_reply' in data)
      this.#handleRefresh(data['_refresh'], { reply: legacy || data['_reply'] === true, legacy })
    } else if (data['_error']) {
      this.#handleError(data['_error'])
    } else if (data['_ack']) {
      this.#handleStatus('subscribed')

      // Pending elements skipped the renders that came while they waited. When
      // the server says one was this message's, inside its parent's refresh,
      // catching up to it replies
      const missed = this.#componentState.renderCount !== this.#renderCountAtSend

      if (data['_rendered'] && missed && this.#controller?.inFlight === 1) {
        this.#handleRefresh(null, { reply: true })
      } else if (this.#controller?.finishLoading()) {
        this.catchUp()
      }
    }

    // Dispatch after the branch above so events attached to a refresh fire
    // once the morph has completed and handlers see the updated DOM
    if (data['_events']) {
      this.#dispatchEvents(data['_events'])
    }
  }

  /**
   * Fire server-dispatched events as bubbling CustomEvents from the
   * component's root element, or from window when the event asks for it.
   *
   * @param {Array<{name: string, detail: Object, window: boolean}>} events
   * @private
   */
  #dispatchEvents(events) {
    events.forEach(({ name, detail, window: onWindow }) => {
      const target = onWindow ? window : this.#controller?.element

      if (target) {
        target.dispatchEvent(new CustomEvent(name, { detail, bubbles: true }))
      }
    })
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

    this.#controller.resetLoading()
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
      // Replies still on their way go to a subscription that no longer exists
      this.#controller?.resetLoading()
      this.unsubscribe()
    }
  }

  /**
   * Handle DOM refreshes from the server.
   * Updates the DOM using morphdom.
   * @param {Object} refresh - Refresh data from the server
   * @param {Object} [options]
   * @param {boolean} [options.reply] - Whether the refresh answers this
   *   component's own message, which ends its loading state
   * @param {boolean} [options.legacy] - Whether it came from a 0.4 server,
   *   which never answers an inline child
   * @private
   */
  #handleRefresh(refresh, { reply = false, legacy = false } = {}) {
    // If we're getting a refresh we must be connected
    this.#handleStatus('subscribed')

    // If no controller is attached, we can't update the DOM
    if (!this.#controller) {
      return
    }

    // A focused field whose form or trigger awaits a reply takes its value,
    // unless that echoes what the field itself sent; read before the restore
    const focused = document.activeElement
    const awaiting = focused?.closest('[live-loading]:not([data-live-id-value])')
    const sent = awaiting === focused ? this.#sentValues.get(focused.name) : undefined

    // Restore live-loading / live-disable-with state before morphing so the
    // morph applies the server-rendered truth on top of the original DOM.
    // Only replies count, and with multiple messages in flight this only
    // restores once the last one arrives - until then the morph below
    // preserves the pending elements so live-disable-with buttons can't be
    // clicked early.
    if (reply) {
      this.#controller.finishLoading()
    }

    const rootElement = this.#controller.element
    const stillLoading = this.#controller.isLoading
    const childResults = refresh?.c || {}
    const morphing = { rootElement, stillLoading, childResults, legacy, focused, awaiting, sent }

    const loops = refresh ? this.#componentState.applyRowOps(refresh) : null

    if (loops && this.#patchRows(loops, morphing)) {
      return
    }

    const refreshDOM = this.#buildRefreshDOM(loops ? null : refresh)

    if (stillLoading) {
      refreshDOM.setAttribute('live-loading', '')
    }

    morphdom(rootElement, refreshDOM, this.#morphOptions(morphing))
  }

  /**
   * Apply row ops straight to the rows' elements, leaving the rest of the
   * component alone.
   * @param {Array} loops - From ComponentState#applyRowOps
   * @param {Object} morphing - What #morphOptions needs
   * @returns {boolean} Whether the rows could be patched in place
   * @private
   */
  #patchRows(loops, morphing) {
    const { rootElement, focused } = morphing
    const selection = isTypedField(focused) ? [focused.selectionStart, focused.selectionEnd] : null

    const patched = patchRows(rootElement, loops, this.#componentState.statics, {
      buildRow: (html, namespace) => {
        const row = createRowFromHTML(html, namespace)

        if (row) {
          this.#fillChildren(row, {})
        }

        return row
      },
      morphRow: (fromEl, toEl) => morphdom(fromEl, toEl, this.#morphOptions(morphing)),
    })

    // Moving a row takes focus from what it holds
    if (patched && focused?.isConnected && document.activeElement !== focused) {
      focused.focus({ preventScroll: true })

      if (selection) {
        focused.setSelectionRange(...selection)
      }
    }

    return patched
  }

  /**
   * @param {Object} morphing
   * @returns {Object} morphdom options that keep what the page must keep
   * @private
   */
  #morphOptions({ rootElement, stillLoading, childResults, legacy, focused, awaiting, sent }) {
    let keepFocusedValue = false

    return {
      // Preserve elements marked with live-ignore attribute
      onBeforeElUpdated(fromEl, toEl) {
        if (!fromEl.hasAttribute) {
          return true
        }

        if (fromEl.hasAttribute('live-ignore')) {
          return false
        }

        // Keep elements that are still awaiting a server response untouched
        // (the root is handled above so the rest of the tree still morphs)
        if (stillLoading && fromEl !== rootElement && fromEl.hasAttribute('live-loading')) {
          return false
        }

        // A nested component's loading state waits for its own answer, unless a
        // 0.4 server, which never answers an inline child, sent its render
        const owner = fromEl.hasAttribute('live-loading') && fromEl.closest('[data-live-id-value]')

        if (owner && owner !== rootElement) {
          const liveId = `${owner.getAttribute('data-live-component-value')}/${owner.getAttribute('data-live-id-value')}`

          if (!legacy || !(liveId in childResults)) {
            if (owner !== fromEl) {
              return false
            }

            toEl.setAttribute('live-loading', '')
          }
        }

        // defaultValue is what the server last rendered for the field
        if (fromEl === focused) {
          const echoed = toEl.defaultValue === sent ||
            (sent !== undefined && !rendersValue(fromEl) && !rendersValue(toEl))

          keepFocusedValue = isTypedField(fromEl) &&
            (awaiting ? echoed : fromEl.defaultValue === toEl.defaultValue)
        }

        return true
      },
      // Skipping its children skips morphdom's value sync, so the focused
      // field keeps what the user typed
      onBeforeElChildrenUpdated(fromEl, toEl) {
        // morphdom updates a textarea's text node, which an empty one lacks;
        // once typed into, setting it leaves the value alone
        if (fromEl instanceof HTMLTextAreaElement && fromEl.defaultValue !== toEl.defaultValue) {
          fromEl.defaultValue = toEl.defaultValue
        }

        return !(keepFocusedValue && fromEl === focused)
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
    }
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

    this.#fillChildren(rootNode, refresh?.c || {})

    return rootNode
  }

  /**
   * Replace the child component placeholders in a node with the children,
   * built from this refresh's results or from what each last rendered.
   * @param {Node} rootNode
   * @param {Object} childResults - Child results by live id
   * @private
   */
  #fillChildren(rootNode, childResults) {
    const placeholders = childPlaceholders(rootNode)
    const replaced = new Set()

    while (placeholders.length > 0) {
      const { placeholder, liveId } = placeholders.shift()
      const childResult = childResults[liveId]

      if (replaced.has(liveId)) {
        console.error(`[LiveCable] ${liveId} is rendered more than once in a single refresh`)
        placeholder.remove()
        continue
      }

      replaced.add(liveId)

      const componentState = subscriptionManager.getComponentState(liveId)
      let childElement

      if (componentState) {
        // ComponentState already exists (either in subscription or standalone)
        childElement = (childResult || componentState.hasRender)
          ? componentState.createRefresh(childResult)
          : document.createTextNode('')
      } else {
        // No state exists yet - create ComponentState
        childElement = this.#buildChildElement(childResult)
        subscriptionManager.registerComponent(liveId, childElement, childResult)
      }

      const status = subscriptionManager.statusOf(liveId)

      if (status && childElement.setAttribute) {
        childElement.setAttribute('data-live-status-value', status)
      }

      placeholder.replaceWith(childElement)
      placeholders.push(...childPlaceholders(childElement))
    }
  }

  #buildChildElement(childResult) {
    if (!childResult) {
      return document.createTextNode('')
    }

    const html = renderParts(childResult['p'], childResult['s'] ?? {})

    return createDOMFromHTML(html)
  }
}

const subscriptionManager = new SubscriptionManager()

export default subscriptionManager
