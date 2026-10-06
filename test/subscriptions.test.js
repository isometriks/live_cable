import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

// The subscription manager creates an ActionCable consumer at import time, so
// the module is stubbed before importing it.
const sentMessages = []
const createdSubscriptions = []
// ActionCable's send returns false, and drops the message, on a closed socket
const socket = { open: true }

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: {
      create(params, handlers) {
        const subscription = {
          params,
          handlers,
          unsubscribed: false,
          send(message) {
            if (!socket.open) {
              return false
            }

            sentMessages.push(message)
            return true
          },
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

describe('SubscriptionManager', () => {
  beforeEach(() => {
    sentMessages.length = 0
    createdSubscriptions.length = 0
    socket.open = true
    subscriptionManager.unsubscribe('timer/day-timer')
  })

  it('reuses the existing subscription when a controller reconnects', () => {
    const first = buildController(buildElement())
    const subscription = subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', first)

    const second = buildController(buildElement())
    const again = subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', second)

    expect(again).toBe(subscription)
    expect(createdSubscriptions).toHaveLength(1)
    expect(createdSubscriptions[0].unsubscribed).toBe(false)
  })

  describe('when a controller reconnects after a Turbo navigation', () => {
    it('pushes the retained status onto the new controller', () => {
      const first = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', first)

      // Server confirms the subscription against the original element.
      createdSubscriptions[0].handlers.received({ _status: 'subscribed' })
      expect(first.statusValue).toBe('subscribed')

      // Turbo renders a new page; the element is replaced and a fresh
      // controller connects to the same, still-live subscription.
      const second = buildController(buildElement('disconnected'))
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', second)

      expect(second.statusValue).toBe('subscribed')
    })

    it('replays the last render into the new element', () => {
      const first = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', first)

      createdSubscriptions[0].handlers.received({
        _refresh: { h: 'tpl', p: ['<div data-live-id-value="day-timer" data-live-component-value="timer"><span>from server</span></div>'] },
      })

      const secondElement = buildElement('disconnected')
      const second = buildController(secondElement)
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', second)

      expect(second.element.textContent).toContain('from server')
      expect(second.statusValue).toBe('subscribed')
    })

    it('does not replay when no render has been received yet', () => {
      const first = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', first)

      const secondElement = buildElement('disconnected')
      const second = buildController(secondElement)

      expect(() => {
        subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', second)
      }).not.toThrow()

      expect(second.element.textContent).toContain('original')
    })
  })

  describe('when an element for a live component arrives with defaults', () => {
    afterEach(() => {
      document.documentElement.removeAttribute('data-turbo-preview')
    })

    it('keeps the subscription when the defaults are the same', () => {
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

      expect(createdSubscriptions).toHaveLength(1)
      expect(createdSubscriptions[0].unsubscribed).toBe(false)
    })

    it('subscribes afresh with the new defaults when they differ', () => {
      const first = subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))
      const controller = buildController(buildElement())

      const second = subscriptionManager.subscribe('day-timer', 'timer', 'blob-b', controller)

      expect(second).not.toBe(first)
      expect(createdSubscriptions[0].unsubscribed).toBe(true)
      expect(createdSubscriptions).toHaveLength(2)
      expect(createdSubscriptions[1].params.defaults).toBe('blob-b')
      expect(controller.statusValue).toBe('disconnected')
    })

    it('keeps the subscription for an element rendered over the socket, which carries no defaults', () => {
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

      subscriptionManager.subscribe('day-timer', 'timer', '', buildController(buildElement()))
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

      expect(createdSubscriptions).toHaveLength(1)
    })

    it('waits out a Turbo preview, then subscribes afresh when the page itself renders', () => {
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

      document.documentElement.setAttribute('data-turbo-preview', '')
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-stale', buildController(buildElement()))

      expect(createdSubscriptions).toHaveLength(1)

      document.documentElement.removeAttribute('data-turbo-preview')
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-b', buildController(buildElement()))

      expect(createdSubscriptions).toHaveLength(2)
      expect(createdSubscriptions[1].params.defaults).toBe('blob-b')
    })
  })

  describe('prune', () => {
    it('keeps subscriptions whose component is on the new page', () => {
      const controller = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', controller)

      const newBody = document.createElement('body')
      newBody.innerHTML = '<div live-id="day-timer" live-component="timer"></div>'
      subscriptionManager.prune(newBody)

      expect(createdSubscriptions[0].unsubscribed).toBe(false)
    })

    it('unsubscribes components that are gone', () => {
      const controller = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', controller)

      subscriptionManager.prune(document.createElement('body'))

      expect(createdSubscriptions[0].unsubscribed).toBe(true)
    })
  })

  describe('when the server destroys the component', () => {
    it('unsubscribes and clears the loading state, since no reply follows', () => {
      const controller = buildController(buildElement())
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', controller)

      createdSubscriptions[0].handlers.received({ _status: 'destroy' })

      expect(createdSubscriptions[0].unsubscribed).toBe(true)
      expect(controller.resetLoading).toHaveBeenCalled()
    })
  })

  describe('sending', () => {
    const message = (action) => ({ messages: [{ _action: action }] })

    function subscribe() {
      const controller = buildController(buildElement())
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', controller)
      return { controller, subscription, handlers: createdSubscriptions[0].handlers }
    }

    it('sends straight away once the subscription is confirmed', () => {
      const { subscription, handlers } = subscribe()
      handlers.connected()

      subscription.send(message('increment'))

      expect(sentMessages).toEqual([message('increment')])
    })

    it('holds a message sent before the subscription is confirmed, then sends it', () => {
      const { subscription, handlers } = subscribe()

      subscription.send(message('increment'))
      expect(sentMessages).toEqual([])

      handlers.connected()
      expect(sentMessages).toEqual([message('increment')])
    })

    it('holds messages while the socket is down and sends them in order after it reconnects', () => {
      const { controller, subscription, handlers } = subscribe()
      handlers.connected()

      socket.open = false
      handlers.disconnected()
      expect(controller.statusValue).toBe('disconnected')

      subscription.send(message('first'))
      subscription.send(message('second'))
      expect(sentMessages).toEqual([])

      socket.open = true
      handlers.connected({ reconnected: true })
      expect(sentMessages).toEqual([message('first'), message('second')])
    })

    it('holds a message the socket refused before ActionCable noticed it had closed', () => {
      const { subscription, handlers } = subscribe()
      handlers.connected()

      socket.open = false
      subscription.send(message('increment'))

      socket.open = true
      handlers.connected({ reconnected: true })
      expect(sentMessages).toEqual([message('increment')])
    })

    it('counts held messages until they are sent', () => {
      const { subscription, handlers } = subscribe()

      subscription.send(message('first'))
      subscription.send(message('second'))
      expect(subscription.pendingCount).toBe(2)

      handlers.connected()
      expect(subscription.pendingCount).toBe(0)
    })

    it('discards held messages when asked, so they are never sent', () => {
      const { subscription, handlers } = subscribe()

      subscription.send(message('increment'))
      expect(subscription.discardPending()).toBe(1)

      handlers.connected()
      expect(sentMessages).toEqual([])
    })
  })

  // Component states outlive each test, so every test uses its own ids.
  describe('nested components', () => {
    const placeholder = (liveId) => `<LiveCable child-live-id="${liveId}"></LiveCable>`
    const find = (component, id) =>
      document.querySelector(`[data-live-component-value="${component}"][data-live-id-value="${id}"]`)

    function connect(element) {
      const id = element.getAttribute('data-live-id-value')
      const component = element.getAttribute('data-live-component-value')
      subscriptionManager.subscribe(id, component, '', buildController(element))
      return createdSubscriptions.at(-1).handlers
    }

    function mountRoot(component, id) {
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', component)
      document.body.appendChild(element)
      return connect(element)
    }

    afterEach(() => {
      vi.restoreAllMocks()
    })

    it('resolves a grandchild arriving in the same refresh as its parent', () => {
      const room = mountRoot('room', 'nested-1')

      room.received({
        _refresh: {
          h: 'room',
          p: ['<div live-id="nested-1" live-component="room">', placeholder('thread/nested-1'), '</div>'],
          c: {
            'thread/nested-1': {
              h: 'thread',
              p: ['<div live-id="nested-1" live-component="thread">', placeholder('messages/nested-1'), '</div>'],
            },
            'messages/nested-1': {
              h: 'messages',
              p: ['<div live-id="nested-1" live-component="messages">hello</div>'],
            },
          },
        },
      })

      expect(find('messages', 'nested-1')?.textContent).toBe('hello')
      expect(document.querySelector('LiveCable')).toBeNull()
    })

    it('keeps a grandchild added by its parent when the grandparent refreshes', () => {
      const room = mountRoot('room', 'nested-2')

      room.received({
        _refresh: {
          h: 'room',
          p: ['<div live-id="nested-2" live-component="room">', '<h1>Lobby</h1>', placeholder('thread/nested-2'), '</div>'],
          c: {
            'thread/nested-2': { h: 'thread', p: ['<div live-id="nested-2" live-component="thread">', '', '</div>'] },
          },
        },
      })

      const thread = connect(find('thread', 'nested-2'))

      thread.received({
        _refresh: {
          h: 'thread',
          p: [null, placeholder('messages/nested-2'), null],
          c: {
            'messages/nested-2': {
              h: 'messages',
              p: ['<div live-id="nested-2" live-component="messages">hello</div>'],
            },
          },
        },
      })

      const messages = find('messages', 'nested-2')
      connect(messages)

      room.received({ _refresh: { h: 'room', p: [null, '<h1>Renamed</h1>', null, null] } })

      expect(document.querySelector('h1').textContent).toBe('Renamed')
      expect(find('messages', 'nested-2')).toBe(messages)
      expect(messages.isConnected).toBe(true)
      expect(messages.textContent).toBe('hello')
    })

    it('drops a child that is rendered inside itself instead of looping', () => {
      const error = vi.spyOn(console, 'error').mockImplementation(() => {})
      const room = mountRoot('room', 'nested-3')

      room.received({
        _refresh: {
          h: 'room',
          p: ['<div live-id="nested-3" live-component="room">', placeholder('thread/nested-3'), '</div>'],
          c: {
            'thread/nested-3': {
              h: 'thread',
              p: ['<div live-id="nested-3" live-component="thread">', placeholder('thread/nested-3'), '</div>'],
            },
          },
        },
      })

      expect(document.querySelectorAll('[data-live-component-value="thread"][data-live-id-value="nested-3"]')).toHaveLength(1)
      expect(document.querySelector('LiveCable')).toBeNull()
      expect(error).toHaveBeenCalledOnce()
    })

    it('still applies a refresh that leaves out a child with nothing to rebuild from', () => {
      const room = mountRoot('room', 'nested-4')

      room.received({
        _refresh: {
          h: 'room',
          p: ['<div live-id="nested-4" live-component="room">', '<h2>Lobby</h2>', placeholder('thread/nested-4'), '</div>'],
          c: {
            'thread/nested-4': { h: 'thread', p: ['<div live-id="nested-4" live-component="thread"></div>'] },
          },
        },
      })

      // Connecting on a copy, not the element the refresh built, leaves the
      // thread's subscription with an empty state.
      const thread = find('thread', 'nested-4')
      const copy = thread.cloneNode(true)
      thread.replaceWith(copy)
      connect(copy)

      room.received({ _refresh: { h: 'room', p: [null, '<h2>Renamed</h2>', null, null] } })

      expect(find('room', 'nested-4').querySelector('h2').textContent).toBe('Renamed')
    })
  })
})
