# code-tidying: consumer configuration

The team layer is `<home>/code-tidying.yaml`, validated by
[`schemas/code-tidying.schema.json`](../schemas/code-tidying.schema.json). `<home>` is the convention
home the repository binds in its root instruction file, `docs/conventions` when it binds none or
declined one. Zero config works: every key has a default.

| Key | Values | Default | Meaning |
|---|---|---|---|
| `upkeep_cadence` | `daily`, `weekly` | `daily` | How often an upkeep batch may open pull requests. |
| `upkeep_backstop` | `weekly`, `monthly` | `weekly` | An area changed since its last sweep is overdue once its oldest unswept commit is older than this window, and goes ahead of other changed areas. An unchanged area is never swept. |
| `upkeep_max_open` | integer, 1 or more | `3` | At most this many `chore/tidy-*` pull requests open at once: `/code-tidying:tidy` stops at it, and an upkeep batch opens only the difference. |

`skills/tidy/scripts/upkeep-setting.sh <key>` is the one reader. It prints the value and the layer
that supplied it. A value outside the table, or a file that does not parse, is reported with its file
and key, and the key resolves to its default. At a root that is `$HOME`, an ancestor of it, or not a
git working tree, or under a broken pointer, the team layer does not apply.

The surface has the plugin default and the team layer only: no `userConfig` option and no personal
overlay, because the limit protects a shared review queue.

The hard-exclusion option and the lane files are separate surfaces, described in the
[README](../README.md) and `skills/tidy/SKILL.md`.
