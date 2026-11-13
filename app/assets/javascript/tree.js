/**
 * Structured parts: how a control block in a .live.erb template arrives.
 *
 * Mirrors LiveCable::Rendering::Tree on the server. A control block (an if,
 * unless, case or loop) is sent as a node instead of an HTML string: the
 * markup it writes is split into statics, sent once per template under the
 * `s` key of a render, and the node carries only the values between them.
 *
 *   branch:  { t: 0, d: ["Hello"] }    statics[0] = ["<p>", "</p>"]
 *   none:    { t: null }               an if with no branch taken
 *   loop:    { t: 2, r: [["1", "Milk"], ["2", "Eggs"]], k: ["todo-1", "todo-2"] }
 *
 * A value is an HTML string or a nested node. After the first render a part
 * carries a diff against the node already held: a node always has a `t` key
 * and a diff never does.
 *
 *   branch diff:  { d: { "0": "Bye" } }                   changed values by index
 *   keyed loop:   { o: [op, ...] }                        row ops, applied in order
 *   unkeyed loop: { n: rowCount, r: { index: rowDiff | fullRow } }
 *
 * Row ops name the row they are about second:
 *
 *   ["d", key, ...]          delete (a key not held is ignored)
 *   ["a", key, row]          append
 *   ["p", key, row]          prepend
 *   ["i", key, row, after]   insert after the row keyed `after`
 *   ["m", key, after]        move after `after`, or to the front when null
 *   ["s", key, ...]          sort: these rows first, in this order
 *   ["u", key, change]       update: changed values by index, or a whole row
 *   ["r"]                    reset: drop every row
 *
 * An insert of a key already held replaces that row where it is, and one
 * after a key not held appends. An update, delete or sort skips a key not
 * held; rows a sort doesn't name follow, in their order.
 *
 * A collection stream's node is a keyed loop with its name in `st` and,
 * when it has one, its limit in `l`: an insert that adds a row past the
 * limit drops one from the other end, the last after a prepend and the
 * first otherwise. With `ik`, each row's id is its key, which its values
 * leave out and the key fills in.
 */

/**
 * Render a part - an HTML string or a node - to HTML.
 *
 * @param {string|Object|null} node
 * @param {Object.<string, string[]>} statics - Statics by scope id
 * @param {Set<string>} [skip] - Streams whose rows to leave out
 * @returns {string}
 */
export function renderNode(node, statics, skip) {
  if (node === null || node === undefined) {
    return ''
  }

  if (typeof node !== 'object') {
    return String(node)
  }

  if (node.t === null || node.t === undefined) {
    return ''
  }

  const template = statics[node.t]

  if (!template) {
    throw new Error(`LiveCable: no statics for scope ${node.t}`)
  }

  if (Array.isArray(node.r)) {
    if (skip?.has(node.st)) {
      return ''
    }

    if (node.ik) {
      let html = ''

      for (let index = 0; index < node.r.length; index++) {
        html += interleave(template, node.r[index], statics, skip, escapeKey(node.k[index]))
      }

      return html
    }

    return node.r.map(row => interleave(template, row, statics, skip)).join('')
  }

  return interleave(template, node.d, statics, skip)
}

/**
 * Render a list of parts to one HTML string.
 *
 * @param {Array<string|Object|null>} parts
 * @param {Object.<string, string[]>} statics
 * @param {Set<string>} [skip] - Streams whose rows to leave out
 * @returns {string}
 */
export function renderParts(parts, statics, skip) {
  return parts.map(part => renderNode(part, statics, skip)).join('')
}

/**
 * Apply an update to what is held for a part.
 *
 * @param {string|Object|undefined} stored - The part held so far
 * @param {string|Object} update - An HTML string, a node or a diff
 * @returns {string|Object} The part to hold from now on
 */
export function applyPart(stored, update) {
  if (!isDiff(update) || !stored || typeof stored !== 'object') {
    return update
  }

  if (Array.isArray(stored.r)) {
    return applyLoop(stored, update)
  }

  return { ...stored, d: applyValues(stored.d, update.d) }
}

function isDiff(update) {
  return update !== null && typeof update === 'object' && !('t' in update)
}

