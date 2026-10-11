---
bump: minor
---

### Added

- `/session-flow:workflow continue` offers a cloud session as advice when the next chunk of work fits one, pointing at the upstream local-versus-cloud criteria and noting which account a cloud session draws on. The new `cloud_route` option (`offer` by default, or `off`) controls the suggestion.
- `/session-flow:continue-in-background --cloud` launches a cloud session with `claude --cloud` under the same explicit-request gate, after checking the tree is clean and the fetched branch matches its remote, and reports the teleport and follow-up commands. A plan-backed continuation launches through the prompt-only path with the committed plan's repo-relative path; the effort level is advised for `/effort` in the session rather than passed as a flag.
