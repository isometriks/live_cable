import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { Application } from '@hotwired/stimulus'
import LoadingState from '../app/assets/javascript/loading.js'
import { applyPart, renderParts } from '../app/assets/javascript/tree.js'

// The subscription manager creates an ActionCable consumer at import time, so
// the module is stubbed before importing it.
const sentMessages = []
const createdSubscriptions = []
// ActionCable's send returns false, and drops the message, on a closed socket
const socket = { open: true }
// Stands in for Connection.prototype.events, the socket's handlers
const actionCableEvents = { open: vi.fn(), message: vi.fn(), close: vi.fn() }
const cableConnection = {
  active: true,
  reopen: vi.fn(),
  open: vi.fn(),
  isActive() { return this.active },
  events: actionCableEvents,
}

// What ActionCable's socket handlers do with a frame from the server
function receiveFrame(frame) {
  cableConnection.events.message.call(cableConnection, { data: JSON.stringify(frame) })
}

function openSocket() {
  cableConnection.events.open.call(cableConnection)
}

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
    openSocket()
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

  it('subscribes with the path and query of the page the component is on', () => {
    history.replaceState(null, '', '/products?page=2#reviews')

    subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

    expect(createdSubscriptions[0].params.path).toBe('/products?page=2')
    history.replaceState(null, '', '/')
  })

  it('subscribes with the protocol it speaks, so the server can turn away what it would misread', () => {
    subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

    expect(createdSubscriptions[0].params.protocol).toBe(3)
  })

  it('subscribes with the src of the turbo-frame the component was loaded into', () => {
    history.replaceState(null, '', '/dashboard')
    const frame = document.createElement('turbo-frame')
    frame.setAttribute('src', '/products?page=2')
    frame.appendChild(buildElement())
    document.body.appendChild(frame)

    subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(frame.firstElementChild))

    expect(createdSubscriptions[0].params.path).toBe('/products?page=2')
    history.replaceState(null, '', '/')
  })

  it("subscribes with the page's path from a turbo-frame loaded from another origin", () => {
    history.replaceState(null, '', '/dashboard')
    const frame = document.createElement('turbo-frame')
    frame.setAttribute('src', 'https://elsewhere.test/products')
    frame.appendChild(buildElement())
    document.body.appendChild(frame)

    subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(frame.firstElementChild))

    expect(createdSubscriptions[0].params.path).toBe('/dashboard')
    history.replaceState(null, '', '/')
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
      cableConnection.open.mockClear()
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
      expect(cableConnection.open).not.toHaveBeenCalled()
    })

    describe('after the server refused the socket', () => {
      const message = { messages: [{ _action: 'increment' }] }
      let kept

      beforeEach(() => {
        kept = subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))
        createdSubscriptions.at(-1).handlers.disconnected({ willAttemptReconnect: false })
        cableConnection.active = false
      })

      it('opens it again when the identity changes, so the components come back as the new session', () => {
        renderPageFor('digest-b')

        expect(cableConnection.open).toHaveBeenCalledOnce()
      })

      it('holds what a kept component sends while the socket it opened connects', () => {
        renderPageFor('digest-b')

        kept.send(message)

        expect(kept.pendingCount).toBe(1)
      })

      it('holds what a component sends while its own subscribe opens the socket', () => {
        const element = buildElement()
        element.setAttribute('data-live-id-value', 'fresh-timer')
        const fresh = subscriptionManager.subscribe('fresh-timer', 'timer', 'blob-a', buildController(element))

        fresh.send(message)
        kept.send(message)

        expect(fresh.pendingCount).toBe(1)
        expect(kept.pendingCount).toBe(1)
        subscriptionManager.unsubscribe('timer/fresh-timer')
      })

      it('leaves it closed while the identity is the same', () => {
        renderPageFor('digest-a')

        expect(cableConnection.open).not.toHaveBeenCalled()
      })
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

      function renderLayout(id, defaults = '', { attributes = '', wrap = (html) => html, structured = false } = {}) {
        document.body.innerHTML = wrap(`<div ${attributes} data-live-id-value="${id}" data-live-component-value="layout"></div>`)
        connect('layout', id, defaults)

        const sidebarPart = structured ? { t: 0, r: [[placeholder(`sidebar/${id}`)]] } : placeholder(`sidebar/${id}`)

        createdSubscriptions.at(-1).handlers.received({
          _refresh: {
            h: 'layout',
            p: [`<div ${attributes} live-id="${id}" live-component="layout"><h1>`, 'Lobby', '</h1>', sidebarPart, '</div>'],
            s: { 0: ['', ''] },
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

      it('keeps a child whose id is escaped in its placeholder', () => {
        document.body.innerHTML = '<div data-live-id-value="turbo-10" data-live-component-value="layout"></div>'
        connect('layout', 'turbo-10')
        createdSubscriptions.at(-1).handlers.received({
          _refresh: {
            h: 'layout',
            p: ['<div live-id="turbo-10" live-component="layout">', placeholder('tag/say &quot;hi&quot;'), '</div>'],
            c: { 'tag/say "hi"': { h: 'tag', p: ['<span live-id="say &quot;hi&quot;" live-component="tag">hi</span>'] } },
          },
        })
        const tag = document.querySelector('[data-live-component-value="tag"]')
        subscriptionManager.subscribe('say "hi"', 'tag', '', buildController(tag))

        const newBody = document.createElement('body')
        newBody.innerHTML = '<div live-id="turbo-10" live-component="layout"><span>hi</span></div>'
        subscriptionManager.prune(newBody)

        expect(createdSubscriptions.map(({ params }) => params.component)).toEqual(['layout', 'tag'])
        expect(unsubscribed()).toEqual([])
      })

      it('keeps a child placed inside a <select> under parsing that drops it there', () => {
        const own = Object.getOwnPropertyDescriptor(HTMLTemplateElement.prototype, 'innerHTML')
        let proto = HTMLTemplateElement.prototype
        while (!Object.getOwnPropertyDescriptor(proto, 'innerHTML')) proto = Object.getPrototypeOf(proto)
        const { set } = Object.getOwnPropertyDescriptor(proto, 'innerHTML')
        const dropInSelect = (html) => html.replace(/(<select[^>]*>.*?)<LiveCable[^>]*><\/LiveCable>/g, '$1')
        Object.defineProperty(HTMLTemplateElement.prototype, 'innerHTML', {
          configurable: true,
          set(html) { set.call(this, dropInSelect(html)) },
        })

        try {
          document.body.innerHTML = '<div data-live-id-value="turbo-11" data-live-component-value="picker"></div>'
          connect('picker', 'turbo-11')
          createdSubscriptions.at(-1).handlers.received({
            _refresh: {
              h: 'picker',
              p: ['<div live-id="turbo-11" live-component="picker"><select>', placeholder('choice/turbo-11'), '</select></div>'],
              c: { 'choice/turbo-11': { h: 'choice', p: ['<option live-id="turbo-11" live-component="choice">A</option>'] } },
            },
          })
          connect('choice', 'turbo-11')

          const newBody = document.createElement('body')
          newBody.innerHTML = '<div live-id="turbo-11" live-component="picker"><select><option>A</option></select></div>'
          subscriptionManager.prune(newBody)

          expect(find('choice', 'turbo-11')).not.toBeNull()
          expect(unsubscribed()).toEqual([])
        } finally {
          if (own) Object.defineProperty(HTMLTemplateElement.prototype, 'innerHTML', own)
          else delete HTMLTemplateElement.prototype.innerHTML
        }
      })

      it('keeps the children a component places inside a control block', () => {
        renderLayout('turbo-6', '', { structured: true })

        const newBody = document.createElement('body')
        newBody.innerHTML = '<div live-id="turbo-6" live-component="layout"><h1>Lobby</h1></div>'
        subscriptionManager.prune(newBody)

        expect(unsubscribed()).toEqual([])
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

      it('unsubscribes the children of a component a frame or stream builds again from other defaults', () => {
        renderLayout('turbo-10', 'account-1')
        find('layout', 'turbo-10').insertAdjacentHTML('beforeend', '<em data-live-id-value="turbo-10" data-live-component-value="clock"></em>')
        connect('clock', 'turbo-10')

        // Neither runs prune; the new element's controller connects in place of the old
        document.body.innerHTML =
          '<div data-live-id-value="turbo-10" data-live-component-value="layout"><h1>Lobby</h1><aside><span>3 online</span></aside></div>'
        connect('layout', 'turbo-10', 'account-5')

        expect(unsubscribed()).toEqual(['layout', 'sidebar', 'badge', 'clock'])
        expect(subscriptionManager.getComponentState('sidebar/turbo-10')).toBeUndefined()
        expect(subscriptionManager.getComponentState('badge/turbo-10')).toBeUndefined()
      })

      it('keeps the children of a component a frame or stream renders with the same defaults', () => {
        const before = renderLayout('turbo-11', 'account-1')

        document.body.innerHTML =
          '<div data-live-id-value="turbo-11" data-live-component-value="layout"><h1>Lobby</h1><aside><span>3 online</span></aside></div>'
        connect('layout', 'turbo-11', 'account-1')

        expect(unsubscribed()).toEqual([])
        expect(connect('sidebar', 'turbo-11')).toBe(before.sidebar)
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

  describe('when the server rejects the subscription', () => {
    function reject() {
      const controller = buildController(buildElement())
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', controller)
      subscription.send({ messages: [{ _action: 'increment' }] })
      createdSubscriptions[0].handlers.rejected()

      return { controller, subscription }
    }

    it('says so, drops what it held and ends its loading state', () => {
      const { controller, subscription } = reject()

      expect(controller.statusValue).toBe('rejected')
      expect(subscription.pendingCount).toBe(0)
      expect(controller.resetLoading).toHaveBeenCalled()
    })

    it('tells the page from the component', () => {
      const rejections = []
      document.addEventListener('live:rejected', (event) => rejections.push(event.target), { once: true })

      const { controller } = reject()

      expect(rejections).toEqual([controller.element])
    })

    it('forgets the subscription ActionCable has already forgotten, so the component can subscribe again', () => {
      reject()

      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

      expect(createdSubscriptions).toHaveLength(2)
      expect(createdSubscriptions[0].unsubscribed).toBe(false)
    })

    it('drops a message sent afterwards and ends its loading state', () => {
      const { controller, subscription } = reject()

      subscription.send({ messages: [{ _action: 'increment' }] })

      expect(subscription.pendingCount).toBe(0)
      expect(controller.finishLoading).toHaveBeenCalled()
    })
  })

  describe('when the server refuses the component', () => {
    const frame = { _refused: true, _reason: 'membership_ended', _error: '<details>An error occurred</details>' }

    function refuse() {
      const controller = buildController(buildElement())
      const subscription = subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', controller)
      createdSubscriptions[0].handlers.connected()
      socket.open = false
      subscription.send({ messages: [{ _action: 'increment' }] })
      createdSubscriptions[0].handlers.received(frame)

      return { controller, subscription }
    }

    it('keeps its markup and says so, instead of showing the error box older clients show', () => {
      const { controller } = refuse()

      expect(controller.statusValue).toBe('refused')
      expect(controller.element.isConnected).toBe(true)
      expect(document.body.textContent).toContain('original')
      expect(document.body.textContent).not.toContain('An error occurred')
    })

    it('drops what it held, ends its loading state and unsubscribes', () => {
      const { controller, subscription } = refuse()

      expect(subscription.pendingCount).toBe(0)
      expect(controller.resetLoading).toHaveBeenCalled()
      expect(createdSubscriptions[0].unsubscribed).toBe(true)
    })

    it('tells the page from the component, with the reason', () => {
      const refusals = []
      document.addEventListener('live:refused', (event) => refusals.push(event), { once: true })

      const { controller } = refuse()

      expect(refusals.map(({ target, detail }) => ({ target, detail }))).toEqual([
        { target: controller.element, detail: { reason: 'membership_ended', components: 1 } },
      ])
    })

    it('stays refused when its controller connects again on markup a parent rendered', () => {
      const { subscription } = refuse()

      const again = subscriptionManager.subscribe('day-timer', 'timer', '', buildController(buildElement()))

      expect(again).toBe(subscription)
      expect(createdSubscriptions).toHaveLength(1)
      expect(subscriptionManager.statusOf('timer/day-timer')).toBe('refused')
    })

    it('subscribes again on a page rendered with it', () => {
      refuse()

      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))

      expect(createdSubscriptions).toHaveLength(2)
    })

    it('does not unsubscribe again when the page lets it go', () => {
      refuse()
      const unsubscribe = vi.spyOn(createdSubscriptions[0], 'unsubscribe')

      subscriptionManager.prune(document.createElement('body'))

      expect(unsubscribe).not.toHaveBeenCalled()
      expect(subscriptionManager.getComponentState('timer/day-timer')).toBeUndefined()
    })

    it('drops a message sent afterwards and ends its loading state', () => {
      const { controller, subscription } = refuse()
      socket.open = true

      subscription.send({ messages: [{ _action: 'increment' }] })

      expect(sentMessages).toEqual([])
      expect(controller.finishLoading).toHaveBeenCalled()
    })
  })

  describe('keeps', () => {
    const rendered = (attributes) => {
      const template = document.createElement('template')
      template.innerHTML = `<div ${attributes}></div>`
      return template.content.firstChild
    }

    it.each([
      ['the same component with the same defaults', 'live-id="day-timer" live-component="timer" live-defaults="blob-a"', true],
      ['the same component with other defaults', 'live-id="day-timer" live-component="timer" live-defaults="blob-b"', false],
      ['another component', 'live-id="night-timer" live-component="timer" live-defaults="blob-a"', false],
      ['no component', 'class="timer"', false],
    ])('says whether an element that renders %s keeps the live one', (_, attributes, kept) => {
      const element = buildElement()
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(element))

      expect(subscriptionManager.keeps(element, rendered(attributes))).toBe(kept)
    })

    it('does not keep the element of a component that is not subscribed', () => {
      const element = buildElement()

      expect(subscriptionManager.keeps(element, rendered('live-id="day-timer" live-component="timer"'))).toBe(false)
    })
  })

  describe('pruneDetached', () => {
    function inFrame(element) {
      const frame = document.createElement('turbo-frame')
      frame.appendChild(element)
      document.body.appendChild(frame)
      return frame
    }

    it('unsubscribes a component Turbo took off the page', () => {
      const element = buildElement()
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(element))
      const leaving = subscriptionManager.liveIdsWithin([inFrame(element)])

      element.remove()
      subscriptionManager.pruneDetached(leaving)

      expect(createdSubscriptions[0].unsubscribed).toBe(true)
      expect(subscriptionManager.getComponentState('timer/day-timer')).toBeUndefined()
    })

    it('keeps a component whose element is still on the page', () => {
      const element = buildElement()
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(element))
      const leaving = subscriptionManager.liveIdsWithin([inFrame(element)])

      subscriptionManager.pruneDetached(leaving)

      expect(createdSubscriptions[0].unsubscribed).toBe(false)
    })

    it('keeps a component that was off the page outside what Turbo changed', () => {
      const element = buildElement()
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(element))

      element.remove()
      const leaving = subscriptionManager.liveIdsWithin([inFrame(document.createElement('p'))])
      subscriptionManager.pruneDetached(leaving)

      expect(createdSubscriptions[0].unsubscribed).toBe(false)
    })

    it('keeps a component whose new element has connected in place of the one that left', () => {
      const element = buildElement()
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(element))
      const leaving = subscriptionManager.liveIdsWithin([inFrame(element)])

      element.remove()
      subscriptionManager.subscribe('day-timer', 'timer', 'blob-a', buildController(buildElement()))
      subscriptionManager.pruneDetached(leaving)

      expect(createdSubscriptions).toHaveLength(1)
      expect(createdSubscriptions[0].unsubscribed).toBe(false)
    })

    it('drops the stored state of a child Turbo took away before it connected', () => {
      const child = document.createElement('div')
      const frame = inFrame(child)
      subscriptionManager.registerComponent('timer/child-timer', child, { h: 'child', p: ['<div></div>'] })
      const leaving = subscriptionManager.liveIdsWithin([frame])

      frame.remove()
      subscriptionManager.pruneDetached(leaving)

      expect(subscriptionManager.getComponentState('timer/child-timer')).toBeUndefined()
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

  describe('when the server refuses the socket', () => {
    const message = (action) => ({ messages: [{ _action: action }] })
    let sequence = 0
    let refusals

    const onRefused = (event) => refusals.push(event)

    function mountTimer() {
      const element = buildElement()
      const id = `refused-${++sequence}`
      element.setAttribute('data-live-id-value', id)
      const controller = buildController(element)
      const subscription = subscriptionManager.subscribe(id, 'timer', 'blob-a', controller)
      const handlers = createdSubscriptions.at(-1).handlers
      handlers.connected()

      return { controller, subscription, handlers }
    }

    const tick = () => Promise.resolve()

    beforeEach(() => {
      refusals = []
      document.addEventListener('live:refused', onRefused)
    })

    afterEach(() => {
      document.removeEventListener('live:refused', onRefused)
    })

    it('says so, drops what it held and ends its loading state, since no reconnect is coming', () => {
      const { controller, subscription, handlers } = mountTimer()
      socket.open = false
      subscription.send(message('increment'))

      handlers.disconnected({ willAttemptReconnect: false })

      expect(controller.statusValue).toBe('refused')
      expect(subscription.pendingCount).toBe(0)
      expect(controller.resetLoading).toHaveBeenCalled()
    })

    it.each([
      ['will reconnect', { willAttemptReconnect: true }],
      ['says nothing about reconnecting', undefined],
    ])('waits for the reconnect when ActionCable %s', (_, argument) => {
      const { controller, subscription, handlers } = mountTimer()
      socket.open = false
      subscription.send(message('increment'))

      handlers.disconnected(argument)

      expect(controller.statusValue).toBe('disconnected')
      expect(subscription.pendingCount).toBe(1)
    })

    it('tells the page once, with how many components it stopped', async () => {
      const timers = [mountTimer(), mountTimer(), mountTimer()]

      receiveFrame({ type: 'disconnect', reason: 'unauthorized', reconnect: false })
      timers.forEach(({ handlers }) => handlers.disconnected({ willAttemptReconnect: false }))
      await tick()

      expect(refusals).toHaveLength(1)
      expect(refusals[0].target).toBe(document)
      expect(refusals[0].detail).toEqual({ reason: 'unauthorized', components: 3 })
      expect(actionCableEvents.message).toHaveBeenCalled()
    })

    it('gives no reason when the server sent none before the socket closed', async () => {
      const { handlers } = mountTimer()

      handlers.disconnected({ willAttemptReconnect: false })
      await tick()

      expect(refusals[0].detail.reason).toBeNull()
    })

    it('forgets the reason a previous socket was closed for', async () => {
      const { handlers } = mountTimer()
      receiveFrame({ type: 'disconnect', reason: 'server_restart', reconnect: true })
      openSocket()

      handlers.disconnected({ willAttemptReconnect: false })
      await tick()

      expect(refusals[0].detail.reason).toBeNull()
    })

    it('tells the page again when a later socket is refused too', async () => {
      const { handlers } = mountTimer()

      handlers.disconnected({ willAttemptReconnect: false })
      await tick()
      openSocket()
      handlers.disconnected({ willAttemptReconnect: false })
      await tick()

      expect(refusals).toHaveLength(2)
    })

    it('drops a message sent while refused and ends its loading state', () => {
      const { controller, subscription, handlers } = mountTimer()
      handlers.disconnected({ willAttemptReconnect: false })
      socket.open = false

      subscription.send(message('increment'))

      expect(subscription.pendingCount).toBe(0)
      expect(controller.finishLoading).toHaveBeenCalled()
    })

    it('holds messages again once a socket opens', () => {
      const { subscription, handlers } = mountTimer()
      handlers.disconnected({ willAttemptReconnect: false })
      socket.open = false

      openSocket()
      subscription.send(message('increment'))

      expect(subscription.pendingCount).toBe(1)
    })
  })

  // Component states outlive each test, so every test uses its own ids.
  describe('structured parts', () => {
    it('builds the DOM from statics and applies diffs to the parts it holds', () => {
      const element = document.createElement('ul')
      element.setAttribute('data-live-id-value', 'todos-1')
      element.setAttribute('data-live-component-value', 'todos')
      document.body.appendChild(element)
      subscriptionManager.subscribe('todos-1', 'todos', '', buildController(element))
      const todos = createdSubscriptions.at(-1).handlers

      todos.received({
        _refresh: {
          h: 'todos',
          p: [
            '<ul live-id="todos-1" live-component="todos">',
            { t: 0, r: [['1', 'Milk'], ['2', 'Eggs']], k: ['1', '2'] },
            '</ul>',
          ],
          s: { 0: ['<li live-key="', '">', '</li>'] },
        },
      })

      const eggs = element.querySelector('[live-key="2"]')
      expect(element.textContent).toBe('MilkEggs')

      todos.received({
        _refresh: { h: 'todos', p: [null, { o: [['d', '1'], ['p', '3', ['3', 'Bread']]] }, null] },
      })

      expect(Array.from(element.querySelectorAll('li')).map(li => li.textContent)).toEqual(['Bread', 'Eggs'])
      expect(element.querySelector('[live-key="2"]')).toBe(eggs)
    })
  })

  describe('row ops', () => {
    const rowStatics = { 0: ['\n    <li live-key="', '"><span>', '</span></li>\n  '] }
    const loop = (...keys) => ({ t: 0, r: keys.map(key => [key, `Row ${key}`]), k: keys })
    const keysOf = (list) => Array.from(list.children, li => li.getAttribute('live-key'))
    let sequence = 0

    function mount(node, { statics = rowStatics, open = '<ul>\n  ', close = '</ul>', children } = {}) {
      const id = `rows-${++sequence}`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'rows')
      document.body.appendChild(element)
      subscriptionManager.subscribe(id, 'rows', '', buildController(element))
      const handlers = createdSubscriptions.at(-1).handlers

      handlers.received({
        _refresh: { h: 'rows', p: [`<div live-id="${id}" live-component="rows">${open}`, node, `${close}</div>`], s: statics, c: children },
      })

      return { element, handlers, list: element.firstElementChild }
    }

    // What the page shows when the node arrives whole, rebuilt and morphed
    function rendered(node, options) {
      const { element } = mount(node, options)
      const html = element.innerHTML
      element.remove()
      return html
    }

    function send(handlers, ops, extra = {}) {
      handlers.received({ _refresh: { h: 'rows', p: [null, { o: ops }, null], ...extra } })
    }

    // A small seeded generator, so a failing sequence can be replayed
    function generator(seed) {
      let state = seed
      return (limit) => {
        state = (state * 1103515245 + 12345) % 2147483648
        return state % limit
      }
    }

    function randomOps(keys, random, fresh) {
      const held = keys.slice()
      const ops = []
      const pick = (list) => list[random(list.length)]

      for (let count = 1 + random(4); count > 0; count--) {
        const choice = held.length === 0 ? 1 : random(7)
        const key = choice >= 1 && choice <= 3 ? String(fresh()) : pick(held)

        if (choice === 0) {
          ops.push(['d', key])
          held.splice(held.indexOf(key), 1)
        } else if (choice === 1) {
          ops.push(['a', key, [key, `New ${key}`]])
          held.push(key)
        } else if (choice === 2) {
          ops.push(['p', key, [key, `New ${key}`]])
          held.unshift(key)
        } else if (choice === 3) {
          const after = pick(held)
          ops.push(['i', key, [key, `New ${key}`], after])
          held.splice(held.indexOf(after) + 1, 0, key)
        } else if (choice === 4) {
          const others = held.filter(other => other !== key)
          const after = others.length > 0 && random(3) > 0 ? pick(others) : null
          ops.push(['m', key, after])
          held.splice(held.indexOf(key), 1)
          held.splice(after === null ? 0 : held.indexOf(after) + 1, 0, key)
        } else if (choice === 5) {
          ops.push(['u', key, { 1: `Changed ${fresh()}` }])
        } else {
          const named = held.filter(() => random(5) > 1).reverse()
          ops.push(['s', ...named, String(fresh())])
          held.splice(0, held.length, ...named, ...held.filter(other => !named.includes(other)))
        }
      }

      return ops
    }

    it('applies row ops to the rows alone', () => {
      const { handlers, list } = mount(loop('1', '2', '3'))
      const kept = list.querySelector('[live-key="2"]')
      // A morph of the whole component would take this off again
      list.setAttribute('data-touched', '')

      send(handlers, [['d', '1'], ['a', '4', ['4', 'Row 4']], ['u', '2', { 1: 'Eggs' }]])

      expect(keysOf(list)).toEqual(['2', '3', '4'])
      expect(list.querySelector('[live-key="2"]')).toBe(kept)
      expect(kept.textContent).toBe('Eggs')
      expect(list.hasAttribute('data-touched')).toBe(true)
    })

    it('leaves the page as a rebuild would, whitespace and all, for any ops', () => {
      const random = generator(20261112)
      let next = 100
      const fresh = () => next++

      for (let run = 0; run < 150; run++) {
        const start = Array.from({ length: 1 + random(6) }, () => String(fresh()))
        const { element, handlers, list } = mount(loop(...start))
        list.setAttribute('data-touched', '')
        let node = loop(...start)

        for (let frame = 0; frame < 4 && node.k.length > 0; frame++) {
          const ops = randomOps(node.k, random, fresh)
          node = applyPart(node, { o: ops })
          send(handlers, ops)

          expect(list.hasAttribute('data-touched'), JSON.stringify(ops)).toBe(true)
          list.removeAttribute('data-touched')
          expect(element.innerHTML, JSON.stringify(ops)).toBe(rendered(node))
          list.setAttribute('data-touched', '')
        }

        element.remove()
      }
    })

    it('rebuilds and morphs when the refresh changes anything else', () => {
      const { handlers, list } = mount(loop('1', '2'))
      list.setAttribute('data-touched', '')

      handlers.received({ _refresh: { h: 'rows', p: ['<div live-id="x" live-component="rows"><ul class="new">\n  ', { o: [['d', '1']] }, null] } })

      expect(keysOf(list)).toEqual(['2'])
      expect(list.className).toBe('new')
      expect(list.hasAttribute('data-touched')).toBe(false)
    })

    it('applies row ops to the rows alone when another part re-ran to the HTML it had', () => {
      const { handlers, list } = mount(loop('1', '2'))
      list.setAttribute('data-touched', '')
      const open = `<div live-id="rows-${sequence}" live-component="rows"><ul>\n  `

      handlers.received({ _refresh: { h: 'rows', p: [open, { o: [['d', '1']] }, null] } })

      expect(keysOf(list)).toEqual(['2'])
      expect(list.hasAttribute('data-touched')).toBe(true)
    })

    it('finds rows by whichever of id and live-key comes first, as the server keys them', () => {
      const both = { 0: ['<li id="', '" live-key="other-', '">', '</li>'] }
      const node = { t: 0, r: ['1', '2'].map(key => [key, key, `Row ${key}`]), k: ['1', '2'] }
      const { handlers, list } = mount(node, { statics: both })
      list.setAttribute('data-touched', '')

      send(handlers, [['u', '2', { 2: 'Eggs' }], ['a', '3', ['3', '3', 'Row 3']]])

      expect(Array.from(list.children, li => li.textContent)).toEqual(['Row 1', 'Eggs', 'Row 3'])
      expect(list.hasAttribute('data-touched')).toBe(true)
    })

    it('rebuilds and morphs when the loop held no rows to place new ones by', () => {
      const { element, handlers, list } = mount(loop())
      list.setAttribute('data-touched', '')

      send(handlers, [['a', '1', ['1', 'Row 1']]])

      expect(keysOf(list)).toEqual(['1'])
      expect(list.hasAttribute('data-touched')).toBe(false)
      expect(element.innerHTML).toBe(rendered(loop('1')))
    })

    it('rebuilds and morphs when the page no longer shows the rows it holds', () => {
      const { handlers, list } = mount(loop('1', '2', '3'))
      list.querySelector('[live-key="2"]').remove()

      send(handlers, [['u', '3', { 1: 'Changed' }]])

      expect(keysOf(list)).toEqual(['1', '2', '3'])
      expect(list.lastElementChild.textContent).toBe('Changed')
    })

    it('leaves a live-ignore row alone, and the rows inside a live-ignore element', () => {
      const ignoredRow = { 0: ['<li live-key="', '" live-ignore>', '</li>'] }
      const row = mount(loop('1', '2'), { statics: ignoredRow })
      row.list.querySelector('[live-key="2"]').textContent = 'kept'

      send(row.handlers, [['u', '2', { 1: 'Changed' }], ['a', '3', ['3', 'Row 3']]])

      expect(keysOf(row.list)).toEqual(['1', '2', '3'])
      expect(row.list.querySelector('[live-key="2"]').textContent).toBe('kept')

      const container = mount(loop('1', '2'), { open: '<ul live-ignore>' })

      send(container.handlers, [['d', '1'], ['u', '2', { 1: 'Changed' }]])

      expect(keysOf(container.list)).toEqual(['1', '2'])
      expect(Array.from(container.list.children, li => li.textContent)).toEqual(['Row 1', 'Row 2'])
    })

    it('keeps focus and what was typed in a row that moves', () => {
      const inputs = { 0: ['<li live-key="', '"><input name="title" value="', '"><b>', '</b></li>'] }
      const node = { t: 0, r: ['1', '2', '3'].map(key => [key, `Row ${key}`, 'idle']), k: ['1', '2', '3'] }
      const { handlers, list } = mount(node, { statics: inputs })
      const input = list.querySelector('[live-key="1"] input')
      input.focus()
      input.value = 'typing'
      input.setSelectionRange(2, 4)

      send(handlers, [['m', '1', '3'], ['u', '1', { 2: 'saving' }]])

      expect(keysOf(list)).toEqual(['2', '3', '1'])
      expect(list.querySelector('[live-key="1"] b').textContent).toBe('saving')
      expect(document.activeElement).toBe(input)
      expect(input.value).toBe('typing')
      expect([input.selectionStart, input.selectionEnd]).toEqual([2, 4])
    })

    it('keeps focus and what was typed in a row through a frame that also changes other markup', () => {
      const inputs = { 0: ['<li live-key="', '"><input name="title"><b>', '</b></li>'] }
      const { element, handlers, list } = mount(loop('1', '2'), { statics: inputs })
      const input = list.querySelector('[live-key="2"] input')
      input.focus()
      input.value = 'typing'
      input.setSelectionRange(2, 4)

      handlers.received({
        _refresh: { h: 'rows', p: [`<div live-id="${element.dataset.liveIdValue}" live-component="rows"><h2>Renamed</h2><ul>\n  `, { o: [['p', '0', ['0', 'Row 0']]] }, null] },
      })

      expect(element.querySelector('h2').textContent).toBe('Renamed')
      expect(keysOf(element.querySelector('ul'))).toEqual(['0', '1', '2'])
      expect(document.activeElement).toBe(input)
      expect(input.value).toBe('typing')
      expect([input.selectionStart, input.selectionEnd]).toEqual([2, 4])
    })

    it('builds new rows of a loop inside an svg as svg elements', () => {
      const circles = { 0: ['<circle id="', '" r="', '"></circle>'] }
      const node = { t: 0, r: ['1', '2'].map(key => [key, '3']), k: ['1', '2'] }
      const { handlers, list } = mount(node, { statics: circles, open: '<svg>', close: '</svg>' })
      list.setAttribute('data-touched', '')

      send(handlers, [['a', '3', ['3', '4']], ['i', '4', ['4', '5'], '1']])

      expect(Array.from(list.children, circle => circle.id)).toEqual(['1', '4', '2', '3'])
      expect(Array.from(list.children, circle => circle.namespaceURI)).toEqual(Array(4).fill('http://www.w3.org/2000/svg'))
      expect(list.hasAttribute('data-touched')).toBe(true)
    })

    it('rebuilds and morphs when another element of the component carries the key a loop starts with', () => {
      const statics = { 0: ['<li live-key="', '">tab ', '</li>'], 1: ['<div live-key="', '">panel ', '</div>'] }
      const tabs = (...keys) => ({ t: 0, r: keys.map(key => [key, key]), k: keys })
      const panels = (...keys) => ({ t: 1, r: keys.map(key => [key, key]), k: keys })
      const id = `rows-${++sequence}`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'rows')
      document.body.appendChild(element)
      subscriptionManager.subscribe(id, 'rows', '', buildController(element))
      const { handlers } = createdSubscriptions.at(-1)
      const parts = (first, second) => [`<div live-id="${id}" live-component="rows"><ul>`, first, '</ul><section>', second, '</section></div>']

      handlers.received({ _refresh: { h: 'rows', p: parts(tabs('1', '2', '3'), panels('1', '2', '3')), s: statics } })
      handlers.received({ _refresh: { h: 'rows', p: [null, null, null, { o: [['u', '2', { 1: 'two!' }], ['d', '3']] }, null] } })

      expect(element.querySelector('ul').innerHTML).toBe(renderParts([tabs('1', '2', '3')], statics))
      expect(element.querySelector('section [live-key="2"]').textContent).toBe('panel two!')
      element.remove()
    })

    it('rebuilds and morphs when an element inside a row has the id of the row key', () => {
      const inputs = { 0: ['<li live-key="', '"><input id="', '"></li>'] }
      const node = (...keys) => ({ t: 0, r: keys.map(key => [key, key]), k: keys })
      const { element, handlers, list } = mount(node('1'), { statics: inputs })

      send(handlers, [['a', '2', ['2', '2']]])

      expect(keysOf(list)).toEqual(['1', '2'])
      expect(element.innerHTML).toBe(rendered(node('1', '2'), { statics: inputs }))
    })

    it('finds rows whose keys need escaping in a selector', () => {
      const keys = ['a"b', 'c\\d', 'e\nf', '1 2']
      const escaped = (...list) => ({ ...loop(...list), r: list.map(key => [key.replace(/"/g, '&quot;'), `Row ${key}`]) })
      const { handlers, list } = mount(escaped(...keys))
      list.setAttribute('data-touched', '')

      send(handlers, [['u', keys[0], { 1: 'Changed' }], ['a', '9', ['9', 'Row 9']]])

      expect(keysOf(list)).toEqual([...keys, '9'])
      expect(list.firstElementChild.textContent).toBe('Changed')
      expect(list.hasAttribute('data-touched')).toBe(true)
    })

    it('keeps the child components in its rows, and places new rows in table markup', () => {
      const placeholder = (liveId) => `<LiveCable child-live-id="${liveId}"></LiveCable>`
      const tableRows = { 0: ['<tr id="', '"><td>', '</td></tr>'] }
      const badge = (id) => ({ h: 'badge', p: [`<span live-id="${id}" live-component="badge">badge ${id}</span>`] })
      const rows = (...keys) => ({ t: 0, r: keys.map(key => [key, placeholder(`badge/${key}`)]), k: keys })
      const { element, handlers, list } = mount(rows('1', '2'), {
        statics: tableRows,
        open: '<table><tbody>',
        close: '</tbody></table>',
        children: { 'badge/1': badge('1'), 'badge/2': badge('2') },
      })
      const tbody = list.querySelector('tbody')
      const first = tbody.querySelector('[data-live-id-value="1"]')

      send(handlers, [['m', '1', '2'], ['i', '3', ['3', 'plain'], '2'], ['u', '2', { 1: `${placeholder('badge/2')} and more` }]])

      expect(Array.from(tbody.children, tr => tr.id)).toEqual(['2', '3', '1'])
      expect(tbody.querySelector('[data-live-id-value="1"]')).toBe(first)
      expect(tbody.querySelector('[id="2"]').textContent).toBe('badge 2 and more')
      expect(tbody.querySelector('[id="3"]').textContent).toBe('plain')
      expect(element.querySelector('LiveCable')).toBeNull()
    })
  })

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

    it('keeps a refused child as it was when its parent renders it again', () => {
      const room = mountRoot('room', 'nested-refused')

      room.received({
        _refresh: {
          h: 'room',
          p: ['<div live-id="nested-refused" live-component="room">', '<h1>Lobby</h1>', placeholder('thread/nested-refused'), '</div>'],
          c: {
            'thread/nested-refused': { h: 'thread', p: ['<div live-id="nested-refused" live-component="thread">hello</div>'] },
          },
        },
      })

      connect(find('thread', 'nested-refused')).received({ _refused: true, _reason: 'gone', _error: '<details></details>' })

      room.received({ _refresh: { h: 'room', p: [null, '<h1>Renamed</h1>', null, null] } })

      const thread = find('thread', 'nested-refused')
      expect(thread?.textContent).toBe('hello')
      expect(thread.getAttribute('data-live-status-value')).toBe('refused')
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
      // A subscription that has received nothing holds no render to rebuild from
      const thread = document.createElement('div')
      thread.setAttribute('data-live-id-value', 'nested-4')
      thread.setAttribute('data-live-component-value', 'thread')
      connect(thread)
      const room = mountRoot('room', 'nested-4')

      room.received({
        _refresh: {
          h: 'room',
          p: ['<div live-id="nested-4" live-component="room">', '<h2>Lobby</h2>', placeholder('thread/nested-4'), '</div>'],
        },
      })
      room.received({ _refresh: { h: 'room', p: [null, '<h2>Renamed</h2>', null, null] } })

      expect(find('room', 'nested-4').querySelector('h2').textContent).toBe('Renamed')
    })

    describe('subscribing a child the page rendered before the socket did', () => {
      const row = (id, attributes = '') => ({
        h: 'row',
        p: [`<div ${attributes} live-id="${id}" live-component="row"><span>`, 'first', '</span></div>'],
      })

      // The prerendered child carries no live attributes; the parent's first
      // render over the socket brings them, with the child in c
      function loadPage(id, { childAttributes = '', prerendered = '' } = {}) {
        const element = document.createElement('div')
        element.setAttribute('data-live-id-value', id)
        element.setAttribute('data-live-component-value', 'shelf')
        element.innerHTML = prerendered
        document.body.appendChild(element)

        const shelf = connect(element)
        shelf.received({
          _refresh: {
            h: 'shelf',
            p: [`<div live-id="${id}" live-component="shelf">`, placeholder(`row/${id}`), '</div>'],
            c: { [`row/${id}`]: row(id, childAttributes) },
          },
          _reply: false,
          _subscribed: true,
        })

        return shelf
      }

      function loadIdRootedChild(id) {
        loadPage(id, {
          childAttributes: `id="row-${id}"`,
          prerendered: `<div id="row-${id}"><span>first</span></div>`,
        })

        const child = find('row', id)
        expect(subscriptionManager.getComponentState(`row/${id}`).element).not.toBe(child)

        return child
      }

      it('applies a delta to a child whose root has an id', () => {
        const child = loadIdRootedChild('load-1')

        connect(child).received({ _refresh: { h: 'row', p: [null, 'second', null] }, _reply: false, _subscribed: true })

        expect(subscriptionManager.getComponentState('row/load-1').hasRender).toBe(true)
        expect(find('row', 'load-1')).toBe(child)
        expect(child.textContent).toBe('second')
      })

      it('applies an unchanged render to a child whose root has an id', () => {
        const child = loadIdRootedChild('load-2')
        const handlers = connect(child)

        expect(() => handlers.received({ _refresh: { h: 'row', p: [null, null, null] }, _reply: false, _subscribed: true })).not.toThrow()

        expect(subscriptionManager.getComponentState('row/load-2').hasRender).toBe(true)
        expect(child.textContent).toBe('first')
      })

      it('applies a delta to a child whose root has no id', () => {
        loadPage('load-3', { prerendered: '<div><span>first</span></div>' })
        const child = find('row', 'load-3')

        connect(child).received({ _refresh: { h: 'row', p: [null, 'second', null] }, _reply: false, _subscribed: true })

        expect(subscriptionManager.getComponentState('row/load-3').hasRender).toBe(true)
        expect(child.textContent).toBe('second')
      })

      it('applies a delta to a child its parent rebuilt on a Turbo visit before the child connected', () => {
        loadPage('load-4')
        const shelfElement = find('shelf', 'load-4')
        const copy = shelfElement.cloneNode(true)
        shelfElement.replaceWith(copy)
        subscriptionManager.subscribe('load-4', 'shelf', '', buildController(copy))
        const child = find('row', 'load-4')

        connect(child).received({ _refresh: { h: 'row', p: [null, 'second', null] }, _reply: false, _subscribed: true })

        expect(subscriptionManager.getComponentState('row/load-4').hasRender).toBe(true)
        expect(find('row', 'load-4').textContent).toBe('second')
      })
    })


    it('places children inside table markup where the parent renders them', () => {
      const table = mountRoot('table', 'nested-5')
      const row = (n) => ({ h: 'row', p: [`<tr live-id="row-${n}" live-component="row"><td>row ${n}</td></tr>`] })
      const parts = (...rows) => [
        '<div live-id="nested-5" live-component="table"><table><tbody>',
        '<tr live-ignore><td>pinned</td></tr>',
        rows.map(n => placeholder(`row/row-${n}`)).join(''),
        '</tbody></table></div>',
      ]

      table.received({ _refresh: { h: 'table', p: parts(1, 2), c: { 'row/row-1': row(1), 'row/row-2': row(2) } } })

      const tbody = find('table', 'nested-5').querySelector('tbody')
      tbody.querySelector('[live-ignore] td').textContent = 'kept'
      expect([...tbody.children].map(tr => tr.textContent)).toEqual(['kept', 'row 1', 'row 2'])

      table.received({ _refresh: { h: 'table', p: [null, null, parts(1, 2, 3)[2], null], c: { 'row/row-3': row(3) } } })

      expect([...tbody.children].map(tr => tr.textContent)).toEqual(['kept', 'row 1', 'row 2', 'row 3'])
      expect(find('table', 'nested-5').firstElementChild.tagName).toBe('TABLE')
    })

    it('places a child whose id is escaped in its placeholder', () => {
      const list = mountRoot('list', 'nested-6')
      const tag = { h: 'tag', p: ['<span live-id="a &amp; &quot;b&quot;" live-component="tag">tagged</span>'] }

      list.received({
        _refresh: {
          h: 'list',
          p: ['<div live-id="nested-6" live-component="list">', placeholder('tag/a &amp; &quot;b&quot;'), '</div>'],
          c: { 'tag/a & "b"': tag },
        },
      })

      expect(find('list', 'nested-6').textContent).toBe('tagged')
    })

    it('keeps a subscribed child subscribed when its parent rebuilds it from what it last rendered', async () => {
      const application = Application.start()
      application.register('live', LiveController)
      const tick = () => new Promise((resolve) => setTimeout(resolve, 0))

      try {
        document.body.innerHTML = '<div data-controller="live" data-live-id-value="nested-7" data-live-component-value="room"></div>'
        await tick()

        const room = createdSubscriptions.at(-1).handlers
        room.received({
          _refresh: {
            h: 'room',
            p: ['<div live-id="nested-7" live-component="room" data-live-status-value="subscribed"><h2>', 'Lobby', '</h2>', placeholder('thread/nested-7'), '</div>'],
            c: {
              'thread/nested-7': { h: 'thread', p: ['<div live-id="nested-7" live-component="thread" data-live-status-value="disconnected"></div>'] },
            },
          },
          _reply: false,
          _subscribed: true,
        })
        room.connected()
        await tick()

        createdSubscriptions.at(-1).handlers.received({ _status: 'subscribed' })

        expect(find('thread', 'nested-7').getAttribute('data-live-status-value')).toBe('subscribed')

        room.received({ _refresh: { h: 'room', p: [null, 'Renamed', null, null, null] }, _reply: false })

        expect(find('room', 'nested-7').querySelector('h2').textContent).toBe('Renamed')
        expect(find('thread', 'nested-7').getAttribute('data-live-status-value')).toBe('subscribed')
      } finally {
        application.stop()
      }
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

      it('fires the events on its ack once it has caught up with the render its parent carried', () => {
        const { id, room, child } = mountRoom()
        const seen = []
        child.controller.element.addEventListener('composer:sent', () => {
          seen.push({ label: child.button().textContent, disabled: child.button().disabled })
        })
        child.submit()

        room.handlers.received({
          _refresh: {
            h: 'room',
            p: [null, null, null, placeholder(`composer/${id}`), null],
            c: { [`composer/${id}`]: { h: 'composer', p: [composer(id, { label: 'Send another' })] } },
          },
          _reply: false,
        })
        child.handlers.received({ _ack: true, _rendered: true, _events: [{ name: 'composer:sent', detail: {}, window: false }] })

        expect(seen).toEqual([{ label: 'Send another', disabled: false }])
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

        it('catches up with the render its parent carried when that render moves it while it waits', async () => {
          const id = `loading-board-${++sequence}`
          const [a, b] = [`a-${id}`, `b-${id}`]
          const card = (cardId, position) =>
            `<div live-id="${cardId}" live-component="card" live-actions='["down"]'>` +
            `<button live-action="down" live-value-from="${position}" live-disable-with="Moving...">#${position} down</button></div>`
          const board = (order, positions) => ({
            h: 'board',
            p: [`<div live-id="${id}" live-component="board">`, order.map(c => placeholder(`card/${c}`)).join(''), '</div>'],
            c: Object.fromEntries(order.map(c => [`card/${c}`, { h: 'card', p: [card(c, positions[c])] }])),
          })
          document.body.innerHTML = `<div data-controller="live" data-live-id-value="${id}" data-live-component-value="board"></div>`
          await tick()

          const boardHandlers = createdSubscriptions.at(-1).handlers
          boardHandlers.received({ _refresh: board([a, b], { [a]: 1, [b]: 2 }), _reply: false, _subscribed: true })
          boardHandlers.connected()
          await tick()

          const cardHandlers = (cardId) => createdSubscriptions.findLast(s => s.params.id === cardId).handlers
          cardHandlers(a).connected()
          cardHandlers(b).connected()
          const button = () => document.querySelector(`[data-live-id-value="${a}"] button`)
          button().click()

          expect(sentMessages.at(-1).messages[0]).toMatchObject({ _action: 'down', params: 'from=1' })

          boardHandlers.received({ _refresh: board([b, a], { [a]: 2, [b]: 1 }), _reply: false })
          await tick()
          cardHandlers(a).received({ _ack: true, _rendered: true })

          expect(document.querySelector(`[data-live-id-value="${id}"]`).lastElementChild.getAttribute('data-live-id-value')).toBe(a)
          expect(button().disabled).toBe(false)
          expect(button().getAttribute('data-live-from-param')).toBe('"2"')
          expect(button().textContent).toBe('#2 down')
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

      it('catches up with a render that came while a send waited when the socket is refused', () => {
        const chat = mountComposer()
        chat.submit()

        chat.render({ _reply: false }, { draft: 'hi', label: 'Send to 3 people' })
        chat.handlers.disconnected({ willAttemptReconnect: false })

        expect(chat.controller.isLoading).toBe(false)
        expect(chat.button().disabled).toBe(false)
        expect(chat.button().textContent).toBe('Send to 3 people')
        expect(chat.controller.statusValue).toBe('refused')
      })

      it('catches up with a render that came while a send waited when the component is refused', () => {
        const chat = mountComposer()
        chat.submit()

        chat.render({ _reply: false }, { draft: 'hi', label: 'Send to 3 people' })
        chat.handlers.received({ _refused: true, _reason: 'membership_ended', _error: '<details></details>' })

        expect(chat.controller.isLoading).toBe(false)
        expect(chat.button().disabled).toBe(false)
        expect(chat.button().textContent).toBe('Send to 3 people')
        expect(chat.controller.statusValue).toBe('refused')
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
          replyWith: (count) => handlers.received({ _refresh: { h: 'chat', p: [null, count, null, null, null] }, _reply: true }),
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

      it.each([
        ['an input', () => `<input ${attributes}>`],
        ['a textarea', () => `<textarea ${attributes}></textarea>`],
      ])('keeps what was typed into %s the template renders no value for through its own reply', async (_kind, field) => {
        const chat = await mountDraft(field)
        chat.type('hel')
        vi.advanceTimersByTime(300)
        chat.type('hello')

        chat.replyWith('1 result')

        expect(chat.field.value).toBe('hello')

        vi.advanceTimersByTime(300)
        chat.replyWith('2 results')

        expect(sentMessages.at(-1)).toEqual({ messages: [{ _action: '_reactive', name: 'draft', value: 'hello' }] })
        expect(chat.field.value).toBe('hello')
      })

      it('takes the value the server rendered before when it answers its own update with it', async () => {
        const chat = await mountDraft()
        chat.type('hel')
        vi.advanceTimersByTime(300)

        chat.reply('')

        expect(chat.field.value).toBe('')
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
