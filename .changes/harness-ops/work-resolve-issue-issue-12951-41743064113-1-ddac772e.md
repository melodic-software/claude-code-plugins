---
bump: minor
---

### Added

- `behavior-probes` has a `plugin-eval` area: its `unlisted-tools-offered` case runs one `claude plugin eval` case whose `allowed_tools` lists only `Read`, `Glob` and `Grep`, and records the run's init tools and what became of a call to each of `Skill`, `Task`, `TaskStop` and `ToolSearch`: not offered, denied, refused, ran, called with no result, or offered but not called. It passes when `Skill` is offered and its call runs.
