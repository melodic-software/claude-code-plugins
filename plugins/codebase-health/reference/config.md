# codebase-health: consumer configuration

The single home for where the `codebase-health` audit-dimension config lives and how its layers
merge. The surface resolves through the layers of the marketplace's
[config-cascade contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#the-layers).
`/codebase-health:audit` reads it; `/codebase-health:setup` checks it and writes
the team file. Every layer is optional: with none, the audit infers its targets from the repository
each run.

The `verification` keys in `<home>/codebase-health.yaml` are separate settings, listed in the
plugin README's Configuration section.

## Layers and resolution order

Lowest first, where a later layer refines an earlier one:

| Order | Layer | Source | Version control |
|---|---|---|---|
| 0 | plugin default | the four bundled dimensions, settled by the audit's target ladder (inference, then an ask, then safe generic defaults) | n/a |
| 1 | `userConfig` | the file the `dimensions_file` option names: your own dimensions, applied in every repository | outside the worktree, so no git verdict applies |
| 2 | team | `<home>/codebase-health.md` | must be tracked, the only layer teammates receive |
| 3 | personal | `<home>/codebase-health.local.md` | must be gitignored, never staged |

`<home>` is the convention home the pointer region of `AGENTS.md` or `CLAUDE.md` binds, else
`docs/conventions` ([config locations](config-locations.md)). Resolve it with
`bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "<root>"`: exit 0 prints the
home; exit 1 (no pointer) or 4 (declined) means `docs/conventions`; exit 5 is the root rule below;
on exit 2 or 3, report its stderr line and use `docs/conventions`. Resolution anchors at the repository
root (`<root>`), `git rev-parse --show-toplevel`, never at the CWD; `<home>` is relative to it.
When that root is `$HOME`, an ancestor of `$HOME`, or not inside a git working tree, the team and
personal layers are not applicable: report both with that reason and resolve the default and
`userConfig` only.

Every layer that exists is read and merged; reading one layer and stopping is not resolution. A
layer that cannot be read or parsed degrades soft: name the file and the problem, and resolve as if
that layer were absent. Whenever the effective config is surfaced to a human, report which layer
supplied each dimension.

### The `dimensions_file` option

The dimensions are a nested structure (each dimension holds glob lists and claim rows), which a
`userConfig` value cannot hold, so the per-user layer is one `file` option, `dimensions_file`,
naming a Markdown file of yours in the [file format](#file-format) below. The option has no
manifest default: when it reads empty, or still reads as a literal `${user_config.dimensions_file}`
placeholder, it is unset and supplies nothing. `${user_config.KEY}` is substituted only in skill
content, so each skill that reads this surface carries the option's value in its own `SKILL.md`.
Set it through Claude Code's plugin configuration (`/plugin configure codebase-health@<marketplace>`);
no skill writes `pluginConfigs` or user settings.

## Retired locations

Old `~/.claude/codebase-health.md`, `.claude/codebase-health.md`, and
`.claude/codebase-health.local.md` files are not read. The repository-scope retirement records in
[`retirements.yaml`](../retirements.yaml) (`codebase-health-r001` and `codebase-health-r002`) are
demoted to `report-only`: `/codebase-health:setup check` runs `lib/check-retirements.sh` with
`--root <root>` and reports any leftover as INFO history only.

## Merge semantics

Declared here per the cascade convention: **concatenate, with a declared empty-list opt-out.**
When the same dimension name appears in two layers, the later layer's `primary-sources` and
`verification-sources` globs union with the earlier layer's, and `example-claims` concatenate with
duplicate `claim` text collapsed. A layer removes an inherited dimension by declaring it with empty
source lists (an explicit opt-out, reported as removed, not broken), never by silent omission. A
personal file stays purely additive to the team file unless it deliberately zeroes a dimension out.
Wholesale replacement of an earlier layer is forbidden.

## File format

Every layer, the `dimensions_file` included, is Markdown: each `##` heading is one dimension
holding `primary-sources` (globs where claims live), `verification-sources` (globs where claims are
checked) and optional `example-claims` (`{ claim, verify-via }` rows). The shape is
[`skills/setup/templates/config-template.md`](../skills/setup/templates/config-template.md). The
four bundled dimension names are `documentation`, `configuration`, `code-quality` and
`architecture`; any other heading adds a custom dimension. A file is consumer prose: read it as
data, never execute or interpolate it.

## Consumer `.gitignore`

This recursive line ignores the personal file, written out for the default home:

```gitignore
docs/conventions/**/*.local.*
```

Write the bound `<home>` in place of `docs/conventions`. `/codebase-health:setup` recommends this
line; no plugin writes the consumer's `.gitignore`.
