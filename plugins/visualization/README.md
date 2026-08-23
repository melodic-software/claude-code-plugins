# visualization

A Claude Code plugin for on-demand visualization. One skill, one job: at any point
in a conversation, decide **what** is most worth showing visually and **how** to
show it, then render it — a form-and-medium router, not a craft teacher.

| Skill | What it does |
|---|---|
| `/visualization:visualize` | Infer the target from the conversation, pick a form (mermaid diagram, table, chart, ASCII/Unicode, or a rich page) and a medium (terminal, local HTML file, or published Artifact), and render it — asking only on genuine ambiguity |

## What it decides

Two decisions, then the output:

- **Form** — matched to the *shape* of the content: a mermaid diagram for flow /
  hierarchy / sequence / state / relationships; a markdown table for attribute
  comparison; a chart for quantities; ASCII/Unicode for a small structural sketch;
  a rich rendered page for a composite or interactive view; a hand-editable design
  canvas (via the bundled `design` skill, when that presence-gated preview is
  available) for a visual layout the user would rather tweak by hand.
- **Medium** — one of three ascending tiers, **inline terminal → local HTML file →
  published Artifact**, chosen by the form's weight, a configurable preference, and
  which surfaces are actually available.

The full grounded catalog — every mermaid family, the zero-dependency chart paths,
and the rendering-surface facts — lives in the skill's
[`context/decision-matrix.md`](skills/visualize/context/decision-matrix.md).

## Router, not craft

This skill decides the form and medium; it does **not** own the craft of a good
chart or the fundamentals of a good page. When a chart is the right form and a
chart-craft/dataviz capability is installed, it routes the craft there; when a rich
page is the right medium, the page's contract and design are owned by the Artifact
tool's own contract and an artifact-design capability. Each is invoked through its
capability when present and degrades to a documented fallback when absent — this
skill never restates their guidance.

It is also **not** a comprehension aid: restating dense text in plainer words is a
different concern. This skill is form-driven (render content as a visual), not
comprehension-driven.

```shell
/visualization:visualize                          # infer the target, auto-decide form and medium
/visualization:visualize this as a sequence       # honor a named form
/visualization:visualize file                     # render richer forms as a local HTML file, never published
/visualization:visualize artifact                 # prefer a published Artifact when that surface is available
```

## Surfaces and availability

A published Artifact is heavily gated (plan, sign-in, provider, version, and
context constraints); when it is unavailable the skill writes a self-contained
local HTML file instead, and if no page surface is available it degrades visibly to
the terminal. A ` ```mermaid ` fence in the terminal is shown as source, not a
rendered diagram. These facts and their sources are documented in the catalog.

## Configuration

- **`medium`** (`userConfig`, string, default `auto`). Preferred delivery medium
  when the skill auto-selects: `auto` (decide by content and available surfaces),
  `terminal` (always inline), `file` (rich forms as a local HTML file, never
  published off the machine), or `artifact` (prefer a published Artifact when
  available, else a local file, else terminal). An unrecognized value is reported
  and treated as `auto`. There is no native enum type for `userConfig`, so the
  allowed values are validated in-skill.

Configure with `/plugin configure visualization@<marketplace>`, or headless with
`claude plugin install visualization@<marketplace> -s <scope> --config
medium=<value>` — against an already-installed plugin that prints `already
installed` and still writes the value, verified on Claude Code 2.1.240 for a
non-sensitive option at `user` scope. Never uninstall to reconfigure: that drops
the whole stored `pluginConfigs` entry and resets every option to its manifest
default. No persistent state; no external prerequisites; no network calls of
its own.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install visualization@<marketplace>
```

## Possible future change

- **Third-party visualization server.** No credible egress-free, self-hostable
  visualization server exists to depend on today. Re-evaluate if one lands with a
  maintained security posture (a self-hosted AntV deployment is the current
  candidate) — until then the skill relies only on native rendering surfaces and
  the presence-gated craft capabilities.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `medium` | string | `"auto"` | `CLAUDE_PLUGIN_OPTION_MEDIUM` | Preferred delivery medium when the skill auto-selects. One of: 'auto' (decide by content and available surfaces), 'terminal' (always render inline, degrading richer forms to their best terminal approximation), 'file' (render richer forms as a self-contained local HTML file, never published off the machine), 'artifact' (prefer a published Artifact when that surface is available, else fall back to a local HTML file, else terminal). An unrecognized value is reported and treated as 'auto'. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure visualization@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install visualization@<marketplace> -s <scope> --config medium=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "visualization@<marketplace>": {
         "options": {
           "medium": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
