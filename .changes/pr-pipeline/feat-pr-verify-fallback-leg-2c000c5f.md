---
bump: patch
---

### Changed

- pr-verify judges once more, on the central fallback subscription token `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`, when the pr-verify role's subscription token also stops (a limit stop, a credit stop, or a 401 or 402) with no permission denial: `check-intent-subscription` passes `fallback-ready` to run-claude-cli, and the new `check-intent-fallback` job runs on a third VM and records `fallback-reason` `limit-stop`, `credit-stop` or `auth`. With the secret empty, the subscription leg stays the last and the lane runs as before.
