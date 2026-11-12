/**
 * Row ops applied straight to the page.
 *
 * A refresh whose only changes are row ops on keyed loops (see tree.js) can
 * be applied to the elements those rows rendered instead of rebuilding the
 * component's HTML and morphing all of it. Each row of a keyed loop renders
 * one element, keyed by its live-key or id, so the loop's rows are a run of
 * sibling elements: new rows are inserted into it, gone rows removed, moved
 * rows moved, and changed rows morphed one by one.
 *
 * A collection stream's rows are the element children of its live-stream
 * container, so a stream is found by its container and can take rows while
 * it is empty.
 *
 * Anything this can't place exactly - an empty loop with nothing to insert
 * next to, rows the page no longer shows as the client holds them, a loop
 * inside a live-ignore or live-loading element, a row that doesn't render
 * one element keyed as the client holds it - makes patchRows return false
 * before it changes anything, and the caller morphs as usual.
 */

import { keyChanges, renderNode } from "@isometriks/live_cable/tree"

const INSERTS = new Set(['a', 'p', 'i'])

/**
 * The keyed loops a refresh changes, when row ops are all it carries. A part
 * that re-ran to the HTML already held changes nothing.
 *
 * @param {Array} stored - The parts held for the template
 * @param {Array} parts - The refresh's parts
 * @param {Object.<string, string[]>} statics - The statics held for the template
 * @returns {Array<{path: number[], before: Object, ops: Array, around: string[]}>|null}
 */
export function rowOpLoops(stored, parts, statics) {
  const loops = []

  for (let index = 0; index < parts.length; index++) {
    const part = parts[index]
    const around = [stored[index - 1], stored[index + 1]].map(text => typeof text === 'string' ? text : '')

    if (part !== null && part !== stored[index] && !collect(stored[index], part, [index], loops, statics, around)) {
      return null
    }
  }

  return loops.length > 0 ? loops : null
}

/**
 * The collection streams a refresh leaves in place: those whose node it
 * neither replaces nor sits inside a part or branch it replaces, with the
 * row ops it carries for each, if any. With no parts, every stream held.
 *
 * @param {Array} stored - The parts held for the template
 * @param {Array|null} parts - The refresh's parts
 * @param {Object.<string, string[]>} statics - The statics held for the template
 * @returns {Array<{path: number[], before: Object, ops: Array|null, around: string[]}>}
 */
export function heldStreams(stored, parts, statics) {
  const streams = []

  const walk = (node, update, path, around) => {
    if (!isNode(node) || node.t === null || node.t === undefined || (update != null && (!isNode(update) || 't' in update))) {
      return
    }

    if (Array.isArray(node.r)) {
      const opsOnly = update == null || (Array.isArray(update.o) && Object.keys(update).length === 1)

      if (node.st !== undefined && node.k && opsOnly) {
        streams.push({ path, before: node, ops: update?.o ?? null, around })
      }

      return
    }

    const template = statics[node.t] ?? []

    node.d.forEach((value, index) =>
      walk(value, update?.d?.[index], [...path, index], [template[index] ?? '', template[index + 1] ?? '']))
  }

  stored.forEach((part, index) => {
    const around = [stored[index - 1], stored[index + 1]].map(text => typeof text === 'string' ? text : '')
    walk(part, parts?.[index], [index], around)
  })

  return streams
}

/**
 * A stream's container when it shows exactly the rows held for it and
 * nothing keeps a morph out of it.
 *
 * @param {Element} root - The component's element
 * @param {Object} node - The stream's node
 * @returns {Element|null}
 */
export function heldContainer(root, node) {
  const container = streamContainer(root, node.st)

  return container && !blocked(root, container) && container.childElementCount === node.k.length ? container : null
}

/**
 * @param {Array} parts
 * @param {number[]} path - A part index, then value indices
 * @returns {Object} The node at the path
 */
export function nodeAt(parts, [index, ...rest]) {
  return rest.reduce((node, value) => node.d[value], parts[index])
}

/**
 * `around` is the markup either side of the node, which for a stream ends
 * and starts with the whitespace its container holds around the rows.
 */
function collect(node, update, path, loops, statics, around) {
  if (!isNode(node) || !isNode(update) || 't' in update) {
    return false
  }

  if (Array.isArray(node.r)) {
    if (!node.k || !Array.isArray(update.o) || Object.keys(update).length !== 1) {
      return false
    }

    loops.push({ path, before: node, ops: update.o, around })
    return true
  }

  const template = statics[node.t] ?? []

  return Object.entries(update.d ?? {}).every(([index, change]) =>
    collect(node.d[Number(index)], change, [...path, Number(index)], loops, statics,
      [template[Number(index)] ?? '', template[Number(index) + 1] ?? '']))
}

