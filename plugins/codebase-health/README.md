# codebase-health

A Claude Code plugin for repo-wide drift auditing: it verifies that a codebase's **factual claims** in docs, config, code, and architecture notes still match reality. Every claim is checked against
ground truth via a parallel per-file subagent fan-out, findings are severity-rated, and the audit
reports them read-only. Remediation is delegated to the implementation/verification skills.

Diff/PR review judges a change. This plugin instead verifies whether the repo's own written claims
about itself are true.

Other kinds of drift belong to other skills. The audit skill's
[Boundary](skills/audit/SKILL.md#boundary-the-adjacent-drift-skills) section names seven of them
(whether a page deserves to exist or is fresh in a change under review, stale session assumptions,
currency against upstream docs, prose copied from an external source, Claude Code's own
configuration and instruction surfaces, and the placement and enforcement delta skills) with the
sibling that owns each. It reports such a request as uncovered and names that skill for the operator
to run, whether or not its plugin is installed, without invoking it.

| Skill | What it does |
|---|---|
| `/codebase-health:audit` | Runs the audit. Prime conventions, fan out claim-extraction per file, independently validate, severity-rate, and report read-only; remediation is delegated to the implementation/verification skills. |
| `/codebase-health:setup` | `check` inspects the audit-dimension config read-only across its layers and names any old-location file; `apply` moves an old file after a yes, interviews the user, infers targets from the layout, and writes the team file `<home>/codebase-health.md`. |

## The audit

Four phases (0–3): prime the repo's conventions, discover via per-file fan-out, validate each
finding (a separate agent re-verifies, never self-review, at the `standard` level after a fan-out
Phase 1 and always at `strict`; at the default `light`, and at `off`, no validator runs and the
findings are reported `unverified`), then categorize and present
in a severity-rated table with a verified-non-issues proof-of-thoroughness list, drift patterns, fix
priority, enforcement escalation, and config-gap observations. Bare invocation is read-only. It
reports and stops.

Remediation is not owned here. Fixing, verifying, self-reviewing, and retrospecting are delegated to
the dedicated skills: `/implementation:implement` (fix) and `/verification:confirm` (verify), used as
soft dependencies when those plugins are installed. The explicit `--fix` flag hands the Phase 3
findings off to those skills rather than fixing inline; when they are absent, the findings table is the
handoff and remediation is manual in the reported fix-priority order.

```shell
/codebase-health:audit                      # report-only audit of every configured dimension (scope-gated)
/codebase-health:audit docs/ --docs-only    # one dimension, scoped to a subtree, report-only
/codebase-health:audit README.md --fix      # scoped, then hand findings to the remediation skills
```

Dimension filters (`--docs-only`, `--code-only`, `--config-only`, `--arch-only`) are mutually
exclusive. A scope path narrows the file set. An unscoped whole-repo run is gated: the skill
requires a scope, a filter, or explicit confirmation before fanning out, because a full fan-out spans
every doc/config/source file.

In an interactive session with the `visualization` plugin installed, the audit ends its report with
an offer to render it through `/visualization:visualize`, and never builds a page itself.
The shared medium resolver (`lib/view-settings.mjs`, producer `codebase-health:audit`) decides the
offer from `--medium <value>`, the plugin's `medium` option and the `rendered-views` settings under
`docs/conventions/`. The audit prints the resolver's report line, `view: <medium> (<what decided
it>)`, and any notice. A `terminal` result drops the offer. The tracked team file,
`docs/conventions/rendered-views.yaml`, never publishes the view. The retired
`~/.claude/rendered-views.md` and `.claude/rendered-views*.md` files each get a notice naming the
new home; a `terminal` or `file` value in one still keeps the view local when no other setting
decides, and a publishing value there is ignored.

## Configurable audit dimensions

What the audit reads and how it verifies claims is **not baked in**. It comes from the consuming
repo's config, resolved additively across the
[config-cascade layers](reference/config.md#layers-and-resolution-order), where `<home>` is the
repository's convention home (default `docs/conventions`):

1. The file the `dimensions_file` option names: your own dimensions for every repository (optional)
2. `<home>/codebase-health.md`: team config (tracked)
3. `<home>/codebase-health.local.md`: personal override (gitignored)

The old files `~/.claude/codebase-health.md`, `.claude/codebase-health.md` and
`.claude/codebase-health.local.md` are still read while they exist, wherever the new location does
not supply that layer, and each run prints one warning naming the old file, its new location and
`/codebase-health:setup apply`, which moves it after a preview and your yes, then deletes it
([Old locations](reference/config.md#old-locations-dual-read-window)).

Each dimension declares `primary-sources` (globs where claims live), `verification-sources` (globs
where claims are checked against ground truth), and `example-claims` (concrete `{ claim, verify-via }`
rows that teach the extraction pass what drift looks like in THIS repo). The four bundled dimensions
are `documentation`, `configuration`, `code-quality`, and `architecture`; the config may tune their
globs, remove a dimension, or add custom ones.

When no config is present, the audit infers targets from the repo layout, uses them, and offers to
persist the inference via `/codebase-health:setup apply`, so the next run is deterministic. It never
hardcodes a repo's layout.

```shell
/codebase-health:setup check   # inspect the effective config read-only (default)
/codebase-health:setup apply   # move old files, interview + write <home>/codebase-health.md (re-runnable)
```

Add the recursive `<home>/**/*.local.*` line (`docs/conventions/**/*.local.*` for the default home)
to your `.gitignore` so personal overrides stay out of version control while team config stays
tracked.

## Consumer conventions

Phase 0 reads the consuming repo's own `CLAUDE.md` / `AGENTS.md` / `.claude/rules/` to learn what
"correct" looks like. A claim contradicting those conventions is a finding; one following them is a
verified non-issue. Nothing project-specific is baked into the plugin.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install codebase-health@melodic-software
```

