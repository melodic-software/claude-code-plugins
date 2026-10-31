---
bump: minor
---

### Added

- `merge.dependabot.trusted-action-owners` lists action owners whose Dependabot bumps skip
  ci-status's trust-gate hold: a Dependabot pull request passes when every changed file is a
  modified workflow or `action.yml` and every change block only swaps the SHA ref of one `uses:`
  line of an action by a listed owner, to a commit a tag of that action's repository points to.
  Any other line, file, owner or ref keeps the hold, and an unreadable list fails closed. This repository lists `anthropics` (owner decision Q-ANTHROPIC-DEPS).
