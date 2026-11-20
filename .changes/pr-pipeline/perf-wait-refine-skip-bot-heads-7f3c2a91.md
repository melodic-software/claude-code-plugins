---
bump: patch
---

### Changed

- `wait-refine.mjs` no longer lists and polls dispatcher runs on a head no refine run can start for: when the runner's event file shows both the sender and the PR author in `NO_REFINE_ACCOUNTS` (dependabot, the release App, the standards-sync App) and its PR number and head match, Wait For Refine reviews after the one finish read. A human, lanes App or mixed event, or a missing, malformed or mismatched event file, still polls.
