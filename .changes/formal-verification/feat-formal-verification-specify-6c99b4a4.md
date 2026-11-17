---
bump: minor
---

### Added

- `/formal-verification:specify`: bare proposes the promise most worth proving (its harm, tool and the `formal-<area>` folder `create` would write) and writes nothing; `create "<promise>"` chooses the tool with the user, writes the model and the `formal-<area>` skill, and hands off only after a seeded break, made in a throwaway git worktree, is caught; `create --unattended` is a dry run that lists its open questions; `check` runs the contract check. `create` first checks that the repository's project instructions opt in to the enforcement ladder's `formal-verification` rung; without it, it goes on only on an attended yes for that run, and an unattended run reports `blocked: formal verification not opted in`. It names no verification tool and installs none.
- `scripts/check.mjs`, the deterministic contract check: it fails a `formal-<area>` skill on missing or wrong frontmatter, a missing section, a missing or invalid `sync.yaml`, a sync commit that is not an ancestor of `HEAD`, a covered path missing at `HEAD` or a check whose command `## Run` does not give, and warns on stale coverage and on verification skills outside the contract. It edits nothing.
- The `skills_dir` and `check.on_stale` keys of `docs/conventions/formal-verification.yaml`, and an optional `on_stale` (`warn` or `fail`) on a `sync.yaml` entry.
