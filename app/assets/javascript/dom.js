class DOM {
  #attributeMap = {
    'live-component': this.#replaceLiveComponent,
    'live-defaults': this.#replaceLiveDefaults,
    'live-actions': this.#replaceLiveActions,
    // live-id is last so everything else is available for Stimulus to take over
    'live-id': this.#replaceLiveId,
  }

  mutate(element) {
    for (const [attribute, callback] of Object.entries(this.#attributeMap)) {
      if (element.hasAttribute(attribute)) {
        callback.call(this, element, attribute, element.getAttribute(attribute))
      }
    }

    element.querySelectorAll('[live-form]').forEach(element => {
      this.#convertValues(element)
      this.#addActions(element, 'form', 'live-form', ':prevent')
    })

    element.querySelectorAll('[live-action]').forEach(element => {
      this.#convertValues(element)
      this.#addActions(element, 'action', 'live-action')
    })

    element.querySelectorAll('[live-debounce]').forEach(element => {
      this.#convertDebounce(element)
    })

    element.querySelectorAll('[live-reactive]').forEach(element => {
      this.#convertReactive(element)
    })

    // Check for live-id elements in descendants
    element.querySelectorAll('[live-id]').forEach(element => {
      this.mutate(element)
    })
  }

  #addActions(element, type, attribute, event_modifier = '') {
    const actions = element.getAttribute(attribute).trim().split(/\s+/).map(actionString => {
      const maybeWithEvent = actionString.split(/->/)
      const [event, action] = maybeWithEvent.length === 2 ? maybeWithEvent : [false, maybeWithEvent[0]]
      const stimulusEvent = event ? `${event}->` : ''

      return `${stimulusEvent}live#${type}_$${action}${event_modifier}`
    })

    element.removeAttribute(attribute)
    this.#appendToAttribute(element, 'data-action', actions.join(' '))
  }

  #convertValues(element) {
    // Get all attributes that start with 'live-value-'
    Array.from(element.attributes).forEach(attr => {
      if (attr.name.startsWith('live-value-')) {
        // Extract the parameter name (everything after 'live-value-')
        const paramName = attr.name.substring('live-value-'.length)
        const value = attr.value

        // Remove the live-value-* attribute
        element.removeAttribute(attr.name)

        // Add the data-live-*-param attribute
        element.setAttribute(`data-live-${paramName}-param`, value)
      }
    })
  }

  #convertDebounce(element) {
    const value = element.getAttribute('live-debounce')
    element.removeAttribute('live-debounce')
    element.setAttribute('data-live-debounce-param', value)
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

  #replaceLiveComponent(element, attribute, value) {
    element.removeAttribute(attribute)
    element.setAttribute('data-live-component-value', value)
  }

  #replaceLiveDefaults(element, attribute, value) {
    element.removeAttribute(attribute)
    element.setAttribute('data-live-defaults-value', value)
  }

  #replaceLiveActions(element, attribute, value) {
    element.removeAttribute(attribute)
    element.setAttribute('data-live-actions-value', value)
  }

  #replaceLiveId(element, attribute, value) {
    element.removeAttribute(attribute)
    element.setAttribute('data-live-id-value', value)
    this.#appendToAttribute(element, 'data-controller', 'live')
  }

  /**
   * Helper method to append a value to an attribute
   * If the attribute exists, appends with a space separator
   * If it doesn't exist, creates it with the value
   */
  #appendToAttribute(element, attributeName, value) {
    const existing = element.getAttribute(attributeName)
    if (existing) {
      element.setAttribute(attributeName, `${existing} ${value}`)
    } else {
      element.setAttribute(attributeName, value)
    }
  }
}

export default new DOM()
