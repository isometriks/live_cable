import { describe, it, expect, beforeEach, vi } from 'vitest'
import LoadingState from '../app/assets/javascript/loading.js'
import { applyPart } from '../app/assets/javascript/tree.js'

// Collection streams on the page: frames shaped as the server sends them for
//
//   <div class="chat">
//     <h2><%= room_name %></h2>
//     <% if expanded %>
//       <ul class="messages <%= density %>" live-stream="messages">
//         <%= live_stream_for :messages do |message| %>
//           <li class="message"><b><%= message.body %></b> <button ...>Like <%= message.likes %></button> <input name="note"></li>
//         <% end %>
//       </ul>
//     <% else %>
//       <button live-action="toggle">Show chat</button>
//     <% end %>
//   </div>

const createdSubscriptions = []

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    connection: { events: { open() {}, message() {} }, isActive: () => true },
    subscriptions: {
      create(params, handlers) {
        const subscription = { params, handlers, send: () => true, unsubscribe() {} }
        createdSubscriptions.push(subscription)
        return subscription
      },
    },
  }),
}))

const subscriptionManager = (await import('../app/assets/javascript/subscriptions.js')).default

const statics = {
  0: ['\n    <ul class="messages ', '" live-stream="messages">\n      ', '\n    </ul>\n  '],
  1: ['<li id="', '" class="message"><b>', '</b> <button live-action="like" live-disable-with="Liking">Like ', '</button> <input name="note"></li>'],
  2: ['\n    <button live-action="toggle">Show chat</button>\n  '],
}

const key = (id) => `messages_message_${id}`
const row = (id, body = `Message ${id}`, likes = 0) => [key(id), body, String(likes)]
const stream = (rows, extra = {}) => ({ t: 1, st: 'messages', r: rows, k: rows.map(([rowKey]) => rowKey), ...extra })
const ops = (...list) => ({ d: { 1: { o: list } } })

let sequence = 0

// The live controller's loading API around a real LoadingState
function controllerFor(element) {
  const loading = new LoadingState(element)

  return {
    element,
    statusValue: 'disconnected',
    loading,
    finishLoading: () => loading.finish(),
    resetLoading: () => loading.reset(),
    get isLoading() { return loading.active },
    get inFlight() { return loading.inFlight },
  }
}

function chatParts(id, node, { title = 'Lobby', density = 'cozy' } = {}) {
  return [
    `<div live-id="${id}" live-component="chat" class="chat">\n  <h2>`,
    title,
    '</h2>\n  ',
    node === null ? { t: 2, d: [] } : { t: 0, d: [density, node] },
    '\n</div>',
  ]
}

function mountChat(node, { component = 'chat', options, templateStatics = statics } = {}) {
  const id = `chat-${++sequence}`
  const element = document.createElement('div')
  element.setAttribute('data-live-id-value', id)
  element.setAttribute('data-live-component-value', component)
  document.body.appendChild(element)

  const controller = controllerFor(element)
  const subscription = subscriptionManager.subscribe(id, component, '', controller)
  const { handlers } = createdSubscriptions.at(-1)
  let held = chatParts(id, node, options)

  handlers.received({ _refresh: { h: 'chat', p: held, s: templateStatics }, _reply: false, _subscribed: true })

  return {
    id,
    element,
    controller,
    subscription,
    handlers,
    list: () => element.querySelector('[live-stream]'),
    keys: () => Array.from(element.querySelector('[live-stream]')?.children ?? [], li => li.id),
    state: () => subscriptionManager.getComponentState(`${component}/${id}`),
    send(parts, extra = {}) {
      held = held.map((part, index) => parts[index] === null || parts[index] === undefined ? part : applyPart(part, parts[index]))
      handlers.received({ _refresh: { h: 'chat', p: parts, ...extra }, _reply: false, ...extra._frame })
    },
    sendOps(...list) {
      this.send([null, null, null, ops(...list), null])
    },
    // What the page shows when the parts held so far arrive whole
    rendered() {
      return renderedHTML(held, id, templateStatics)
    },
  }
}

function renderedHTML(parts, id, templateStatics) {
  const element = document.createElement('div')
  element.setAttribute('data-live-id-value', `${id}-rebuilt`)
  element.setAttribute('data-live-component-value', 'chat')
  document.body.appendChild(element)
  subscriptionManager.subscribe(`${id}-rebuilt`, 'chat', '', controllerFor(element))
  const rebuiltParts = parts.slice()
  rebuiltParts[0] = rebuiltParts[0].replace(`live-id="${id}"`, `live-id="${id}-rebuilt"`)
  createdSubscriptions.at(-1).handlers.received({ _refresh: { h: 'chat', p: rebuiltParts, s: templateStatics } })
  const html = element.innerHTML
  element.remove()
  subscriptionManager.unsubscribe(`chat/${id}-rebuilt`)
  return html
}

