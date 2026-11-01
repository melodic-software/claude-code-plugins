---
bump: minor
---

### Added

- `/source-control:pull-request evidence` posts one evidence comment per pull request after the verifier passes for its head, and updates it in place for a new head with `gh pr comment --edit-last --create-if-none --attach`. It attaches only the captures in the run's `publishable` list, a video only when every frame passed the masking check, in collapsed sections laid out by `templates/evidence-comment.md`, and links the CI capture artifact with its expiry or says media was not uploaded. A file outside the list, a leak-scan hit on the body, or an account that posts other comments on the PR posts nothing. When `gh` rejects `--attach` beside `--edit-last`, it deletes the earlier evidence comment and posts a new one ([#11391](https://github.com/melodic-software/claude-code-plugins/issues/11391)).

### Changed

- `create`'s Visual evidence step no longer asks the person to drag captures into the PR description: it points at the evidence step, which attaches them ([#11391](https://github.com/melodic-software/claude-code-plugins/issues/11391)).
