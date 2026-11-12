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
 * An insert of a key already held replaces that row and moves it. A delete or
 * sort skips a key not held; rows a sort doesn't name follow, in their order.
 */

/**
 * Render a part - an HTML string or a node - to HTML.
 *
 * @param {string|Object|null} node
 * @param {Object.<string, string[]>} statics - Statics by scope id
 * @returns {string}
 */
export function renderNode(node, statics) {
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
    return node.r.map(row => interleave(template, row, statics)).join('')
  }

  return interleave(template, node.d, statics)
}

/**
 * Render a list of parts to one HTML string.
 *
 * @param {Array<string|Object|null>} parts
 * @param {Object.<string, string[]>} statics
 * @returns {string}
 */
export function renderParts(parts, statics) {
  return parts.map(part => renderNode(part, statics)).join('')
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

function interleave(template, values, statics) {
  let html = template[0] ?? ''

  values.forEach((value, index) => {
    html += renderNode(value, statics) + (template[index + 1] ?? '')
  })

  return html
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
    return { ...stored, ...applyOps(stored, update.o ?? []) }
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

/**
 * Apply row ops to a keyed loop's keys and rows.
 *
 * @param {{k: string[], r: Array}} stored
 * @param {Array} ops
 * @returns {{k: string[], r: Array}}
 */
function applyOps(stored, ops) {
  let keys = stored.k.slice()
  const rows = new Map(keys.map((key, index) => [key, stored.r[index]]))

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
      case 'i':
        if (rows.has(key)) {
          keys.splice(keys.indexOf(key), 1)
        }
        rows.set(key, args[0])
        keys.splice(insertPosition(code, keys, args[1]), 0, key)
        break
      case 'm':
        heldRow(rows, key)
        keys.splice(keys.indexOf(key), 1)
        keys.splice(args[0] === null || args[0] === undefined ? 0 : keyIndex(keys, args[0]) + 1, 0, key)
        break
      case 'u':
        rows.set(key, Array.isArray(args[0]) ? args[0] : applyValues(heldRow(rows, key), args[0]))
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

  return code === 'p' ? 0 : keyIndex(keys, after) + 1
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
