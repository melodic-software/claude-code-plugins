# Native surfaces registry

Generated view over the native-overlap store. The block between the markers below is rendered from
`docs/native-surfaces/records.json` by
`plugins/harness-ops/skills/audit-native-overlap/scripts/overlap.py generate` and kept in sync by CI.
**Never hand-edit it.** Verdicts, evidence, and recheck triggers are edited in the store; this
file is output.

Every verdict here is a human's. Rows are recorded per overlap between a native Claude Code surface
and a component in this repository, and each one carries the observable event that obliges
re-deriving it. Availability is never asserted: an observation record says what was seen, where,
and when. See `docs/conventions/native-references/`.

<!-- native-surfaces:start -->

## Summary

| Lane | Rows | Baked | Integration | Verdicts |
|---|---|---|---|---|
| Built-in CLI commands | 0 | 0 | none | none |
| Bundled skills | 1 | 0 | route 1 | defer 1 |
| Bundled workflows | 0 | 0 | none | none |
| Plugin-backed built-ins | 0 | 0 | none | none |
| Built-in subagents | 0 | 0 | none | none |
| Built-in tools | 0 | 0 | none | none |
| Session-provided skills (observation-only) | 0 | 0 | none | none |
| First-party marketplace plugins | 0 | 0 | none | none |

## Built-in CLI commands

No rows recorded in this lane.

## Bundled skills

### `recap` → `demo:session-digest`

- **Verdict:** `defer`: Not yet ruled: both summarize the session, scope differences unverified.
- **Integration:** `route`
- **Native surface:** `recap` (bundled skill; markers: none)
- **Our component:** `demo:session-digest` (skill)
- **Evidence:**
  - `recap` present in the extraction as bundled-skill
- **Observation:** extraction: extracted from binary v2.1.290 on 2026-10-10 (2026-10-10)
- **Recheck trigger:** a Claude Code release changes the bundled `recap` skill's roster entry (verified 2026-10-10)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

## Bundled workflows

No rows recorded in this lane.

## Plugin-backed built-ins

No rows recorded in this lane.

## Built-in subagents

No rows recorded in this lane.

## Built-in tools

No rows recorded in this lane.

## Session-provided skills (observation-only)

No rows recorded in this lane.

## First-party marketplace plugins

No rows recorded in this lane.

## Dismissed

Pairs a human ruled are not an overlap. `detect` suppresses each one until either side's fingerprint changes, then lists it again flagged "resurfaced: description changed".

No dismissals recorded.

<!-- native-surfaces:end -->
