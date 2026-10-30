---
bump: patch
---

### Changed

- `/user-interface:setup`: changing a `css_*` option no longer only points at the README. The skill prints the reconfiguration routes itself: `claude plugin configure user-interface@<marketplace> --values-stdin` as the preferred headless route, the `claude plugin install --config` rerun as its fallback for a Claude Code release before 2.1.285, and the four caveats the plugin-reconfiguration convention requires.
