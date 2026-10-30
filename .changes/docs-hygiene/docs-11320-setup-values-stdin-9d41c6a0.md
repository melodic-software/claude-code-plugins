---
bump: patch
---

### Changed

- The setup skill's reconfiguration short form names `claude plugin configure docs-hygiene@<marketplace> --values-stdin` as the preferred headless route and the `claude plugin install --config` rerun as its fallback before Claude Code 2.1.285, and now prints all four caveats (never uninstall, scope, next-session observation, each route's failure signal), per the plugin-reconfiguration convention.
