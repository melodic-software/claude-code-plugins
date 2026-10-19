# Dispatch tagged phase reviews to quality-gate at the phase boundary

- Status: accepted
- Date: 2026-10-19
- Related: [ADR 0078](0078-own-code-design-review-criteria-in-the-review-plugin.md) (the review
  plugin owns the `code-design` mode this dispatches to). Refs
  [#8326](https://github.com/melodic-software/claude-code-plugins/issues/8326).

## Context

A plan phase can carry a `Review:` concern tag (`architecture`, `security`, `code-design`,
`concurrency`), but no implementation skill read it, so a tagged phase got no review before its
commit. Plan-to-code drift surfaced only at PR review, after every later phase had built on it.

## Decision

`/implementation:implement` and `/implementation:implement-dispatch` run one
`/review:quality-gate` call per `Review:` tag at the phase boundary, before the acceptance verdict
and the boundary commit. A phase with no tag, or a tag outside the table, dispatches nothing
(`plugins/implementation/skills/implement/SKILL.md:212-219`).

| Tag | Mode |
|---|---|
| `architecture` | `architecture` |
| `security` | `security` |
| `code-design` | `code-design` |
| `concurrency` | `slice concurrency` |

- Each call is `--report-only` against the previous phase-boundary commit, with the plan's
  `Quality bar:` line when present and the implementer's rationale withheld.
- Findings are fixed inside the phase fence, then one re-review runs. A CRITICAL on the re-review
  goes to `DEVIATIONS.md` as a blocking `human-decision` entry and is escalated once, never looped
  (`plugins/implementation/skills/implement/SKILL.md:221`,
  `plugins/implementation/skills/implement/context/phase-review.md:36-47`).
- In a dispatched run, an unattended permission mode that denies the review's reads means the
  review did not run: the orchestrator appends an `unverified` `discovery` entry naming the phase
  and tag, reports the phase as not reviewed, continues to the `phase-verifier`, and never retries
  in another shape (`plugins/implementation/skills/implement-dispatch/SKILL.md:245`).

Shipped in [#8394](https://github.com/melodic-software/claude-code-plugins/pull/8394) (issue
[#8331](https://github.com/melodic-software/claude-code-plugins/issues/8331)).

## Why

The tag already says which lens a phase needs, and `/review:quality-gate` already has a mode for
each one, so the dispatch is a lookup table, not a new reviewer. Report-only keeps the gate from
editing the implementer's tree; the single re-review and escalation bound the cost of a disputed
finding; logging a denied review as `unverified` keeps an unattended run moving without claiming a
review that never ran.

## Alternatives considered

- **Dispatch `code-design` only and leave the other tags unread.** Rejected: wiring all four tags
  costs the same as wiring one, and the other three tags would stay promises nothing keeps. Revisit
  if a quality-gate mode cannot take a phase diff.
