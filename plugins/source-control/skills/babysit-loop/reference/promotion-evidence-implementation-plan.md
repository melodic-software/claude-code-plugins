# Promotion-evidence trusted seam. Implementation plan (#4588)

Status: Phase 1 approved by the owner. Phases 2-3 are unapproved and are re-decided after the
bootstrap contract is reviewed. Phases 2 and 3 are not implemented.

User-approved plan required before code changes. This document proposes scope and phases; it does
not wire the seam.

## Problem

The merge lane must resolve each promotable cell's **effective** promotion state through
`check-security-binding.mjs --evidence` on a **qualified, non-forgeable** read
([`promotion-evidence-resolution.md`](promotion-evidence-resolution.md)). Today the lane has no
invocation path that supplies `--probe-evidence-root` (or equivalent bootstrap) outside the target
repository's blast radius, so evaluation mode fail-closes and every cell stays effective-unpromoted.
Tracked `babysit_loop_merge: c3-autonomous` therefore does not admit autonomous merge for C2/C3
classes.

## Decision record

- **Claim:** Closing #4588 requires a cross-plugin implementation (babysit-loop cycle step +
  autonomy `check-security-binding.mjs` invocation + operator bootstrap documentation), not a
  prose-only update to the fail-closed paragraph.
- **Basis:**
  - Issue [#4588](https://github.com/melodic-software/claude-code-plugins/issues/4588).
  - `plugins/autonomy/skills/setup/scripts/check-security-binding.mjs`: usage line 12 names
    `--evidence` and `--probe-evidence-root`; `verifyProbeTranscript` (line 1310) returns the
    fail-closed reason "no --probe-evidence-root configured" at lines 1316-1317 when the root is
    null.
  - `plugins/autonomy/skills/setup/SKILL.md`: "Agent-unwritable bootstrap for security
    resolution" (line 214).
  - `plugins/autonomy/skills/setup/scripts/check-security-binding.fixtures.test.mjs`: builds each
    fixture argv with `--probe-evidence-root` (line 80) and `--evidence` (line 81).
  - [`cycle-shape.md`](cycle-shape.md) step 3, "Rung partition" (line 22), whose promotion gate
    reads at lines 45-50.
  - `prompts/loops/loop-lane-prompts.md`: `{{MERGE}}` guidance (lines 75-80), "2. Merge lane"
    (line 628), and the "C2 auto-merge may lack its promotion evidence" known gap (line 1248).
- **As of:** 2026-09-29.
- **Recheck:** issue #4588 changing state, or any cited file changing the quoted usage line,
  fail-closed message, bootstrap section, fixture argv, or step 3 promotion gate.

## Exit criteria (from #4588)

1. `check-security-binding.mjs --evidence` returns a qualified read through the trusted seam when
   the operator bootstrap is configured.
2. Repository evidence predicates in `prompts/loops/loop-lane-prompts.md` merge-lane copy-blocks can
   be met.
3. A promoted cell with clean in-epoch evidence resolves promoted; contrary events still demote per
   the fail-closed table.
4. Update the "Current seam state" paragraph in `promotion-evidence-resolution.md` to match shipped
   behavior.

## Phases (implement after PLAN approval)

### Phase 1. Bootstrap contract

- Document the required operator surfaces: security binding location, `--probe-evidence-root` path
  class (agent-unwritable), and how epoch-scoped promotion-evidence artifacts are published.
- Add a babysit-loop preflight check that names the missing bootstrap when evaluation would
  fail-closed (without weakening merge safety).

### Phase 2. Cycle-step invocation

- In babysit-loop cycle-shape step 3, invoke `check-security-binding.mjs` evaluation mode through
  the documented bootstrap only (never repo-local JSON the lane could forge).
- Map script output to the promotable-cell table already in `promotion-evidence-resolution.md`.
- Report bound→effective pairs and fail-closed reasons in the cycle-start config report.

### Phase 3. Verification

- Extend `check-security-binding.fixtures.test.mjs` coverage for the invocation argv the lane uses.
- Add babysit-loop eval or harness case where bootstrap qualifies and C2/C3 PRs enter the
  merge-eligible set.
- Flip "Current seam state" from present-tense gap to operator instructions once Phase 2 ships.

## Out of scope

- Lowering fail-closed rules when bootstrap is absent (operators keep `--merge human-only`).
- Reading promotion evidence from `.claude/source-control.md` or any agent-writable repo surface.
