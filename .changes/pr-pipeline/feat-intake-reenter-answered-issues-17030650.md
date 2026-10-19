---
bump: minor
---

### Added

- `intake-reenter.yml` sends an answered issue back to intake: a listed human's `**Decision recorded.**` comment on a `status: needs-decision` issue, or the author's or a listed human's reply on a `status: needs-info` issue, removes the status label, adds `needs-triage` and dispatches `intake-triage.yml` once. It never adds `agent-ready`. A dispatched intake run no longer skips a born-triaged issue ([README.md, Stages](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#stages)).
