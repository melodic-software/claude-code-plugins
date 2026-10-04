# planning: settings

The key contract for the `planning` plugin. Every key is optional: with nothing set, each skill
runs on the defaults below.

## Layers

Resolved lowest first; a later layer wins
([ADR 0054](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0054-home-plugin-customization-in-docs-conventions-yaml.md)
Decision 8):

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | per user | the plugin's `userConfig` option of the same name |
| 2 | repository | `docs/conventions/planning.yaml` at the repository root, tracked, validated by [`schemas/planning.schema.json`](../schemas/planning.schema.json) |

No `~/.claude` file, `.claude/` file or local overlay sets these keys. The reading skill resolves
each key in its own text, with no reader script, and reports one line naming the value and the
layer that supplied it. `/planning:setup apply <key>=<value>` writes the repository file after
validating it against the schema, and shows the diff and asks before it changes an existing one.

**Root rule.** The repository file is read only when the working directory is inside a git working
tree whose root is neither `$HOME` nor an ancestor of it. Otherwise the repository layer is skipped
and the report says so; `/planning:setup apply` refuses to write there.

**Unset and invalid values.** A missing file or key leaves that layer unset. A literal, unexpanded
`${user_config.<key>}` means the user layer is unset, and a user value equal to the default is
reported as the default, since the two cannot be told apart. A value outside the key's list, in
either layer, is named with its file (or `userConfig`), key and value, and that layer is dropped: a
valid higher layer still wins, with none the key resolves its default, and a lower layer's value is
never used in its place. An invalid value never stops the run.

## Keys

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `plan_store` | `local`, `tracker` | `local` | `/planning:plan`, final persist step: `tracker` also publishes the approved plan to the claimed work item through `/work-items:track publish-plan` | repository file over user config over default |
| `phase_order` | `composed`, `subtraction-first`, `riskiest-first` | `composed` | `/planning:plan` Step 2, after build-technique selection: the order of the plan's phases | repository file over user config over default |

`phase_order` values, in phase order:

- `composed`: dead code the change touches is removed first (a bug fix skips this), then the
  integration slice, then the riskiest remaining unknown, then scaffold, then the remaining
  features.
- `subtraction-first`: dead-code removal, then scaffold, then features.
- `riskiest-first`: the step whose failure would invalidate the most downstream work, then the
  rest in dependency order.

Under every value a phase that needs another phase's output still follows it.
