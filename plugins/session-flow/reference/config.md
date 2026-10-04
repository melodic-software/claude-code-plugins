# session-flow settings

The keys session-flow's skills read in their own text, one row each. A key is set per user through
the plugin's `userConfig` option of the same name and per repository in
`docs/conventions/session-flow.yaml`, validated by
[`schemas/session-flow.schema.json`](../schemas/session-flow.schema.json). No `~/.claude` file,
`.claude/` file or local overlay sets these keys. `/session-flow:setup apply` writes the repository
file after validating it against the schema; `/session-flow:setup check` validates it. The observer and `audit_sessions_*` options are
`userConfig` only; the README's Options reference lists them.

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `worker_continuation` | `resume`, `respawn` | `resume` | `/session-flow:orchestrate` (priming addendum only; export modes omit it) | repository file over user option over default |

`resume` keeps a worker across related units, as imperative 4 of the orchestration brief says.
`respawn` gives each new unit (a fix round, a follow-up, a retry, the next queue item) a fresh
worker whose brief consolidates the original brief, every later directive, the prior worker's
report and its branch, and resumes the old worker only when the unit needs state that lives in it
and is costly to move: its checkout, uncommitted changes, or a running process. Under either
value, a worker is respawned after an interrupt, and every resume message restates the brief's
scope fence and standing constraints.

## Resolution

The reading skill resolves each key once, lowest layer first:

1. The default in the table above.
2. The user's option, rendered into the skill as `${user_config.<key>}`. A literal, unexpanded
   placeholder means the option is unset. A user value equal to the default reads as the default,
   since the two cannot be told apart.
3. The key in the repository's `docs/conventions/session-flow.yaml`, read with the plugin's copy
   of the shared reader, `skills/retro/scripts/parse-concern-value.sh`. A missing file or key
   leaves this layer unset.

The later layer wins. The skill reports one line naming the resolved value and the layer that
supplied it, for example `worker_continuation: respawn (docs/conventions/session-flow.yaml)`. A
value outside the key's values in either layer is named with its file or option, the key and the
value, and that layer is dropped: a valid higher layer still wins, otherwise the key's default,
never a lower layer's value. An invalid value never stops the run.

**Root rule.** The repository file is read only when the working directory's git root is neither
`$HOME` nor an ancestor of it. Otherwise the repository layer is skipped and the report line says
so. This is step 2 of the config-cascade resolution algorithm, applied in the skill text.

**Older releases.** A plugin release without a key has no option for it and ignores the repository
key, since unknown keys are inert, so it keeps its earlier behavior.
