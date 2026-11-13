import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { Application } from '@hotwired/stimulus'

const sent = []

vi.mock('@isometriks/live_cable/subscriptions', () => ({
  default: {
    subscribe: () => ({
      pendingCount: 0,
      send: (message) => sent.push(message),
      discardPending: () => 0,
    }),
  },
}))

const { default: LiveController } = await import('../app/assets/javascript/controllers/live_controller.js')

describe('live controller', () => {
  let application

  beforeEach(async () => {
    sent.length = 0
    application = Application.start()
    application.register('live', LiveController)
  })

  afterEach(() => {
    application.stop()
  })

  async function mount(html) {
    document.body.innerHTML = `
      <div data-controller="live" data-live-id-value="x" data-live-component-value="c" data-live-actions-value="[]">
        ${html}
      </div>
    `
    await new Promise((resolve) => setTimeout(resolve, 0))
  }

  function change(element) {
    element.dispatchEvent(new Event('change', { bubbles: true }))
  }

  function lastReactive() {
    return sent.at(-1).messages.at(-1)
  }

  describe('reactive', () => {
    it('sends a checkbox as a boolean', async () => {
      await mount('<input type="checkbox" name="notify" data-action="change->live#reactive">')
      const checkbox = document.querySelector('input')

      checkbox.checked = true
      change(checkbox)
      expect(lastReactive()).toEqual({ _action: '_reactive', name: 'notify', value: true })

      checkbox.checked = false
      change(checkbox)
      expect(lastReactive()).toEqual({ _action: '_reactive', name: 'notify', value: false })
    })

    it('sends a checkbox as a boolean even with a value attribute', async () => {
      await mount('<input type="checkbox" name="agree" value="yes" data-action="change->live#reactive">')
      const checkbox = document.querySelector('input')

      checkbox.checked = false
      change(checkbox)

      expect(lastReactive().value).toBe(false)
    })

    it('sends every selected option of a multiple select', async () => {
      await mount(`
        <select multiple name="tags" data-action="change->live#reactive">
          <option value="a">A</option>
          <option value="b">B</option>
          <option value="c">C</option>
        </select>
      `)
      const select = document.querySelector('select')

      select.options[1].selected = true
      select.options[2].selected = true
      change(select)
      expect(lastReactive().value).toEqual(['b', 'c'])

      select.options[1].selected = false
      select.options[2].selected = false
      change(select)
      expect(lastReactive().value).toEqual([])
    })

    it('sends the value of a single select', async () => {
      await mount(`
        <select name="size" data-action="change->live#reactive">
          <option value="s">S</option>
          <option value="m">M</option>
        </select>
      `)
      const select = document.querySelector('select')

      select.value = 'm'
      change(select)

      expect(lastReactive().value).toBe('m')
    })

    it('sends the value of the chosen radio', async () => {
      await mount(`
        <input type="radio" name="size" value="s" data-action="change->live#reactive">
        <input type="radio" name="size" value="m" data-action="change->live#reactive">
      `)
      const radio = document.querySelector('input[value="m"]')

      radio.checked = true
      change(radio)

      expect(lastReactive()).toEqual({ _action: '_reactive', name: 'size', value: 'm' })
    })

    it('sends the value of a text input', async () => {
      await mount('<input type="text" name="query" data-action="input->live#reactive">')
      const input = document.querySelector('input')

      input.value = 'hello'
      input.dispatchEvent(new Event('input', { bubbles: true }))

      expect(lastReactive()).toEqual({ _action: '_reactive', name: 'query', value: 'hello' })
    })

    it('sends a debounced checkbox as a boolean', async () => {
      await mount(`
        <input type="checkbox" name="notify" data-action="change->live#reactive" data-live-debounce-param="1000">
        <input type="text" name="query" data-action="input->live#reactive">
      `)
      const checkbox = document.querySelector('input[type="checkbox"]')
      const input = document.querySelector('input[type="text"]')

      checkbox.checked = true
      change(checkbox)
      input.value = 'x'
      input.dispatchEvent(new Event('input', { bubbles: true }))

      expect(sent.at(-1).messages).toEqual([
        { _action: '_reactive', name: 'notify', value: true },
        { _action: '_reactive', name: 'query', value: 'x' },
      ])
    })
  })
})
