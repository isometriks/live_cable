import { describe, it, expect, beforeEach } from 'vitest'
import LoadingState from '../app/assets/javascript/loading.js'

describe('LoadingState', () => {
  let root
  let loading

  beforeEach(() => {
    root = document.createElement('div')
    document.body.appendChild(root)
    loading = new LoadingState(root)
  })

  describe('start', () => {
    it('marks the root element with live-loading', () => {
      loading.start()

      expect(root.hasAttribute('live-loading')).toBe(true)
      expect(loading.active).toBe(true)
    })

    it('marks the trigger element with live-loading', () => {
      const button = document.createElement('button')
      root.appendChild(button)

      loading.start(button)

      expect(button.hasAttribute('live-loading')).toBe(true)
    })

    it('does not mark the root twice when trigger is the root', () => {
      loading.start(root)

      expect(root.hasAttribute('live-loading')).toBe(true)
    })

    it('ignores non-element triggers', () => {
      expect(() => loading.start(null)).not.toThrow()
      expect(() => loading.start('not-an-element')).not.toThrow()
    })
  })

  describe('live-disable-with', () => {
    it('disables the trigger and swaps its label', () => {
      const button = document.createElement('button')
      button.setAttribute('live-disable-with', 'Saving...')
      button.textContent = 'Save'
      root.appendChild(button)

      loading.start(button)

      expect(button.disabled).toBe(true)
      expect(button.textContent).toBe('Saving...')
    })

    it('disables without swapping when the attribute has no value', () => {
      const button = document.createElement('button')
      button.setAttribute('live-disable-with', '')
      button.textContent = 'Save'
      root.appendChild(button)

      loading.start(button)

      expect(button.disabled).toBe(true)
      expect(button.textContent).toBe('Save')
    })

    it('swaps the value for input elements', () => {
      const input = document.createElement('input')
      input.type = 'submit'
      input.value = 'Save'
      input.setAttribute('live-disable-with', 'Saving...')
      root.appendChild(input)

      loading.start(input)

      expect(input.disabled).toBe(true)
      expect(input.value).toBe('Saving...')
    })

    it('disables marked descendants when the trigger is a form', () => {
      const form = document.createElement('form')
      const submit = document.createElement('button')
      submit.setAttribute('live-disable-with', 'Submitting...')
      submit.textContent = 'Submit'
      const other = document.createElement('button')
      other.textContent = 'Cancel'
      form.append(submit, other)
      root.appendChild(form)

      loading.start(form)

      expect(submit.disabled).toBe(true)
      expect(submit.textContent).toBe('Submitting...')
      expect(other.disabled).toBe(false)
      expect(other.textContent).toBe('Cancel')
    })

    it('does not disable the trigger when disable is false', () => {
      const input = document.createElement('input')
      input.setAttribute('live-disable-with', 'Wait...')
      input.value = 'typing'
      root.appendChild(input)

      loading.start(input, { disable: false })

      expect(input.disabled).toBe(false)
      expect(input.value).toBe('typing')
      expect(input.hasAttribute('live-loading')).toBe(true)
    })
  })

  describe('finish', () => {
    it('restores the root and trigger elements', () => {
      const button = document.createElement('button')
      button.setAttribute('live-disable-with', 'Saving...')
      button.textContent = 'Save'
      root.appendChild(button)

      loading.start(button)
      loading.finish()

      expect(root.hasAttribute('live-loading')).toBe(false)
      expect(button.hasAttribute('live-loading')).toBe(false)
      expect(button.disabled).toBe(false)
      expect(button.textContent).toBe('Save')
      expect(loading.active).toBe(false)
    })

    it('preserves a previously disabled state', () => {
      const button = document.createElement('button')
      button.setAttribute('live-disable-with', 'Saving...')
      button.disabled = true
      root.appendChild(button)

      loading.start(button)
      loading.finish()

      expect(button.disabled).toBe(true)
    })

    it('only clears once all in-flight messages are answered', () => {
      const button = document.createElement('button')
      button.setAttribute('live-disable-with', 'Working...')
      button.textContent = 'Go'
      root.appendChild(button)

      loading.start(button)
      loading.start()

      loading.finish()
      expect(root.hasAttribute('live-loading')).toBe(true)
      expect(button.disabled).toBe(true)

      loading.finish()
      expect(root.hasAttribute('live-loading')).toBe(false)
      expect(button.disabled).toBe(false)
      expect(button.textContent).toBe('Go')
    })

    it('is a no-op when nothing is in flight', () => {
      expect(loading.finish()).toBe(false)
      expect(root.hasAttribute('live-loading')).toBe(false)
    })

    it('does not double-swap when the same element triggers twice', () => {
      const button = document.createElement('button')
      button.setAttribute('live-disable-with', 'Saving...')
      button.textContent = 'Save'
      root.appendChild(button)

      loading.start(button)
      loading.start(button)
      loading.finish()
      loading.finish()

      expect(button.textContent).toBe('Save')
      expect(button.disabled).toBe(false)
    })
  })

  describe('reset', () => {
    it('clears everything regardless of in-flight count', () => {
      const button = document.createElement('button')
      button.setAttribute('live-disable-with', 'Saving...')
      button.textContent = 'Save'
      root.appendChild(button)

      loading.start(button)
      loading.start(button)
      loading.reset()

      expect(loading.active).toBe(false)
      expect(root.hasAttribute('live-loading')).toBe(false)
      expect(button.disabled).toBe(false)
      expect(button.textContent).toBe('Save')
    })
  })
})
