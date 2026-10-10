# education: consumer configuration

The key contract for the repository layer of the `education` plugin. Every key is optional: with
nothing set, each skill runs on the defaults below. The plugin's other `userConfig` options
(`quiz_policy`, `report_library_dir`, `workspace_root`) are per-user only and are not keys here.

## Layers

Resolved lowest first; a later layer wins
([ADR 0060](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0060-home-plugin-customization-in-docs-conventions-yaml.md)
Decision 8):

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | per user | the plugin's `userConfig` option of the same name |
| 2 | repository | `docs/conventions/education.yaml` at the repository root, tracked, validated by [`schemas/education.schema.json`](../schemas/education.schema.json) |

No `~/.claude` file, `.claude/` file or local overlay sets these keys. The reading skill reads the
repository file through its bundled copy of the shared reader, `parse-concern-value.sh`. A missing
file or key leaves that layer unset, and the layer does not apply outside a git working tree or
when the working tree's root is `$HOME` or an ancestor of it. Every run that reads a key reports
the value and the layer that supplied it.

A value outside the key's values in any layer is reported, naming the layer's file (or
`userConfig`), the key and the value, and that layer is dropped: a valid higher layer still wins,
and with none the key resolves to its default; a lower layer's value is never used in its place.
The run never stops on an invalid value. A `userConfig` value equal to the default is reported as
the default level, since the two cannot be told apart, and a literal unexpanded
`${user_config.<key>}` means the layer is unset.

## Keys

| Key | Values | Default | Reader and effect |
|---|---|---|---|
| `explain_starting_rung` | `plain`, `peer` | `plain` | `/education:explain`. `plain` starts at rung 1, an everyday analogy with no jargon, and offers the next rung up. `peer` starts at rung 3: one precise sentence of definition, then full detail, and offers the plain version instead of a higher rung. Either way the skill climbs or drops a rung only when the reader asks. |
