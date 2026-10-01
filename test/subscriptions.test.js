import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { Application } from '@hotwired/stimulus'
import LoadingState from '../app/assets/javascript/loading.js'

// The subscription manager creates an ActionCable consumer at import time, so
// the module is stubbed before importing it.
const sentMessages = []
const createdSubscriptions = []
// ActionCable's send returns false, and drops the message, on a closed socket
const socket = { open: true }
const cableConnection = { active: true, reopen: vi.fn(), isActive() { return this.active } }

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    connection: cableConnection,
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
const { default: LiveController } = await import('../app/assets/javascript/controllers/live_controller.js')

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

  describe('when a page says who it was rendered for', () => {
    function renderPageFor(identity) {
      document.head.querySelector('meta[name="live-cable-identity"]')?.remove()

      if (identity) {
        const meta = document.createElement('meta')
        meta.name = 'live-cable-identity'
        meta.content = identity
        document.head.appendChild(meta)
      }

      subscriptionManager.syncIdentity()
    }

    beforeEach(() => {
      cableConnection.active = true
      renderPageFor('digest-a')
      cableConnection.reopen.mockClear()
    })

    afterEach(() => {
      document.head.querySelector('meta[name="live-cable-identity"]')?.remove()
      document.documentElement.removeAttribute('data-turbo-preview')
    })

    it('keeps the socket while it is the same', () => {
      renderPageFor('digest-a')

      expect(cableConnection.reopen).not.toHaveBeenCalled()
    })

    it('reopens the socket when it changes, once', () => {
      renderPageFor('digest-b')
      renderPageFor('digest-b')

      expect(cableConnection.reopen).toHaveBeenCalledOnce()
    })

    it('ignores a page without the tag', () => {
      renderPageFor(null)
      renderPageFor('digest-a')

      expect(cableConnection.reopen).not.toHaveBeenCalled()
    })

    it('ignores a Turbo preview of a cached page, whose tag may be stale', () => {
      document.documentElement.setAttribute('data-turbo-preview', '')
      renderPageFor('digest-stale')
      document.documentElement.removeAttribute('data-turbo-preview')
      renderPageFor('digest-a')

      expect(cableConnection.reopen).not.toHaveBeenCalled()
    })

    it('does not open a socket that is not open, which will identify the new session anyway', () => {
      cableConnection.active = false
      renderPageFor('digest-b')
      cableConnection.active = true
      renderPageFor('digest-b')

      expect(cableConnection.reopen).not.toHaveBeenCalled()
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

    describe('with a component that renders children inline', () => {
      const placeholder = (liveId) => `<LiveCable child-live-id="${liveId}"></LiveCable>`
      const find = (component, id) =>
        document.querySelector(`[data-live-component-value="${component}"][data-live-id-value="${id}"]`)
      const connect = (component, id, defaults = '') =>
        subscriptionManager.subscribe(id, component, defaults, buildController(find(component, id)))
      const unsubscribed = () =>
        createdSubscriptions.filter(subscription => subscription.unsubscribed).map(({ params }) => params.component)

      function renderLayout(id, defaults = '', { attributes = '', wrap = (html) => html } = {}) {
        document.body.innerHTML = wrap(`<div ${attributes} data-live-id-value="${id}" data-live-component-value="layout"></div>`)
        connect('layout', id, defaults)

        createdSubscriptions.at(-1).handlers.received({
          _refresh: {
            h: 'layout',
            p: [`<div ${attributes} live-id="${id}" live-component="layout"><h1>`, 'Lobby', '</h1>', placeholder(`sidebar/${id}`), '</div>'],
            c: {
              [`sidebar/${id}`]: {
                h: 'sidebar',
                p: [`<aside live-id="${id}" live-component="sidebar">`, placeholder(`badge/${id}`), '</aside>'],
              },
              [`badge/${id}`]: {
                h: 'badge',
                p: [`<span live-id="${id}" live-component="badge">`, '3 online', '</span>'],
              },
            },
          },
        })

        const sidebar = connect('sidebar', id)
        const badge = connect('badge', id)
        createdSubscriptions.at(-1).handlers.received({ _refresh: { h: 'badge', p: [null, '4 online', null] } })

        return { sidebar, badge }
      }

      it('keeps the children of a component on the new page, so it can rebuild them', () => {
        const before = renderLayout('turbo-1')

        // The HTTP prerender gives only the root a live id
        const newBody = document.createElement('body')
        newBody.innerHTML =
          '<div live-id="turbo-1" live-component="layout"><h1>Lobby</h1><aside><span>3 online</span></aside></div>'
        subscriptionManager.prune(newBody)

        expect(unsubscribed()).toEqual([])

        document.body.innerHTML =
          '<div data-live-id-value="turbo-1" data-live-component-value="layout"><h1>Lobby</h1><aside><span>3 online</span></aside></div>'
        connect('layout', 'turbo-1')

        expect(find('sidebar', 'turbo-1')).not.toBeNull()
        expect(find('badge', 'turbo-1')?.textContent).toBe('4 online')
        expect(connect('sidebar', 'turbo-1')).toBe(before.sidebar)
        expect(connect('badge', 'turbo-1')).toBe(before.badge)
        expect(createdSubscriptions).toHaveLength(3)
      })

      it('unsubscribes the children of a component that is gone', () => {
        renderLayout('turbo-2')
        subscriptionManager.subscribe('day-timer', 'timer', {}, buildController(buildElement()))

        const newBody = document.createElement('body')
        newBody.innerHTML = '<div live-id="day-timer" live-component="timer"></div>'
        subscriptionManager.prune(newBody)

        expect(unsubscribed()).toEqual(['layout', 'sidebar', 'badge'])
      })

      it('keeps the children of a component the new page renders with the same defaults', () => {
        renderLayout('turbo-3', 'account-1')

        const newBody = document.createElement('body')
        newBody.innerHTML = '<div live-id="turbo-3" live-component="layout" live-defaults="account-1"><h1>Lobby</h1></div>'
        subscriptionManager.prune(newBody)

        expect(unsubscribed()).toEqual([])
      })

      it('unsubscribes the children of a component the new page builds again from other defaults', () => {
        renderLayout('turbo-4', 'account-1')

        const newBody = document.createElement('body')
        newBody.innerHTML = '<div live-id="turbo-4" live-component="layout" live-defaults="account-5"></div>'
        subscriptionManager.prune(newBody)

        expect(unsubscribed()).toEqual(['sidebar', 'badge'])
      })

      it.each([
        ['a data-turbo-permanent component', 'turbo-7', { attributes: 'id="shell" data-turbo-permanent' }],
        ['a component in a data-turbo-permanent element', 'turbo-8', { wrap: (html) => `<nav id="shell" data-turbo-permanent>${html}</nav>` }],
      ])('keeps the children of %s that Turbo carries over, whatever defaults the new page gives it', (_, id, permanent) => {
        const { attributes = '', wrap = (html) => html } = permanent
        renderLayout(id, 'account-1', permanent)

        // Turbo keeps the element already on the page and drops the new page's
        const newBody = document.createElement('body')
        newBody.innerHTML = wrap(`<div ${attributes} live-id="${id}" live-component="layout" live-defaults="account-5"></div>`)
        subscriptionManager.prune(newBody)

        expect(unsubscribed()).toEqual([])
      })

      it('unsubscribes the children of a component only the new page marks data-turbo-permanent', () => {
        renderLayout('turbo-9', 'account-1', { wrap: (html) => `<nav id="shell">${html}</nav>` })

        const newBody = document.createElement('body')
        newBody.innerHTML =
          '<nav id="shell" data-turbo-permanent><div live-id="turbo-9" live-component="layout" live-defaults="account-5"></div></nav>'
        subscriptionManager.prune(newBody)

        expect(unsubscribed()).toEqual(['sidebar', 'badge'])
      })

      it.each([
        ['the same', 'turbo-5', 'account-1', []],
        ['other', 'turbo-6', 'account-5', ['sidebar', 'badge', 'clock']],
      ])('on a cached page that renders it with %s defaults, keeps its children only with its own', (_, id, defaults, closed) => {
        renderLayout(id, 'account-1')
        // A child with a plain .html.erb template is rendered in place, with no placeholder
        find('layout', id).insertAdjacentHTML('beforeend', `<em data-live-id-value="${id}" data-live-component-value="clock"></em>`)
        connect('clock', id)

        // A Turbo snapshot is a copy of the page, so it carries the children's elements
        const snapshot = document.body.cloneNode(true)
        snapshot.querySelector('[data-live-component-value="layout"]').setAttribute('data-live-defaults-value', defaults)
        subscriptionManager.prune(snapshot)

        expect(unsubscribed()).toEqual(closed)
      })
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

  describe('loading state', () => {
    let sequence = 0
    const message = { messages: [{ _action: 'send' }] }

    const composer = (id, { draft = '', label = 'Send' } = {}) =>
      `<div live-id="${id}" live-component="composer"><form live-form="send">` +
      `<input name="draft" value="${draft}"><button live-disable-with="Sending...">${label}</button></form></div>`

    // The live controller's loading API around a real LoadingState
    function mount(element) {
      const id = element.getAttribute('data-live-id-value')
      const component = element.getAttribute('data-live-component-value')
      const loading = new LoadingState(element, { onStalled: () => { controller.statusValue = 'stalled' } })
      const controller = {
        element,
        statusValue: 'disconnected',
        finishLoading: () => loading.finish(),
        resetLoading: () => loading.reset(),
        get isLoading() { return loading.active },
        get inFlight() { return loading.inFlight },
      }
      const subscription = subscriptionManager.subscribe(id, component, '', controller)

      return {
        controller,
        handlers: createdSubscriptions.at(-1).handlers,
        input: () => element.querySelector('input'),
        button: () => element.querySelector('button'),
        submit() {
          loading.start(element.querySelector('form'))
          subscription.send(message)
        },
        click() {
          loading.start(element.querySelector('button'))
          subscription.send(message)
        },
        sendReactive(field) {
          loading.start(field, { disable: false })
          subscription.send({ messages: [{ _action: '_reactive', name: field.name, value: field.value }] })
        },
      }
    }

    function mountComposer({ draft = 'hi' } = {}) {
      const id = `loading-${++sequence}`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'composer')
      document.body.appendChild(element)

      const chat = mount(element)
      const render = (extra, options = { draft }) =>
        chat.handlers.received({ _refresh: { h: 'composer', p: [composer(id, options)] }, ...extra })

      render({ _reply: false, _subscribed: true })
      chat.handlers.connected()

      return { ...chat, render }
    }

    beforeEach(() => {
      vi.useFakeTimers()
    })

    afterEach(() => {
      vi.useRealTimers()
    })

    it('keeps loading through a refresh that is not a reply, and ends it on the reply', () => {
      const chat = mountComposer()
      chat.submit()

      chat.render({ _reply: false })

      expect(chat.controller.isLoading).toBe(true)
      expect(chat.button().disabled).toBe(true)
      expect(chat.button().textContent).toBe('Sending...')

      chat.render({ _reply: true }, { draft: '' })

      expect(chat.controller.isLoading).toBe(false)
      expect(chat.button().disabled).toBe(false)
      expect(chat.button().textContent).toBe('Send')
      expect(chat.input().value).toBe('')
    })

    it('catches up with a render that came while it waited when the reply is an ack', () => {
      const chat = mountComposer()
      chat.submit()

      chat.render({ _reply: false }, { draft: 'hi', label: 'Send to 3 people' })
      chat.handlers.received({ _ack: true })

      expect(chat.controller.isLoading).toBe(false)
      expect(chat.button().disabled).toBe(false)
      expect(chat.button().textContent).toBe('Send to 3 people')
    })

    it('catches up with a render that came before a second send when both replies are acks', () => {
      const chat = mountComposer()
      chat.submit()
      chat.render({ _reply: false }, { draft: 'hi', label: 'Send to 3 people' })
      chat.submit()

      chat.handlers.received({ _ack: true })
      chat.handlers.received({ _ack: true })

      expect(chat.controller.isLoading).toBe(false)
      expect(chat.button().textContent).toBe('Send to 3 people')
    })

    it('says it is subscribed again when an ack answers a message after a stall', () => {
      const chat = mountComposer()
      chat.submit()
      vi.advanceTimersByTime(LoadingState.timeout)

      expect(chat.controller.statusValue).toBe('stalled')

      chat.submit()
      chat.handlers.received({ _ack: true })

      expect(chat.controller.isLoading).toBe(false)
      expect(chat.controller.statusValue).toBe('subscribed')
    })

    it('leaves what the user changed alone when an ack follows no other render', () => {
      const id = `loading-${++sequence}`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'profile')
      document.body.appendChild(element)

      const profile = mount(element)
      profile.handlers.received({
        _refresh: {
          h: 'profile',
          p: [`<div live-id="${id}" live-component="profile"><form live-form="save"><input name="nickname">` +
            '<input type="checkbox" name="public"><button live-disable-with="Saving...">Save</button></form></div>'],
        },
        _reply: false,
        _subscribed: true,
      })
      profile.handlers.connected()

      const checkbox = element.querySelector('[name="public"]')
      profile.input().value = 'Ada'
      checkbox.checked = true
      profile.submit()

      profile.handlers.received({ _ack: true })

      expect(profile.controller.isLoading).toBe(false)
      expect(profile.button().disabled).toBe(false)
      expect(profile.input().value).toBe('Ada')
      expect(checkbox.checked).toBe(true)
    })

    it('treats a refresh from a server that does not mark replies as a reply', () => {
      const chat = mountComposer()
      chat.submit()

      chat.render({})

      expect(chat.controller.isLoading).toBe(false)
      expect(chat.button().disabled).toBe(false)
    })

    it('resets a focused field on the reply to the form it was submitted from', () => {
      const chat = mountComposer({ draft: '' })
      chat.input().focus()
      chat.input().value = 'hello'
      chat.submit()

      chat.render({ _reply: true })

      expect(chat.input().value).toBe('')
    })

    describe('in a nested component', () => {
      const placeholder = (liveId) => `<LiveCable child-live-id="${liveId}"></LiveCable>`

      function mountRoom({ draft = 'hi' } = {}) {
        const id = `loading-room-${++sequence}`
        const element = document.createElement('div')
        element.setAttribute('data-live-id-value', id)
        element.setAttribute('data-live-component-value', 'room')
        document.body.appendChild(element)

        const room = mount(element)
        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [`<div live-id="${id}" live-component="room"><p>`, 'nobody is typing', '</p>', placeholder(`composer/${id}`), '</div>'],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { draft })] } },
          },
          _reply: false,
          _subscribed: true,
        })
        room.handlers.connected()

        const child = mount(element.querySelector('[data-live-component-value="composer"]'))
        child.handlers.connected()

        return { id, element, room, child }
      }

      it('keeps the in-flight trigger when its parent refreshes without it', () => {
        const { element, room, child } = mountRoom()
        child.submit()

        room.handlers.received({ _refresh: { h: 'room', p: [null, 'alice is typing', null, null, null] }, _reply: false })

        expect(element.querySelector('p').textContent).toBe('alice is typing')
        expect(child.controller.isLoading).toBe(true)
        expect(child.controller.element.hasAttribute('live-loading')).toBe(true)
        expect(child.button().disabled).toBe(true)
        expect(child.button().textContent).toBe('Sending...')

        child.handlers.received({ _ack: true })

        expect(child.controller.element.hasAttribute('live-loading')).toBe(false)
        expect(child.button().disabled).toBe(false)
        expect(child.button().textContent).toBe('Send')
      })

      it('applies its render that rides in a parent\'s refresh from a server that does not mark replies', () => {
        const { id, room, child } = mountRoom()
        child.submit()

        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [null, null, null, placeholder(`composer/${id}`), null],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { draft: '', label: 'Send another' })] } },
          },
        })

        expect(child.input().value).toBe('')
        expect(child.button().textContent).toBe('Send another')
        expect(child.controller.element.hasAttribute('live-loading')).toBe(false)
      })

      it('keeps a child\'s button disabled through the parent render that answers its sibling', () => {
        const id = `loading-list-${++sequence}`
        const element = document.createElement('div')
        element.setAttribute('data-live-id-value', id)
        element.setAttribute('data-live-component-value', 'todo_list')
        document.body.appendChild(element)

        // Every todo reads the list's shared `done`, so completing one renders them all
        const todo = (todoId, done) =>
          `<span live-id="${todoId}" live-component="todo">${todoId}` +
          (done.includes(todoId) ? '' : '<button live-action="complete" live-disable-with="Saving...">Done</button>') +
          '</span>'
        const render = (done) => ({
          h: 'todo_list',
          p: [`<div live-id="${id}" live-component="todo_list"><ul>`, ['a', 'b'].map(t => `<li>${placeholder(`todo/${t}-${id}`)}</li>`).join(''), '</ul></div>'],
          c: Object.fromEntries(['a', 'b'].map(t => [`todo/${t}-${id}`, { h: 'todo', p: [todo(`${t}-${id}`, done)] }])),
        })

        const list = mount(element)
        list.handlers.received({ _refresh: render([]), _reply: false, _subscribed: true })
        list.handlers.connected()

        const [a, b] = ['a', 'b'].map(t => mount(element.querySelector(`[data-live-id-value="${t}-${id}"]`)))
        a.handlers.connected()
        b.handlers.connected()
        a.click()
        b.click()

        list.handlers.received({ _refresh: render([`a-${id}`]), _reply: false })
        a.handlers.received({ _ack: true, _rendered: true })

        expect(a.button()).toBeNull()
        expect(b.controller.isLoading).toBe(true)
        expect(b.controller.element.hasAttribute('live-loading')).toBe(true)
        expect(b.button().disabled).toBe(true)
        expect(b.button().textContent).toBe('Saving...')

        list.handlers.received({ _refresh: render([`a-${id}`, `b-${id}`]), _reply: false })
        b.handlers.received({ _ack: true, _rendered: true })

        expect(b.controller.isLoading).toBe(false)
        expect(b.button()).toBeNull()
      })

      it.each([
        ['its status frame', (child, id) => child.handlers.received({ _status: 'subscribed', id, _subscribed: true })],
        ['its re-confirmation', (child) => child.handlers.connected()],
      ])('catches up with the render its parent\'s re-subscribe carried once %s settles a lost send', (_, settle) => {
        const { id, room, child } = mountRoom()
        child.submit()

        // ActionCable swapped a stale socket without reporting it closed
        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [null, null, null, placeholder(`composer/${id}`), null],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { draft: '', label: 'Send again' })] } },
          },
          _reply: false,
          _subscribed: true,
        })
        settle(child, id)

        expect(child.controller.isLoading).toBe(false)
        expect(child.button().disabled).toBe(false)
        expect(child.button().textContent).toBe('Send again')
        expect(child.input().value).toBe('')
      })

      it('catches up with the render its parent carried once the socket closes on its send', () => {
        const { id, room, child } = mountRoom()
        child.submit()

        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [null, null, null, placeholder(`composer/${id}`), null],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { label: 'Send again' })] } },
          },
          _reply: false,
        })
        room.handlers.disconnected()
        child.handlers.disconnected()

        expect(child.controller.isLoading).toBe(false)
        expect(child.button().disabled).toBe(false)
        expect(child.button().textContent).toBe('Send again')
        expect(child.controller.statusValue).toBe('disconnected')
      })

      describe('under the live controller', () => {
        let application
        const tick = () => new Promise((resolve) => setTimeout(resolve, 0))
        const liveComposer = (id, options) =>
          composer(id, options).replace('live-component="composer"', 'live-component="composer" live-actions=\'["send"]\'')

        beforeEach(() => {
          vi.useRealTimers()
          application = Application.start()
          application.register('live', LiveController)
        })

        afterEach(() => {
          application.stop()
        })

        it('catches up with the render its parent carried once its loading stalls', async () => {
          const id = `loading-room-${++sequence}`
          document.body.innerHTML = `<div data-controller="live" data-live-id-value="${id}" data-live-component-value="room"></div>`
          await tick()

          const room = createdSubscriptions.at(-1).handlers
          room.received({
            _refresh: {
              h: 'room',
              p: [`<div live-id="${id}" live-component="room"><p>`, 'nobody is typing', '</p>', placeholder(`composer/${id}`), '</div>'],
              c: { [`composer/${id}`]: { h: 'composer', p: [liveComposer(id)] } },
            },
            _reply: false,
            _subscribed: true,
          })
          room.connected()
          await tick()

          createdSubscriptions.at(-1).handlers.connected()
          vi.useFakeTimers()

          const element = document.querySelector('[data-live-component-value="composer"]')
          const button = () => element.querySelector('button')
          element.querySelector('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))

          expect(button().textContent).toBe('Sending...')

          room.received({
            _refresh: {
              h: 'room',
              p: [null, null, null, placeholder(`composer/${id}`), null],
              c: { [`composer/${id}`]: { h: 'composer', p: [liveComposer(id, { label: 'Send again' })] } },
            },
            _reply: false,
          })
          vi.advanceTimersByTime(LoadingState.timeout)

          expect(element.getAttribute('data-live-status-value')).toBe('stalled')
          expect(button().disabled).toBe(false)
          expect(button().textContent).toBe('Send again')
        })
      })

      it('applies its render that rode in its parent\'s refresh once the ack ends loading', () => {
        const { id, room, child } = mountRoom()
        child.submit()

        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [null, null, null, placeholder(`composer/${id}`), null],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { draft: '', label: 'Send another' })] } },
          },
          _reply: false,
        })

        expect(child.button().disabled).toBe(true)
        expect(child.button().textContent).toBe('Sending...')

        child.handlers.received({ _ack: true, _rendered: true })

        expect(child.input().value).toBe('')
        expect(child.controller.isLoading).toBe(false)
        expect(child.button().disabled).toBe(false)
        expect(child.button().textContent).toBe('Send another')
      })

      it('resets a focused field in its submitted form when its render rides in its parent\'s refresh', () => {
        const { id, room, child } = mountRoom({ draft: '' })
        child.input().focus()
        child.input().value = 'hello'
        child.submit()

        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [null, null, null, placeholder(`composer/${id}`), null],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { draft: '' })] } },
          },
          _reply: false,
        })
        child.handlers.received({ _ack: true, _rendered: true })

        expect(child.input().value).toBe('')
      })

      it('keeps what was typed into a field whose own update, riding in its parent\'s refresh, echoes what it sent', () => {
        const { id, room, child } = mountRoom({ draft: '' })
        const field = child.input()
        field.focus()
        field.value = 'hel'
        child.sendReactive(field)
        field.value = 'hello'

        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [null, null, null, placeholder(`composer/${id}`), null],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { draft: 'hel' })] } },
          },
          _reply: false,
        })
        child.handlers.received({ _ack: true, _rendered: true })

        expect(child.controller.isLoading).toBe(false)
        expect(field.value).toBe('hello')
      })

      it('keeps what was typed into its form when its own render came while an action that changed nothing waited', () => {
        const { id, child } = mountRoom()
        const input = child.input()
        input.focus()
        input.value = 'hello'
        child.submit()
        input.value = 'hello there'

        // A stream_from render of the child itself
        child.handlers.received({ _refresh: { h: 'composer', p: [composer(id, { draft: 'hi', label: 'Send to 3 people' })] }, _reply: false })
        child.handlers.received({ _ack: true })

        expect(child.controller.isLoading).toBe(false)
        expect(child.button().textContent).toBe('Send to 3 people')
        expect(input.value).toBe('hello there')
      })

      it('keeps what was typed into its form when its parent re-rendered it while an action that changed nothing waited', () => {
        const { id, room, child } = mountRoom({ draft: '' })
        const input = child.input()
        input.focus()
        input.value = 'hel'
        child.submit()
        input.value = 'hello'

        // The parent renders the child again for a reason of its own
        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [null, null, null, placeholder(`composer/${id}`), null],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { draft: '', label: 'Send to 3 people' })] } },
          },
          _reply: false,
        })
        child.handlers.received({ _ack: true })

        expect(child.controller.isLoading).toBe(false)
        expect(child.button().textContent).toBe('Send to 3 people')
        expect(input.value).toBe('hello')
      })
    })

    describe('across a reconnect', () => {
      it.each([
        ['when the socket reports closing', true],
        ['when the socket is swapped without reporting it', false],
      ])('settles a send lost with the socket by the re-subscribe, %s', (_, reportsClosing) => {
        const chat = mountComposer()
        chat.submit()

        if (reportsClosing) {
          chat.handlers.disconnected()

          expect(chat.controller.isLoading).toBe(false)
        }

        // A fresh server instance renders from its defaults
        chat.render({ _reply: false, _subscribed: true }, { draft: '' })

        expect(chat.controller.isLoading).toBe(false)
        expect(chat.button().disabled).toBe(false)
        expect(chat.input().value).toBe('')

        chat.handlers.connected({ reconnected: true })
        vi.advanceTimersByTime(60_000)

        expect(chat.controller.statusValue).toBe('subscribed')
      })

      it('catches up with a render that came while a send waited when the socket closes', () => {
        const chat = mountComposer()
        chat.submit()

        chat.render({ _reply: false }, { draft: 'hi', label: 'Send to 3 people' })
        chat.handlers.disconnected()

        expect(chat.controller.isLoading).toBe(false)
        expect(chat.button().disabled).toBe(false)
        expect(chat.button().textContent).toBe('Send to 3 people')
        expect(chat.controller.statusValue).toBe('disconnected')
      })

      it('settles a lost send at re-confirmation when nothing marked the re-subscribe', () => {
        const chat = mountComposer()
        chat.submit()

        chat.render({ _reply: false })
        expect(chat.controller.isLoading).toBe(true)

        chat.handlers.connected({ reconnected: true })

        expect(chat.controller.isLoading).toBe(false)
        expect(chat.button().disabled).toBe(false)
      })

      it('keeps a send held while disconnected loading until its own reply', () => {
        const chat = mountComposer()
        socket.open = false
        chat.handlers.disconnected()
        chat.submit()

        socket.open = true
        chat.render({ _reply: false, _subscribed: true })
        chat.handlers.connected({ reconnected: true })

        expect(sentMessages).toEqual([message])
        expect(chat.controller.isLoading).toBe(true)
        expect(chat.button().disabled).toBe(true)

        chat.render({ _reply: true }, { draft: '' })

        expect(chat.controller.isLoading).toBe(false)
        expect(chat.button().disabled).toBe(false)
      })

      it('settles only the lost send when another is held', () => {
        const chat = mountComposer()
        chat.submit()
        socket.open = false
        chat.submit()

        socket.open = true
        chat.render({ _reply: false, _subscribed: true })
        chat.handlers.connected({ reconnected: true })

        expect(chat.controller.isLoading).toBe(true)
        expect(chat.controller.inFlight).toBe(1)

        chat.handlers.received({ _ack: true })

        expect(chat.controller.isLoading).toBe(false)
      })
    })
  })

  // Component states outlive each test, so every test uses its own ids.
  describe('a focused field', () => {
    let sequence = 0

    const input = (value) => `<input name="draft" value="${value}">`
    const textarea = (value) => `<textarea name="draft">${value}</textarea>`

    function mountChat(field, value) {
      const id = `focus-${++sequence}`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'chat')
      document.body.appendChild(element)

      subscriptionManager.subscribe(id, 'chat', '', buildController(element))
      const { handlers } = createdSubscriptions.at(-1)
      handlers.received({
        _refresh: { h: 'chat', p: [`<div live-id="${id}" live-component="chat"><p>`, '1 message', '</p>', field(value), '</div>'] },
      })

      return {
        field: () => element.querySelector('[name="draft"]'),
        count: () => element.querySelector('p').textContent,
        messageArrives: (count) => handlers.received({ _refresh: { h: 'chat', p: [null, `${count} messages`, null, null, null] }, _reply: false }),
        valueChanges: (newValue) => handlers.received({ _refresh: { h: 'chat', p: [null, null, null, field(newValue), null] }, _reply: false }),
      }
    }

    function type(element, value) {
      element.focus()
      element.value = value
    }

    it('keeps what the user typed through a refresh that leaves its value alone', () => {
      const chat = mountChat(input, 'hel')
      type(chat.field(), 'hello')

      chat.messageArrives(2)

      expect(chat.count()).toBe('2 messages')
      expect(chat.field().value).toBe('hello')
    })

    it('takes a value the server changed', () => {
      const chat = mountChat(input, 'hel')
      type(chat.field(), 'hello')

      chat.valueChanges('')

      expect(chat.field().value).toBe('')
    })

    it('leaves a field that is not focused to the server as before', () => {
      const chat = mountChat(input, 'hel')
      chat.field().value = 'hello'

      chat.messageArrives(2)

      expect(chat.field().value).toBe('hel')
    })

    it.each([
      ['date', '2026-01-01', '2026-02-03'],
      ['range', '10', '40'],
    ])('keeps a focused %s input\'s new value through a refresh that leaves its value alone', (type, value, entered) => {
      const chat = mountChat((v) => `<input type="${type}" name="draft" value="${v}">`, value)
      chat.field().focus()
      chat.field().value = entered

      chat.messageArrives(2)

      expect(chat.field().value).toBe(entered)
    })

    it('leaves a focused checkbox to the server as before', () => {
      const chat = mountChat(() => '<input type="checkbox" name="draft">', '')
      chat.field().focus()
      chat.field().checked = true

      chat.messageArrives(2)

      expect(chat.field().checked).toBe(false)
    })

    it('keeps what the user typed in a textarea through several refreshes, until the server changes it', () => {
      const chat = mountChat(textarea, 'hel')
      type(chat.field(), 'hello')

      chat.messageArrives(2)
      chat.messageArrives(3)

      expect(chat.count()).toBe('3 messages')
      expect(chat.field().value).toBe('hello')

      chat.valueChanges('')

      expect(chat.field().value).toBe('')
    })

    it('keeps what the user typed in a textarea first rendered empty, once the server has set its value', () => {
      const chat = mountChat(textarea, '')
      type(chat.field(), 'hel')
      chat.valueChanges('hel')
      type(chat.field(), 'hello')

      chat.messageArrives(2)

      expect(chat.field().value).toBe('hello')
    })

    describe('sending its own live-reactive updates', () => {
      let application
      const tick = () => new Promise((resolve) => setTimeout(resolve, 0))
      const attributes = 'name="draft" live-reactive live-debounce="300" live-action="keydown.enter->send"'
      const fields = {
        'an input': (value) => `<input ${attributes} value="${value}">`,
        'a textarea': (value) => `<textarea ${attributes}>${value}</textarea>`,
      }

      beforeEach(() => {
        application = Application.start()
        application.register('live', LiveController)
      })

      afterEach(() => {
        application.stop()
        vi.useRealTimers()
      })

      async function mountDraft(draft = fields['an input']) {
        const id = `focus-${++sequence}`
        document.body.innerHTML =
          `<div data-controller="live" data-live-id-value="${id}" data-live-component-value="chat" data-live-actions-value='["send"]'></div>`
        await tick()

        const { handlers } = createdSubscriptions.at(-1)
        handlers.received({
          _refresh: { h: 'chat', p: [`<div live-id="${id}" live-component="chat" live-actions='["send"]'><p>`, '1 message', '</p>', draft(''), '</div>'] },
          _reply: false,
          _subscribed: true,
        })
        handlers.connected()
        await tick()
        vi.useFakeTimers()

        const field = document.querySelector('[name="draft"]')
        field.focus()

        return {
          field,
          type(value) {
            field.value = value
            field.dispatchEvent(new Event('input', { bubbles: true }))
          },
          reply: (value) => handlers.received({ _refresh: { h: 'chat', p: [null, null, null, draft(value), null] }, _reply: true }),
          messageArrives: () => handlers.received({ _refresh: { h: 'chat', p: [null, '2 messages', null, null, null] }, _reply: false }),
        }
      }

      it.each(Object.keys(fields))('keeps what was typed into %s while the reply only echoes the value it sent', async (kind) => {
        const chat = await mountDraft(fields[kind])
        chat.type('hel')
        vi.advanceTimersByTime(300)
        chat.type('hello')

        chat.reply('hel')
        chat.messageArrives()

        expect(chat.field.value).toBe('hello')

        vi.advanceTimersByTime(300)

        expect(sentMessages.at(-1)).toEqual({ messages: [{ _action: '_reactive', name: 'draft', value: 'hello' }] })
      })

      it('takes the value an action it triggered set, even one it sent before', async () => {
        const chat = await mountDraft()
        chat.type('x')
        chat.type('')
        vi.advanceTimersByTime(300)
        chat.reply('')

        chat.type('hello')
        chat.field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
        chat.reply('')

        expect(sentMessages.at(-1).messages.map(({ _action }) => _action)).toEqual(['_reactive', 'send'])
        expect(chat.field.value).toBe('')
      })

      it('takes the value an action it triggered set back to the one it last sent', async () => {
        const chat = await mountDraft()
        chat.type('x')
        chat.type('')
        vi.advanceTimersByTime(300)
        chat.reply('')

        chat.field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
        chat.reply('apple')

        expect(chat.field.value).toBe('apple')

        chat.field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
        chat.reply('')

        expect(chat.field.value).toBe('')
      })
    })
  })
})
