---
bump: minor
---

### Added

- `docs/conventions/source-control.yaml` now holds the nine remaining loop-lane keys
  (`babysit_loop_discovery_scope`, `babysit_loop_fixing`, `babysit_loop_thread_resolution`,
  `babysit_loop_draft_elevation`, `babysit_loop_barrier_overrides`, `babysit_loop_escalation`,
  `babysit_loop_cycle_budget`, `babysit_loop_no_progress_threshold`,
  `babysit_loop_trusted_internal_bot_logins`) and the seven babysit-prs repository-policy keys
  (`babysit_merge_method`, `babysit_merge_block_labels`, `babysit_extra_dependency_manager_logins`,
  `babysit_approval_downgrade_logins`, `babysit_skip_downgrade_logins`,
  `babysit_review_gate_context`, `babysit_ci_gateway_context`), and
  `schemas/source-control.schema.json` validates them. For one release a key the YAML lacks is still
  read from its `## <key>` section of `.claude/source-control.md`.

### Changed

- `/source-control:babysit-prs` reads the seven repository-policy keys from the target
  repository's default-branch `docs/conventions/source-control.yaml` first. A YAML the shared
  reader rejects, or one that gives a key the wrong shape, is a repository config error and does
  not fall back to `.claude/source-control.md`. The merge modes against `userConfig` are unchanged.
- Any `babysit_loop_*` key in the team YAML now counts as tracked adoption, so a YAML carrying only
  a non-merge loop-lane key gives the `c2-mechanical` baseline rung.
- With no `.claude/source-control.md` at the base SHA, the unattended merge gate now takes
  `babysit_loop_merge` from `docs/conventions/source-control.yaml` alone. While both files exist
  the lower value still binds.
- The merge gate's skip key now includes `docs/conventions/source-control.yaml`, so a change to it
  re-runs a skipped refusal.
- A change to `docs/conventions/source-control.yaml` now holds for a person, as the `.claude/**`
  row held `.claude/source-control.md`: the hold floor gains a `gate` row for it, so a pull request
  that only adds a trusted bot login there no longer merges unattended.
