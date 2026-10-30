---
bump: patch
---

### Changed

- The setup skill's personal-configuration section names `claude plugin configure code-tidying@<marketplace> --values-stdin` as the preferred headless route and the `claude plugin install --config` rerun as its fallback before Claude Code 2.1.285, and carries the scope and failure-signal caveats for both routes, per the plugin-reconfiguration convention.