function isNode(value) {
  return value !== null && typeof value === 'object'
}

/**
 * Apply each loop's row ops to the page.
 *
 * @param {Element} root - The component's element
 * @param {Array<{before: Object, after: Object, ops: Array, around: string[]}>} loops
 * @param {Object.<string, string[]>} statics
 * @param {Object} hooks
 * @param {function(string, string): Node} hooks.buildRow - Builds a row's element from its HTML, in the namespace of the rows it joins
 * @param {function(Element, Element): Element} hooks.morphRow - Morphs a row into a built one
 * @returns {boolean} Whether the rows were patched; false means nothing changed
 */
export function patchRows(root, loops, statics, { buildRow, morphRow }) {
  const plans = []

  for (const loop of loops) {
    const plan = planLoop(root, loop, statics, buildRow)

    if (!plan) {
      return false
    }

    plans.push(plan)
  }

  plans.forEach(plan => plan.stream ? applyStreamPlan(plan, morphRow) : applyPlan(plan, morphRow))

  return true
}

function planLoop(root, loop, statics, buildRow) {
  if (loop.before.st !== undefined) {
    return planStream(root, loop, statics, buildRow)
  }

  const { before, after, ops } = loop
  const elements = locateRun(root, before.k)
  const template = statics[before.t]

  if (!elements || !template) {
    return null
  }

  const rows = new Map(after.k.map((key, index) => [key, after.r[index]]))
  const changed = new Set()
  const placed = new Set()

  for (const [code, key, ...args] of ops) {
    if (INSERTS.has(code) || code === 'u') {
      changed.add(key)
    }

    if (INSERTS.has(code) || code === 'm') {
      placed.add(key)
    } else if (code === 's') {
      [key, ...args].forEach(sorted => placed.add(sorted))
    }
  }

  const namespace = elements.values().next().value.namespaceURI

  const built = new Map()

  for (const key of changed) {
    if (!rows.has(key)) {
      continue
    }

    const element = buildRow(renderNode({ t: before.t, r: [rows.get(key)] }, statics).trim(), namespace)

    if (!(element instanceof Element) || element.namespaceURI !== namespace || rowKey(element) !== key) {
      return null
    }

    built.set(key, element)
  }

  return {
    elements,
    built,
    placed,
    keys: after.k,
    lead: template[0].match(/^\s*/)[0],
    trail: template[template.length - 1].match(/\s*$/)[0],
  }
}

/**
 * The elements of a loop's rows, by key, when the page shows exactly those
 * rows in that order as one run of siblings inside the component.
 */
function locateRun(root, keys) {
  if (keys.length === 0) {
    return null
  }

  let element = findRow(root, keys[0])

  if (!element || blocked(root, element.parentElement)) {
    return null
  }

  const elements = new Map()

  for (const key of keys) {
    if (!element || rowKey(element) !== key) {
      return null
    }

    elements.set(key, element)
    element = element.nextElementSibling
  }

  return elements
}

/**
 * Only a row that is inserted again can move in a stream, so only the rows
 * the ops touch are looked up, and each new or inserted row goes in after
 * the one before it, which puts every row in place. Row markup has no
 * whitespace around its element; while the container is empty it holds
 * only the whitespace the template puts around the rows.
 */
function planStream(root, { before, after, ops, around: [opening, closing] }, statics, buildRow) {
  const container = streamContainer(root, before.st)
  const template = statics[before.t]
  const lead = opening.match(/\s*$/)[0]

  if (!container || !template || blocked(root, container) || container.childElementCount !== before.k.length ||
      /^\s/.test(template[0]) || /\s$/.test(template[template.length - 1]) ||
      (before.k.length === 0 && container.textContent !== lead + closing.match(/^\s*/)[0])) {
    return null
  }

  const find = rowFinder(container)
  const inserted = new Set(ops.filter(([code]) => INSERTS.has(code)).map(([, key]) => key))
  const changed = new Set([...inserted, ...ops.filter(([code]) => code === 'u').map(([, key]) => key)])
  const { gone, held, touched } = streamChanges(before, after, changed)
  const removed = gone.map(find)
  const morphs = []
  const placements = []
  const anchors = new Map()

  for (const index of touched) {
    const key = after.k[index]
    const element = buildRow(renderNode({ t: before.t, ik: before.ik, k: [key], r: [after.r[index]] }, statics), container.namespaceURI)

    if (!(element instanceof Element) || rowKey(element) !== key) {
      return null
    }

    if (held(key)) {
      morphs.push({ key, existing: find(key), element })
    }

    if (!held(key) || inserted.has(key)) {
      const previous = index > 0 ? after.k[index - 1] : null

      if (previous !== null && held(previous)) {
        anchors.set(previous, find(previous))
      }

      placements.push({ key, element: held(key) ? null : element, previous })
    }
  }

  if (removed.includes(null) || morphs.some(({ existing }) => !existing) || [...anchors.values()].includes(null)) {
    return null
  }

  return { stream: true, start: { container, offset: lead.length }, removed, morphs, placements, anchors }
}

