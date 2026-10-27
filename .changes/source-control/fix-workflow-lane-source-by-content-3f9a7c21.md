---
bump: patch
---

### Changed

- A changed workflow file no longer unbinds the review lanes when its head copy cannot post as `github-actions[bot]` with a write token nor reach a secret (`babysit_review_evidence.readonly_workflow`), so a clean security review clears such a pull request with no person (owner direction 2026-10-27). It must be a top-level `.github/workflows/*.yml` other than the two review callers, and either deleted at the head (proved against the pull request's base, which `bind()` now takes as `base_sha`) or one plain YAML document with: no anchor, alias, tag, merge key or repeated key; only known top-level and job keys; `name:` equal to the file stem; no `pull_request_target` or `workflow_run` trigger; every job's `permissions:` set, its own or the top level's, with each scope `read` or `none` (`read-all` and `{}` too); and no `secrets` reference but `secrets.GITHUB_TOKEN`, which also rules out `secrets: inherit`. Anything else, a rename, a read that fails, or a gate with no PyYAML stays a lane source (`lane-source-changed`).
