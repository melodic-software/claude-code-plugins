---
bump: minor
---

### Added

- The optional `red-main` block (`dry-run`, `daily-cap`, `max-culprit-age-hours`, `confirm-wait-minutes`) and the Red main rule: after a full run on `main` fails, `post-merge-demotion-alert.yml`'s report job confirms the red on its one re-run, pins the culprit merge, and reports whether the bot would revert it, in dry-run only ([README.md, Red main](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#red-main)).
