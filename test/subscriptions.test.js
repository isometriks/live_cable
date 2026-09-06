import { describe, it, expect, beforeEach, vi } from 'vitest'

// The subscription manager creates an ActionCable consumer at import time, so
// the module is stubbed before importing it.
const sentMessages = []
const createdSubscriptions = []
// The socket the mocked consumer pretends to hold: open until a reconnect
// closes it, at which point the test re-opens it by firing `connected`.
const consumerSocket = { open: true, disconnects: 0, connects: 0 }

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    connection: {
      isOpen: () => consumerSocket.open,
    },
    disconnect() {
      consumerSocket.open = false
      consumerSocket.disconnects++
    },
    connect() {
      consumerSocket.connects++
    },
    subscriptions: {
      create(params, handlers) {
        const subscription = {
          params,
          handlers,
          unsubscribed: false,
          send: (message) => sentMessages.push(message),
          unsubscribe() {
            this.unsubscribed = true
          },
        }
        createdSubscriptions.push(subscription)
        return subscription
      },
    },
  }),
}))

const subscriptionManager = (await import('../app/assets/javascript/subscriptions.js')).default

// Minimal stand-in for the Stimulus live controller.
function buildController(element) {
  return {
    element,
    statusValue: 'disconnected',
    isLoading: false,
    finishLoading: vi.fn(),
    resetLoading: vi.fn(),
  }
}

function buildElement(status = 'disconnected') {
  const element = document.createElement('div')
  element.setAttribute('data-live-id-value', 'day-timer')
  element.setAttribute('data-live-component-value', 'timer')
  element.setAttribute('data-live-status-value', status)
  element.innerHTML = '<span>original</span>'
  document.body.appendChild(element)
  return element
}

function setCsrfToken(token) {
  let meta = document.querySelector("meta[name='csrf-token']")
  if (!meta) {
    meta = document.createElement('meta')
    meta.setAttribute('name', 'csrf-token')
    document.head.appendChild(meta)
  }
  meta.setAttribute('content', token)
}

