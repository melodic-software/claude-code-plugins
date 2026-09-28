# Skill-listing 500-character exceptions

## Decision

**Parked remainder after the #4661 trim fleet.** The #4661 plugin table is the
shared-listing trim fleet. Remaining listing-eligible descriptions over 500
characters are intentional exceptions: skipped this pass (map / pixel / Fable),
covered by in-flight Refs PRs, or outside that table.

**Claim:** remaining listing descriptions over 500 characters after the #4661
heavy-plugin fleet are intentional exceptions, not unfinished fleet work.
**Basis:** #4661's per-plugin table and longest-entry list; `check-listing-budget.sh
plugins/*/skills` at origin/main `a22473fe0` (211 listing-eligible skills, 135,960
chars) plus the shipped `cursor/4661-*-descriptions-37e9` trims; operator skip of
map / pixel / Fable. **As of:** 2026-09-28. **Recheck:** a listing-budget audit
that still shows an original-table plugin over 500 after the in-flight Refs PRs
merge, or a maintainer unparks `architecture:map-landscape`, `pixel-art`, or
`playbooks:fable-5`.

## Rationale

- Description length, not skill count, drives shared listing cost. The #4661
  table is the agreed fleet; one PR per plugin, 500 characters or fewer, no
  renames, no merges, no `disable-model-invocation` flips (#4659).
- map / pixel / Fable stay long on purpose this pass: `architecture:map-landscape`,
  the `pixel-art` plugin, and `playbooks:fable-5`. Trimming architecture without
  `map-landscape` would leave that plugin over the per-plugin 500-character bar.
- In-flight Refs PRs still carry code-metrics, instruction-placement, and
  overengineering. This record does not close #4660 (the enablement-rule child).

## Original #4661 table

| plugin | this pass |
|---|---|
| session-flow | on main |
| docs-hygiene | on main |
| claude-ops | on main |
| planning | on main (#4931) |
| work-items | on main |
| discipline | on main (#4555) |
| claude-config | on main |
| code-metrics | Refs PR #4777 |
| instruction-placement | Refs PR #4954 |
| overengineering | Refs PR #4958 |
| performance | `cursor/4661-performance-descriptions-37e9` |
| knowledge | on main (#4955) |
| discovery | `cursor/4661-discovery-descriptions-37e9` |
| code-tidying | `cursor/4661-code-tidying-descriptions-37e9` |
| architecture | skipped (map) |
| context-budget | `cursor/4661-context-budget-descriptions-37e9` |

Longest singles from the issue that are not table rows: `improvement:find` waits
on the overengineering baseline shrink (serialize `skill-description-cap-baseline.txt`);
`fleet:reach` is outside the table.

## Skipped this pass

- `architecture:map-landscape` (and therefore the architecture plugin)
- `pixel-art` (`scene`, `animate`, `sprite`)
- `playbooks:fable-5`

## Revisit when

- The in-flight Refs PRs merge and an original-table plugin is still over 500, or
- A maintainer unparks map / pixel / Fable, or
- A fleet listing-budget audit is asked to take the non-table remainder
  (songwriting, evals, review, and the other single-skill plugins still over 500).

## Prior requests

- #4661 (2026-09-28): trim child of #4657.
- #4657 (2026-09-28): parent shared-listing cut; this record closes the trim
  child and the parent. #4660 remains the enablement-rule child.
