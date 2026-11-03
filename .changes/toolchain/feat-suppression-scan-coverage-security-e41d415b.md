---
bump: minor
---

### Added

- report coverage, mutation and security-scanner suppressions

  suppression-scan.py now lists directives that switch off the evidence a
  quality bar relies on, beside the lint and type suppressions it already
  reports: istanbul and c8 ignore comments and coverage.py's no-cover
  pragma, Stryker's disable comment, and Bandit nosec, nosemgrep and
  gitleaks allow. Each spelling comes from the tool's own docs, listed in
  the skill's upstream syntax record. The scanner stays report-only.

  The canonical scanner is lib/suppression-scan.py; both generated copies
  (code-metrics and toolchain ratchet) are regenerated. The findings
  relay gives directives that cannot name a rule a reason-only remedy.
  The addyosmani-agent-skills record moves the suppressions row to take.

  Refs: #12829
