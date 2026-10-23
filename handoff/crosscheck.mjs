// Run from the repo root: bundle exec ruby handoff/crosscheck.rb | node handoff/crosscheck.mjs
import { applyPart, renderParts } from '../app/assets/javascript/tree.js'
import fs from 'fs'
const { statics, cases } = JSON.parse(fs.readFileSync(0, 'utf8'))
let failed = 0, bytesFull = 0, bytesDiff = 0
for (const c of cases) {
  const held = c.held.map((p, i) => c.update[i] === null ? p : applyPart(p, c.update[i]))
  const html = renderParts(held, statics)
  if (html !== c.html) { failed++; console.log('MISMATCH', c.from, '->', c.to) }
}
console.log(`${cases.length} transitions, ${failed} mismatches`)
