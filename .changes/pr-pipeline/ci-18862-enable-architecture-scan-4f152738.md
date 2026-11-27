---
bump: minor
---

### Changed

- The `maintenance-scan-architecture` lane is on (`enabled: true`): its daily run, past the gate, files up to `find_open_item_cap` architecture candidates as `source: architecture-improve` issues on the job's own `GITHUB_TOKEN`. Its forced measuring run on main scanned in 12m07s of standard-runner time (free on a public repository) with 4 REST calls before filing and 71 of 75 subscription turns.

### Fixed

- The lane's model legs can now run Bash and write their candidate file: the prepared tree creates `.claude/commands` and `.claude/agents` before it turns read-only, since Claude Code's sandbox mounts over both, and puts the checkout on `github.ref_name`, since a detached head gives `/architecture:improve` no branch for its candidate path. Each leg fails when any tool call shows a sandbox (bwrap) refusal, so a run that could not use its shell is red rather than an empty green scan.
