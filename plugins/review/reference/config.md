# review settings

The keys the review plugin's skills read, one row each. A key is set per user through the
plugin's `userConfig` option of the same name and per repository in
`docs/conventions/review.yaml`, validated by
[`schemas/review.schema.json`](../schemas/review.schema.json). No `~/.claude` file, `.claude/`
file or local overlay sets these keys. `/review:setup apply` writes the repository file.

| Key | Values | Default | Reader |
|---|---|---|---|
| `ratchet_offer` | `true`, `false` | `true` | `/review:audit-enforceability` (step 5): passes `--ratchet-offer on` or `off` to the stub writer |

## Resolution

A skill resolves each key lowest layer first, and the later layer wins:

1. The default in the table above.
2. The user's option, rendered into the skill as `${user_config.<key>}`. A literal, unexpanded
   placeholder means the option is unset. A user value equal to the default reads as the default,
   since the two cannot be told apart.
3. The key in the repository's `docs/conventions/review.yaml`, read with
   `skills/setup/scripts/setup-apply.mjs --check`, which validates the whole file against the
   schema. A missing file or key leaves this layer unset; a key that is present but invalid (an
   empty value, `null`, a quoted string, a list such as `[]`) is an invalid layer, not an unset
   one.

The skill reports one line naming the resolved value and the layer that supplied it, for example
`ratchet_offer: false (docs/conventions/review.yaml)`. A value outside the key's values in either
layer, or a repository file the reader cannot parse, is named with its file or option, the key and
the value, and that layer is dropped: a valid higher layer still wins, otherwise the key's default,
never a lower layer's value (ADR 0054 Decision 7). The run continues either way.

**Root rule.** The repository file is read only when the repository root (`CLAUDE_PROJECT_DIR`,
else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an
ancestor of it. Otherwise the repository layer is skipped and the report line says why.

**Older releases.** A plugin release without a key has no option for it and ignores the repository
key, since unknown keys are inert, so it keeps its earlier behavior.
