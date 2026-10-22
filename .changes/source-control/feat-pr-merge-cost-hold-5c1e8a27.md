---
bump: minor
---

### Added

- The unattended merge scorer holds a pull request that could add or raise a charge as HIGH
  `cost-review-required`, in both lanes, whatever `high-path-floor` says and whatever an adopted
  author's own paths leave off the floor: Pulumi, Terraform or Bicep files and anything under a
  Pulumi project; a file renamed into a workflow or `pr-pipeline.yaml`; a workflow that adds a
  schedule, a `--model` or `--max-turns` flag, a model credential `secrets.` reference, a new
  `run-claude-cli` or `claude-code-action` leg, a raised timeout on a model leg, or a runner that
  is not a free standard label (any runner off a public repository); and a `pr-pipeline.yaml` line
  on a spend key. The hold clears only when the body links an owner's unedited
  `**Decision recorded.**` comment on the closing issue or the pull request.
