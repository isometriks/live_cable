import DOM from "live_cable_dom"

/**
 * LiveCable DOM Observer
 *
 * Observes the DOM for elements with the `live-id` attribute
 */
export default class LiveObserver {
  #observer

  /**
   * Start observing the DOM for live components
   */
  start() {
    if (this.#observer) {
      return
    }

    this.#observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        // Handle added nodes
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE) {
            this.checkElement(node)
          }
        })

        // Handle attribute changes
        if (mutation.type === 'attributes' && mutation.attributeName === 'live-id') {
          const element = mutation.target
          if (element.hasAttribute('live-id')) {
            DOM.mutate(element)
          }
        }
      })
    })

    this.#observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['live-id'],
    })

    // Check the DOM as well when we start
    this.checkElement(document.documentElement)
  }

  /**
   * Stop observing the DOM
   */
  stop() {
    if (this.#observer) {
      this.#observer.disconnect()
      this.#observer = null
    }
  }

  /**
   * Check if an element or its descendants have live-id attribute
   */
  checkElement(element) {
    if (element.hasAttribute && element.hasAttribute('live-id')) {
      DOM.mutate(element)
    }

    if (element.querySelectorAll) {
      const liveElements = element.querySelectorAll('[live-id]')
      liveElements.forEach((liveElement) => {
        DOM.mutate(liveElement)
      })
    }
  }
}
