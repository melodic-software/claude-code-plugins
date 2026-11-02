---
bump: patch
---

### Changed

- `/verification:measure` compare reports now include `Limiter:`, `Ruled out:` and `Handed off:` lines for both the `performance` and `metrics` families. A performance compare can fill the first two lines from its own runs or hand the compare to `/performance:verify`, and the `Handed off:` line says which. A code-metric compare always fills them itself. When either line reads `unknown`, the verdict is INCONCLUSIVE, because a number with no known limit cannot be trusted.
- `/verification:confirm`'s evidence step now requires a cited check to be scripted. Its command goes in the manifest's `## Reproduction` block and its output stays in the run's evidence directory, so a reviewer can rerun it and compare. A check that was only looked at once is cited as an observation, not as proof. Both changes come from pstack's `explain-the-number` and `prove-it-works` principles (`docs/upstream/cursor-pstack.md`).
