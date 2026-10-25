---
bump: minor
---

### Added

- **`research`:** restatements cite a claim ID instead of restating the claim. Each sidecar claim carries an `id:` (`M1`, `CI-02`), and the index Summary, the Settled list and the rest of the handoff, catalog and table cells, and sidecar abstracts cite it; a line naming a claim at `HIGH (single source)`, `MEDIUM` or `LOW` carries that label on the same line. The researcher writes to the rule, and the research verifier grades restatements under row 12, or row 7 for a `MEDIUM` or `LOW` claim ([#6070](https://github.com/melodic-software/claude-code-plugins/issues/6070)).
- **`research`:** `scripts/check-restatement-labels.py` reports every line of a research slice that names a labeled claim's ID without its label. The parent runs it after the acceptance gate and hands what it reports to the verifier; it is advisory, so no exit halts the run ([#6070](https://github.com/melodic-software/claude-code-plugins/issues/6070)).

### Changed

- **`research`:** the outcome gate's result line points at "Effort, source breadth" for its rework bounds instead of saying run-owned rows have no iteration limit ([#6070](https://github.com/melodic-software/claude-code-plugins/issues/6070)).
