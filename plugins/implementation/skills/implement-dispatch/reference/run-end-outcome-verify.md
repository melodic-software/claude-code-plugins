# Run-end outcome verification (#3956)

The current contract is stated below. Whether to add a worker/verifier pair for post-phase
source commits is an open owner decision tracked at #3956.

## Decision record

- **Claim:** Run-end already routes to `/implementation:implement` Step 5, which hands the
  Brief's outcome criteria to `/verification:confirm` when that plugin is installed (else
  self-verify against intent). A worker plus fresh-context verifier pair for *post-phase*
  orchestrator source commits (edits after the last numbered phase) is not implemented;
  adding one is an open owner decision tracked at
  [#3956](https://github.com/melodic-software/claude-code-plugins/issues/3956).
- **Basis:** this skill's Integration table ("All phases complete" to implement Step 5) and
  `/implementation:implement` Step 5 item 6.
- **As of:** 2026-09-29.
- **Recheck:** the live state of #3956, this skill gains a rule that treats a source-touching
  commit after the last numbered phase as a phase with a worker and a fresh-context verifier,
  or implement Step 5 drops the `/verification:confirm` handoff.

## Options

| Option | Scope |
| --- | --- |
| **Current contract** | "All phases complete" invokes implement Step 5; outcome verification is that step's `/verification:confirm` (or self-verify) |
| **Alternative (not implemented)** | Every post-phase source commit needs the same worker plus verifier pair as a numbered phase |

## Post-phase source commits

The skip the issue measured (orchestrator source edits after the last numbered phase, no
worker, no verifier) is real. Closing it means changing the dispatch ritual, not restating
Step 5. A run that edits source after the last `[DONE]` phase is outside this skill's
numbered cadence; say so in the handoff or deviations log rather than implying a verifier
ran.