## Configuration

Two `userConfig` options: `medium`, your own default for the rendered-view offer (default `auto`),
read by the shared medium resolver above; and `dimensions_file`, the audit-dimension file applied
in every repository. Audit targets flow through the tracked `<home>/codebase-health.md` config file
above (written by `/codebase-health:setup apply`). No hooks, no MCP servers, no bundled scripts
beyond the shared `lib/` copies (medium resolver, prerequisites check, verification reader,
convention-home resolver, retirement check), no network
calls of its own (Phase 2 may use whatever documentation-research tools your setup provides). State:
the audit reads and writes only the consumer's own files under the scope you give it.

A repository can commit `codebase-health.yaml` in its convention home (default `docs/conventions`)
to set these keys, checked against
[`schemas/codebase-health.schema.json`](schemas/codebase-health.schema.json):

| Key | Values | Default | What it controls |
|---|---|---|---|
| `verification`, `verification_skills.<skill>` | `off`, `light`, `standard`, `strict` | `light` | Whether `/codebase-health:audit` runs its Phase 2 false-positive gate as a separate subagent: `strict` dispatches it even after an inline Phase 1, `light` and `off` skip it and report the findings `unverified`. Read from the default branch only, through `lib/read-verification.sh`; a skill entry beats the plugin value ([verification level](../../docs/contracts/verification-level/README.md)). |

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `medium` | string | `"auto"` | Where the audit's optional rendered view goes, read by the shared medium resolver. auto (default): the view is offered and visualization:visualize picks the medium; terminal: no offer; file: local, never published; artifact or hosted: passed to visualization:visualize. |
| `dimensions_file` | file | *(none)* | A Markdown file of yours declaring audit dimensions (primary-sources, verification-sources, example-claims) for every repository, in the setup template's format. A repository's own codebase-health.md merges over it per dimension. |

### How to set these

Set the options above for `codebase-health@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
