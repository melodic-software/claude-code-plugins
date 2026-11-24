---
bump: patch
---

### Changed

- `CI Status`'s trust-gate hold lets a Dependabot pull request through when it only moves an official vendor action (`actions`, `github`, `dependabot`, `microsoft`, `azure`, `anthropics`, `openai`, any case) from one version tag (`vN`, `vN.N`, `vN.N.N`) to another that exists in the action's repository, the same as a full-SHA swap to a tagged commit (owner decision 2026-11-23, [#18604](https://github.com/melodic-software/claude-code-plugins/issues/18604)). A first-party or third-party tag swap, a tag moved to a branch, a non-version tag or a SHA, a SHA moved to a tag, and a changed action path still keep the hold.
