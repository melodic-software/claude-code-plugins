---
bump: minor
---

### Added

- The pr-merge workflow's merge job shows each candidate's verdict on its head as one `pr-merge / gate`
  check run: neutral and titled with the top refusal, with the blockers in the summary, or success
  once enqueued or merged over a refusal already on show. One GraphQL read per 50 candidates, and a
  write only where the title or conclusion changed. The job's own `GITHUB_TOKEN` writes it, so the
  merge job now holds `checks: write`. The check is never required and is not part of `ci-status`.

### Changed

- A `verify:fail` escalation whose verdict record cannot be read, or a `verify:earlier-fail`, quotes
  the last fail summary the lane's comment carried, under the head it was given at.
