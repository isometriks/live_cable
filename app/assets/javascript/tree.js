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
 *   loop diff:    { k: [...new key order], r: { key: rowDiff | fullRow } }
 *                 { n: rowCount, r: { index: rowDiff | fullRow } }   unkeyed loop
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

function rowKeys(node) {
  return node.k ?? node.r.map((_row, index) => String(index))
}

function applyLoop(stored, update) {
  const storedKeys = rowKeys(stored)
  const storedRows = new Map(storedKeys.map((key, index) => [key, stored.r[index]]))

  let keys = storedKeys

  if (update.k) {
    keys = update.k
  } else if (update.n !== undefined) {
    keys = Array.from({ length: update.n }, (_value, index) => String(index))
  }

  const changes = update.r ?? {}

  const rows = keys.map(key => {
    const change = changes[key]

    if (Array.isArray(change)) {
      return change
    }

    if (!storedRows.has(key)) {
      throw new Error(`LiveCable: no row ${key} to update`)
    }

    return change ? applyValues(storedRows.get(key), change) : storedRows.get(key)
  })

  const node = { ...stored, r: rows }

  if (stored.k) {
    node.k = keys
  }

  return node
}
