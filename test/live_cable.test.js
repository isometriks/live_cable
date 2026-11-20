import { describe, it, expect, beforeEach, vi } from 'vitest'

const manager = vi.hoisted(() => ({
  syncIdentity: vi.fn(),
  prune: vi.fn(),
  keeps: vi.fn(),
  liveIdsWithin: vi.fn(),
  pruneDetached: vi.fn(),
}))

vi.mock('@isometriks/live_cable/subscriptions', () => ({ default: manager }))
vi.mock('@isometriks/live_cable/observer', () => ({ default: class { start() {} } }))

await import('../app/assets/javascript/live_cable.js')

const nextTask = () => new Promise((resolve) => setTimeout(resolve, 0))

function streamElement(attributes) {
  const stream = document.createElement('div')
  Object.entries(attributes).forEach(([name, value]) => stream.setAttribute(name, value))
  stream.targetElements = Array.from(document.querySelectorAll(`#${attributes.target}`))
  return stream
}

function beforeStreamRender(detail) {
  const event = new CustomEvent('turbo:before-stream-render', { bubbles: true, cancelable: true, detail })
  document.dispatchEvent(event)
  return event
}

describe('Turbo integration', () => {
  beforeEach(() => {
    Object.values(manager).forEach((fn) => fn.mockReset())
  })

  it('closes what a stream action took off the page, and only that', async () => {
    document.body.innerHTML = '<div id="item"></div><div id="other"></div>'
    const item = document.getElementById('item')
    const leaving = new Set(['timer/day-timer'])
    manager.liveIdsWithin.mockReturnValue(leaving)

    const event = beforeStreamRender({ render: vi.fn() })
    await event.detail.render(streamElement({ action: 'remove', target: 'item' }))
    await nextTask()

    expect(manager.liveIdsWithin).toHaveBeenCalledWith([item])
    expect(manager.pruneDetached).toHaveBeenCalledWith(leaving)
  })

  it('closes nothing for a stream action with no target', async () => {
    const event = beforeStreamRender({ render: vi.fn() })
    await event.detail.render(streamElement({ action: 'refresh' }))
    await nextTask()

    expect(manager.liveIdsWithin).toHaveBeenCalledWith([])
  })

  it('leaves a stream event without a render function alone', () => {
    const errors = []
    const onError = (event) => errors.push(event.error)
    window.addEventListener('error', onError)

    expect(() => beforeStreamRender(null)).not.toThrow()
    expect(beforeStreamRender({}).detail.render).toBeUndefined()

    window.removeEventListener('error', onError)
    expect(errors).toEqual([])
  })

  it('closes what a frame render took off the page, and only that', async () => {
    document.body.innerHTML = '<turbo-frame id="frame"></turbo-frame>'
    const frame = document.getElementById('frame')
    const leaving = new Set(['timer/day-timer'])
    manager.liveIdsWithin.mockReturnValue(leaving)

    frame.dispatchEvent(new CustomEvent('turbo:before-frame-render', { bubbles: true, detail: {} }))
    frame.dispatchEvent(new CustomEvent('turbo:frame-render', { bubbles: true, detail: {} }))
    await nextTask()

    expect(manager.liveIdsWithin).toHaveBeenCalledWith([frame])
    expect(manager.pruneDetached).toHaveBeenCalledWith(leaving)
  })
})
