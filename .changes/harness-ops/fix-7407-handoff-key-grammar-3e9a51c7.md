---
bump: patch
---

### Fixed

- `/harness-ops:changelog apply --ci` states the exact grammar every `ci-plan.json` handoff key must match, the release being applied on both sides of `..`, with a valid example, and gives each native-drift handoff its own plan key in that grammar, built from its drift identity, with the dedupe key kept as the body's `Drift key:` line, instead of using the dedupe key itself, which the release lane rejects ([#7407](https://github.com/melodic-software/claude-code-plugins/issues/7407)).
