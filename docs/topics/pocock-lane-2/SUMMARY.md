# Lane 2 summary: phase boundaries (issue #2900)

Second of six vetting lanes under the `pocock-course-lanes` contract
(`docs/topics/pocock-course-lanes/PLAN.md`). Closed 2026-08-17. Scope: the course lesson
"Clear, Compact, Handoff, Or Subagent" against the `session-flow:workflow` continuation router
(`context/continuation.md`), plus the effort's build deliverable: the Q9 context-driven router
evolution. The lane ran across two sessions (a stale resume prompt caused one hop through the
lane-1 handoff; state was reconstructed from the ledger and the verified explore slice with no
loss).

## Decisions (register Q20 through Q23; rows in `docs/upstream/aihero-course.md`)

- **Subagent terminal / AFK criterion (Q20, user-delegated):** ADOPT modified. The AFK question
  becomes a router edge pointing to `session-flow:orchestrate` for the spawn-brief decision;
  delegation stays non-terminal so orchestrate keeps spawn ownership and
  continue-in-background's explicit-intent launch gate is untouched (the router suggests, never
  launches). Filed in #2971.
- **Router inputs (Q21):** via existing informants. Plan, work-item state, and session history
  arrive through presence-gated pointers to orient's read patterns, reconcile's liveness answer,
  the workflow checklist, and the work-item seam, exactly as the zone seam consumes
  context-guard's reader contract. No duplicated reads; zone stays word-only.
- **Autonomy meaning (Q22):** both tiers. Top level: per-invocation explicit opt-in
  (`continue auto` or explicit user words; never a standing config) executes the routed
  mechanism. Worker level: the orchestrator relay parked from lane 1 (worker emits its handoff
  at a fork point; the orchestrator retires the worker and seeds a fresh agent with the resume
  prompt) is codified as the autonomous tier for delegated work. I23-clean: initiative comes
  from the user's opt-in or the orchestrator, never injected context.
- **Eval and hygiene debt (Q23):** file both. Router eval coverage (zero evals, one
  already-regressed ordering invariant) as #2972; the context-guard
  `reference/reader-contract.md:185-207` pre-0.5.0 advisory-injection drift (verifier finding)
  as #2973.

## Fact-graded dispositions (claim ladder, no user decision owed)

- His "compact seeds a new session" wording: REJECT as a harness claim (verdict C4, two-pool
  REFUTED; same session continues over a structured summary).
- Numeric anchors 30k/80k/150k and the ~150k smart zone: recorded as folklore anchors with named
  provenance, never adopted as numbers (claim-ladder bucket ii, amendment A1).
- Handoff-narrowing: REJECT, confirming the lane-1 UNION decision and the prior repo-tree
  rejection.
- Boundary-only discipline, ordered first-yes-wins, clear-when-disposable, compact-last with
  steering, reasoning-verbatim continue criterion, primary-to-secondary trade: COVERED at parity
  or stronger.

## Work items filed (changes execute outside the lane)

- #2971: the Q9 router evolution (informant-seam inputs, AFK edge, suggest-by-default,
  two-tier autonomy, I23 reconciliation).
- #2972: router eval coverage, to land with or before #2971.
- #2973: context-guard reader-contract advisory-injection section update to the 0.5.0
  audience split.

## Parked to other lanes

- Lane 6 (#2904): dictionary-term adoption surfaced here (primary/secondary source, smart zone,
  AFK, phase boundary) and the SSOT "measured bands" wording correction (already on lane 6's
  list per amendment A1).

## Process notes

- Grounding: fresh-context explore of the router and its siblings
  (`.work/pocock-lane-2/`, gate exit 0, verifier PASS 23/23 with parent write-back); course
  lesson cached verbatim in the same slice; harness claims cited from the durable verdict table
  in the lane contract rather than re-researched.
- The verifier's new find (reader-contract drift) became #2973, demonstrating the
  write-back loop paying for itself.
