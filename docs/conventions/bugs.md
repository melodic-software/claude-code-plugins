# bugs

Prose for this repository's `bugs` plugin settings. The values live in
[`bugs.yaml`](bugs.yaml), read by `/bugs:scan` for its rotation lanes and its filing posture; keys,
layer order and merge semantics are the plugin's `reference/config.md`. Run `/bugs:setup` to change
them. A `## Gotchas` section here is the team layer of the consumer gotchas `/bugs:scan` and
`/bugs:write` load.

Lanes follow the bundled default order so a run that falls to the date floor lands on the same
lane it would on any repository. Globs are include-only; test suites the globs also match
(`*.test.sh`, `*.test.mjs`, `test_*.py`, `*.Tests.ps1`) are companions the hunters read for a
unit's contract and never hunt, which the scan skill's scope step applies.

Filing posture is `allowed` because this repository's triage lane consumes `needs-triage` raw
intake, and on a cloud session the tracker is the only output that survives the container. A bare
`/bugs:scan` still files nothing; `--track` is required.