describe('SubscriptionManager', () => {
  beforeEach(() => {
    sentMessages.length = 0
    createdSubscriptions.length = 0
    consumerSocket.open = true
    consumerSocket.disconnects = 0
    consumerSocket.connects = 0
    subscriptionManager.unsubscribe('timer/day-timer')
    subscriptionManager.unsubscribe('timer/night-timer')
    setCsrfToken('token-at-handshake')
  })

  it('reuses the existing subscription when a controller reconnects', () => {
    const first = buildController(buildElement())
    const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, first)

    const second = buildController(buildElement())
    const again = subscriptionManager.subscribe('day-timer', 'timer', {}, second)

    expect(again).toBe(subscription)
    expect(createdSubscriptions).toHaveLength(1)
    expect(createdSubscriptions[0].unsubscribed).toBe(false)
  })

  describe('when a controller reconnects after a Turbo navigation', () => {
    it('pushes the retained status onto the new controller', () => {
      const first = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', {}, first)

      // Server confirms the subscription against the original element.
      createdSubscriptions[0].handlers.received({ _status: 'subscribed' })
      expect(first.statusValue).toBe('subscribed')

      // Turbo renders a new page; the element is replaced and a fresh
      // controller connects to the same, still-live subscription.
      const second = buildController(buildElement('disconnected'))
      subscriptionManager.subscribe('day-timer', 'timer', {}, second)

      expect(second.statusValue).toBe('subscribed')
    })

    it('replays the last render into the new element', () => {
      const first = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', {}, first)

      createdSubscriptions[0].handlers.received({
        _refresh: { h: 'tpl', p: ['<div data-live-id-value="day-timer" data-live-component-value="timer"><span>from server</span></div>'] },
      })

      const secondElement = buildElement('disconnected')
      const second = buildController(secondElement)
      subscriptionManager.subscribe('day-timer', 'timer', {}, second)

      expect(second.element.textContent).toContain('from server')
      expect(second.statusValue).toBe('subscribed')
    })

    it('does not replay when no render has been received yet', () => {
      const first = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', {}, first)

      const secondElement = buildElement('disconnected')
      const second = buildController(secondElement)

      expect(() => {
        subscriptionManager.subscribe('day-timer', 'timer', {}, second)
      }).not.toThrow()

      expect(second.element.textContent).toContain('original')
    })
  })

  describe('send', () => {
    it('wraps the batch with the page\'s current CSRF token', () => {
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, buildController(buildElement()))

      subscription.send([{ _action: 'tick' }])

      expect(sentMessages).toEqual([
        { messages: [{ _action: 'tick' }], _csrf_token: 'token-at-handshake' },
      ])
    })
  })

  describe('when the server refuses a batch for a CSRF token from a newer session', () => {
    const refresh = { h: 'tpl', p: ['<div data-live-id-value="day-timer" data-live-component-value="timer"><span>fresh</span></div>'] }
    const batch = [{ _action: 'tick', params: '' }]

    function refuse(cable, messages = batch) {
      cable.handlers.received({ _reconnect: true, messages })
    }

    // What the server sends while re-subscribing on the fresh socket
    function resubscribe(cable, token = 'token-from-socket') {
      cable.handlers.received({ _csrf_token: token })
      cable.handlers.received({ _refresh: refresh })
      cable.handlers.connected()
    }

    it('reconnects the consumer so the next handshake carries the current cookie', () => {
      const controller = buildController(buildElement())
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, controller)
      subscription.send(batch)

      refuse(createdSubscriptions[0])

      expect(consumerSocket.disconnects).toBe(1)
      expect(consumerSocket.connects).toBe(1)
      // Nothing is replayed until the new socket confirms the subscription
      expect(sentMessages).toHaveLength(1)
    })

    it('replays the refused batch with the token the fresh socket issued', () => {
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, buildController(buildElement()))
      subscription.send(batch)
      refuse(createdSubscriptions[0])

      resubscribe(createdSubscriptions[0])

      expect(sentMessages).toHaveLength(2)
      expect(sentMessages[1]).toEqual({ messages: batch, _csrf_token: 'token-from-socket' })
      // The page carries the fresh token from now on
      expect(document.querySelector("meta[name='csrf-token']").getAttribute('content')).toBe('token-from-socket')
    })

    it('replays with the page\'s own token when the socket issued none', () => {
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, buildController(buildElement()))
      subscription.send(batch)
      refuse(createdSubscriptions[0])

      // Rendered from the newer session in the meantime
      setCsrfToken('token-from-new-page')
      createdSubscriptions[0].handlers.received({ _refresh: refresh })
      createdSubscriptions[0].handlers.connected()

      expect(sentMessages[1]).toEqual({ messages: batch, _csrf_token: 'token-from-new-page' })
    })

    it('does not reuse a token issued before the reconnect', () => {
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, buildController(buildElement()))
      createdSubscriptions[0].handlers.received({ _csrf_token: 'token-from-stale-socket' })
      subscription.send(batch)
      refuse(createdSubscriptions[0])

      createdSubscriptions[0].handlers.connected()

      expect(sentMessages[1]._csrf_token).toBe('token-at-handshake')
    })

    it('leaves the page\'s token alone on an ordinary subscribe', () => {
      subscriptionManager.subscribe('day-timer', 'timer', {}, buildController(buildElement()))

      // A socket kept across a Turbo navigation issues a token for the
      // session it was opened with, which may be older than the page's
      createdSubscriptions[0].handlers.received({ _csrf_token: 'token-from-socket' })
      createdSubscriptions[0].handlers.connected()

      expect(document.querySelector("meta[name='csrf-token']").getAttribute('content')).toBe('token-at-handshake')
      expect(sentMessages).toHaveLength(0)
      expect(consumerSocket.disconnects).toBe(0)
    })

    it('keeps the loading state until the replay is answered', () => {
      const controller = buildController(buildElement())
      controller.isLoading = true
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, controller)
      subscription.send(batch)
      refuse(createdSubscriptions[0])

      // The render from re-subscribing is not the batch's answer
      createdSubscriptions[0].handlers.received({ _refresh: refresh })
      expect(controller.finishLoading).not.toHaveBeenCalled()

      createdSubscriptions[0].handlers.connected()
      createdSubscriptions[0].handlers.received({ _refresh: refresh })
      expect(controller.finishLoading).toHaveBeenCalledTimes(1)
    })

    it('reconnects once when several components are refused together', () => {
      const day = subscriptionManager.subscribe('day-timer', 'timer', {}, buildController(buildElement()))
      const nightElement = buildElement()
      nightElement.setAttribute('data-live-id-value', 'night-timer')
      const night = subscriptionManager.subscribe('night-timer', 'timer', {}, buildController(nightElement))
      day.send(batch)
      night.send(batch)

      refuse(createdSubscriptions[0])
      refuse(createdSubscriptions[1])

      expect(consumerSocket.disconnects).toBe(1)
      expect(consumerSocket.connects).toBe(1)

      resubscribe(createdSubscriptions[0])
      resubscribe(createdSubscriptions[1])
      expect(sentMessages).toHaveLength(4)
    })

    it('replays each refused batch on its own so each gets an answer', () => {
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, buildController(buildElement()))
      const first = [{ _action: 'tick', params: '' }]
      const second = [{ _action: 'tock', params: '' }]
      subscription.send(first)
      subscription.send(second)
      refuse(createdSubscriptions[0], first)
      refuse(createdSubscriptions[0], second)

      resubscribe(createdSubscriptions[0])

      expect(sentMessages.slice(2).map(m => m.messages)).toEqual([first, second])
    })

    it('gives up without touching the page when the replay is refused as well', () => {
      const error = vi.spyOn(console, 'error').mockImplementation(() => {})
      const reload = vi.spyOn(window.location, 'reload').mockImplementation(() => {})
      const controller = buildController(buildElement())
      const rejected = vi.fn()
      document.addEventListener('live:rejected', rejected)
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', {}, controller)
      subscription.send(batch)
      refuse(createdSubscriptions[0])
      resubscribe(createdSubscriptions[0])
      // Typed while the replay was in flight
      controller.element.innerHTML = '<input value="typed by the user">'

      refuse(createdSubscriptions[0])

      expect(reload).not.toHaveBeenCalled()
      expect(consumerSocket.disconnects).toBe(1)
      expect(sentMessages).toHaveLength(2)
      expect(controller.resetLoading).toHaveBeenCalledTimes(1)
      expect(rejected).toHaveBeenCalledTimes(1)
      expect(rejected.mock.calls[0][0].detail).toEqual({ messages: batch })
      expect(controller.element.querySelector('input').value).toBe('typed by the user')

      document.removeEventListener('live:rejected', rejected)
      reload.mockRestore()
      error.mockRestore()
    })
  })

  describe('prune', () => {
    it('keeps subscriptions whose component is on the new page', () => {
      const controller = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', {}, controller)

      const newBody = document.createElement('body')
      newBody.innerHTML = '<div live-id="day-timer" live-component="timer"></div>'
      subscriptionManager.prune(newBody)

      expect(createdSubscriptions[0].unsubscribed).toBe(false)
    })

    it('unsubscribes components that are gone', () => {
      const controller = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', {}, controller)

      subscriptionManager.prune(document.createElement('body'))

      expect(createdSubscriptions[0].unsubscribed).toBe(true)
    })
  })
})
