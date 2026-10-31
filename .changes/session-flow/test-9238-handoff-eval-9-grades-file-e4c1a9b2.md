---
bump: none
---

Eval-only: case 9 of `skills/handoff/evals/evals.json` now grades the handoff file the run writes, read from disk, not the trace. A judge that reads only the trace cannot see that file's contents. The skill itself is unchanged.
