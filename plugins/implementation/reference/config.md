# implementation settings

The keys the implementation plugin's skills read, one row each. A key is set per user through the
plugin's `userConfig` option of the same name and per repository in
`docs/conventions/implementation.yaml`, validated by
[`schemas/implementation.schema.json`](../schemas/implementation.schema.json). No `~/.claude` file,
`.claude/` file or local overlay sets these keys.

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `verify_mechanical_phases` | `true`, `false` | `false` | `/implementation:implement-dispatch` (Gates; Phase boundaries); `/implementation:implement` (Step 4 item 1) | floor: `true` in any layer wins |
| `drain_cadence` | `on-arrival`, `batched` | `on-arrival` | `/implementation:implement-dispatch` (Dispatch cadence step 2) | repository file over user option over default |
| `code_writing` | `inline`, `dispatch` | `inline` | `/implementation:implement` (Step 0); `/implementation:implement-dispatch` (When this skill applies) | repository file over user option over default |
| `per_unit_check` | `pilot`, `every` | `pilot` | `/implementation:implement` (Step 2, Multi-site step) | repository file over user option over default |

`implement_dispatch_wave_cap` is a `userConfig` option only; the README's Options reference lists it.

## Resolution

A skill resolves each key in prose, lowest layer first:

1. The default in the table above.
2. The user's option, rendered into the skill as `${user_config.<key>}`. A literal, unexpanded
   placeholder means the option is unset. A user value equal to the default reads as the default,
   since the two cannot be told apart.
3. The key in the repository's `docs/conventions/implementation.yaml`. A missing file or key leaves
   this layer unset.

The later layer wins unless the key's level rule says otherwise. The skill reports one line naming
the resolved value and the layer that supplied it, for example
`verify_mechanical_phases: true (docs/conventions/implementation.yaml)`. A value outside the key's
values in either layer is named with its file or option, the key and the value, and that layer is
dropped: a valid higher layer still wins, otherwise the key's default, never a lower layer's value
(ADR 0054 Decision 7). Under the floor exception below, a valid `true` in any layer still counts. For `verify_mechanical_phases` the default is `false`, which keeps the carve-out; for `drain_cadence` it is `on-arrival`, which reads each worker return as it comes in; for `code_writing` it is `inline`, which leaves inline editing versus dispatch to the run's other signals (an autonomous run, a plan that routes phases to workers); for `per_unit_check` it is `pilot`, which checks a few units before applying a multi-site change to the rest.

**Root rule.** The repository file is read only when the repository root (`CLAUDE_PROJECT_DIR`,
else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an
ancestor of it. Otherwise the repository layer is skipped and the report line says why. This is
step 2 of the config-cascade resolution algorithm, applied in the skill text.

**Floor exception.** `verify_mechanical_phases` does not take the later layer. `true` in the user's
option or in the repository file resolves `true`, so a repository cannot switch off a user's `true`
and a user cannot switch off a repository's `true`. The repository layer is read from the checkout
and, when it resolves, from the default branch's committed copy
(`git show origin/HEAD:docs/conventions/implementation.yaml`); `true` in either counts, so a branch
cannot lower the value its default branch set.

**Older releases.** A plugin release without a key has no option for it and ignores the repository
key, since unknown keys are inert, so it keeps its earlier behavior.
