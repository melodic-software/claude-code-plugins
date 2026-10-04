# discovery: consumer configuration

The key contract for the `discovery` plugin. Every key is optional: with nothing set, each skill
runs on the defaults below.

## Layers

Resolved lowest first; a later layer wins
([ADR 0054](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0054-home-plugin-customization-in-docs-conventions-yaml.md)
Decision 8):

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | per user | the plugin's `userConfig` option of the same name |
| 2 | repository | `docs/conventions/discovery.yaml` at the repository root, tracked, validated by [`schemas/discovery.schema.json`](../schemas/discovery.schema.json) |

`/discovery:setup apply` writes the repository file after validating it against the schema, and
shows the diff and asks before it changes an existing one. `userConfig` is the per-user layer;
no `~/.claude` file, `.claude/` file or local overlay sets these keys. The skill reads the repository file itself; a missing file or key leaves that layer unset,
and the layer does not apply outside a git working tree. Every run that reads a key reports the value and
the layer that supplied it.

A value outside the key's values in any layer is reported, naming the layer's file (or
`userConfig`), the key and the value, and that layer is dropped: a valid higher layer still wins,
and with none the key resolves to its default; a lower layer's value is never used in its place. A `userConfig` value equal to the default is
reported as the default level, since the two cannot be told apart, and a literal unexpanded
`${user_config.<key>}` means the layer is unset.

## Keys

| Key | Values | Default | Reader and effect |
|---|---|---|---|
| `explore_output` | `auto`, `change-prep`, `explain` | `auto` | `/discovery:explore`. Picks the final reply only; `EXPLORE.md` and its sidecars are written the same way under every value. `change-prep` replies with the handoff summary for the next stage (research or planning). `explain` replies with a walkthrough of how the scope works, each step citing `path:line`. `auto` picks `explain` only when a person asks how something works, and `change-prep` for anything else, including every call from another skill. A caller passes `--output explain` or `--output change-prep` to set it for one run; that argument wins over every layer. |
