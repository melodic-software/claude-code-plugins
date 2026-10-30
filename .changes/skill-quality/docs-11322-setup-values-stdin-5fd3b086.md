---
bump: patch
---

### Changed

- `/skill-quality:setup`: the reconfiguration guidance names `claude plugin configure skill-quality@<marketplace> --values-stdin` as the preferred headless route and keeps the `claude plugin install --config` rerun as its fallback for a Claude Code release before 2.1.285, with the four caveats the plugin-reconfiguration convention requires.
