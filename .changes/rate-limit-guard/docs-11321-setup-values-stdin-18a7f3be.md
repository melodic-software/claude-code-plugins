---
bump: patch
---

### Changed

- `/rate-limit-guard:setup` names `claude plugin configure rate-limit-guard@<marketplace> --values-stdin` as the preferred headless way to change an option, and keeps the `claude plugin install --config` rerun as the fallback for a Claude Code release without `plugin configure`, with each route's scope rule and failure signal, per the plugin-reconfiguration convention.