// A key fills the first gap, ahead of the values
function interleave(template, values, statics, skip, key) {
  let html = template[0] ?? ''
  let offset = 1

  if (key !== undefined) {
    html += key + (template[1] ?? '')
    offset = 2
  }

  for (let index = 0; index < values.length; index++) {
    html += renderNode(values[index], statics, skip) + (template[index + offset] ?? '')
  }

  return html
}

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }
const UNSAFE = /[&<>"']/

function escapeKey(key) {
  return UNSAFE.test(key) ? key.replace(/[&<>"']/g, char => ESCAPES[char]) : key
}

function applyValues(values, changes) {
  if (!changes) {
    return values
  }

  const result = values.slice()

  for (const [index, change] of Object.entries(changes)) {
    result[Number(index)] = applyPart(result[Number(index)], change)
  }

  return result
}

function applyLoop(stored, update) {
  if (stored.k) {
    return applyOps(stored, update.o ?? [])
  }

  const changes = update.r ?? {}
  const count = update.n ?? stored.r.length

  const rows = Array.from({ length: count }, (_value, index) => {
    const change = changes[index]

    if (Array.isArray(change)) {
      return change
    }

    if (index >= stored.r.length) {
      throw new Error(`LiveCable: no row ${index} to update`)
    }

    return change ? applyValues(stored.r[index], change) : stored.r[index]
  })

  return { ...stored, r: rows }
}

// The keys of a keyed loop node, handed on to the node its ops make, and
// what those ops added and removed relative to the node they were applied to
const heldKeys = new WeakMap()
const changesByNode = new WeakMap()

/**
 * The keys ops added to and removed from a keyed loop, and the keys it then
 * held, when `after` is what applying them to `before` made. Good until ops
 * are applied to `after`.
 *
 * @param {Object} before
 * @param {Object} after
 * @returns {{added: Set<string>, removed: Set<string>, keys: Set<string>}|null}
 */
export function keyChanges(before, after) {
  const changes = changesByNode.get(after)

  return changes?.from === before ? changes : null
}

/**
 * Apply row ops to a keyed loop, copying its keys and rows once.
 *
 * @param {{k: string[], r: Array, l?: number}} stored
 * @param {Array} ops
 * @returns {Object} The loop the ops make
 */
function applyOps(stored, ops) {
  let keys = stored.k.slice()
  let rows = stored.r.slice()
  const held = heldKeys.get(stored) ?? new Set(keys)
  const limit = stored.l
  const added = new Set()
  const removed = new Set()

  if (held.size !== keys.length) {
    return { ...stored, ...applyOpsByMap(stored, ops) }
  }

  heldKeys.delete(stored)

  const remove = (gone, index) => {
    keys.splice(index, 1)
    rows.splice(index, 1)
    held.delete(gone)

    if (!added.delete(gone)) {
      removed.add(gone)
    }
  }

  for (const [code, key, ...args] of ops) {
    switch (code) {
      case 'd':
        for (const gone of [key, ...args]) {
          if (held.has(gone)) {
            remove(gone, keys.indexOf(gone))
          }
        }
        break
      case 'a':
      case 'p':
      case 'i': {
        if (held.has(key)) {
          rows[keys.indexOf(key)] = args[0]
          break
        }

        const position = insertPosition(code, keys, args[1])
        keys.splice(position, 0, key)
        rows.splice(position, 0, args[0])
        held.add(key)

        if (!removed.delete(key)) {
          added.add(key)
        }

        if (limit && keys.length > limit) {
          const index = code === 'p' ? keys.length - 1 : 0
          remove(keys[index], index)
        }
        break
      }
      case 'm': {
        if (!held.has(key)) {
          throw new Error(`LiveCable: no row ${key} to update`)
        }

        const index = keys.indexOf(key)
        const [row] = rows.splice(index, 1)
        keys.splice(index, 1)
        const position = args[0] === null || args[0] === undefined ? 0 : keyIndex(keys, args[0]) + 1
        keys.splice(position, 0, key)
        rows.splice(position, 0, row)
        break
      }
      case 'u':
        if (held.has(key)) {
          const index = keys.indexOf(key)
          rows[index] = Array.isArray(args[0]) ? args[0] : applyValues(rows[index], args[0])
        }
        break
      case 's': {
        const byKey = new Map(keys.map((rowKey, index) => [rowKey, rows[index]]))
        const named = new Set([key, ...args].filter(sorted => held.has(sorted)))
        keys = [...named, ...keys.filter(other => !named.has(other))]
        rows = keys.map(sorted => byKey.get(sorted))
        break
      }
      case 'r':
        keys.slice().forEach(gone => {
          if (!added.delete(gone)) {
            removed.add(gone)
          }
        })
        keys.length = 0
        rows.length = 0
        held.clear()
        break
      default:
        throw new Error(`LiveCable: unknown row op ${code}`)
    }
  }

  const result = { ...stored, k: keys, r: rows }
  heldKeys.set(result, held)
  changesByNode.set(result, { from: stored, added, removed, keys: held })

  return result
}

/**
 * Apply row ops to a keyed loop whose keys repeat, as a Map of them does.
 */
function applyOpsByMap(stored, ops) {
  let keys = stored.k.slice()
  const rows = new Map(keys.map((key, index) => [key, stored.r[index]]))
  const limit = stored.l

  for (const [code, key, ...args] of ops) {
    switch (code) {
      case 'd':
        for (const gone of [key, ...args]) {
          if (rows.delete(gone)) {
            keys.splice(keys.indexOf(gone), 1)
          }
        }
        break
      case 'a':
      case 'p':
      case 'i': {
        const added = !rows.has(key)
        rows.set(key, args[0])

        if (added) {
          keys.splice(insertPosition(code, keys, args[1]), 0, key)

          if (limit && keys.length > limit) {
            rows.delete(code === 'p' ? keys.pop() : keys.shift())
          }
        }
        break
      }
      case 'm':
        heldRow(rows, key)
        keys.splice(keys.indexOf(key), 1)
        keys.splice(args[0] === null || args[0] === undefined ? 0 : keyIndex(keys, args[0]) + 1, 0, key)
        break
      case 'u':
        if (rows.has(key)) {
          rows.set(key, Array.isArray(args[0]) ? args[0] : applyValues(rows.get(key), args[0]))
        }
        break
      case 's': {
        const named = new Set([key, ...args].filter(held => rows.has(held)))
        keys = [...named, ...keys.filter(held => !named.has(held))]
        break
      }
      case 'r':
        keys.length = 0
        rows.clear()
        break
      default:
        throw new Error(`LiveCable: unknown row op ${code}`)
    }
  }

  return { k: keys, r: keys.map(key => rows.get(key)) }
}

function insertPosition(code, keys, after) {
  if (code === 'a') {
    return keys.length
  }

  if (code === 'p') {
    return 0
  }

  const index = keys.indexOf(after)

  return index === -1 ? keys.length : index + 1
}

function keyIndex(keys, key) {
  const index = keys.indexOf(key)

  if (index === -1) {
    throw new Error(`LiveCable: no row ${key} to update`)
  }

  return index
}

function heldRow(rows, key) {
  if (!rows.has(key)) {
    throw new Error(`LiveCable: no row ${key} to update`)
  }

  return rows.get(key)
}
