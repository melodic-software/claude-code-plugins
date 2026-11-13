# docs-hygiene: consumer configuration

The key contract for the settings of the `docs-hygiene` plugin. Every key is optional: with
nothing set, each skill runs on the defaults below.

## Layers

Resolved lowest first; a later layer wins
([ADR 0064](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0064-home-plugin-customization-in-docs-conventions-yaml.md)
Decision 8):

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | per user | the plugin's `userConfig` option of the same name |
| 2 | repository | `docs/conventions/docs-hygiene.yaml` at the repository root, tracked, validated by [`schemas/docs-hygiene.schema.json`](../schemas/docs-hygiene.schema.json) |

No `~/.claude` file, `.claude/` file or personal override sets these keys. The reading skill reads the
repository file through the plugin's bundled copy of the shared reader, `lib/parse-concern-value.sh`:
`compress_articles` through `skills/compress/scripts/articles-setting.sh`, and
`compress_revert_below_pct` by calling the reader directly. A missing file or key leaves that
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
`/docs-hygiene:setup check` reports. `/docs-hygiene:setup apply` names it in one warning, writes
the asked-for key and keeps the unknown key's line as written.

## Keys

| Key | Values | Default | Reader and effect |
|---|---|---|---|
| `compress_articles` | `keep`, `cut` | `keep` | `/docs-hygiene:compress`. `keep` leaves every `a`, `an` and `the` in place and runs the in-session Edit backend with the batch path's word-level cuts only: no sentence or restatement is deleted, and `/caveman:caveman-compress` is not used even when installed, because it always removes articles ([caveman's Remove list](#caveman-removes-articles)). `cut` treats articles as flavor and keeps the earlier behavior: the caveman backend when installed, otherwise the Edit backend with the full flavor matrix. |
| `compress_revert_below_pct` | a whole number from `0` to `100` | `3` | `/docs-hygiene:compress`. A result that compresses the target by less than this percent with zero semantic loss is reverted, on any file. `0` turns the auto-revert off. A run's `--force` flag beats every layer. Read from the repository file with the plugin's copy of `lib/parse-concern-value.sh`, under the same layer rules as `compress_articles`. |
| `verification`, `verification_skills.<skill>` | `off`, `light`, `standard`, `strict` | `light` | `/docs-hygiene:compress` (the semantic-diff dispatch), `/docs-hygiene:audit-derivability` (the spot-test), `/docs-hygiene:audit-noise` (the verification pass) and `/docs-hygiene:extract-ssot` (the adversarial-review round), through `lib/read-verification.sh`. Repository file only, read from the default branch; no user option; a skill entry beats the plugin value ([verification level](../../../docs/contracts/verification-level/README.md)). |

### caveman removes articles

`compress_articles: keep` skips the caveman backend because caveman's compress skill lists
"Articles: a, an, the" under **Remove**, with no setting that keeps them.

- **Pointer**: [caveman's compress skill](https://raw.githubusercontent.com/JuliusBrussee/caveman/main/skills/caveman-compress/SKILL.md),
  its **Remove** list.
- **Recheck trigger**: the **Remove** list drops articles or makes them optional, or the skill is
  renamed or moved (it is `caveman-compress` today, which Step B invokes as `caveman:caveman-compress`).