// A morph of the whole component takes this off the root again
function touch(element) {
  element.setAttribute('data-touched', '')
  return () => element.hasAttribute('data-touched')
}

describe('collection streams', () => {
  beforeEach(() => {
    document.body.innerHTML = ''
    createdSubscriptions.length = 0
  })

  describe('a frame of row ops alone', () => {
    it('inserts, updates in place and removes rows without morphing the component', () => {
      const chat = mountChat(stream([row(1), row(2), row(3)]))
      const untouched = touch(chat.element)
      const second = chat.list().children[1]
      second.expando = 'kept'
      const renders = chat.state().renderCount

      chat.sendOps(['a', key(4), row(4)], ['p', key(0), row(0)], ['u', key(2), row(2, 'Edited', 1)], ['d', key(3)])

      expect(untouched()).toBe(true)
      expect(chat.keys()).toEqual([key(0), key(1), key(2), key(4)])
      expect(chat.list().children[2]).toBe(second)
      expect(second.expando).toBe('kept')
      expect(second.querySelector('b').textContent).toBe('Edited')
      expect(chat.state().renderCount).toBe(renders + 1)
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('fills an empty stream through its container, and empties it again, whitespace and all', () => {
      const chat = mountChat(stream([]))
      const untouched = touch(chat.element)

      chat.sendOps(['a', key(1), row(1)])

      expect(untouched()).toBe(true)
      expect(chat.keys()).toEqual([key(1)])
      expect(chat.element.innerHTML).toBe(chat.rendered())

      chat.sendOps(['d', key(1)])
      chat.sendOps(['p', key(2), row(2)], ['a', key(3), row(3)])

      expect(untouched()).toBe(true)
      expect(chat.keys()).toEqual([key(2), key(3)])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('fills a stream at the top of the template, outside any block', () => {
      const id = `feed-${++sequence}`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'feed')
      document.body.appendChild(element)
      subscriptionManager.subscribe(id, 'feed', '', controllerFor(element))
      const { handlers } = createdSubscriptions.at(-1)
      const open = `<div live-id="${id}" live-component="feed">\n  <ol live-stream="messages">\n    `

      handlers.received({ _refresh: { h: 'feed', p: [open, stream([]), '  </ol>\n</div>'], s: statics } })
      const untouched = touch(element)
      handlers.received({ _refresh: { h: 'feed', p: [null, { o: [['a', key(1), row(1)]] }, null] } })

      expect(untouched()).toBe(true)
      expect(Array.from(element.querySelector('ol').childNodes, node => node.nodeType === Node.TEXT_NODE ? node.data : node.id))
        .toEqual(['\n    ', key(1), '  '])
    })

    it('applies keys it holds and keys it does not as a stream server sends them', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      const untouched = touch(chat.element)

      chat.sendOps(['a', key(1), row(1, 'Again')], ['u', key(9), row(9)], ['d', key(8)], ['i', key(3), row(3), key(7)])

      expect(untouched()).toBe(true)
      expect(chat.keys()).toEqual([key(1), key(2), key(3)])
      expect(chat.list().firstElementChild.querySelector('b').textContent).toBe('Again')
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('moves a row a frame deletes or trims and then inserts again, keeping its element', () => {
      const chat = mountChat(stream([row(1), row(2), row(3)]))
      const first = chat.list().firstElementChild

      chat.sendOps(['d', key(1)], ['a', key(1), row(1, 'Back')])

      expect(chat.keys()).toEqual([key(2), key(3), key(1)])
      expect(chat.list().lastElementChild).toBe(first)
      expect(chat.element.innerHTML).toBe(chat.rendered())

      const limited = mountChat(stream([row(1), row(2)], { l: 2 }))

      limited.sendOps(['a', key(3), row(3)], ['p', key(1), row(1, 'Back')], ['a', key(2), row(2, 'Kept')])

      expect(limited.keys()).toEqual([key(1), key(2)])
      expect(limited.element.innerHTML).toBe(limited.rendered())
    })

    it('leaves the page as a rebuild would for any sequence of stream ops, with and without a limit', () => {
      let state = 20261112
      const random = (limit) => {
        state = (state * 1103515245 + 12345) % 2147483648
        return state % limit
      }
      let next = 100

      for (let run = 0; run < 80; run++) {
        const start = Array.from({ length: random(5) }, () => row(next++))
        const limit = random(2) === 0 ? 1 + random(4) : undefined
        const node = stream(limit ? start.slice(-limit) : start, limit ? { l: limit } : {})
        const chat = mountChat(node)
        const untouched = touch(chat.element)
        let held = node

        for (let frame = 0; frame < 4; frame++) {
          const known = [...held.k, key(next++)]
          const pick = () => known[random(known.length)]
          const list = Array.from({ length: 1 + random(4) }, () => {
            const choice = random(6)
            const target = pick()
            const id = target.replace('messages_message_', '')

            if (choice === 0) return [['d', target]]
            if (choice === 1) return [['u', target, row(id, `Edited ${next++}`)]]
            if (choice === 2) return [['p', target, row(id, `New ${next++}`)]]
            if (choice === 3) return [['d', target], [random(2) ? 'a' : 'p', target, row(id, `Back ${next++}`)]]
            return [['a', target, row(id, `New ${next++}`)]]
          }).flat()

          held = applyPart(held, { o: list })
          chat.sendOps(...list)

          expect(untouched(), JSON.stringify(list)).toBe(true)
          expect(chat.keys(), JSON.stringify(list)).toEqual(held.k)
          chat.element.removeAttribute('data-touched')
          expect(chat.element.innerHTML, JSON.stringify(list)).toBe(chat.rendered())
          chat.element.setAttribute('data-touched', '')
        }

        chat.element.remove()
      }
    })

    it('trims to the limit on the page as in the state it holds', () => {
      const chat = mountChat(stream([row(1), row(2), row(3)], { l: 3 }))
      const untouched = touch(chat.element)

      chat.sendOps(['a', key(4), row(4)], ['a', key(5), row(5)])

      expect(chat.keys()).toEqual([key(3), key(4), key(5)])

      chat.sendOps(['p', key(0), row(0)], ['a', key(4), row(4, 'Replaced')])

      expect(untouched()).toBe(true)
      expect(chat.keys()).toEqual([key(0), key(3), key(4)])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('dispatches the events the frame carries after the rows are in', () => {
      const chat = mountChat(stream([row(1)]))
      const seen = []
      chat.element.addEventListener('chat:message-received', (event) => {
        seen.push([event.target, Array.from(chat.list().children, li => li.id)])
      })

      chat.handlers.received({
        _refresh: { h: 'chat', p: [null, null, null, ops(['a', key(2), row(2)]), null] },
        _reply: false,
        _events: [{ name: 'chat:message-received', detail: {} }],
      })

      expect(seen).toEqual([[chat.element, [key(1), key(2)]]])
    })

    it('wires the actions of a row it inserts', () => {
      const chat = mountChat(stream([]))

      chat.sendOps(['a', key(1), row(1)])

      expect(chat.list().querySelector('button').getAttribute('data-action')).toBe('live#action_$like')
    })

    it('ignores an element elsewhere in the component with a row key as its id', () => {
      const chat = mountChat(stream([row(1), row(2)]), { options: { title: `<span id="${key(1)}">pinned</span>` } })
      const untouched = touch(chat.element)

      chat.sendOps(['u', key(1), row(1, 'Edited')], ['d', key(2)])

      expect(untouched()).toBe(true)
      expect(chat.element.querySelector('h2 span').textContent).toBe('pinned')
      expect(chat.list().firstElementChild.querySelector('b').textContent).toBe('Edited')
      expect(chat.keys()).toEqual([key(1)])
    })

    it('finds rows by id without a selector, whatever their keys', () => {
      const keys = ['1-one', '2"two', 'three four']
      const rows = keys.map(rowKey => [rowKey.replace(/"/g, '&quot;'), rowKey, '0'])
      const chat = mountChat({ t: 1, st: 'messages', r: rows, k: keys })
      const untouched = touch(chat.element)

      chat.sendOps(['u', keys[1], ['2&quot;two', 'Edited', '1']], ['d', keys[2]])

      expect(untouched()).toBe(true)
      expect(chat.keys()).toEqual(keys.slice(0, 2))
      expect(chat.list().children[1].querySelector('b').textContent).toBe('Edited')
    })
  })

  describe('a frame that changes more than rows', () => {
    const rowsUntouched = (chat) => {
      const marks = Array.from(chat.list().children, touch)
      return () => marks.map(untouched => untouched())
    }

    it('morphs the rest of the component and applies the ops to the rows alone', () => {
      const chat = mountChat(stream([row(1), row(2), row(3)]))
      const second = chat.list().children[1]
      const untouched = rowsUntouched(chat)

      chat.send([null, 'Renamed', null, ops(['a', key(4), row(4)], ['u', key(1), row(1, 'Edited')], ['d', key(3)]), null])

      expect(chat.element.querySelector('h2').textContent).toBe('Renamed')
      expect(chat.keys()).toEqual([key(1), key(2), key(4)])
      expect(chat.list().children[1]).toBe(second)
      expect(untouched()).toEqual([false, true, true])
      chat.list().children[1].removeAttribute('data-touched')
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('leaves the rows alone when the part around the container re-runs or only other markup changes', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      const untouched = rowsUntouched(chat)

      chat.send([null, null, null, { d: { 0: 'compact' } }, null])
      expect(chat.list().className).toBe('messages compact')

      chat.send([null, 'Renamed', null, null, null])
      expect(chat.element.querySelector('h2').textContent).toBe('Renamed')

      expect(untouched()).toEqual([true, true])
      chat.list().querySelectorAll('[data-touched]').forEach(li => li.removeAttribute('data-touched'))
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('fills and empties an empty stream alongside other changes, whitespace and all', () => {
      const chat = mountChat(stream([]))

      chat.send([null, 'One', null, ops(['a', key(1), row(1)]), null])
      expect(chat.element.innerHTML).toBe(chat.rendered())

      chat.send([null, 'None', null, { d: { 0: 'compact', 1: { o: [['d', key(1)]] } } }, null])
      expect(chat.keys()).toEqual([])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('leaves the page as a rebuild would for any mix of ops and other changes', () => {
      let state = 20261113
      const random = (limit) => {
        state = (state * 1103515245 + 12345) % 2147483648
        return state % limit
      }
      let next = 100

      for (let run = 0; run < 40; run++) {
        const start = Array.from({ length: random(5) }, () => row(next++))
        const limit = random(2) === 0 ? 1 + random(4) : undefined
        let held = stream(limit ? start.slice(-limit) : start, limit ? { l: limit } : {})
        const chat = mountChat(held)

        for (let frame = 0; frame < 5; frame++) {
          const known = [...held.k, key(next++)]
          const target = known[random(known.length)]
          const id = target.replace('messages_message_', '')
          const list = [[['a', target, row(id, `New ${next++}`)]], [['d', target]], [['u', target, row(id, `Edited ${next++}`)]],
            [['d', target], ['p', target, row(id, `Back ${next++}`)]]][random(4)]
          const change = random(3)
          const node = random(4) === 0 ? null : { o: list }
          const block = change === 0 ? { d: { 0: `d${next++}`, ...(node ? { 1: node } : {}) } } : (node ? { d: { 1: node } } : null)

          if (node) held = applyPart(held, node)
          chat.send([null, change === 0 ? null : `Title ${next++}`, null, block, null])

          expect(chat.keys(), JSON.stringify(list)).toEqual(held.k)
          expect(chat.element.innerHTML, JSON.stringify(list)).toBe(chat.rendered())
        }

        chat.element.remove()
      }
    })

    it('morphs the rows a reset or a branch change replaces', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      const survivor = chat.list().lastElementChild

      chat.send([null, 'Reset', null, { d: { 1: stream([row(2), row(3)]) } }, null])
      expect(chat.keys()).toEqual([key(2), key(3)])
      expect(chat.list().firstElementChild).toBe(survivor)
      expect(chat.element.innerHTML).toBe(chat.rendered())

      chat.send([null, 'Hidden', null, { t: 2, d: [] }, null])
      expect(chat.list()).toBe(null)

      chat.send([null, 'Shown', null, { t: 0, d: ['cozy', stream([row(5)])] }, null])
      expect(chat.keys()).toEqual([key(5)])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('keeps the container when another list appears before it', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      const list = chat.list()
      const first = list.firstElementChild

      chat.send([null, null, '</h2>\n  <ul class="pinned"><li>Pinned</li></ul>\n  ', ops(['a', key(3), row(3)]), null])

      expect(chat.list()).toBe(list)
      expect(list.firstElementChild).toBe(first)
      expect(chat.keys()).toEqual([key(1), key(2), key(3)])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('repairs rows a morph left alone while they awaited a reply', () => {
      const wrapped = { ...statics, 0: ['\n    <form><ul class="messages ', '" live-stream="messages">\n      ', '\n    </ul></form>\n  '] }
      const chat = mountChat(stream([row(1), row(2)]), { templateStatics: wrapped })
      chat.controller.loading.start(chat.element.querySelector('form'))
      chat.subscription.send({ messages: [{ _action: 'like' }] })

      chat.send([null, 'Waiting', null, ops(['u', key(1), row(1, 'Edited')]), null])
      expect(chat.list().firstElementChild.querySelector('b').textContent).toBe('Message 1')

      chat.send([null, 'Answered', null, null, null], { _frame: { _reply: true } })

      expect(chat.list().firstElementChild.querySelector('b').textContent).toBe('Edited')
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('repairs rows the page lost or gained outside a render, and leaves a row a script changed', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      chat.list().lastElementChild.remove()

      chat.send([null, 'Renamed', null, null, null])
      expect(chat.keys()).toEqual([key(1), key(2)])

      chat.list().querySelector('b').textContent = 'Scribbled'
      chat.send([null, 'Once', null, null, null])
      expect(chat.list().querySelector('b').textContent).toBe('Scribbled')

      chat.list().append(document.createElement('li'))
      chat.send([null, 'Again', null, null, null])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('keeps the component loading through a morph of the whole component it falls back to', () => {
      const chat = mountChat(stream([row(1)]))
      chat.controller.loading.start(chat.element)
      chat.subscription.send({ messages: [{ _action: 'rename' }] })

      chat.send([null, 'Renamed', null, ops(['a', key(2), [`${key(2)}"></li><li id="extra`, 'Two', '0']]), null])

      expect(chat.element.querySelector('h2').textContent).toBe('Renamed')
      expect(chat.element.hasAttribute('live-loading')).toBe(true)

      chat.send([null, 'Answered', null, null, null], { _frame: { _reply: true } })
      expect(chat.element.hasAttribute('live-loading')).toBe(false)
    })

    it('keeps a focused field and what was typed in a row', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      const input = chat.list().lastElementChild.querySelector('input')
      input.focus()
      input.value = 'typing'

      chat.send([null, 'Renamed', null, ops(['p', key(0), row(0)]), null])

      expect(document.activeElement).toBe(input)
      expect(input.value).toBe('typing')
      expect(chat.keys()).toEqual([key(0), key(1), key(2)])
    })

    it('keeps a parent stream and a child stream of the same name apart', () => {
      const id = `room-${++sequence}`
      const childId = `${id}-panel`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'room')
      document.body.appendChild(element)
      subscriptionManager.subscribe(id, 'room', '', controllerFor(element))
      const { handlers } = createdSubscriptions.at(-1)
      const childStatics = { 5: ['<li id="', '">child ', '</li>'] }

      handlers.received({
        _refresh: {
          h: 'room',
          p: [`<div live-id="${id}" live-component="room"><h1>`, 'Room', '</h1>', `<LiveCable child-live-id="panel/${childId}"></LiveCable>`, '<ul live-stream="messages">', { t: 1, st: 'messages', r: [row(1)], k: [key(1)] }, '</ul></div>'],
          s: statics,
          c: { [`panel/${childId}`]: { h: 'panel', p: [`<section live-id="${childId}" live-component="panel"><ul live-stream="messages">`, { t: 5, st: 'messages', r: [[key(1), 'one']], k: [key(1)] }, '</ul></section>'], s: childStatics } },
        },
      })

      handlers.received({ _refresh: { h: 'room', p: [null, 'Renamed', null, null, null, { o: [['a', key(2), row(2)]] }, null] } })

      expect(Array.from(element.querySelectorAll(':scope > ul > li'), li => li.id)).toEqual([key(1), key(2)])
      expect(Array.from(element.querySelectorAll('section li'), li => li.textContent)).toEqual(['child one'])
      expect(element.querySelector('h1').textContent).toBe('Renamed')
    })
  })

  describe('rows whose id is their key', () => {
    const bare = (id, ...rest) => row(id, ...rest).slice(1)
    const keyed = (ids) => ({ ...stream(ids.map(id => row(id))), ik: 1, r: ids.map(id => bare(id)) })

    it('fills each id from the key, on the first render, from row ops alone and beside other changes', () => {
      const chat = mountChat(keyed([1, 2, 3]))
      const untouched = touch(chat.element)

      expect(chat.keys()).toEqual([key(1), key(2), key(3)])

      chat.sendOps(['a', key(4), bare(4)], ['p', key(0), bare(0)], ['u', key(2), bare(2, 'Edited', 1)], ['d', key(3)])

      expect(untouched()).toBe(true)
      expect(chat.keys()).toEqual([key(0), key(1), key(2), key(4)])
      expect(chat.list().children[2].querySelector('b').textContent).toBe('Edited')

      chat.send([null, 'Renamed', null, ops(['a', 'a&"<\'>', bare(5)]), null])

      expect(chat.keys()).toEqual([key(0), key(1), key(2), key(4), 'a&"<\'>'])
      expect(chat.element.innerHTML).toBe(chat.rendered())
      expect(chat.element.innerHTML).toContain('id="messages_message_4" class="message"><b>Message 4</b>')
    })
  })

  describe('rows in table and select markup', () => {
    function mountMarkup(open, rowStatics, close, node) {
      const id = `markup-${++sequence}`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'markup')
      document.body.appendChild(element)
      subscriptionManager.subscribe(id, 'markup', '', controllerFor(element))
      const { handlers } = createdSubscriptions.at(-1)
      handlers.received({ _refresh: { h: 'markup', p: [`<div live-id="${id}" live-component="markup">${open}`, node, `${close}</div>`], s: { 1: rowStatics } } })

      return {
        element,
        untouched: touch(element),
        send: (...list) => handlers.received({ _refresh: { h: 'markup', p: [null, { o: list }, null] } }),
      }
    }

    it('parses table rows in context', () => {
      const { element, untouched, send } = mountMarkup('<table><tbody live-stream="messages">', ['<tr id="', '"><td>', '</td></tr>'], '</tbody></table>', stream([]))

      send(['a', key(1), [key(1), 'One']], ['a', key(2), [key(2), 'Two']])

      expect(untouched()).toBe(true)
      expect(Array.from(element.querySelectorAll('tbody > tr'), tr => tr.textContent)).toEqual(['One', 'Two'])
    })

    it('parses options in context', () => {
      const { element, untouched, send } = mountMarkup('<select live-stream="messages">', ['<option id="', '">', '</option>'], '</select>', stream([[key(1), 'One']]))

      send(['p', key(2), [key(2), 'Two']])

      expect(untouched()).toBe(true)
      expect(Array.from(element.querySelector('select').options, option => option.text)).toEqual(['Two', 'One'])
    })
  })

  describe('a frame the fast path does not take', () => {
    it('morphs for ops alongside another part, child results, another template or a whole node', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      let untouched = touch(chat.element)

      chat.send([null, 'Renamed', null, ops(['a', key(3), row(3)]), null])
      expect(untouched()).toBe(false)
      expect(chat.element.innerHTML).toBe(chat.rendered())

      untouched = touch(chat.element)
      chat.send([null, null, null, ops(['d', key(1)]), null], { c: { 'badge/1': { h: 'badge', p: ['<span live-id="1" live-component="badge"></span>'] } } })
      expect(untouched()).toBe(false)
      expect(chat.keys()).toEqual([key(2), key(3)])

      untouched = touch(chat.element)
      chat.send([null, null, null, { d: { 1: stream([row(7)]) } }, null])
      expect(untouched()).toBe(false)
      expect(chat.keys()).toEqual([key(7)])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('morphs for ops that arrive under another template', () => {
      const chat = mountChat(stream([row(1)]))
      chat.handlers.received({ _refresh: { h: 'other', p: [`<div live-id="${chat.id}" live-component="chat"><p>other</p></div>`] }, _reply: false })
      const untouched = touch(chat.element)

      chat.handlers.received({ _refresh: { h: 'chat', p: [null, null, null, ops(['a', key(2), row(2)]), null] }, _reply: false })

      expect(untouched()).toBe(false)
      expect(chat.keys()).toEqual([key(1), key(2)])
    })

    it('falls back to a morph when the page has lost the container, without throwing', () => {
      const chat = mountChat(stream([row(1)]))
      chat.list().removeAttribute('live-stream')

      chat.sendOps(['a', key(2), row(2)])

      expect(chat.keys()).toEqual([key(1), key(2)])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('falls back to a morph when a row renders two elements or another id', () => {
      const chat = mountChat(stream([row(1)]))
      let untouched = touch(chat.element)

      chat.sendOps(['a', key(2), [`${key(2)}"></li><li id="extra`, 'Two', '0']])
      expect(untouched()).toBe(false)
      expect(chat.element.innerHTML).toBe(chat.rendered())

      untouched = touch(chat.element)
      chat.sendOps(['a', key(3), ['someone-else', 'Three', '0']])
      expect(untouched()).toBe(false)
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })

    it('falls back to a morph when a row it holds is missing from the page', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      chat.list().lastElementChild.remove()

      chat.sendOps(['u', key(2), row(2, 'Edited')])

      expect(chat.keys()).toEqual([key(1), key(2)])
      expect(chat.list().lastElementChild.querySelector('b').textContent).toBe('Edited')
    })

    it('leaves a container under live-ignore alone either way', () => {
      const chat = mountChat(stream([row(1)]))
      chat.list().setAttribute('live-ignore', '')

      chat.sendOps(['a', key(2), row(2)])
      expect(chat.keys()).toEqual([key(1)])

      chat.send([null, 'Renamed', null, ops(['a', key(3), row(3)]), null])
      expect(chat.keys()).toEqual([key(1)])
      expect(chat.element.querySelector('h2').textContent).toBe('Renamed')
    })

    it('leaves a container inside an element awaiting a reply to the morph, then catches up', () => {
      const wrapped = { ...statics, 0: ['\n    <form><ul class="messages ', '" live-stream="messages">\n      ', '\n    </ul></form>\n  '] }
      const chat = mountChat(stream([row(1)]), { templateStatics: wrapped })
      const wrapper = chat.element.querySelector('form')
      chat.controller.loading.start(wrapper)
      chat.subscription.send({ messages: [{ _action: 'refresh' }] })

      chat.sendOps(['a', key(2), row(2)])
      expect(chat.keys()).toEqual([key(1)])

      chat.handlers.received({ _ack: true })
      expect(chat.keys()).toEqual([key(1), key(2)])
      expect(chat.element.innerHTML).toBe(chat.rendered())
    })
  })

  describe('a row with something in progress', () => {
    it('keeps a Like button in flight disabled through an update, then shows what the server rendered', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      const button = () => chat.list().firstElementChild.querySelector('button')
      chat.controller.loading.start(button())
      chat.subscription.send({ messages: [{ _action: 'like' }] })
      expect(button().disabled).toBe(true)

      chat.sendOps(['u', key(1), row(1, 'Edited', 0)])

      expect(button().disabled).toBe(true)
      expect(button().textContent).toBe('Liking')
      expect(chat.list().firstElementChild.querySelector('b').textContent).toBe('Edited')

      chat.send([null, null, null, ops(['u', key(1), row(1, 'Edited', 1)]), null], { _frame: { _reply: true } })

      expect(button().disabled).toBe(false)
      expect(button().textContent).toBe('Like 1')
    })

    it('keeps what is typed into a focused field through an update that leaves its value, and takes a changed one', () => {
      const valued = { ...statics, 1: ['<li id="', '"><b>', '</b><input name="note" value="', '"></li>'] }
      const id = `notes-${++sequence}`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'chat')
      document.body.appendChild(element)
      subscriptionManager.subscribe(id, 'chat', '', controllerFor(element))
      const { handlers } = createdSubscriptions.at(-1)
      const noted = (body, note) => [key(1), body, note]
      handlers.received({ _refresh: { h: 'chat', p: chatParts(id, stream([noted('One', '')])), s: valued } })
      const input = element.querySelector('input')
      input.focus()
      input.value = 'typing'

      handlers.received({ _refresh: { h: 'chat', p: [null, null, null, ops(['u', key(1), noted('Liked', '')]), null] } })

      expect(element.querySelector('b').textContent).toBe('Liked')
      expect(document.activeElement).toBe(input)
      expect(input.value).toBe('typing')

      handlers.received({ _refresh: { h: 'chat', p: [null, null, null, ops(['u', key(1), noted('Liked', 'from server')]), null] } })

      expect(input.value).toBe('from server')
    })
  })

  describe('nested components', () => {
    const childStatics = { 5: ['<li id="', '">child ', '</li>'] }

    function mountWithChild() {
      const id = `room-${++sequence}`
      const childId = `${id}-panel`
      const element = document.createElement('div')
      element.setAttribute('data-live-id-value', id)
      element.setAttribute('data-live-component-value', 'room')
      document.body.appendChild(element)
      const controller = controllerFor(element)
      const subscription = subscriptionManager.subscribe(id, 'room', '', controller)
      const { handlers } = createdSubscriptions.at(-1)
      const childParts = (node) => [`<section live-id="${childId}" live-component="panel"><ul live-stream="messages">`, node, '</ul></section>']

      handlers.received({
        _refresh: {
          h: 'room',
          p: [`<div live-id="${id}" live-component="room"><ul live-stream="messages">`, { t: 1, st: 'messages', r: [row(1)], k: [key(1)] }, '</ul>', `<LiveCable child-live-id="panel/${childId}"></LiveCable>`, '</div>'],
          s: statics,
          c: { [`panel/${childId}`]: { h: 'panel', p: childParts({ t: 5, st: 'messages', r: [[key(1), 'one']], k: [key(1)] }), s: childStatics } },
        },
      })

      return { id, childId, element, controller, subscription, handlers, childParts }
    }

    it('keeps a parent and a child stream of the same name apart', () => {
      const room = mountWithChild()
      const parentList = room.element.querySelector(':scope > ul')
      const childList = room.element.querySelector('section ul')
      const untouched = touch(room.element)

      room.handlers.received({ _refresh: { h: 'room', p: [null, { o: [['a', key(2), row(2)], ['u', key(1), row(1, 'Edited')]] }, null, null, null] } })

      expect(untouched()).toBe(true)
      expect(Array.from(parentList.children, li => li.id)).toEqual([key(1), key(2)])
      expect(parentList.firstElementChild.querySelector('b').textContent).toBe('Edited')
      expect(Array.from(childList.children, li => li.textContent)).toEqual(['child one'])
    })

    it('rebuilds an inline child from its own rows when a kept parent replays', () => {
      const room = mountWithChild()
      const childElement = room.element.querySelector('section')
      const child = subscriptionManager.subscribe(room.childId, 'panel', '', controllerFor(childElement))
      createdSubscriptions.at(-1).handlers.received({ _refresh: { h: 'panel', p: [null, { o: [['a', key(2), [key(2), 'two']]] }, null] } })

      expect(Array.from(childElement.querySelectorAll('li'), li => li.textContent)).toEqual(['child one', 'child two'])

      // A Turbo visit that keeps the parent connects its controller on the new page's element
      const next = document.createElement('div')
      next.setAttribute('data-live-id-value', room.id)
      next.setAttribute('data-live-component-value', 'room')
      room.element.replaceWith(next)
      subscriptionManager.subscribe(room.id, 'room', '', controllerFor(next))

      expect(Array.from(next.querySelectorAll('section li'), li => li.textContent)).toEqual(['child one', 'child two'])
      child.unsubscribe()
    })

    it('reuses the row elements of a prerendered child when the parent first renders it over the socket', () => {
      const id = `prerendered-${++sequence}`
      const childId = `${id}-panel`
      document.body.innerHTML = `<div data-live-id-value="${id}" data-live-component-value="room"><section live-id="${childId}" live-component="panel"><ul live-stream="messages"><li id="${key(1)}">child one</li></ul></section></div>`
      const element = document.body.firstElementChild
      const prerendered = element.querySelector('li')
      subscriptionManager.subscribe(id, 'room', '', controllerFor(element))
      const childParts = [`<section live-id="${childId}" live-component="panel"><ul live-stream="messages">`, { t: 5, st: 'messages', r: [[key(1), 'one'], [key(2), 'two']], k: [key(1), key(2)] }, '</ul></section>']

      createdSubscriptions.at(-1).handlers.received({
        _refresh: {
          h: 'room',
          p: [`<div live-id="${id}" live-component="room">`, `<LiveCable child-live-id="panel/${childId}"></LiveCable>`, '</div>'],
          c: { [`panel/${childId}`]: { h: 'panel', p: childParts, s: childStatics } },
        },
        _subscribed: true,
      })

      expect(element.querySelector('li')).toBe(prerendered)
      expect(Array.from(element.querySelectorAll('li'), li => li.textContent)).toEqual(['child one', 'child two'])
    })
  })

  describe('across page changes', () => {
    it('reuses the prerendered rows when the subscribe render arrives', () => {
      const id = `page-${++sequence}`
      document.body.innerHTML = `<div data-live-id-value="${id}" data-live-component-value="chat" class="chat">\n  <h2>Lobby</h2>\n  \n    <ul class="messages cozy" live-stream="messages">\n      <li id="${key(1)}" class="message"><b>Message 1</b> <button>Like 0</button> <input name="note"></li>\n    </ul>\n  \n</div>`
      const element = document.body.firstElementChild
      const prerendered = element.querySelector('li')
      subscriptionManager.subscribe(id, 'chat', '', controllerFor(element))

      createdSubscriptions.at(-1).handlers.received({ _refresh: { h: 'chat', p: chatParts(id, stream([row(1), row(2)])), s: statics }, _subscribed: true })

      expect(element.querySelector('li')).toBe(prerendered)
      expect(Array.from(element.querySelectorAll('li'), li => li.id)).toEqual([key(1), key(2)])
    })

    it('replays every row it holds, including ops that arrived during a Turbo visit, into the new element', () => {
      const chat = mountChat(stream([row(1)]))
      const next = document.createElement('div')
      next.setAttribute('data-live-id-value', chat.id)
      next.setAttribute('data-live-component-value', 'chat')

      chat.element.remove()
      chat.sendOps(['a', key(2), row(2)])
      document.body.appendChild(next)
      subscriptionManager.subscribe(chat.id, 'chat', '', controllerFor(next))

      expect(Array.from(next.querySelectorAll('li'), li => li.id)).toEqual([key(1), key(2)])
    })

    it('takes a whole stream node after a reconnect and keeps the rows that survived', () => {
      const chat = mountChat(stream([row(1), row(2)]))
      const survivor = chat.list().lastElementChild

      chat.handlers.received({ _refresh: { h: 'chat', p: chatParts(chat.id, stream([row(2), row(3)])), s: statics }, _subscribed: true, _reply: false })

      expect(chat.keys()).toEqual([key(2), key(3)])
      expect(chat.list().firstElementChild).toBe(survivor)
    })
  })
})
