---
bump: patch
---

### Changed

- The review-dependency verdict job counts an official vendor action (`actions`, `github`, `dependabot`, `microsoft`, `azure`, `anthropics`, `openai`) moved from one version tag (`vN`, `vN.N`, `vN.N.N`) to another as a pin swap, so a Dependabot vendor tag bump with a `merge` verdict gets the merge marker instead of escalating `dependency-workflow-unpinned` (owner decision 2026-11-23, [#18604](https://github.com/melodic-software/claude-code-plugins/issues/18604)). A vendor tag moved to a branch or SHA, any third-party or first-party ref off a full SHA, and any other workflow edit still escalate.