/**
 * The keys held before that the ops removed, whether a key was held before,
 * and in order the indices in `after` of the rows to build: those new or
 * changed. From what applying the ops recorded when there is a record,
 * without going through every row.
 */
function streamChanges(before, after, changed) {
  const record = keyChanges(before, after)

  if (!record) {
    const held = new Set(before.k)
    const kept = new Set(after.k)
    const touched = []

    after.k.forEach((key, index) => {
      if (!held.has(key) || changed.has(key)) {
        touched.push(index)
      }
    })

    return { gone: before.k.filter(key => !kept.has(key)), held: key => held.has(key), touched }
  }

  const { added, removed, keys } = record
  const named = [...new Set([...added, ...changed])].filter(key => keys.has(key))
  const positions = named.length > 32 ? new Map(after.k.map((key, index) => [key, index])) : null
  const touched = named.map(key => positions ? positions.get(key) : after.k.indexOf(key)).sort((a, b) => a - b)

  return { gone: [...removed], held: key => !added.has(key), touched }
}

/**
 * Finds a row of the container by its key without a selector, so any id
 * works, and ignores an element elsewhere with the same id.
 */
function rowFinder(container) {
  let byKey = null

  return (key) => {
    const element = container.ownerDocument.getElementById(key)

    if (element?.parentElement === container && rowKey(element) === key) {
      return element
    }

    byKey ??= new Map(Array.from(container.children, child => [rowKey(child), child]))

    return byKey.get(key) ?? null
  }
}

function applyStreamPlan({ start, removed, morphs, placements, anchors }, morphRow) {
  const placed = new Map(anchors)

  for (const { key, existing, element } of morphs) {
    placed.set(key, morphRow(existing, element))
  }

  removed.forEach(element => element.remove())

  for (const { key, element: built, previous } of placements) {
    const element = built ?? placed.get(key)
    const anchor = previous === null ? null : placed.get(previous)
    const first = start.container.firstElementChild

    if (anchor ? anchor.nextElementSibling !== element : first !== element) {
      if (anchor) {
        anchor.after(element)
      } else if (first) {
        first.before(element)
      } else {
        insertAt(start, element)
      }
    }

    placed.set(key, element)
  }
}

const containers = new WeakMap()

/**
 * The component's own live-stream element for a stream: a nested
 * component's stream of the same name is never it.
 */
function streamContainer(root, name) {
  const cached = containers.get(root)?.get(name)

  if (cached && ownsStream(root, cached, name)) {
    return cached
  }

  const candidates = [root, ...root.querySelectorAll('[live-stream]')].filter(element => ownsStream(root, element, name))

  if (candidates.length !== 1) {
    return null
  }

  if (!containers.has(root)) {
    containers.set(root, new Map())
  }

  containers.get(root).set(name, candidates[0])

  return candidates[0]
}

function ownsStream(root, element, name) {
  return element.getAttribute('live-stream') === name && root.contains(element) &&
    element.closest('[data-live-id-value]') === root
}

/**
 * The one element of the component keyed `key`. When another element, such
 * as a second loop's row or a field inside a row, has the key too, the run
 * can't be told apart, so there is none.
 */
function findRow(root, key) {
  const found = Array.from(root.querySelectorAll('[live-key], [id]')).filter(element =>
    rowKey(element) === key && element.parentElement.closest('[data-live-id-value]') === root)

  return found.length === 1 ? found[0] : null
}

function blocked(root, element) {
  for (let node = element; node && node !== root; node = node.parentElement) {
    if (node.hasAttribute('live-ignore') || node.hasAttribute('live-loading')) {
      return true
    }
  }

  return root.hasAttribute('live-ignore')
}

/**
 * The key a row element was rendered with: its first live-key or id
 * attribute, as the server reads it.
 */
