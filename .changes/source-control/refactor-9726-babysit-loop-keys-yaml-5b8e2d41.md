---
bump: minor
---

### Added

- `babysit_loop_stop_mode`, `babysit_loop_tier`, `babysit_loop_merge` and `babysit_loop_grace_window_minutes` take their team value from `docs/conventions/source-control.yaml`, and `schemas/source-control.schema.json` declares them ([#9726](https://github.com/melodic-software/claude-code-plugins/issues/9726)). For one release a key the YAML lacks is still read from its `## <key>` section of `.claude/source-control.md`, and a YAML the shared reader rejects stops the lookup instead of falling back. Either file carrying a loop-lane key counts as tracked adoption.
- `babysit_repo_config.py loop-keys <owner/repo>` reads those four keys from the target repository's default branch through the contents API, YAML first, and prints each value with the layer that supplied it and whether the repository adopted the lane. It exits 1 when a file it needs cannot be fetched, the YAML is rejected or names one of the four keys without a scalar value, or the supplying layer holds a value outside the key's table. `/source-control:babysit-loop` uses it when the checkout is not the target, and `lib/convention-key.sh` when it is.

### Changed

- The unattended merge gate (`babysit_merge.py --unattended`) reads `babysit_loop_merge` from `docs/conventions/source-control.yaml` as well as `.claude/source-control.md` at the base SHA and takes the lower value, so a demotion written to either file holds the gate. Either file the gate cannot read or trust (a rejected YAML or legacy file, an empty, non-scalar or unknown YAML value, an empty or repeated legacy H2) turns the rung off, never the other file's value alone.
- The `babysit-loop` evals that adopt the lane at `c3-autonomous` now seed `docs/conventions/source-control.yaml` in place of `.claude/source-control.md`.
