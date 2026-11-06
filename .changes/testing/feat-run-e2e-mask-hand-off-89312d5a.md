---
bump: minor
---

### Changed

- run-e2e's unattended summary scan follows a control skill hub's `## Mask` hand-off to its driving tool's `## Mask`, under the same `trusted-root=` rule as the hub, and accepts a `values:` source that prints one `none: <reason>` line and exits 0 as resolved with no values ([#13757](https://github.com/melodic-software/claude-code-plugins/issues/13757)). A hand-off target that cannot be read, or a values source that fails, keeps `e2e-summary.json` out of `publishable`; a hand-off is never scanned as a hub with no `values:` line.
