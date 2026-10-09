---
bump: minor
---

### Added

- **`/session-flow:audit-friction`**: audits permission and autonomy friction across this machine's sessions (last 7 days by default; `--since`, `--until`, `--days`, `--project`, `--session`, `--source <dir>`). `friction.py mine` aggregates a window, `cause` maps each denial and approved prompt to the permission rules that could match it, `estimate` sizes the `consequential` (default), `full` and `probes` verification modes with agent counts and token and wall-clock ranges, and `diff` compares a later window with a saved baseline. Agents classify the friction into five classes, plan and verify the fixes; the run ends in one decision brief, user-run scripts for edits auto mode blocks, and a PR-draft list. It ships a default decision policy (#6691).

### Changed

- **audit-sessions records per-event friction.** Each stored session record gains a `friction` block: every classifier, hook and rule denial (with the classifier category or hook name), approved permission prompt, ask, hand-off, `!` command, correction and interrupt, with the command shape and every stored string redacted, plus tool-wait, polling, CI-wait and merge-conflict counts. The collector's code changed, so the next collect re-reads every transcript once. The sweep's `permission` lens now suggests `/session-flow:audit-friction`.
- **The shared transcript reader parses permission outcomes**: `permission_event` for a transcript's tool results and `permission_denials` for a stream-json `result` record, which it now counts as a known record type.
