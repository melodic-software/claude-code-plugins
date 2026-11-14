# prototype: settings

The key contract for the `prototype` plugin. Every key is optional: with nothing set, each skill
runs on the defaults below. Each key is defined in
[`schemas/prototype.schema.json`](../schemas/prototype.schema.json) and described here; no other
file restates them.

## Layers

Keys resolve through the four layers of
[ADR 0075](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/adr/0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md),
lowest first; a later layer wins key by key:

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | userConfig | the plugin's `userConfig` option of the same name (`level` only) |
| 2 | team | `<home>/prototype.yaml`, tracked |
| 3 | personal | `<home>/prototype.local.yaml`, gitignored |

`<home>` is the convention home the repository's pointer line binds, `docs/conventions` when it
binds none. Both file layers are skipped when the repository declined a home, when the project is
not a git working tree or is the user's home or above it, or when the home cannot be resolved; the
resolver says which. Above the four layers, for one run, a level the request names wins, and the
`--level` argument wins over that.

[`lib/prototype-settings.mjs`](../lib/prototype-settings.mjs) resolves the keys through the
plugin's copy of the shared cascade and prints one JSON line, the report line
`level: <name> (<layer>)`, where `<layer>` is `argument`, `prompt`, `personal`, `team`, `userConfig`
or `default`, then one `notice:` line per value it ignored.

**Invalid values.** A value the schema refuses, or a `level` that names no level, is named with its
file (or `userConfig`), key and value, and its layer is dropped for that key: a valid higher layer
still wins, otherwise the default; a lower layer's value is never used. An invalid personal value
leaves the team value standing. An invalid value never stops the run.

## Keys

| Key | Values | Default | Reader |
|---|---|---|---|
| `level` | the name of a level in the resolved `levels` map | `standard` | `/prototype:explore-directions` step 1, by the skill's `reference/levels.md` |
| `levels` | a map of level name to its definition, below | the shipped levels in [`levels.default.yaml`](levels.default.yaml) | same |

`level` is checked against the names `levels` resolves to, not a fixed list, so a team file can add
a level. `/prototype:pressure-test` does not read either key yet.

`levels` merges per dimension: a file that sets `levels.full.variants` changes that one value and
keeps the rest of `full`, and a new name adds a level beside the shipped ones. Both file layers may
set it. A level name is lowercase letters, digits and hyphens, at most 32 characters. A level counts
only when it sets every dimension marked required below, from any layer; one that does not is named
in a notice and is not a level, so a `level` naming it is invalid.

| Dimension | Required | Values | Meaning |
|---|---|---|---|
| `variants` | yes | integer 1 to 5 | variants planned for one screen |
| `screens` | yes | `one`, `flow` | `one` narrows the run to one screen; `flow` lets a small set of screens in one flow be one run |
| `states` | yes | `core`, `planned` | `core` builds populated and empty; `planned` builds every state the screen has |
| `extra_states` | no (`[]`) | list of `narrow-viewport`, `dark-scheme`, `reduced-motion` | states each variant also builds, each the populated state under that condition |
| `evidence` | yes | `per-variant`, `per-state` | handover screenshots: one per variant, or also one per state |
| `offers` | no (`[]`) | list of `review-mode`, `real-stack` | which offers the run may make when their condition holds |
| `phrases` | no (`[]`) | list of strings | words in a request that select the level, besides its name |

A team file that adds a level:

```yaml
level: design-system
levels:
  design-system:
    variants: 4
    screens: one
    states: planned
    evidence: per-state
    phrases: [design system]
```
