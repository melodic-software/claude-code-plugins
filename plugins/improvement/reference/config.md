# improvement: consumer configuration

The single home for the `improvement` plugin's config-key contract. The surface resolves through
the four layers of the marketplace's
[config-cascade contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#the-layers).
It is read by `/improvement:find` for Tier 2 evidence-source resolution, the hotspot recipe's
churn window and exclusion patterns, and the unattended run controls, and verified/written by
`/improvement:setup`. All layers are optional: **zero config is a fully working state**. Tier 0
repo-native evidence needs nothing declared, and an absent Tier 2 declaration is a recorded
evidence gap in the finder's report, never an error.

## Layers and resolution order

Four layers, lowest first, where a later layer refines an earlier one:

| Order | Layer | Source | Version control |
|---|---|---|---|
| 0 | plugin default | the Default column of [Keys](#keys) | n/a |
| 1 | `userConfig` | the plugin's `userConfig` option for the key ([userConfig options](#userconfig-options)), per person, across repositories | outside the worktree, so no git verdict applies |
| 2 | team | `<home>/improvement.yaml`, validated by [`schemas/improvement.schema.json`](../schemas/improvement.schema.json) | must be tracked, the only layer teammates receive |
| 3 | personal | `<home>/improvement.local.yaml`, same schema | must be gitignored, never staged |

`<home>` is the convention home the pointer region of `AGENTS.md` or `CLAUDE.md` binds, else
`docs/conventions` ([config locations](config-locations.md)). Resolution anchors at the repository
root (`<root>`), `git rev-parse --show-toplevel`, never at the CWD; `<home>` is relative to it. When that root is `$HOME`, an ancestor of
`$HOME`, or not inside a git working tree, the team and personal layers are not applicable: report
both with that reason and resolve the default and `userConfig` only.

Every layer that exists is read and merged; reading one layer and stopping is not resolution. A
malformed layer degrades soft: name the file, key and value, and resolve as if that layer were
absent, so a valid higher layer still wins, otherwise the default. Unknown keys are inert. Whenever
the effective config is surfaced to a human, report which layer supplied each value.

### userConfig options

Each key in [Keys](#keys) has a `userConfig` option of the same name, except `evidence_sources`:
a nested map that `userConfig` cannot hold, so its option is `evidence_sources_file`, a `file`
option naming a YAML file of the user's whose top-level `evidence_sources` key has the shape below.
The options have no manifest default: an option that reads empty, or still reads as a literal
`${user_config.…}` placeholder, is unset and supplies nothing. `${user_config.KEY}` is substituted
only in skill content, so each skill that reads this surface carries the option values in its own
`SKILL.md`. Values are set through Claude Code's plugin configuration
(`/plugin configure improvement@<marketplace>`); no skill writes `pluginConfigs` or user settings.

## Old locations (dual-read window)

Before this surface adopted the four layers it read three other files. While one of them exists,
it is still read, and a run that finds one prints **one** warning line naming each old file found,
the location to move it to, and `/improvement:setup apply`, which moves it:

| Old path | Read as | Moves to |
|---|---|---|
| `~/.claude/improvement.md`: one Read of that literal path, `~` kept; never Glob for it, spell out a home directory, or search the home tree | the `userConfig` layer, for each key whose option is unset | the `userConfig` options ([userConfig options](#userconfig-options)) |
| `<root>/.claude/improvement.md` | the team layer, when `<home>/improvement.yaml` is absent | `<home>/improvement.yaml` |
| `<root>/.claude/improvement.local.md` | the personal layer, when `<home>/improvement.local.yaml` is absent | `<home>/improvement.local.yaml` |

An old file uses the old format: Markdown holding one fenced `yaml` block with the keys below. When
the new location also supplies that layer, the new one wins, and the warning lists each key the old
file sets that therefore does not apply, so no old setting is dropped silently: for the team and
personal files it names both files; for `~/.claude/improvement.md` it names the options already
set. The old team and personal files take the root rule and the tracked and ignored verdicts of the
layer they stand in for, so at a root that is `$HOME` they are not read as team or personal layers.

The repository-scope window is declared by the plugin's retirement records,
[`retirements.yaml`](../retirements.yaml): `improvement-r001` (`.claude/improvement.md`) and
`improvement-r002` (`.claude/improvement.local.md`), both `migrate`, evaluated by
`lib/check-retirements.sh` from `/improvement:setup`, always with `--root <root>` so the helper
checks the same root as every other read (left out, it checks `${CLAUDE_PROJECT_DIR}` first). `~/.claude/improvement.md` is machine scope,
outside that mechanism, so setup detects it with its own Read. Removing these reads is a separate
later change (demoting the records to `report-only`), made once no run reports an old file.

## Merge semantics

Declared here per the cascade convention: **per-key override, with two declared list
refinements and one ceiling.**

- **Scalar keys** (`churn_window`, `churn_exclude_defaults`, and every `find_*` key except
  `find_open_item_cap`): a later layer replaces the value key by key; a key absent from a later
  layer keeps the earlier layer's value.
- **`find_open_item_cap`** is a ceiling personal settings can only lower. The team layer's value,
  else the bundled default, sets it. The `userConfig` and personal layers each apply only
  when lower, so the effective cap is the smallest of the three. A higher personal value is ignored
  and reported.
- **`churn_exclude`**: entries **union** across layers, and with the mechanical files resolved from
  the repository unless `churn_exclude_defaults: false`. A later layer adds patterns; it never silently drops an
  earlier layer's.
- **`evidence_sources`** merges **per source name**: a later layer's entry for source X
  replaces X only. A later layer declaring a source name with an empty body is an explicit
  opt-out that removes the inherited source (reported as removed, not broken).

Wholesale replacement of an earlier layer is forbidden.

## File format

The team and personal files are plain YAML. The `evidence_sources_file` a `userConfig` option names
holds only the `evidence_sources` key, in the same shape.

```yaml
churn_window: "90 days ago"
churn_exclude:
  - '(^|/)generated/'
  - '(^|/)fixtures/recorded/'
churn_exclude_defaults: true
find_open_item_cap: 5
find_run_item_cap: 3
find_run_item_cap_floor: 1
find_run_item_cap_ceiling: 5
find_size_band: all
find_scope: repo
find_suppress_dismissed: true
evidence_sources:
  app-telemetry:
    mcp_server: my-observability-mcp
    kind: metrics
    scope: production web tier
    hints: start with request failure rate and p95 latency
```

## Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `churn_window` | string accepted by `git log --since`, made of letters, digits, spaces and `.:,/+-` only | `"90 days ago"` | The hotspot recipe's change-frequency window, its main tuning knob. A value with any other character is malformed and never reaches the command. The recipe's history-depth gate still applies: a window the history does not cover shrinks or downgrades to an evidence gap regardless of this value. |
| `churn_exclude` | list of ERE patterns | `[]` | Extra patterns matched against paths from `git log --name-only` and excluded from churn counting. Unioned across layers and with the mechanical files resolved from the repository. |
| `churn_exclude_defaults` | boolean (`true` \| `false`, since bare `on`/`off` is the YAML 1.1 coercion footgun and is not accepted) | `true` | `false` drops the exclusions resolved from the repository (the lockfiles, generated or minified output, snapshots and vendored trees its `.gitattributes`, build and manifest files show: the hotspot recipe's Step 2), leaving only declared patterns. The plugin ships no exclusion list. |
| `find_open_item_cap` | non-negative integer | `5` | Applied to each source label on its own (`source: improvement-find`, `source: architecture-improve`): unattended `/improvement:find` files nothing under a label while the open items carrying it number at or above this, and otherwise files no more than the room left under it. A hard stop the invocation prompt cannot raise, and personal layers can only lower ("Merge semantics"); `0` stops all unattended filing. A value that is not a non-negative integer is malformed: that layer's value is ignored and reported. |
| `find_run_item_cap` | positive integer | `3` | Where the adaptive per-run filing cap starts: how many items one unattended run files, across all source labels. |
| `find_run_item_cap_floor`, `find_run_item_cap_ceiling` | positive integers | `1`, `5` | The range that cap adapts within. Floor, start and ceiling must ascend (equal is allowed); otherwise all three take their defaults and the conflict is reported. |
| `find_size_band` | `all` \| `small` \| `medium` \| `large` | `all` | The candidate sizes an unattended run ranks. |
| `find_scope` | `repo`, or a target in the form `/improvement:find` accepts | `repo` | What an unattended run scans. |
| `find_suppress_dismissed` | boolean (`true` \| `false`) | `true` | Whether an unattended run suppresses candidates an operator dismissed before. |
| `evidence_sources` | mapping of named source declarations | `{}` | Tier 2 application-telemetry declarations, one entry per source (sub-keys below). Empty or absent means Tier 2 is an evidence gap. |

The run cap, size band, scope and dismissed-candidate keys apply to unattended runs and resolve in
the order invocation prompt, then config, then default. A value outside a key's stated type is
malformed: that layer's value is ignored and reported. Cadence and time of day have no key: the
scheduler that fires the run owns them.

### `evidence_sources.<name>` sub-keys

| Sub-key | Required | Values | Meaning |
|---|---|---|---|
| `mcp_server` | yes | MCP server name | The server as named in the consumer's own MCP configuration. The plugin declares which server carries telemetry; it never ships, installs, or configures one, and never hardcodes a vendor. |
| `kind` | no | `metrics` \| `logs` \| `errors` \| `traces` \| `events` | What class of evidence the source yields, guiding which scan dimensions consume it. |
| `scope` | no | prose | What product surface the source covers (e.g. "production web tier"). |
| `hints` | no | prose | Where to start: key queries, dashboards, or tables worth reading first. |

At find-time every declared source is probed presence-gated: when the named MCP server is not
available in the session, that source becomes a recorded evidence-gap line for the run, never a
hard error and never a fabricated reading.

## Consumer `.gitignore`

This recursive line ignores the personal file, written out for the default home:

```gitignore
docs/conventions/**/*.local.*
```

Write the bound `<home>` in place of `docs/conventions`. While an old
`.claude/improvement.local.md` exists, `.claude/**/*.local.*` keeps it ignored.
`/improvement:setup` recommends these lines; no plugin writes the consumer's `.gitignore`.
