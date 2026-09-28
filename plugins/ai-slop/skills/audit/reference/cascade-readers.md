# Config-cascade readers in `detect.sh`

Recorded park for
[#3419](https://github.com/melodic-software/claude-code-plugins/issues/3419),
a deepening candidate that would hoist `detect.sh`'s four config-cascade
readers into one module.

## Decision

**Park. Do not hoist.** The four reader idioms stay in `detect.sh`.

- **Option A (taken):** no unpaid hoist. `cfg_scalar`, `cfg_array`, the
  `rule_allowed_paths` per-slug loop, and the `phrase_add` / `phrase_remove`
  presence-keyed reader keep their own last-layer-wins, jq-exit, and CR-strip
  logic. Which idiom governs which key stays documented next to each reader.
- **Option B (declined):** one cascade-reader module exposing scalar override,
  wholesale-replace list, and per-slug map, with `detect.sh` reduced to calls.

**Claim:** `plugins/ai-slop/skills/audit/scripts/detect.sh` keeps four
cascade-reader idioms over the same three-layer list. Shared invariants
(last-layer-wins, jq-exit-status guarding, CR stripping) stay restated per
reader. A cascade-reader module is unpaid.
**Basis:** origin/main as of this record. `cfg_scalar` (per-key override),
`cfg_array` (wholesale replacement), the `rule_allowed_paths` `while IFS=$'\t'
read` loop (per-slug merge), and `read_phrase_list` / `phrase_add` /
`phrase_remove` (presence-keyed on `jq has()`). The comment block above
`cfg_scalar` names why each is exposed differently and why every reader strips
CR (#3343 / #3361, 6676109d0: Windows jq CRLF silently disabled
`excluded_paths`, `em_dash_allowed_paths`, and `disabled_rules`).
`docs/conventions/config-cascade/README.md` owns the layering contract, not an
implementation. Sibling plugins that resolve a `.local.<ext>` overlay are out
of scope for this record.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds one reader module with a suite that asserts
layer precedence, a CRLF-terminated layer equals LF, a valid-then-truncated
layer is refused whole, and an explicit `[]` in an overlay clears an inherited
list.

## Rationale

- The four shapes are not one library that drifted. `cfg_array`'s space-join
  would split a phrase such as `honest take`. A per-slug map is not a
  wholesale list. Forcing one API is the unpaid design, not a mechanical
  extract.
- The #3343 fix already touches every reader in this file. A module would have
  to preserve that CR contract on every key shape without changing effective
  values.
- The issue is `work-class: structural` and `needs-human`.

## Revisit when

- A maintainer funds the module and names the first key shape to migrate, or
- a new encoding or precedence defect has to be patched in more than one
  reader at once again.

## Prior requests

- #3419 (2026-09-28): deepening candidate; Option A recorded here.
