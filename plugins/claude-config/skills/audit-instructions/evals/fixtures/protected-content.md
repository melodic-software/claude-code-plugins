# Protected content — one line per category the detectors must never flag

Each line below belongs to a protected-content category named by the container spec (#3118,
"Protected content — no detector may flag it"). None carries a forced-compliance marker or a
blanket tool default, so the I28 families must return zero rows for this file. A row here is a
false positive against a named category, not a borderline call.

Directive: resolve the item id before calling the seam.
Threshold: the lease TTL is 24 hours.
Numeric bound: at most 5 concurrent dispatch waves.
Qualifier: prefer the plugin-dir path when both resolve.
Version pin: requires gh 2.94 or newer.
Proper noun: the GitHub adapter owns this operation.
Path: plugins/review/context/severity.md holds the tier tests.
Command string: run `git worktree add -b <name> <path> <base>`.
Env var: CLAUDE_PLUGIN_ROOT resolves the bundled seam.
Motivating context: the lease exists because two lanes can pick the same item.
Completion criteria: the run is done when CI is green and the item is closed.
Worked example: given `feat/42-thing`, the branch parse yields item 42.
