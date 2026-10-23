# Handoff: structured control blocks (`slot-tree-parts`)

Notes for whoever picks this branch up next, human or agent. Everything here
was written at the end of the session that built the feature; it is the
context that does not fit in commit messages. **Delete the `handoff/`
directory before merging** — it lives in its own commit for that reason.

## TL;DR

- A top-level `if`/`unless`/`case`/`case…in`/`for`/`while`/`until`, or an
  iterating block (`each`, `times`, `find_each`…), in a `.live.erb` template
  now compiles to **static markup + values** instead of one HTML string.
  Statics go to the client once per component; every later render sends a
  **diff** against the structure the client holds.
- Output HTML is byte-identical to the old path. With
  `config.structured_blocks = false` the compiler emits exactly what `main`
  does (verified for all 26 dummy templates).
- Payloads on a 20-row todo list: ~11 KB → 118–444 bytes per update; first
  full render 12.9 KB → 3.5 KB. Server CPU: about +1.5 ms per render at 200
  rows (before JSON serialization, which shrinks a lot).
- All suites passed locally (see "Status and how it was tested" — the local
  environment was unusual, so **run CI on Ruby 3.4 first**).

## Why this exists

This came out of comparing LiveCable with ReActionView / Herb's "slots"
system (marcoroth/reactionview, marcoroth/herb). Before this change,
LiveCable's compiler folded each top-level control block into one opaque
`:block` part, so any change touching a block re-rendered and resent the
whole block's HTML (every row of a loop, every nested branch) and morphdom
sorted it out. Herb's slots split blocks into per-branch / per-row values
but are stateless (they resend every value, every time). LiveCable is
stateful (a component lives on the ActionCable connection), so it can keep
its dependency-based part skipping **and** diff values server-side. That
combination is what this branch implements.

Relevant Herb code if you want to compare approaches:
`lib/herb/engine/slots/visitor.rb`, `dynamics_compiler.rb`,
`subtree_compiler.rb`, and `javascript/packages/client/src/slots/apply.ts`,
`collections.ts` (keyed row reconciliation, marker-based DOM patching).

## Design

### Pipeline (server)

1. `Rendering::Handler` parses with Herb and runs `Rendering::Compiler`
   (subclass of `Herb::Engine::Compiler`) over the AST.
2. The compiler emits Herb's normal tokens. It **tags** the code tokens that
   open/close structure (`if`, `elsif`, `else`, `when`, `in`, `end`,
   `items.each do |x|`, `for`, `while`, `until`) with a
   `TreeBuilder::Structure` (stored in the token's 3rd slot, which Herb only
   uses for expression context). It does **not** add tokens: the existing
   `block_start`/`block_end` sentinels (value `"\n"`) are kept with exactly
   the same nesting as before, because Herb's whitespace helpers
   (`at_line_start?`, `preceding_token_ends_with_newline?`, trim handling)
   look at neighbouring tokens. Changing sentinel nesting changes whitespace.
3. `optimize_tokens` groups each top-level block into `[:block, tokens]`, as
   before. Inside a block, sentinels marked `:opaque` survive as
   `[:opaque_open]` / `[:opaque_close]`.
4. `generate_block` hands a block to `TreeBuilder` when it starts with a
   tagged opener. `TreeBuilder` emits Ruby that **returns a node** instead of
   writing to the buffer, and collects statics per scope. If the builder
   raises `TreeBuilder::Unsupported`, the block is emitted as a plain HTML
   part, exactly as before.
5. `Renderer#src` produces `Partial.new(parts, metadata, statics)`.
   Part type `:tree` gets a `render_part_N` that wraps the code in
   `render_tree` (not `with_buffer`).
6. `Component::Rendering#render_in` runs `TreeTracker#process`, which swaps
   each node for its diff against the last node sent at that position and
   collects statics the client hasn't seen. `RenderResult#as_json` adds `s`.
   On the initial HTTP render (no live connection) nodes are rendered to HTML
   with `Tree.render`.

### Generated code (example)

```erb
<% if open %><p><%= title %></p><% else %><p>Closed</p><% end %>
```

```ruby
__lc_1 = { 't' => nil }
if open
__lc_2 = []; __lc_1 = { 't' => 0, 'd' => __lc_2 }
__lc_2 << __lc_esc((title
))
else
__lc_3 = []; __lc_1 = { 't' => 1, 'd' => __lc_3 }
end
__lc_1
```

