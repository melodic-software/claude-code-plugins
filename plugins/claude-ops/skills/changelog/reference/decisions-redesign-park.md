# Changelog decisions redesign parked (#4024)

Option A: keep the current skill. Park the remaining decisions-not-items redesign until funded.

## Decision record

- **Claim:** `/claude-ops:changelog` keeps its current contract: item-level P1/P2/P3 triage,
  Phases 0 to 7 on `apply`, and slice 1's read marker / range / replay cap from PR #4041.
  Slices 2 to 4 of the #4024 redesign (lens rubric, surface-discovery script, `apply` as
  handoff) are unpaid and parked.
- **Basis:** Issue [#4024](https://github.com/melodic-software/claude-code-plugins/issues/4024)
  (fifteen-decision contract; four suggested slices). Merged PR
  [#4041](https://github.com/melodic-software/claude-code-plugins/pull/4041) shipped slice 1
  only (`status`, range, cap, marker; body-grep removed). Origin/main
  `skills/changelog/SKILL.md` still assigns P1/P2/P3 and still runs explore / research /
  interview / plan / implement / verify / close-issues inside this skill.
- **As of:** 2026-09-28.
- **Recheck:** a maintainer funds slice 2 (lens rubric, fan-out prose, memory-tier
  persistence) or a later slice as its own issue.

## Options

| Option | Scope | When to choose |
| --- | --- | --- |
| **A: Keep current (taken)** | Marker, range, cap, item table, in-skill apply pipeline | What ships today |
| **B: Remaining redesign (parked)** | `correct`/`replace`/`adopt`/`note`/`skip` lenses; surface-discovery script; `apply` as handoff through marketplace stage skills | Unpaid; slices 2 to 4 of #4024 |

## Park

Do not rewrite `diff` to emit decision rows, do not add the surface-discovery script, and do
not strip Phases 3 to 7 from this skill in this settle. The 2.1.257 to 2.1.263 apply
decisions named on #4024 stay apply work under the current contract, not part of this park.
