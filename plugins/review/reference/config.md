# review settings

The keys the review plugin's skills read, one row each. A key is set per user through the
plugin's `userConfig` option of the same name and per repository in
`docs/conventions/review.yaml`, validated by
[`schemas/review.schema.json`](../schemas/review.schema.json). No `~/.claude` file, `.claude/`
file or local overlay sets these keys. `/review:setup apply` writes the repository file.

| Key | Values | Default | Reader |
|---|---|---|---|
| `ratchet_offer` | `true`, `false` | `true` | `/review:audit-enforceability` (step 5): passes `--ratchet-offer on` or `off` to the stub writer |
| `downstream_probe` | `run`, `report` | `run` | `/review:quality-gate` downstream mode (Step 2): `run` writes the safety-fact probe in a temporary directory outside the tree and runs it; `report` states the probe without running it. Level rule: policy floor, `report` in any layer wins; the repository value is read from the default branch |

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
   one. A WARN on one key's value (including a key set twice) makes this layer invalid for that
   key only: the reader exits 1 and still prints a PASS line for every other key, which this layer
   then sets. Any whole-file problem prints no PASS line, and the layer is dropped for every key:
   a parse error, an unknown key, or a refusal of the file itself (a symlink, a hard link, a path
   that resolves outside the repository, a target that is not a regular file, a file that cannot
   be read, or a committed entry that is not a regular file).

The skill reports one line naming the resolved value and the layer that supplied it, for example
`ratchet_offer: false (docs/conventions/review.yaml)`. A value outside the key's values in either
layer, or a repository file the reader cannot parse, is named with its file or option, the key and
the value, and that layer is dropped: a valid higher layer still wins, otherwise the key's default,
never a lower layer's value (ADR 0060 Decision 7). The run continues either way.

**Policy floor: `downstream_probe`.** This key does not take the later layer. `report` from any
valid layer wins over `run` from the other, so the user option can only tighten the repository
value and the repository file can only tighten the user value. An invalid layer is dropped and
counts as absent; the other layer still applies, and with neither saying `report` the key resolves
`run`. The repository value is read from the default branch's committed copy, never the working
tree: the skill checks the default branch name from `git ls-remote` against the reader's
`--ref` charset (letters, digits, `.`, `_`, `/`, `-`; no leading `-`, no `..`), skipping the layer
on any other name, runs `git fetch origin <default>`, then
`setup-apply.mjs --check --ref origin/<default>`, and reports the commit it read. A pull request
that adds or changes `docs/conventions/review.yaml` on its head therefore cannot switch its own
probe on. When the fetch fails, the last fetched `origin/<default>` is read and the report says so;
when no `origin/<default>` exists, the repository layer is skipped and the report says why.

**Root rule.** The repository file is read only when the repository root (`CLAUDE_PROJECT_DIR`,
else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an
ancestor of it. Otherwise the repository layer is skipped and the report line says why.

**Older releases.** A plugin release without a key has no option for it, and its schema does not
list the key, so its reader reports the repository key as unknown and drops the whole repository
layer. Each key then resolves as it does for an invalid layer: `ratchet_offer` takes its default,
never the lower userConfig value, and `downstream_probe` still takes `report` from userConfig. A
repository shared with users on an older release should add a key only once they have updated.
