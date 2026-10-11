---
bump: minor
---

### Added

- migrate: `cutover-check.sh` runs a nested write probe after its four graded conditions. One metered `claude -p` turn offered only the Write tool writes into `sub/` of a scratch tree with a root and a `sub/` `AGENTS.md` and no `CLAUDE.md`, and prints `[LOADS]`, `[NO-LOAD]` or `[UNREACH]` for the nested file. The probe is reported, not graded, so the exit status is unchanged; `--skip-canary` skips it too, and the new `--skip-write-probe` skips only the probe.
- migrate: `remove-shims.sh` adds the nested write-trigger loss to the price it prints when the repository has a nested `AGENTS.md`. After `cutover-check` runs, it repeats that loss with the probe's result unless the result is `[LOADS]`. For a repository with no nested `AGENTS.md` it passes `--skip-write-probe`, so the probe costs a metered turn only where its answer is priced.

### Fixed

- migrate: `reference/shim-droppable.md` gains condition G, so a repository with nested `AGENTS.md` keeps its nested `@AGENTS.md` shims when the memory docs name a load trigger for a subdirectory's `CLAUDE.md` that they do not name for its `AGENTS.md`, or when the write probe did not print `[LOADS]`, unless the operator accepts the loss. Before, nothing in the droppability check covered a load only the shim carries, and `remove-shims` takes root and nested shims together.
- migrate: the `CLAUDE.local.md` blocker in condition A and the skill's gotcha now offer a gitignored `.claude/rules/<name>.local.md` as a replacement that does not suppress `AGENTS.md`, marking an `@` import inside a rule as undocumented and measured per release. `reference/sources.md` records the five load probes, re-run on Claude Code 2.1.296, under "The nested write trigger".
