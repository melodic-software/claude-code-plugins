---
bump: none
---

- Redesign the 15 `revert-*` eval graders in `plugins/review/evals/revert-*/graders/caught.md` from line-number regexes to `type: llm` high-signal defect graders with calibration samples and `runs: 3`, and document the new workflow inputs in `plugins/review/README.md` (#19532).
