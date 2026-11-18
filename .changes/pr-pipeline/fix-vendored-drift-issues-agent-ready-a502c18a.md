---
bump: minor
---

### Changed

- A vendored-copy upstream-drift issue (github-actions[bot] wrote it, nobody else last edited it, its title is `Upstream drift: <id>` and its first body line is the filer's vendored-copy lead) reaches the issue lane with no owner step, as a hex-pin drift issue does (owner direction 2026-11-18). `driftIssue` in `admit.mjs` decides both kinds at every author gate, and `trustedDriftSpec` gives each its own fixed spec: the vendored one runs the skill's update procedure found from the id's row in `scripts/upstream-drift-vendored-report.sh`, folds the changes into the skill's distilled files and adds the plugin's release record. pr-verify and the merge gate count it only for a pull request that changes nothing outside that plugin and its `.changes/` fragments. It is trusted only when every row for the id carries `files-only` (an apply mode that rewrites vendored files and installs no package), so a row whose update runs `npm install` (firecrawl, context7) is not, and the spec forbids any package install.
- `scripts/upstream-drift-vendored-report.sh` joins the merge hold floor (`enforcement`), as `docs/upstream/**` is: its rows now decide which plugin a vendored drift issue's pull request may change.
- The drift filer runs daily instead of weekly.
