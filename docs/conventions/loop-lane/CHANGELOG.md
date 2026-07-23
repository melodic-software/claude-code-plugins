# Loop-lane convention — changelog

Notable changes to the loop-lane contract. The contract is versioned by SemVer; a change to the
topology, the escalation contract, the capability-tier vocabulary, or any loop-layer invariant is a
major bump, and additive guidance is a minor bump. A new model release re-audits the capability-tier
table (§3) and is recorded here.

## 1.0.0 — 2026-07-23

Initial published contract. Lands before the second adopter, per the convention-registry rule: the
`work-items` `work-loop` / `attend-queue` skills and the `source-control` `babysit-loop` skill share
these concerns across two plugins.

- **Three-session topology** — worker loop authors PRs (never merges), babysit lane owns merges
  within the autonomy matrix's merge-policy column, attended queue holds judgment.
- **Autonomy ladder** — human merge is the shipped default for all but gate-proven C2-mechanical
  PRs (a work-class test, not an authorship one: bot authorship alone never qualifies, and C3/C4/C5/
  unclassified stay human-gated); this default is the recorded baseline rung, and every higher rung
  is opt-in per repo through the matrix's recorded human-ratified config flip.
- **Escalation contract** — `needs-human` role label resolved via `config.role_labels` plus a
  machine-marked discriminator comment; event classes owned by the autonomy guardrails.
- **Capability tiers** — order-defined (frontier / strong / fast), never family names; runtime
  resolution by model alias only, Models API as the build/audit-time path; security-surface work
  routes to frontier always; weekly-cap specifics linked to the official support article, never
  restated.
- **Loop-layer invariants** — stop shapes with a drain-terminal state; `#691` cycle budget restarts
  the session, never the loop; `#502` single edit-in-place telemetry comment with durable loop state;
  headless-config floor; seam exit 8 backoff-as-dirty; snapshot drain exit; subagent discipline
  preamble.
- **Launch surfaces** — `/loop` primary and dependency-free; `claude-ops` `lanes` a one-directional
  supporting launcher (#480), presence-gated with a `/loop` fallback.
- **Rate-limit guard binding** — each lane inlines the operable pause floor and cites the guard
  reader contract for provenance; single-account-per-machine invariant; per-cycle guard-mode
  telemetry.

Live Claude Code surfaces (model aliases, `ScheduleWakeup` bounds, `/loop` self-pacing) verified
against current official documentation on 2026-07-23.
