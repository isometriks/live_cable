import { it, expect, vi } from 'vitest'

const created = []

vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    connection: { events: { open() {}, message() {} }, isActive: () => true },
    subscriptions: {
      create(params, handlers) {
        created.push(handlers)
        return { send: () => true, unsubscribe() {} }
      },
    },
  }),
}))

const subscriptionManager = (await import('../app/assets/javascript/subscriptions.js')).default

const statics = { 0: ['<li id="', '">', '</li>'] }
const row = (id) => [`message-${id}`, `Message ${id}`]

// The median time of an insert into a stream holding size rows
function insertTime(size) {
  const id = `feed-${size}`
  const element = document.createElement('div')
  element.setAttribute('data-live-id-value', id)
  element.setAttribute('data-live-component-value', 'feed')
  document.body.appendChild(element)
  subscriptionManager.subscribe(id, 'feed', '', {
    element, statusValue: 'disconnected', isLoading: false, inFlight: 0, finishLoading: () => false, resetLoading() {},
  })
  const handlers = created.at(-1)
  const rows = Array.from({ length: size }, (_, index) => row(index))
  const node = { t: 0, st: 'messages', r: rows, k: rows.map(([key]) => key) }

  handlers.received({ _refresh: { h: 'feed', p: [`<div live-id="${id}" live-component="feed"><ul live-stream="messages">`, node, '</ul></div>'], s: statics } })

  const times = []

  for (let next = size; next < size + 200; next++) {
    const start = performance.now()
    handlers.received({ _refresh: { h: 'feed', p: [null, { o: [['a', `message-${next}`, row(next)]] }, null] }, _reply: false })
    times.push(performance.now() - start)
  }

  expect(element.querySelectorAll('li')).toHaveLength(size + 200)
  element.remove()

  return times.sort((a, b) => a - b)[times.length / 2]
}

it('applies an insert to a 5,000-row stream in about the time of a 50-row one', () => {
  insertTime(50)

  expect(insertTime(5000) / insertTime(50)).toBeLessThan(4)
}, 60000)
