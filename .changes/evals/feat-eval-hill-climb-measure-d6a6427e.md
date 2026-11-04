---
bump: minor
---

### Added

- `plugin-eval/scripts/win-test.py` decides whether a proposed skill edit beats the unchanged skill. It reads two results of the skill as merged (an A/A pair) and one with the edit, scores cases with `noise-report.py`, and leaves out each case a `summarize.mjs` health line reads `skill loaded: no` or `unknown`. It stops at the first gate that fails, by name and with its numbers: an unfinished pass, a run-validity verdict other than VALID, a pass over its cost ceiling, fewer than 3 cases, no headroom (a with-arm mean of 0.95 or higher), an A/A interval that excludes 0, or a case that drops by a third. An edit wins only when the lower end of its with-arm interval is at least +0.05 and above the A/A interval's upper end. `eval-hill-climb.yml` runs it (#12035).
