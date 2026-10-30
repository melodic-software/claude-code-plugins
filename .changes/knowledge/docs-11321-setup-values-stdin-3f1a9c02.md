---
bump: patch
---

### Changed

- `/knowledge:setup apply` names `claude plugin configure knowledge@<marketplace> --values-stdin` as the preferred headless way to change `library_dir`, and keeps the `claude plugin install --config` rerun as the fallback for a Claude Code release without `plugin configure`, with each route's scope rule and failure signal, per the plugin-reconfiguration convention. The apply-mismatch eval asserts both routes in that order.
