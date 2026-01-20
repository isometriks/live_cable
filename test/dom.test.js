import { describe, it, expect, beforeEach } from 'vitest'
import DOM from '../app/assets/javascript/dom.js'

describe('DOM', () => {
  let element

  beforeEach(() => {
    element = document.createElement('div')
    document.body.appendChild(element)
  })

  describe('mutate', () => {
    describe('live-id transformation', () => {
      it('transforms live-id to data-live-id-value', () => {
        element.setAttribute('live-id', 'test-123')
        DOM.mutate(element)

        expect(element.getAttribute('data-live-id-value')).toBe('test-123')
        expect(element.hasAttribute('live-id')).toBe(false)
      })

      it('adds live controller to data-controller', () => {
        element.setAttribute('live-id', 'test-123')
        DOM.mutate(element)

        expect(element.getAttribute('data-controller')).toBe('live')
      })

      it('appends live to existing data-controller', () => {
        element.setAttribute('live-id', 'test-123')
        element.setAttribute('data-controller', 'dropdown')
        DOM.mutate(element)

        expect(element.getAttribute('data-controller')).toBe('dropdown live')
      })

      it('does not duplicate live controller', () => {
        element.setAttribute('live-id', 'test-123')
        element.setAttribute('data-controller', 'live dropdown')
        DOM.mutate(element)

        expect(element.getAttribute('data-controller')).toBe('live dropdown')
      })
    })

    describe('live-component transformation', () => {
      it('transforms live-component to data-live-component-value', () => {
        element.setAttribute('live-component', 'counter')
        DOM.mutate(element)

        expect(element.getAttribute('data-live-component-value')).toBe('counter')
        expect(element.hasAttribute('live-component')).toBe(false)
      })
    })

    describe('live-actions transformation', () => {
      it('transforms live-actions to data-live-actions-value', () => {
        element.setAttribute('live-actions', '["increment","decrement"]')
        DOM.mutate(element)

        expect(element.getAttribute('data-live-actions-value')).toBe('["increment","decrement"]')
        expect(element.hasAttribute('live-actions')).toBe(false)
      })
    })

    describe('live-defaults transformation', () => {
      it('transforms live-defaults to data-live-defaults-value', () => {
        element.setAttribute('live-defaults', '{"count":0}')
        DOM.mutate(element)

        expect(element.getAttribute('data-live-defaults-value')).toBe('{"count":0}')
        expect(element.hasAttribute('live-defaults')).toBe(false)
      })
    })

    describe('live-action transformation', () => {
      it('transforms live-action to data-action with dynamic method', () => {
        const button = document.createElement('button')
        button.setAttribute('live-action', 'increment')
        element.appendChild(button)

        DOM.mutate(element)

        expect(button.getAttribute('data-action')).toBe('live#action_$increment')
        expect(button.hasAttribute('live-action')).toBe(false)
      })

      it('handles live-action with event modifier', () => {
        const button = document.createElement('button')
        button.setAttribute('live-action', 'keydown->search')
        element.appendChild(button)

        DOM.mutate(element)

        expect(button.getAttribute('data-action')).toBe('keydown->live#action_$search')
      })

      it('handles multiple space-separated actions', () => {
        const button = document.createElement('button')
        button.setAttribute('live-action', 'save reset')
        element.appendChild(button)

        DOM.mutate(element)

        expect(button.getAttribute('data-action')).toBe('live#action_$save live#action_$reset')
      })

      it('appends to existing data-action', () => {
        const button = document.createElement('button')
        button.setAttribute('data-action', 'click->other#method')
        button.setAttribute('live-action', 'increment')
        element.appendChild(button)

        DOM.mutate(element)

        expect(button.getAttribute('data-action')).toBe('click->other#method live#action_$increment')
      })
    })

    describe('live-form transformation', () => {
      it('transforms live-form to data-action with prevent modifier', () => {
        const form = document.createElement('form')
        form.setAttribute('live-form', 'submit->save')
        element.appendChild(form)

        DOM.mutate(element)

        expect(form.getAttribute('data-action')).toBe('submit->live#form_$save:prevent')
        expect(form.hasAttribute('live-form')).toBe(false)
      })

      it('handles live-form with custom event', () => {
        const form = document.createElement('form')
        form.setAttribute('live-form', 'change->filter')
        element.appendChild(form)

        DOM.mutate(element)

        expect(form.getAttribute('data-action')).toBe('change->live#form_$filter:prevent')
      })
    })

    describe('live-value-* transformation', () => {
      it('transforms live-value-* to data-live-*-param', () => {
        const button = document.createElement('button')
        button.setAttribute('live-action', 'update')
        button.setAttribute('live-value-id', '123')
        button.setAttribute('live-value-status', 'active')
        element.appendChild(button)

        DOM.mutate(element)

        expect(button.getAttribute('data-live-id-param')).toBe('123')
        expect(button.getAttribute('data-live-status-param')).toBe('active')
        expect(button.hasAttribute('live-value-id')).toBe(false)
        expect(button.hasAttribute('live-value-status')).toBe(false)
      })

      it('handles kebab-case parameter names', () => {
        const button = document.createElement('button')
        button.setAttribute('live-action', 'update')
        button.setAttribute('live-value-user-email', 'test@example.com')
        element.appendChild(button)

        DOM.mutate(element)

        expect(button.getAttribute('data-live-user-email-param')).toBe('test@example.com')
      })
    })

    describe('live-debounce transformation', () => {
      it('transforms live-debounce to data-live-debounce-param', () => {
        const input = document.createElement('input')
        input.setAttribute('live-reactive', '')
        input.setAttribute('live-debounce', '300')
        element.appendChild(input)

        DOM.mutate(element)

        expect(input.getAttribute('data-live-debounce-param')).toBe('300')
        expect(input.hasAttribute('live-debounce')).toBe(false)
      })

      it('works with live-action and debounce', () => {
        const button = document.createElement('button')
        button.setAttribute('live-action', 'search')
        button.setAttribute('live-debounce', '500')
        element.appendChild(button)

        DOM.mutate(element)

        expect(button.getAttribute('data-action')).toBe('live#action_$search')
        expect(button.getAttribute('data-live-debounce-param')).toBe('500')
      })
    })

    describe('live-reactive transformation', () => {
      it('transforms live-reactive to data-action with reactive method', () => {
        const input = document.createElement('input')
        input.setAttribute('live-reactive', '')
        element.appendChild(input)

        DOM.mutate(element)

        expect(input.getAttribute('data-action')).toBe('live#reactive')
        expect(input.hasAttribute('live-reactive')).toBe(false)
      })

      it('handles live-reactive with event', () => {
        const input = document.createElement('input')
        input.setAttribute('live-reactive', 'keydown')
        element.appendChild(input)

        DOM.mutate(element)

        expect(input.getAttribute('data-action')).toBe('keydown->live#reactive')
      })

      it('handles multiple events', () => {
        const input = document.createElement('input')
        input.setAttribute('live-reactive', 'input change')
        element.appendChild(input)

        DOM.mutate(element)

        expect(input.getAttribute('data-action')).toBe('input->live#reactive change->live#reactive')
      })
    })

    describe('complex scenarios', () => {
      it('handles complete component with all attributes', () => {
        element.setAttribute('live-id', 'counter-1')
        element.setAttribute('live-component', 'counter')
        element.setAttribute('live-actions', '["increment"]')
        element.setAttribute('live-defaults', '{"count":0}')

        const button = document.createElement('button')
        button.setAttribute('live-action', 'increment')
        button.setAttribute('live-value-amount', '5')
        element.appendChild(button)

        DOM.mutate(element)

        // Check root element
        expect(element.getAttribute('data-live-id-value')).toBe('counter-1')
        expect(element.getAttribute('data-live-component-value')).toBe('counter')
        expect(element.getAttribute('data-live-actions-value')).toBe('["increment"]')
        expect(element.getAttribute('data-live-defaults-value')).toBe('{"count":0}')
        expect(element.getAttribute('data-controller')).toBe('live')

        // Check button
        expect(button.getAttribute('data-action')).toBe('live#action_$increment')
        expect(button.getAttribute('data-live-amount-param')).toBe('5')
      })

      it('handles form with debounce and values', () => {
        const form = document.createElement('form')
        form.setAttribute('live-form', 'change->filter')
        form.setAttribute('live-debounce', '300')
        form.setAttribute('live-value-category', 'electronics')
        element.appendChild(form)

        DOM.mutate(element)

        expect(form.getAttribute('data-action')).toBe('change->live#form_$filter:prevent')
        expect(form.getAttribute('data-live-debounce-param')).toBe('300')
        expect(form.getAttribute('data-live-category-param')).toBe('electronics')
      })
    })
  })

  describe('appendToAttribute helper', () => {
    it('creates attribute if it does not exist', () => {
      element.setAttribute('live-id', 'test-123')
      DOM.mutate(element)

      expect(element.getAttribute('data-controller')).toBe('live')
    })

    it('appends to existing attribute with space', () => {
      element.setAttribute('data-controller', 'dropdown')
      element.setAttribute('live-id', 'test-123')
      DOM.mutate(element)

      expect(element.getAttribute('data-controller')).toBe('dropdown live')
    })

    it('does not add duplicate values', () => {
      element.setAttribute('data-controller', 'live dropdown')
      element.setAttribute('live-id', 'test-123')
      DOM.mutate(element)

      // Should not add 'live' again
      expect(element.getAttribute('data-controller')).toBe('live dropdown')
    })

    it('handles multiple appends correctly', () => {
      element.setAttribute('data-action', 'click->other#method')

      const button1 = document.createElement('button')
      button1.setAttribute('live-action', 'save')
      element.appendChild(button1)

      const button2 = document.createElement('button')
      button2.setAttribute('live-action', 'reset')
      element.appendChild(button2)

      DOM.mutate(element)

      expect(button1.getAttribute('data-action')).toBe('live#action_$save')
      expect(button2.getAttribute('data-action')).toBe('live#action_$reset')
    })
  })
})