function rowKey(element) {
  const liveKey = element.getAttribute('live-key')
  const id = element.getAttribute('id')

  if (liveKey === null || id === null) {
    return liveKey ?? id
  }

  return Array.from(element.attributes).find(({ name }) => name === 'live-key' || name === 'id').value
}

function applyPlan({ elements, built, placed, keys, lead, trail }, morphRow) {
  const run = new Run(elements.values(), lead, trail)
  const current = new Map(elements)

  for (const [key, element] of built) {
    const existing = current.get(key)

    if (existing) {
      const morphed = morphRow(existing, element)

      if (morphed !== existing) {
        run.replace(existing, morphed)
        current.set(key, morphed)
      }
    } else {
      current.set(key, element)
    }
  }

  // Rows no op placed keep their order, so placing the others after the row
  // before them in the new order puts every row in place
  let previous = null

  for (const key of keys) {
    const element = current.get(key)

    if (placed.has(key) || !run.has(element)) {
      run.place(element, previous)
    }

    previous = element
  }

  const kept = new Set(keys)

  for (const key of elements.keys()) {
    if (!kept.has(key)) {
      run.remove(current.get(key))
    }
  }
}

/**
 * The sibling elements of one loop's rows, and the whitespace the row
 * markup puts around each: `lead` before a row's element and `trail` after
 * it, so two rows are separated by trail + lead.
 */
class Run {
  #members
  #head
  #lead
  #trail

  constructor(elements, lead, trail) {
    this.#members = new Set(elements)
    this.#head = this.#members.values().next().value
    this.#lead = lead
    this.#trail = trail
  }

  has(element) {
    return this.#members.has(element)
  }

  replace(existing, element) {
    this.#members.delete(existing)
    this.#members.add(element)

    if (this.#head === existing) {
      this.#head = element
    }
  }

  /**
   * Put a row right after `previous`, or first when it is null.
   */
  place(element, previous) {
    if (this.#members.has(element)) {
      if (previous ? this.#nextMember(previous) === element : this.#head === element) {
        return
      }

      this.remove(element)
    }

    const separator = this.#trail + this.#lead

    if (previous) {
      previous.after(...this.#withText(separator, element))
    } else {
      this.#head.before(...this.#withText(element, separator))
      this.#head = element
    }

    this.#members.add(element)
  }

  remove(element) {
    const separator = this.#trail + this.#lead
    const next = this.#nextMember(element)

    if (this.#head !== element) {
      trimEnd(element.previousSibling, separator)
    } else if (next) {
      trimStart(element.nextSibling, separator)
    } else {
      trimEnd(element.previousSibling, this.#lead)
      trimStart(element.nextSibling, this.#trail)
    }

    if (this.#head === element) {
      this.#head = next
    }

    this.#members.delete(element)
    element.remove()
  }

  #nextMember(element) {
    const next = element.nextElementSibling

    return next && this.#members.has(next) ? next : null
  }

  #withText(...nodes) {
    return nodes.filter(node => node !== '').map(node => typeof node === 'string' ? document.createTextNode(node) : node)
  }
}

/**
 * Insert nodes at an offset into the text of a container that holds no
 * elements.
 */
function insertAt({ container, offset }, ...nodes) {
  let rest = offset

  for (const text of Array.from(container.childNodes).filter(node => node.nodeType === Node.TEXT_NODE)) {
    if (rest < text.data.length) {
      (rest === 0 ? text : text.splitText(rest)).before(...nodes)
      return
    }

    rest -= text.data.length

    if (rest === 0) {
      text.after(...nodes)
      return
    }
  }

  container.append(...nodes)
}

function trimEnd(node, text) {
  trim(node, text, 'previousSibling')
}

function trimStart(node, text) {
  trim(node, text, 'nextSibling')
}

/**
 * Take `text` off the text that runs from `node` in a direction, which
 * earlier patches may have left in more than one text node.
 */
function trim(node, text, direction) {
  const backwards = direction === 'previousSibling'
  const nodes = []

  for (let current = node; current?.nodeType === Node.TEXT_NODE; current = current[direction]) {
    nodes.push(current)
  }

  const joined = (backwards ? nodes.slice().reverse() : nodes).map(textNode => textNode.data).join('')

  if (!text || !(backwards ? joined.endsWith(text) : joined.startsWith(text))) {
    return
  }

  let rest = text.length

  for (const textNode of nodes) {
    const taken = Math.min(rest, textNode.data.length)
    textNode.data = backwards ? textNode.data.slice(0, textNode.data.length - taken) : textNode.data.slice(taken)
    rest -= taken
  }
}
