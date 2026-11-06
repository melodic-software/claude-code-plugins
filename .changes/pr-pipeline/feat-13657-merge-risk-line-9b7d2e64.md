---
bump: minor
---

### Added

- A report-only `Merge-Risk:` line on each unattended lane merge (#13657, owner decision Q57). The
  new `pr-rate-merge-risk.yml` runs `/review:merge-risk` on each lanes App head that passes
  pr-require-checks, beside pr-verify and as its own run, and uploads `pr-merge-risk-<pr>-<head>`.
  `enable-auto-merge.mjs` reads it just before it arms that head and sets
  `Merge-Risk: max=<level> demote=<bool> head=<sha> rubric=<version> rater=<model> checker=<model>`,
  or `Merge-Risk: unrated reason=<reason>`, as the body's last line, so the squash commit carries
  it. No gate, hold or rung reads the line, and a missing or failed rating never blocks or delays
  the arm. The rating's model and effort come from `models.routes.merge-risk`, a new run route.
