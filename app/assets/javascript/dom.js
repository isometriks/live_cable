/**
 * DOM transformation module for LiveCable
 *
 * Converts live-* HTML attributes into Stimulus data-* attributes at runtime.
 * This allows for a cleaner HTML syntax while maintaining full Stimulus compatibility.
 */
class DOM {
  // All live-* attributes that trigger DOM processing
  static LIVE_ATTRIBUTES = [
    'live-id',
    'live-component',
    'live-defaults',
    'live-actions',
    'live-form',
    'live-action',
    'live-reactive'
  ]

  /**
   * Transforms all live-* attributes on an element and its descendants
   * @param {HTMLElement} element - The root element to process
   */
  mutate(element) {
    if (!element || !element.querySelectorAll) {
      return
    }

    // Build selector for all live-* attributes we care about
    const selector = DOM.LIVE_ATTRIBUTES.map(attr => `[${attr}]`).join(', ')

    // Get all elements with live-* attributes (including the root element if it matches)
    const liveElements = []
    if (element.matches && element.matches(selector)) {
      liveElements.push(element)
    }
    liveElements.push(...element.querySelectorAll(selector))

    liveElements.forEach(el => {
      // Process component metadata attributes first
      this.#processMetadataAttributes(el)

      // Process interactive attributes (actions, forms, reactive)
      this.#processInteractiveAttributes(el)

      // Process live-id last so all other attributes are converted before
      // the Stimulus controller is attached
      if (el.hasAttribute('live-id')) {
        this.#replaceLiveId(el)
      }
    })
  }

  #processMetadataAttributes(element) {
    if (element.hasAttribute('live-component')) {
      this.#replaceAttribute(element, 'live-component', 'data-live-component-value')
    }
    if (element.hasAttribute('live-defaults')) {
      this.#replaceAttribute(element, 'live-defaults', 'data-live-defaults-value')
    }
    if (element.hasAttribute('live-actions')) {
      this.#replaceAttribute(element, 'live-actions', 'data-live-actions-value')
    }
  }

  #processInteractiveAttributes(element) {
    // Note: convertValues and convertDebounce are called for each type as needed
    if (element.hasAttribute('live-form')) {
      this.#convertValues(element)
      this.#convertDebounce(element)
      this.#addActions(element, 'form', 'live-form', ':prevent')
    }

    if (element.hasAttribute('live-action')) {
      this.#convertValues(element)
      this.#convertDebounce(element)
      this.#addActions(element, 'action', 'live-action')
    }

    if (element.hasAttribute('live-reactive')) {
      this.#convertDebounce(element)
      this.#convertReactive(element)
    }
  }

  #replaceAttribute(element, oldAttr, newAttr) {
    const value = element.getAttribute(oldAttr)
    if (value !== null) {
      element.removeAttribute(oldAttr)
      element.setAttribute(newAttr, value)
    }
  }

  #addActions(element, type, attribute, eventModifier = '') {
    const attributeValue = element.getAttribute(attribute)
    if (!attributeValue) return

    const actions = attributeValue.trim().split(/\s+/).map(actionString => {
      const parts = actionString.split(/->/)
      const [event, action] = parts.length === 2 ? parts : [null, parts[0]]
      const stimulusEvent = event ? `${event}->` : ''

      return `${stimulusEvent}live#${type}_$${action}${eventModifier}`
    })

    element.removeAttribute(attribute)
    this.#appendToAttribute(element, 'data-action', actions.join(' '))
  }

  #convertValues(element) {
    // Get all attributes that start with 'live-value-'
    Array.from(element.attributes).forEach(attr => {
      if (attr.name.startsWith('live-value-')) {
        const paramName = attr.name.substring('live-value-'.length)
        element.removeAttribute(attr.name)
        element.setAttribute(`data-live-${paramName}-param`, attr.value)
      }
    })
  }

  #convertDebounce(element) {
    if (element.hasAttribute('live-debounce')) {
      const value = element.getAttribute('live-debounce')
      element.removeAttribute('live-debounce')
      element.setAttribute('data-live-debounce-param', value)
    }
  }

  #convertReactive(element) {
    const value = element.getAttribute('live-reactive')
    element.removeAttribute('live-reactive')

    if (!value || value.trim() === '') {
      // No events specified, use default Stimulus event
      this.#appendToAttribute(element, 'data-action', 'live#reactive')
    } else {
      // Multiple events specified, convert each to event->live#reactive
      const actions = value.trim().split(/\s+/).map(event => `${event}->live#reactive`)
      this.#appendToAttribute(element, 'data-action', actions.join(' '))
    }
  }

  #replaceLiveId(element) {
    this.#replaceAttribute(element, 'live-id', 'data-live-id-value')
    this.#appendToAttribute(element, 'data-controller', 'live')
  }

  #appendToAttribute(element, attributeName, value) {
    const existing = element.getAttribute(attributeName)

    if (existing) {
      const values = existing.split(/\s+/)
      if (!values.includes(value)) {
        element.setAttribute(attributeName, `${existing} ${value}`)
      }
    } else {
      element.setAttribute(attributeName, value)
    }
  }
}

export default new DOM()
