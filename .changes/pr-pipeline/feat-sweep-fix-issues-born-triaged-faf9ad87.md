---
bump: minor
---

### Changed

- The lane sweep files each fix issue born triaged, so it skips the `needs-triage` queue and reaches the owning session as priority work: Issue Type `Bug`, labels `status: confirmed`, `priority: high` and `source: lane-sweep` where they exist (no `needs-triage`), and `<!-- work-items:born-triaged -->` as the body's last line, after the fingerprint. The fingerprint is still read from bodies filed without the marker. A reopen re-applies the same labels (`.github/scripts/maintenance-audit-lane-runs/file-findings.mjs`, [README.md, The lane sweep](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-lane-sweep)).