Loops push a fresh row list at the **start** of each iteration (so the row
exists even if the body raises) and, when keyed, push the key there too.
Opaque constructs become `__lc_capture do … end` values; locals the captured
code assigns are pre-declared with `name = nil if false` so they outlive the
capture block (review bug #1).

Runtime helpers live in `PartialRenderer`: `__lc_esc` (mirrors
`ActionView::OutputBuffer#<<`), `__lc_raw` (mirrors `safe_expr_append=`),
`__lc_capture`, `render_tree`. All `__lc_*` names are filtered out of the
dependency metadata in `Renderer#build_metadata` (`user_names`).

### Wire format (`Rendering::Tree`, mirrored in `app/assets/javascript/tree.js`)

- Branch node: `{ "t": scope, "d": [values] }`; no branch taken: `{ "t": null }`
- Loop node: `{ "t": scope, "r": [[row values], …], "k": [keys] }` (`k` only when keyed)
- A value is an HTML string or a nested node.
- Statics: `s: { "<scope>": ["static", "static", …] }` on the render result,
  `values.length + 1` strings per scope.
- **A node always has `"t"`; a diff never does.** That is how apply tells
  them apart.
- Branch diff: `{ "d": { "<index>": value | diff } }` (unchanged indices omitted)
- Loop diff, keyed: `{ "k": [new order]?, "r": { "<key>": fullRow | rowDiff } }`
- Loop diff, unkeyed: `{ "n": newCount?, "r": { "<index>": fullRow | rowDiff } }`
- A full row is an array; a row diff is an object of changed indices.

Scope ids are a per-template counter assigned at compile time.

### Keys

`Compiler#key_code_for`: the loop body must render exactly one element
(whitespace aside) with an `id` or `live-key` attribute containing an output
tag. Its Ruby must be a **pure read** of the loop's own variables
(`pure_node?`): locals bound by the block / `for`, literals, calls with a
receiver (no `!`/`=` methods, no blocks), and receiverless `dom_id`. The key
is evaluated before the row body runs, which is why impure keys (`cycle`,
`n += 1`) are rejected (review bug #5). Duplicate keys at runtime → that
render is sent unkeyed.

### What stays HTML

- Block helpers (`<%= form_with do %>`, `content_for`, `cache`, `capture`…):
  only calls whose method is in `Compiler::ITERATION_METHODS` become loops,
  decided by parsing the call with Prism (review bug #4). Inside a tree, a
  non-iterating block is captured as one HTML value.
- `begin/rescue` (captured as one value inside a tree).
- Any block whose code uses `next`/`break`/`return`/`redo`/`retry`/`throw`
  anywhere (including inside captured regions and output tags — review bug
  #3). The check is a conservative regex (`ESCAPING_CONTROL_FLOW`); a string
  like `"break time"` also triggers the fallback, which is safe.
- `x = if …` (a conditional used as a value).
- **A block that comes before any other output** (`@output_seen` in the
  compiler), because `insert_root_attributes` writes into the first part and
  that part may be the block (review bug #2).

## Invariants to keep

- Sentinel nesting must stay identical to `main` or whitespace changes. The
  equivalence spec catches this.
- `view` positions exclude `:code` parts (`render_changes` drops them), and
  `TreeTracker` keys state by **template path + output position**. Stable
  because part layout is fixed at compile time.
- `TreeTracker` state for a template resets on a `:all` render, and when the
  statics differ **by value** (template recompiled in dev). Compare by value,
  not identity: the compiled template evaluates `Partial.new(...)` on every
  render, so the statics object is new each time (see follow-up 3).
- `Component#forget_client_render_state` (called from `broadcast_render` when
  `channel` is nil) — a render that was never delivered must not become the
  base of the next diff (review finding #6, confirmed by a spec that fails
  without it).
- JSON keys are strings on the client; `Tree.render` falls back from integer
  to string scope keys so the Ruby test helper (`RenderState`) works on
  JSON-normalized payloads.
- The gem and npm package must ship together (a 0.4 client renders a node as
  `[object Object]`). Flag off is the escape hatch; noted in CHANGELOG.

## File map

| File | Role |
|---|---|
| `lib/live_cable/rendering/compiler.rb` | Tagging, opaque marking, iteration detection, key extraction, tree-vs-HTML routing |
| `lib/live_cable/rendering/tree_builder.rb` | Tagged tokens → node-building Ruby + statics; `Unsupported` fallbacks |
| `lib/live_cable/rendering/tree.rb` | Wire format: `render`, `diff`, `apply`, `scope_ids` |
| `lib/live_cable/rendering/tree_tracker.rb` | Per-component diff state (previous nodes, sent scopes) |
| `lib/live_cable/rendering/renderer.rb` | `add_tree`, statics, `buffer_code_for` (opaque sub-engine), `__lc_` filtering |
| `lib/live_cable/rendering/partial.rb` / `partial_renderer.rb` | `:tree` part methods, runtime helpers |
| `lib/live_cable/component/rendering.rb` | Tracker wiring, `forget_client_render_state` |
| `lib/live_cable/component/broadcasting.rb` | Reset on undelivered render |
| `lib/live_cable/testing/render_state.rb` | Ruby mirror of the client (used by `component.rendered`) |
| `app/assets/javascript/tree.js` | Client `renderNode` / `renderParts` / `applyPart` |
| `app/assets/javascript/subscriptions.js` | `ComponentState` keeps statics per template, applies diffs |
| `spec/lib/live_cable/rendering/structured_blocks_spec.rb` | Equivalence (structured vs HTML, byte for byte), part types, keys, diff/apply round trips |
| `spec/lib/live_cable/structured_rendering_spec.rb` | Integration via `live_mount` on `Live::TodoList`: rendering + payload shape |
| `spec/system/todo_list_component_spec.rb` | Browser flow incl. DOM node identity across updates |
| `test/tree.test.js`, `test/subscriptions.test.js` | Client unit + end-to-end refresh |
| `spec/dummy/app/live/todo_list.rb` + views | The todo component used by specs and benchmarks (`/todo_list`) |
| `handoff/*.rb`, `handoff/crosscheck.mjs` | Benchmark and Ruby↔JS cross-check scripts (not for merging) |

## Status and how it was tested

The session's sandbox could not reach rubygems.org, so the gem set was built
from GitHub sources on **Ruby 3.3.6** (the gemspec requires 3.4; the gemspec
was shimmed locally, not in this branch). Also local-only: simplecov was
stubbed out, and system specs ran on a Chrome-for-Testing 153 build with
chromedriver 147 and `--disable-build-check`. None of those hacks are in the
branch. Results in that environment:

- `bundle exec rspec spec/lib spec/channels`: 456 examples, 0 failures
- `bundle exec rspec spec/system`: 71 examples, 0 failures
- `yarn test`: 102 tests passed
- `bundle exec rubocop`: no offenses
- Ruby diff → JS apply cross-check: 30 transitions, 0 mismatches
- Manual browser run against the dummy app over ActionCable (Playwright):
  add/toggle/filter/remove/clear all correct, unchanged rows kept their DOM
  nodes.

**Not verified:** Ruby 3.4, the real locked gem versions, and CI's coverage
gate (`minimum_suite_coverage: 80`, `minimum_file_coverage: 50`). Run
`bundle exec rspec` (full, with simplecov) and check `coverage/` before
anything else.

## Review findings (independent review, all fixed with regression specs)

1. Locals assigned inside a captured region (`<% c = capture do %>`,
   `begin … total = … rescue`) were scoped to the capture block → NameError /
   nil later. Fixed: pre-declare them (`TreeBuilder#declare_locals`).
2. A template starting with a blank line or comment before its root control
   block broke `insert_root_attributes`. Fixed: a block before any output
   stays HTML.
3. `next`/`break` inside a captured region in a loop (or in an output tag)
   were silently swallowed. Fixed: control-flow check covers those tokens.
4. `ITERATION_CALL` regex matched words in arguments (`cache [todo, step] do`,
   `capture step: 1 do`) → cached/captured content leaked inline. Fixed:
   parse the block call with Prism, check the method name.
5. Key expressions ran twice and out of order (`cycle`, `n += 1`). Fixed:
   only pure reads of the loop's variables become keys.
6. Diff state advanced on renders that were never delivered (child with no
   channel yet) → client `applyLoop` could throw. Fixed: reset render state.

Smaller items fixed: `__lc_capture` now restores `@output_buffer`; CRLF in
statics normalised like Ruby does for plain parts; `x = if …` falls back;
statics reset when a template is recompiled.

## Known behaviour changes and limitations

- Inside a control block, a non-output tag that writes to the buffer
  (`<% concat 'x' %>`) has its output **dropped**, with a one-time warning.
  In CHANGELOG upgrade notes.
- `items.each.with_index(1) do` and other chains after `each` are not
  recognised as loops (captured as one value). Missed optimisation only.
- Adding/removing a row in a keyed loop resends the **whole key list**
  (~2.2 KB at 200 rows). See follow-up 2.
- **Pre-existing bug on `main` (not introduced here):** `<%= count # comment %>`
  generates invalid Ruby in the HTML path, because
  `Renderer#add_rails_expression` wraps `(code)` without a newline before the
  closing paren. Structured blocks avoid it (they add the newline); the
  legacy path still has it. The equivalence spec has a structured-only
  example for this case.

## Follow-ups (suggested order)

1. **Run real CI** (Ruby 3.4, locked gems, coverage gate). Fix anything that
   differs from the local run.
2. **Key-move diffs.** Replace the full `k` list in loop diffs with compact
   ops (e.g. removed keys + inserts with an anchor key, or an LIS-based move
   list). Touch `Tree.diff_loop` / `apply_loop`, `tree.js` `applyLoop`, and
   keep `RenderState` in sync. The diff/apply permutation specs in
   `structured_blocks_spec.rb` and `handoff/crosscheck.*` are the safety net.
3. **Pre-existing perf: `Partial` is rebuilt on every render.** The compiled
   template's method body is `::LiveCable::Rendering::Partial.new(...)`, so
   `build_renderer_class` (a `Class.new` + `class_eval` per part) runs on
   every render. Caching the Partial per compiled template (e.g. a constant
   or memo keyed by the template) likely saves more CPU than this branch
   added. Once it's cached, `TreeTracker` could compare statics by identity
   again.
4. **Trim the structured CPU overhead** (~1.5 ms/render at 200 rows):
   memoise row values by key + item identity, or skip diffing a node that is
   `==` to the previous one before walking it. Measure with
   `handoff/cpu.rb`.
5. **Fix the legacy trailing-comment bug** in
   `Renderer#add_rails_expression` (emit `"\n"` before `)` like
   `TreeBuilder#add_expression` does). Small, separate commit.
6. **Direct DOM patching** (the bigger step 3 from the original plan): emit
   markers around tree values and write them in place instead of rebuilding
   the component's HTML string and running morphdom. Study Herb's
   `slots.ts` (stack-based marker pairing, needed because the parser moves
   nodes, e.g. `<tbody>` insertion) and `collections.ts` first.
7. Optional: support `each.with_index` chains; allow other known-pure helpers
   in keys; add a README mention.

## Running things

```bash
bundle exec rspec                         # everything, incl. system specs (needs Chrome)
bundle exec rspec spec/lib/live_cable/rendering/structured_blocks_spec.rb
yarn test
bundle exec rubocop

# Payload bytes per action, structured vs HTML (TODOS=20 by default)
STRUCTURED=0 bundle exec ruby handoff/bench.rb
STRUCTURED=1 TODOS=200 bundle exec ruby handoff/bench.rb

# Server time per toggle at 200 todos
STRUCTURED=1 bundle exec ruby handoff/cpu.rb

# Ruby diffs applied by the JS client must reproduce the server's HTML
bundle exec ruby handoff/crosscheck.rb | node handoff/crosscheck.mjs
```

To inspect generated code for a template, compile it the way
`structured_blocks_spec.rb#compile` does and print `engine.send(:parts)`.

## Benchmarks from the session (bytes of `_refresh` JSON)

| Action | 20 todos HTML | 20 todos structured | 200 todos HTML | 200 todos structured |
|---|---|---|---|---|
| First full render | 12,869 | 3,527 | 113,174 | 15,913 |
| Toggle one todo | 11,229 | 262 | 111,534 | 264 |
| Rename one todo | 11,222 | 118 | 111,526 | 119 |
| Add a todo (top) | 11,772 | 344 | 112,079 | 2,251 |
| Remove a todo | 11,220 | 268 | 111,526 | 2,171 |
| Filter: active | 11,198 | 360 | 111,502 | 2,262 |
| Filter: all | 11,770 | 444 | 112,075 | 2,347 |
| Clear completed | 10,648 | 259 | 110,953 | 2,162 |

CPU per toggle at 200 todos: ~5.3–6.0 ms HTML vs ~6.0–7.6 ms structured
(noisy sandbox, test channel, no JSON serialization or transport counted).
