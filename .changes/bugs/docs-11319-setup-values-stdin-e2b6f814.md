---
bump: patch
---

### Changed

- The setup skill's `output_dir` reconfiguration step names `claude plugin configure bugs@<marketplace> --values-stdin` as the preferred headless route and the `claude plugin install --config` rerun as its fallback before Claude Code 2.1.285, and carries the four caveats (never uninstall, scope, fresh-session observation, each route's failure signal), per the plugin-reconfiguration convention.
