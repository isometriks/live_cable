import { describe, it, expect } from 'vitest'
import { applyPart, renderNode, renderParts } from '../app/assets/javascript/tree.js'

// Statics as the server sends them for
//
//   <% if todos.any? %>
//     <h2><%= count %> todos</h2>
//     <% todos.each do |todo| %><li id="todo-<%= todo.id %>"><%= todo.title %></li><% end %>
//   <% else %>
//     <p>Nothing to do</p>
//   <% end %>
const statics = {
  0: ['<h2>', ' todos</h2>', ''],
  1: ['<li id="todo-', '">', '</li>'],
  2: ['<p>Nothing to do</p>'],
}

const list = (...todos) => ({
  t: 0,
  d: [
    String(todos.length),
    { t: 1, r: todos.map(([id, title]) => [String(id), title]), k: todos.map(([id]) => `todo-${id}`) },
  ],
})

describe('renderNode', () => {
  it('renders a branch with a nested loop', () => {
    const html = renderNode(list([1, 'Milk'], [2, 'Eggs']), statics)

    expect(html).toBe('<h2>2 todos</h2><li id="todo-1">Milk</li><li id="todo-2">Eggs</li>')
  })

  it('renders the other branch', () => {
    expect(renderNode({ t: 2, d: [] }, statics)).toBe('<p>Nothing to do</p>')
  })

  it('renders nothing for a conditional with no branch taken', () => {
    expect(renderNode({ t: null }, statics)).toBe('')
  })

  it('passes HTML strings through', () => {
    expect(renderParts(['<ul>', list([1, 'Milk']), '</ul>'], statics))
      .toBe('<ul><h2>1 todos</h2><li id="todo-1">Milk</li></ul>')
  })

  it('throws when the statics for a scope never arrived', () => {
    expect(() => renderNode({ t: 9, d: [] }, statics)).toThrow(/no statics for scope 9/)
  })
})

describe('applyPart', () => {
  it('replaces what is held with a whole node', () => {
    expect(applyPart(list([1, 'Milk']), { t: 2, d: [] })).toEqual({ t: 2, d: [] })
  })

  it('replaces what is held with an HTML string', () => {
    expect(applyPart(list([1, 'Milk']), '<p>plain</p>')).toBe('<p>plain</p>')
  })

  it('updates the changed values of a branch', () => {
    const updated = applyPart(list([1, 'Milk']), { d: { 0: '7' } })

    expect(updated.d[0]).toBe('7')
    expect(updated.d[1]).toEqual(list([1, 'Milk']).d[1])
  })

  it('updates one row of a keyed loop', () => {
    const updated = applyPart(list([1, 'Milk'], [2, 'Eggs']), { d: { 1: { o: [['u', 'todo-2', { 1: 'Free-range eggs' }]] } } })

    expect(renderNode(updated, statics)).toContain('<li id="todo-2">Free-range eggs</li>')
    expect(renderNode(updated, statics)).toContain('<li id="todo-1">Milk</li>')
  })

  it('prepends, inserts and deletes rows of a keyed loop', () => {
    const updated = applyPart(list([1, 'Milk'], [2, 'Eggs']), {
      d: {
        0: '3',
        1: { o: [['d', 'todo-2'], ['p', 'todo-3', ['3', 'Bread']], ['i', 'todo-4', ['4', 'Jam'], 'todo-3']] },
      },
    })

    expect(updated).toEqual(list([3, 'Bread'], [4, 'Jam'], [1, 'Milk']))
  })

  it('appends and moves rows of a keyed loop', () => {
    const loop = list([1, 'Milk'], [2, 'Eggs'], [3, 'Bread']).d[1]
    const updated = applyPart(loop, { o: [['a', 'todo-4', ['4', 'Jam']], ['m', 'todo-1', 'todo-4'], ['m', 'todo-3', null]] })

    expect(updated.k).toEqual(['todo-3', 'todo-2', 'todo-4', 'todo-1'])
    expect(updated.r.map(row => row[1])).toEqual(['Bread', 'Eggs', 'Jam', 'Milk'])
  })

  it('resets a keyed loop before the ops after the reset', () => {
    const loop = list([1, 'Milk'], [2, 'Eggs']).d[1]

    expect(applyPart(loop, { o: [['r'], ['a', 'todo-3', ['3', 'Bread']]] })).toEqual(list([3, 'Bread']).d[1])
  })

  it('moves a row inserted under a key it already holds, with the new values', () => {
    const loop = list([1, 'Milk'], [2, 'Eggs']).d[1]

    expect(applyPart(loop, { o: [['p', 'todo-2', ['2', 'Free-range eggs']]] }))
      .toEqual(list([2, 'Free-range eggs'], [1, 'Milk']).d[1])
  })

  it('ignores a delete of a row it does not hold, and takes a whole row as an update', () => {
    const loop = list([1, 'Milk'], [2, 'Eggs']).d[1]

    expect(applyPart(loop, { o: [['d', 'todo-9', 'todo-1'], ['u', 'todo-2', ['2', 'Jam']]] })).toEqual(list([2, 'Jam']).d[1])
  })

  it('orders the rows a sort names, skipping keys it does not hold, with the rest after them', () => {
    const loop = list([1, 'Milk'], [2, 'Eggs'], [3, 'Bread'], [4, 'Jam']).d[1]

    expect(applyPart(loop, { o: [['s', 'todo-3', 'todo-9', 'todo-1', 'todo-3']] }))
      .toEqual(list([3, 'Bread'], [1, 'Milk'], [2, 'Eggs'], [4, 'Jam']).d[1])
  })

  it('resizes an unkeyed loop by row count', () => {
    const unkeyed = { t: 1, r: [['1', 'Milk'], ['2', 'Eggs']] }

    expect(applyPart(unkeyed, { n: 1 })).toEqual({ t: 1, r: [['1', 'Milk']] })
    expect(applyPart(unkeyed, { n: 3, r: { 2: ['3', 'Bread'], 0: { 1: 'Oat milk' } } }))
      .toEqual({ t: 1, r: [['1', 'Oat milk'], ['2', 'Eggs'], ['3', 'Bread']] })
  })

  it('does not change the node it was given', () => {
    const held = list([1, 'Milk'])
    const copy = JSON.parse(JSON.stringify(held))

    applyPart(held, { d: { 0: '9', 1: { o: [['u', 'todo-1', { 1: 'Oat milk' }], ['a', 'todo-2', ['2', 'Eggs']]] } } })

    expect(held).toEqual(copy)
  })

  it('throws when a diff names a row that is not held', () => {
    expect(() => applyPart(list([1, 'Milk']), { d: { 1: { o: [['u', 'todo-5', { 1: 'x' }]] } } })).toThrow(/no row todo-5/)
    expect(() => applyPart(list([1, 'Milk']), { d: { 1: { o: [['i', 'todo-6', ['6', 'x'], 'todo-5']] } } })).toThrow(/no row todo-5/)
    expect(() => applyPart(list([1, 'Milk']), { d: { 1: { o: [['m', 'todo-5', null]] } } })).toThrow(/no row todo-5/)
  })
})
