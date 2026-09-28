# Run-end outcome verification (#3956)

Option A: keep the existing Step 5 route; park the unpaid post-phase worker/verifier pair.

## Decision record

- **Claim:** Run-end already routes to `/implementation:implement` Step 5, which hands the
  Brief's outcome criteria to `/verification:confirm` when that plugin is installed (else
  self-verify against intent). Requiring the worker plus fresh-context verifier pair for
  *post-phase* orchestrator source commits (edits after the last numbered phase) is unpaid
  and parked.
- **Basis:** Issue [#3956](https://github.com/melodic-software/claude-code-plugins/issues/3956)
  and its triage comment (run-end routing already exists: this skill's Integration table
  "All phases complete" to implement Step 5, Step 5 item 6). Origin/main still has no ritual
  that treats a close-out source commit as a numbered phase with a worker and a verifier.
  That pair is the unpaid half; a docs pointer cannot invent it.
- **As of:** 2026-09-28.
- **Recheck:** a maintainer funds a ritual that treats every source-touching commit after the
  last numbered phase as a phase with a worker and a fresh-context verifier, or implement
  Step 5 drops the `/verification:confirm` handoff.

## Options

| Option | Scope | When to choose |
| --- | --- | --- |
| **A: Keep Step 5 route (taken)** | "All phases complete" still invokes implement Step 5; outcome verification stays that step's `/verification:confirm` (or self-verify) | Current contract |
| **B: Unpaid post-phase pair (parked)** | Every post-phase source commit needs the same worker plus verifier pair as a numbered phase | Structural rebuild; not a free docs add |

## Unpaid route

The skip the issue measured (orchestrator source edits after the last numbered phase, no
worker, no verifier) is real. Closing it means changing the dispatch ritual, not restating
Step 5. Until funded, a run that edits source after the last `[DONE]` phase is out of this
skill's numbered cadence; say so in the handoff or deviations log rather than implying a
verifier ran.
