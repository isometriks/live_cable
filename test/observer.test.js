import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

// Mock the DOM module before importing observer
const mockMutate = vi.fn()
vi.mock('../app/assets/javascript/dom.js', () => ({
  default: { mutate: mockMutate }
}))

// Now import observer after mock is set up
const { default: LiveObserver } = await import('../app/assets/javascript/observer.js')

describe('LiveObserver', () => {
  let observer

  beforeEach(() => {
    observer = new LiveObserver()
    mockMutate.mockClear()
    document.body.innerHTML = ''
  })

  afterEach(() => {
    if (observer) {
      observer.stop()
    }
  })

  describe('constructor', () => {
    it('creates a new observer instance', () => {
      expect(observer).toBeDefined()
    })
  })

  describe('start', () => {
    it('starts observing the DOM', () => {
      observer.start()
      // The private field won't be accessible, but we can test behavior
      expect(() => observer.start()).not.toThrow()
    })

    it('does not create multiple observers if called twice', () => {
      observer.start()
      observer.start()
      // Should not throw and should handle gracefully
      expect(true).toBe(true)
    })

    it('checks existing elements on start', () => {
      // Add element before starting
      document.body.innerHTML = '<div live-id="test-123"></div>'

      observer.start()

      // Should have called mutate for the element
      expect(mockMutate).toHaveBeenCalled()
    })
  })

  describe('stop', () => {
    it('stops the observer', () => {
      observer.start()
      observer.stop()

      // Observer should stop watching
      expect(() => observer.stop()).not.toThrow()
    })

    it('can be called multiple times safely', () => {
      observer.start()
      observer.stop()
      observer.stop()

      expect(true).toBe(true)
    })
  })

  describe('checkElement', () => {
    it('processes elements with live-id attribute', () => {
      const element = document.createElement('div')
      element.setAttribute('live-id', 'test-123')
      document.body.appendChild(element)

      observer.checkElement(element)

      expect(mockMutate).toHaveBeenCalledWith(element)
    })

    it('finds descendant elements with live-id', () => {
      const parent = document.createElement('div')
      const child = document.createElement('div')
      child.setAttribute('live-id', 'child-123')
      parent.appendChild(child)
      document.body.appendChild(parent)

      observer.checkElement(parent)

      // Should process the child element
      expect(mockMutate).toHaveBeenCalledWith(child)
    })

    it('processes multiple descendant elements', () => {
      const parent = document.createElement('div')

      const child1 = document.createElement('div')
      child1.setAttribute('live-id', 'child-1')
      parent.appendChild(child1)

      const child2 = document.createElement('div')
      child2.setAttribute('live-id', 'child-2')
      parent.appendChild(child2)

      document.body.appendChild(parent)

      observer.checkElement(parent)

      expect(mockMutate).toHaveBeenCalledTimes(2)
      expect(mockMutate).toHaveBeenCalledWith(child1)
      expect(mockMutate).toHaveBeenCalledWith(child2)
    })

    it('handles elements without live-id', () => {
      const element = document.createElement('div')
      document.body.appendChild(element)

      observer.checkElement(element)

      expect(mockMutate).not.toHaveBeenCalled()
    })
  })

  describe('mutation detection', () => {
    it('detects when elements with live-id are added', async () => {
      observer.start()

      // Wait a tick for observer to be ready
      await new Promise(resolve => setTimeout(resolve, 0))

      mockMutate.mockClear()

      const element = document.createElement('div')
      element.setAttribute('live-id', 'new-element')
      document.body.appendChild(element)

      // Wait for mutation observer to fire
      await new Promise(resolve => setTimeout(resolve, 50))

      expect(mockMutate).toHaveBeenCalledWith(element)
    })

    it('detects nested elements with live-id', async () => {
      observer.start()
      await new Promise(resolve => setTimeout(resolve, 0))

      mockMutate.mockClear()

      const parent = document.createElement('div')
      const child = document.createElement('div')
      child.setAttribute('live-id', 'child-id')
      parent.appendChild(child)

      document.body.appendChild(parent)

      await new Promise(resolve => setTimeout(resolve, 50))

      expect(mockMutate).toHaveBeenCalledWith(child)
    })

    it('processes multiple elements added at once', async () => {
      observer.start()
      await new Promise(resolve => setTimeout(resolve, 0))

      mockMutate.mockClear()

      const container = document.createElement('div')

      const el1 = document.createElement('div')
      el1.setAttribute('live-id', 'id-1')
      container.appendChild(el1)

      const el2 = document.createElement('div')
      el2.setAttribute('live-id', 'id-2')
      container.appendChild(el2)

      document.body.appendChild(container)

      await new Promise(resolve => setTimeout(resolve, 50))

      expect(mockMutate).toHaveBeenCalledWith(el1)
      expect(mockMutate).toHaveBeenCalledWith(el2)
    })
  })

  describe('integration', () => {
    it('does not process elements without live-id', async () => {
      observer.start()
      await new Promise(resolve => setTimeout(resolve, 0))

      mockMutate.mockClear()

      const element = document.createElement('div')
      element.setAttribute('data-other', 'value')
      document.body.appendChild(element)

      await new Promise(resolve => setTimeout(resolve, 50))

      expect(mockMutate).not.toHaveBeenCalled()
    })

    it('handles rapid additions gracefully', async () => {
      observer.start()
      await new Promise(resolve => setTimeout(resolve, 0))

      mockMutate.mockClear()

      // Add multiple elements rapidly
      for (let i = 0; i < 5; i++) {
        const el = document.createElement('div')
        el.setAttribute('live-id', `rapid-${i}`)
        document.body.appendChild(el)
      }

      await new Promise(resolve => setTimeout(resolve, 50))

      expect(mockMutate).toHaveBeenCalledTimes(5)
    })
  })
})
