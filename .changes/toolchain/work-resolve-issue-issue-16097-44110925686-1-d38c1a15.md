---
bump: major
---

### Changed

- `/toolchain:check` and `/toolchain:lint` take an `--unattended` flag. A run is also unattended when `CLAUDE_CODE_REMOTE` is set, under `claude -p`, in a scheduled, loop or CI lane, in a subagent an unattended run dispatched, and when it cannot tell whether a person is present. An unattended run executes only a command the repository's `.claude/ecosystems/<ecosystem>.yaml` records, its instructions state, or its files imply (a manifest script, a task-runner target, or the build tool's own verb on a named entry point, with no flag added). Before each command runs, it prints an `assumed: <ecosystem>.<key>=<command> (<file>:<line>)` line naming the source. It asks nothing, installs nothing and writes no `.claude/ecosystems/` record.
- A key an unattended run cannot resolve, or one whose files imply two commands with nothing to choose between them, no longer runs anything. Its cell reads `skip (unresolved: <ecosystem>.<key>)`, an environment skip that blocks "done" and makes the Overall line `INCOMPLETE`, and the report names the files read and any tied candidates.
- Migration: unattended runs no longer fall back to the bundled defaults in `reference/ecosystems/`. A headless, CI or loop run, a subagent an unattended run dispatched, or a run that cannot tell whether a person is present, that relied on them now reports `skip (unresolved: <ecosystem>.<key>)` for each such key.
- To make a key resolve, record it in `.claude/ecosystems/<ecosystem>.yaml` with `/toolchain:setup apply <ecosystem>`, or merge a lane's record pull request. A recorded `null` resolves the key as not applicable.
