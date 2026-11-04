# codebase-health

A Claude Code plugin for repo-wide drift auditing: it verifies that a codebase's **factual claims** in docs, config, code, and architecture notes still match reality. Every claim is checked against
ground truth via a parallel per-file subagent fan-out, findings are severity-rated, and the audit
reports them read-only. Remediation is delegated to the implementation/verification lanes.

Distinct from diff/PR review (which judges a change): this plugin verifies whether the repo's own
written claims about itself are true.

Other kinds of drift belong to other lanes. The audit skill's
[Boundary](skills/audit/SKILL.md#boundary-the-adjacent-drift-lanes) section routes seven of them
(doc drift in a change under review or in a repo-wide sweep, stale session assumptions, currency
against upstream docs, prose copied from an external source, Claude Code's own configuration and
instruction surfaces, and the placement and enforcement delta lanes) to the sibling that owns each,
presence-gated on that plugin being installed.

| Skill | What it does |
|---|---|
| `/codebase-health:audit` | Runs the audit. Prime conventions, fan out claim-extraction per file, independently validate, severity-rate, and report read-only; remediation is delegated to the implementation/verification lanes. |
| `/codebase-health:setup` | `check` inspects the tracked `.claude/codebase-health.md` config read-only across its merge layers; `apply` interviews the user, infers targets from the layout, and writes the config. |

## The audit

Four phases (0–3): prime the repo's conventions, discover via per-file fan-out, independently
validate each finding (a separate agent re-verifies, never self-review), then categorize and present
in a severity-rated table with a verified-non-issues proof-of-thoroughness list, drift patterns, fix
priority, enforcement escalation, and config-gap observations. Bare invocation is read-only. It
reports and stops.

Remediation is not owned here. Fixing, verifying, self-reviewing, and retrospecting are delegated to
the dedicated lanes: `/implementation:implement` (fix) and `/verification:confirm` (verify), used as
soft dependencies when those plugins are installed. The explicit `--fix` flag hands the Phase 3
findings off to those lanes rather than fixing inline; when they are absent, the findings table is the
handoff and remediation is manual in the reported fix-priority order.

```shell
/codebase-health:audit                      # report-only audit of every configured dimension (scope-gated)
/codebase-health:audit docs/ --docs-only    # one dimension, scoped to a subtree, report-only
/codebase-health:audit README.md --fix      # scoped, then hand findings to the remediation lanes
```

Dimension filters (`--docs-only`, `--code-only`, `--config-only`, `--arch-only`) are mutually
exclusive. A scope path narrows the file set. An unscoped whole-repo run is gated: the skill
requires a scope, a filter, or explicit confirmation before fanning out, because a full fan-out spans
every doc/config/source file.

In an interactive session with the `visualization` plugin installed, the audit ends its report with
an offer to render it through `/visualization:visualize`, and never builds a page itself.
The shared medium resolver (`lib/view-settings.mjs`, lane `codebase-health:audit`) decides the
offer from `--medium <value>`, the plugin's `medium` option and the `rendered-views` settings under
`docs/conventions/`. The audit prints the resolver's report line, `view: <medium> (<what decided
it>)`, and any notice. A `terminal` result drops the offer. The tracked team file,
`docs/conventions/rendered-views.yaml`, never publishes the view. The retired
`~/.claude/rendered-views.md` and `.claude/rendered-views*.md` files each get a notice naming the
new home; a `terminal` or `file` value in one still keeps the view local when no other setting
decides, and a publishing value there is ignored.

## Configurable audit dimensions

What the audit reads and how it verifies claims is **not baked in**. It comes from the consuming
repo's tracked config, resolved additively across three layers:

1. `~/.claude/codebase-health.md`. User-global base (optional)
2. `.claude/codebase-health.md`. Team config (tracked)
3. `.claude/codebase-health.local.md`. Personal overlay (gitignored)

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
/codebase-health:setup apply   # interview + write .claude/codebase-health.md (re-runnable)
```

Add the recursive `.claude/**/*.local.*` line to your `.gitignore` so personal overlays stay out of version control while
team config stays tracked.

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

One `userConfig` option, `medium`: your own default for the rendered-view offer (default `auto`),
read by the shared medium resolver above. Audit targets flow through the tracked
`.claude/codebase-health.md` config seam above (written by `/codebase-health:setup apply`). No
hooks, no MCP servers, no bundled scripts beyond the shared `lib/` copies (medium resolver, prerequisites check), no network
calls of its own (Phase 2 may use whatever documentation-research tools your setup provides). State:
the audit reads and writes only the consumer's own files under the scope you give it.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `medium` | string | `"auto"` | `CLAUDE_PLUGIN_OPTION_MEDIUM` | Where the audit's optional rendered view goes, read by the shared medium resolver. auto (default): the view is offered and visualization:visualize picks the medium; terminal: no offer; file: local, never published; artifact or hosted: passed to visualization:visualize. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure codebase-health@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure codebase-health@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"medium": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install codebase-health@<marketplace> -s <scope> --config medium=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "codebase-health@<marketplace>": {
         "options": {
           "medium": <value>
         }
       }
     }
   }
   ```

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
