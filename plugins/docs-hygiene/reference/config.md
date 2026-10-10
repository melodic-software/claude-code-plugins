# docs-hygiene: consumer configuration

The key contract for the settings of the `docs-hygiene` plugin. Every key is optional: with
nothing set, each skill runs on the defaults below.

## Layers

Resolved lowest first; a later layer wins
([ADR 0060](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0060-home-plugin-customization-in-docs-conventions-yaml.md)
Decision 8):

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | per user | the plugin's `userConfig` option of the same name |
| 2 | repository | `docs/conventions/docs-hygiene.yaml` at the repository root, tracked, validated by [`schemas/docs-hygiene.schema.json`](../schemas/docs-hygiene.schema.json) |

No `~/.claude` file, `.claude/` file or local overlay sets these keys. The reading skill reads the
repository file through `skills/compress/scripts/articles-setting.sh`, which uses the plugin's
bundled copy of the shared reader, `lib/parse-concern-value.sh`. A missing file or key leaves that
layer unset, and the layer does not apply outside a git working tree or when the working tree's
root is `$HOME` or an ancestor of it. Every run that reads a key reports the value and the layer
that supplied it.

A key that is present without a valid value in any layer (outside the key's values, empty, null,
a map or list, set twice, or in a file that does not parse) is reported, naming the layer's file
(or `userConfig`), the key and the value, and that layer is dropped: a valid higher layer still
wins, and with none the key resolves to its default; a lower layer's value is never used in its
place. The run never stops on an invalid value. A `userConfig` value equal to the default is
reported as the default level, since the two cannot be told apart, and a literal unexpanded
`${user_config.<key>}` means the layer is unset.

A key the schema does not list is reported as a warning and does not drop the layer for the other
keys: a valid `compress_articles` beside it still applies, both in `compress` and in what
`/docs-hygiene:setup check` reports. `/docs-hygiene:setup apply` still refuses to write over such
a file until the unknown key is removed by hand.

## Keys

| Key | Values | Default | Reader and effect |
|---|---|---|---|
| `compress_articles` | `keep`, `cut` | `keep` | `/docs-hygiene:compress`. `keep` leaves every `a`, `an` and `the` in place and runs the in-session Edit backend with the batch path's word-level cuts only: no sentence or restatement is deleted, and `/caveman:compress` is not used even when installed, because it always removes articles. `cut` treats articles as flavor and keeps the earlier behavior: the caveman backend when installed, otherwise the Edit backend with the full flavor matrix. |
