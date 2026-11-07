---
bump: patch
---

### Fixed

- `/harness-ops:changelog apply --ci` states the exact grammar every `ci-plan.json` handoff key must match, the release being applied on both sides of `..`, with a valid example, and gives native-drift handoffs a plan key in that grammar with their dedupe key kept as the body's `Drift key:` line, instead of using the dedupe key itself, which the release lane rejects ([#7407](https://github.com/melodic-software/claude-code-plugins/issues/7407)).
