---
bump: minor
---

### Changed

- `block-lane-pr-disable-auto` reads the lanes App login from the new `lanes_app` key in the repository's `docs/conventions/guardrails.yaml` on its default branch, instead of one publisher's App. With the key unset the guard protects no App and passes every auto-merge disable; set `lanes_app` to keep the block.
