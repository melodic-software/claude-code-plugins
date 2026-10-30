---
bump: patch
---

### Changed

- `/markdown-format:setup apply` names `claude plugin configure markdown-format@<marketplace> --values-stdin` as the preferred headless way to toggle the plugin, and keeps the `claude plugin install --config` rerun as the fallback for a Claude Code release without `plugin configure`, with each route's scope rule and failure signal, per the plugin-reconfiguration convention. The headless-toggle eval asserts both routes in that order.
