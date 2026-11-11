---
bump: minor
---

### Changed

- A layer of a native GitHub stack whose stack base is the default branch now runs its lanes (owner decision Q40). `check-trusted-trigger` and `check-trusted-base` accept it, and the gate's `base-sha` for it is `pull_request.stack.base.sha`, a default-branch commit, so every script, action, config and list still loads from the default branch and never from the layer below. ci-status reads its hold config at the default branch tip for such a layer. A PR into any other branch outside such a stack, and a stack into another branch, still stop with `untrusted-base`.
