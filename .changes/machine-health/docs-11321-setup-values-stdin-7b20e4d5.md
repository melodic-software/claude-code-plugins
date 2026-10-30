---
bump: patch
---

### Changed

- `/machine-health:setup apply` names `claude plugin configure machine-health@<marketplace> --values-stdin` as the preferred headless way to change `report_dir`, and keeps the `claude plugin install --config` rerun as the fallback for a Claude Code release without `plugin configure`, with each route's scope rule and failure signal, per the plugin-reconfiguration convention.
