# github

A Claude Code plugin for the **GitHub settings/admin plane**: audit, review, advise, and guided
setup/management for the authenticated user across organizations, repositories, and enterprises.
It covers consistency, drift, standards conformance, and cost control.

Everything is grounded at runtime: live state comes from the consumer's own `gh` CLI session, and
mechanics come from freshly fetched official GitHub documentation. The plugin ships **zero vendored
GitHub knowledge**: no endpoint tables, scope lists, or prices, so it cannot go stale against
GitHub's weekly-moving surface. Where a fetch fails or an area is out of the current credential's
reach, the skills say so honestly instead of guessing.

| Skill | Status | What it does |
|---|---|---|
| `/github:audit <area…> [--apply]` | shipped | Read-only findings over one, several, or all coverage areas: current-state review, drift vs declared conventions, standards conformance, cost signals. |
| `/github:advise <topic> [--apply]` | shipped | Forward-looking guidance and hand-holding ("how should I configure X", "walk me through Y"), plus proactive in-session suggestions. |
| `/github:setup` | shipped | Verify prerequisites (`gh` present and authenticated, config layers) and write consumer config. `check` and `apply`, user-invoked only. |

Areas are **arguments, not skills**. The coverage matrix (rulesets, billing, security model,
Actions policy, webhooks, packages, and the rest) lives in
[`reference/areas.md`](reference/areas.md), and every area routes through the same
[`reference/method-ladder.md`](reference/method-ladder.md). Primary-tier areas additionally carry
a dedicated method recipe under [`reference/recipes/`](reference/recipes/). Those recipes hold curated audit
checklists, drift procedures, and posture heuristics, still with zero vendored GitHub mechanics.

## Verb contract

This plugin follows the marketplace verb grammar: `audit` is a read-only findings report. A bare
invocation performs **zero mutations** (no write-capable `gh api` flags, no non-GET methods, no
GraphQL mutations). It additionally declares one new verb at this coupling site:

- **`advise`** is read-only advisory guidance. Distinct discovery intent from `audit`:
  design/forward-looking ("how should I…") where `audit` is current-state/backward-looking
  ("what is…", "what drifted…").

Mutation is only ever reachable behind the explicit `--apply` override argument, resolves through
the consumer's declared change routing (the `--apply` resolution flow in
[`reference/change-routing.md`](reference/change-routing.md)), and keeps the user in the loop for
every write.

## Prerequisites

- **`gh` CLI, authenticated by you.** The plugin uses your own `gh` session and never stores
  credentials. When a token scope or credential modality cannot reach an area, the skill names the
  gate and recommends the remediation for you to run yourself.

## Consumer configuration

Unconfigured consumers work read-only out of the box: change routing defaults to **propose-only**
(proposed changes are emitted as exact commands or diffs, never executed). Consumer config lives in
`.claude/github/` and layers user-global → team → local overlay:

- [`reference/change-routing.md`](reference/change-routing.md). `routing.yaml`: how proposed
  changes leave the session (`propose` / `guided-apply` / `handoff`), with a team policy floor on
  write-posture keys that personal layers can tighten but never loosen.
- [`reference/conventions-file.md`](reference/conventions-file.md). `conventions.md`: the
  declared standards your audits compare against.

For settings surfaces that turn out to be UI-only (no CLI, no API), the skills may **offer**
opt-in browser automation over your own authenticated session. Never auto-fired, every action
individually confirmed, mechanics in
[`reference/browser-automation.md`](reference/browser-automation.md). One plugin setting,
`offer_browser_automation` (boolean, default `true`, prompted when you enable the plugin),
suppresses the offer when `false`. That is an advisory gate honored by the skills, not a runtime
kill-switch; the hard gate is the per-action user confirm. Guided manual steps with a deep link
remain the always-available fallback.

`/github:setup` writes both files interactively and recommends the one-line recursive overlay
gitignore (`.claude/**/*.local.*`); it never edits your `.gitignore`.

## Install

From whichever marketplace distributes this plugin:

```shell
/plugin marketplace add <marketplace-owner>/<marketplace-repo>
/plugin install github@<marketplace-name>
```

## Configuration

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `offer_browser_automation` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_OFFER_BROWSER_AUTOMATION` | When a settings surface is UI-only, offer opt-in browser automation (never auto-fired; every action individually confirmed). Set false to suppress the offer entirely. Advisory: honored by the skills' prose, layered under the per-action confirm. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure github@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure github@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"offer_browser_automation": "<value>"}
   ```

   This is the preferred headless route in this marketplace's plugin-reconfiguration convention (`docs/contracts/plugin-reconfiguration/README.md`), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install github@<marketplace> -s <scope> --config offer_browser_automation=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "github@<marketplace>": {
         "options": {
           "offer_browser_automation": <value>
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
