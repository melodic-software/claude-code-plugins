---
bump: minor
---

### Added

- `behavior-probes` has a `lane-permissions` area: seven cases that run the CI write lane's tool lists under `dontAsk` and check that its Read deny rules keep Grep, Glob and Read out of `/proc/*/environ` and the checkout's `.git`, with paired in-checkout Grep and Read controls.
- `probe.py` passes a case's `allowed_tools` and `disallowed_tools` (or a shared `tool_rules` file in `cases/lib/`) as `--allowedTools` and `--disallowedTools`, with `${PROBE_WORKDIR}` substituted.
- A `verdict_only` case saves no raw stream and no tool output text, so a failed deny leaves nothing on disk; `rejudge` keeps its row from the live run and says why.
