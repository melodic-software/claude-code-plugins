---
bump: patch
---

### Changed

- `/miro:setup` names `claude plugin configure miro@<marketplace> --values-stdin` as the preferred headless way to rotate `miro_api_token`, since it accepts a sensitive option and keeps the token off the command line, and keeps the `claude plugin install --config` rerun as the fallback for a Claude Code release without `plugin configure`, per the plugin-reconfiguration convention.
