# Adopt a five-layer plugin config cascade read through one shared resolver

- Status: accepted
- Date: 2026-10-10
- Related: [#6594](https://github.com/melodic-software/claude-code-plugins/issues/6594), which owns
  the repo-wide config format and folder layout and may supersede this record

## Context

The `user-interface` plugin is gaining a CSS skill whose behavior consumers must be able to change:
browser target, `!important` policy, layer placement, token fallback, and disabled techniques and
rules. Teams need a checked-in setting, individuals need a personal one, and some values belong to
the user across every repository.

Today the plugin has no team-layer reader, YAML parser or resolver. No shared multi-layer resolver
exists in the repository: each plugin that layers config carries its own, such as `multi-agent`'s
`scripts/resolve-roles.sh`, and `user-experience` carries the only `yaml-subset.mjs` parser.

The [config-cascade convention](../conventions/config-cascade/README.md#the-layers) defines three
layers: user-global `~/.claude/<name>`, team, and a local overlay
`${CLAUDE_PROJECT_DIR}/.claude/<stem>.local.<ext>`. Its "What does not move" paragraph keeps the
user-global and overlay layers under `.claude/` even when the team layer moves to a docs convention
file. [ADR 0044](0044-default-structured-team-config-to-a-docs-convention-file-with-a-claude-fallback.md)
puts a structured team layer in a fenced `yaml config` block inside
`docs/conventions/<concern>.md`.

The maintainer's direction (2026-10-10, recorded on #6594) for config across plugins is: Markdown
for prose, YAML for pure config, one layout mirrored between user scope and project scope, and the
three scopes user-global (not committed), project (committed) and personal-in-project (not
committed). Routing-as-data already puts a plugin's team routing in `<home>/<plugin>.yaml`
([routing-as-data](../conventions/routing-as-data/README.md)), so a separate fenced block would split
one plugin's team config across two files.

## Decision

**Five layers, later wins per key:**

| Order | Layer | Location | Committed |
|---|---|---|---|
| 1 | plugin defaults | `plugins/<plugin>/reference/defaults.yaml` | shipped |
| 2 | userConfig scalar mirror | `settings.json` `pluginConfigs`, scalar keys only | no |
| 3 | user-global | `~/docs/conventions/<plugin>.{yaml,md}` | no |
| 4 | project team | `<home>/<plugin>.{yaml,md}`; `<home>` is the resolved convention home, default `docs/conventions` | yes |
| 5 | project personal | `<home>/<plugin>.local.{yaml,md}` | no, gitignored |

YAML files hold config and Markdown files hold prose. Files are flat, one pair per plugin per layer,
with no per-plugin subfolder.

**Merge rules.**

- Scalars: the later layer wins.
- `*.disable` lists: the union across layers, so a personal layer cannot quietly re-enable what the
  team disabled.
- An invalid value is rejected with a message, and the lower layer keeps the key.
- Keys a plugin declares team-only (`routing` for `user-interface`) are accepted in layer 4 alone
  and rejected in layers 2, 3 and 5, because a personal routing override would change which skill a
  whole team's agents reach for without review.
- Every resolved value carries its provenance: the layer that supplied it, or for a `*.disable`
  list every layer that contributed to the union, in layer order.
- Prose from layers 3, 4 and 5 is concatenated in that order.
- A design system detected in the project outranks every configured default.

**userConfig mirrors scalars only.** Layer 2 uses the same key vocabulary as the files, flattened
(`css_browser_target` for `css.browser_target`). List keys live only in files, because Claude Code's
`/config` editor does not show `multiple` options. A skill passes `${user_config.*}` values to its
scripts in a file written with the Write tool, never through a shell command line.

**One shared resolver.** `lib/config-cascade.mjs` with a canonical `lib/yaml-subset.mjs`, both
vendored into consuming plugins as generated copies under
[ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md). `resolve()` takes the
already-resolved convention home as input and spawns nothing: generated copies sit at different
relative paths in each plugin, so the caller resolves `<home>` through its own copy of
`lib/resolve-convention-home.sh`. The lib holds no plugin key names; callers pass their schema,
defaults and team-only keys. It returns values, per-key provenance, prose paths, per-layer state
(loaded, absent, invalid) and a report of legacy files, which gives setup a migration offer.

**`user-interface` is the first adopter.** Other plugins move onto the resolver in their own
changes, and the repo-wide decision on format and folder layout stays on #6594.

## Deviations

- **From the config-cascade convention's "What does not move".** The user-global layer moves from
  `~/.claude/<name>` to `~/docs/conventions/<plugin>.*`, and the overlay moves from
  `${CLAUDE_PROJECT_DIR}/.claude/<stem>.local.<ext>` to `<home>/<plugin>.local.*`. The convention
  has three layers; this cascade adds plugin defaults and a userConfig mirror as explicit layers.
  The merge semantics match the convention's.
- **From ADR 0044.** The structured team layer is a standalone `<home>/<plugin>.yaml` file, not a
  fenced `yaml config` block inside `docs/conventions/<concern>.md`, with no `.claude/<name>`
  fallback.

## Alternatives considered

- **Keep the convention's locations (`~/.claude/<name>`, `.claude/<stem>.local.<ext>`).** Rejected:
  other agents and tools do not read `.claude/`, and the maintainer asked for one layout mirrored
  between user scope and project scope.
- **A fenced config block in a convention doc, per ADR 0044.** Rejected for this plugin: its team
  routing already lives in `<home>/user-interface.yaml`, so a block would split one plugin's team
  config across two files.
- **A plugin-local resolver.** Rejected: there would be another resolver per plugin, which is the
  situation today, and the maintainer asked for one resolver every plugin honors.
- **The shared lib resolves the convention home itself.** Rejected: a sibling-relative spawn from a
  generated copy breaks in every plugin layout.
- **Mirror list keys in userConfig.** Rejected: `/config` hides `multiple` options, so the value
  would be invisible to the user who set it.
- **Accept `routing` in every layer.** Rejected: personal layers could reroute a team's agents
  without review.
- **Record this after the code ships.** Rejected: the cascade departs from a written convention, so
  reviewers of the resolver and the plugin config change need the rationale first.

## Consequences

- One parser and one resolver serve every adopting plugin. `user-experience`'s `yaml-subset.mjs`
  becomes a generated copy of `lib/yaml-subset.mjs`, and its suite moves to `lib/`.
- The config-cascade [Implementers](../conventions/config-cascade/README.md#implementers) table
  gains a `user-interface` row, stating this deviation, in the change that ships the plugin's
  config on `main`. Implementers rows describe `main`, never intent.
- Two layout shapes coexist until #6594 decides: plugins on `.claude/` paths and ADR 0044 blocks,
  and adopters of this cascade. The resolver's legacy-file report gives setup skills a migration
  path in either direction.
- `/user-interface:setup` writes the team layer at the resolved home, the user-global layer with
  `--user`, and the personal layer with `--local`, and adds the gitignore entry for `.local` files.
- A personal `.local` file lives in one checkout, so a new worktree starts without it. Setup's check
  warns when the main checkout has one and the worktree does not.

## Switch condition

Supersede this record when #6594 settles the repo-wide config format and folder layout. Move the
resolver's paths to that outcome; callers do not change, because no skill text names a layer path.
