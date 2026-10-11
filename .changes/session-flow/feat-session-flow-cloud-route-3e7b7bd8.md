---
bump: minor
---

### Added

- `/session-flow:workflow continue` offers a cloud session as advice when the next chunk of work fits one, pointing at the upstream local-versus-cloud criteria and noting which account a cloud session draws on. The new `cloud_route` option (`offer` by default, or `off`) controls the suggestion.
- `/session-flow:continue-in-background --cloud` launches a cloud session with `claude --cloud` under the same explicit-request gate, after checking the tree is clean and the branch is pushed, and reports the teleport and follow-up commands.
