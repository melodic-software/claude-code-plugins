---
bump: minor
---

### Added

- The unattended merge scorer holds a pull request that could add or raise a charge as HIGH
  `cost-review-required`, in both lanes, whatever `high-path-floor` says and whatever an adopted
  author's own paths leave off the floor: Pulumi, Terraform or Bicep files, the multi-agent role
  map and anything under a Pulumi project; a file renamed into a workflow or `pr-pipeline.yaml`;
  a workflow that adds a schedule, a `--model` or `--max-turns` flag, any new `secrets`
  reference, a new Claude Code action, image or package run, a raised timeout on a model leg, or
  a runner that is not a free standard label (any runner off a public repository); and any
  `pr-pipeline.yaml` change beyond comments, blank lines, `description:` and `title:`. The hold
  clears only when the body links an owner's unedited `**Decision recorded.** Cost:` comment on
  the closing issue or the pull request, created after the pull request.
