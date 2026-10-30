---
bump: patch
---

### Changed

- `/planning:setup` names `claude plugin configure planning@<marketplace> --values-stdin` as the preferred headless way to change `use_ask_user_question`, and keeps the `claude plugin install --config` rerun as the fallback for a Claude Code release without `plugin configure`, with each route's scope rule and failure signal, per the plugin-reconfiguration convention.
