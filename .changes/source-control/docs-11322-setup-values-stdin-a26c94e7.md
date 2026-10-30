---
bump: patch
---

### Changed

- `/source-control:setup`: the babysit config section names `claude plugin configure source-control@<marketplace> --values-stdin` as the preferred headless route and keeps the `claude plugin install --config` rerun as its fallback for a Claude Code release before 2.1.285, with each route's scope rule and failure signal, per the plugin-reconfiguration convention.
