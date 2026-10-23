---
bump: patch
---

### Changed

- The suite's judge samples now cover the answer shapes two judges wrongly failed: `noise-report-before-posting/gate-before-numbers` (absolute script path, a second noise gate, a trailing `partial` check) and `noise-before-gain/not-established` (an opening "the numbers point the right way").
- Three must-fail samples that the reply-only agent paraphrased now use wording it repeats (`measurable-criterion` four-properties sample 3, `worktree-guard-stop` no-way-around sample 4, `zeros-after-usage-limit` check-and-rerun sample 3), and each misses one rubric property.
- `measurable-criterion` must-fail sample 2 again misses only the trial set: its invented baseline is now a target relative to the current bot's rate.
