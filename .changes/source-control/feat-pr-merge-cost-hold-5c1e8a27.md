---
bump: minor
---

### Added

- The unattended merge scorer holds a pull request that could add or raise a charge as HIGH
  `cost-review-required`, in both lanes and whatever `high-path-floor` says: any Pulumi,
  Terraform or Bicep file; a workflow patch that adds a `cron:` line or a larger-runner label, or,
  on a repository that is not public, a `runs-on:` or `macos` line; a workflow that gains a model
  credential `secrets.` reference, a new `run-claude-cli` or `claude-code-action` leg, or a raised
  timeout on a model leg; and a `pr-pipeline.yaml` line on a spend key (model, effort, turns,
  rounds, restarts, caps, admission, pause date, leg timeout, credential route). The hold clears
  only when the body links an owner's unedited `**Decision recorded.**` comment on the closing
  issue or the pull request.
