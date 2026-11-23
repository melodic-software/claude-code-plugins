---
bump: patch
---

### Changed

- `merge.dependabot.trusted-action-owners` also lists the major vendors' GitHub-verified organizations (`actions`, `github`, `google`, `google-github-actions`, `microsoft`, `azure`, `aws-actions`, `docker`, `openai`, `hashicorp`), so a Dependabot pull request that only moves one of their action pins to a tagged commit skips `CI Status`'s trust-gate hold (owner decision 2026-11-23).
