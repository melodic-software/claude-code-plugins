---
bump: major
---

### Changed

- **Breaking:** `pr-pipeline.schema.json` no longer admits `best` or `fable` for a profile's `model` or `subagent-model`, so a `pr-pipeline.yaml` that names either fails validation; name `opus` instead. The two values stay out until the owner sets a Fable allowance for the lanes. Only a test kept them out of the live config before, and a pull request could edit that test with the config.

### Fixed

- Tests settle two open questions about fix-ci's rung-up retry ([#9022](https://github.com/melodic-software/claude-code-plugins/issues/9022)). A rung-up's check is named `pr-unblock / fix-ci`, the name the fix-ci dispatcher counts, so it spends one of the head's `limits.limit-stops-per-head` runs, and a head gets at most two rung-ups (`fix-ci-dispatch.test.mjs`). fix-docs's `default` patch row reads no report, so it never selects `rung-up`, for an empty or a written patch (`apply-patch.test.mjs`).
