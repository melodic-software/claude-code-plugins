---
bump: minor
---

### Added

- `/planning:plan` orders and caps any phase or test step that spends model runs (evals, agent fan-outs, benchmark batches): a graded check that the problem reproduces comes before any baseline or comparison batch, the run count is sized from tokens measured on 1-2 runs, and the phase carries a `**Run budget:**` line whose runner refuses runs past the count and launches nothing after the first usage-limit error. The plan reviewer flags a model-run phase that lacks any of the three.
