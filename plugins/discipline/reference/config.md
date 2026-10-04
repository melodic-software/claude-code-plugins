# discipline: settings

The key contract for the `discipline` plugin's repository-scoped settings. Every key is optional:
with nothing set, each skill runs on the defaults below. The `sweep-all` batch options and
`research_deep_verification` are `userConfig` options only; the README's Options reference lists
them.

## Layers

Resolved lowest first; a later layer wins
([ADR 0054](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0054-home-plugin-customization-in-docs-conventions-yaml.md)
Decision 8):

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | per user | the plugin's `userConfig` option of the same name |
| 2 | repository | `docs/conventions/discipline.yaml` at the repository root, tracked, validated by [`schemas/discipline.schema.json`](../schemas/discipline.schema.json) |

No `~/.claude` file, `.claude/` file or local overlay sets these keys. The reading skill resolves
each key in its own text, with no reader script, and reports one line naming the value and the
layer that supplied it. `/discipline:setup apply <key>=<value>` writes the repository file after
validating it against the schema, and shows the diff and asks before it changes an existing one.

**Root rule.** The repository file is read only when the repository root (`CLAUDE_PROJECT_DIR`,
else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an
ancestor of it. Otherwise the repository layer is skipped and the report says why;
`/discipline:setup apply` refuses to write there.

**Unset and invalid values.** A missing file or key leaves that layer unset. A literal, unexpanded
`${user_config.<key>}` means the user layer is unset, and a user value equal to the default is
reported as the default, since the two cannot be told apart. A value outside the key's list, in
either layer, is named with its file (or `userConfig`), key and value, and that layer is dropped: a
valid higher layer still wins, with none the key resolves its default, and a lower layer's value is
never used in its place. An invalid value never stops the run.

**Older releases.** A plugin release without a key has no option for it and ignores the repository
key, since unknown keys are inert, so it keeps its earlier behavior.

## Keys

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `lever_scope` | `deterministic`, `non-trivial` | `deterministic` | `/discipline:script-the-deterministic-work lever-check`, called by `/implementation:implement` before a multi-site block and by `/implementation:implement-dispatch` before a fan-out | repository file over user config over default |

`lever_scope` values:

- `deterministic`: build a lever (a script or tool that applies the change) only when the change is
  a mechanical transformation, one whose result at each site follows from the site with no
  judgment. Any other repeated change is edited by hand.
- `non-trivial`: build a lever for any repeated change that is not trivial, judgment-bearing ones
  included, using an established codemod or refactoring tool for the language. A refactoring script
  written from scratch for the occasion does not count as a lever under this value.

Under either value the first site is changed by hand, and the lever's output on that site is
compared with the hand edit before the lever runs on the remaining sites.
