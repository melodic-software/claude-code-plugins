# firecrawl

A Claude Code plugin that wraps the [`firecrawl-cli`](https://www.npmjs.com/package/firecrawl-cli)
binary as an agent skill for web scraping, search, crawling, URL discovery,
browser interaction, and local file parsing, with a core discipline: every
non-trivial result is written to disk with `-o <path>` and selectively `Read`
back, instead of streaming tens of thousands of tokens into the conversation.

Invoke it with `/firecrawl:firecrawl <command>` (scrape, search, crawl, map,
parse, interact, agent, monitor, and more), or let Claude reach for it when a
plain fetch is blocked by anti-bot protection or a page needs JS rendering.

## What it provides

- **Fourteen CLI subcommands** routed through one skill, with a decision table for
  when to escalate from a plain fetch to a managed scrape and when NOT to
  spend Firecrawl credits at all.
- **Write-to-disk pattern**. Examples for scrape/search/interact all land in
  tempfiles the agent reads selectively; direct stdout is reserved for tiny
  results.
- **Reference tables** for every flag and configuration knob under `context/`.
- **A gated maintainer update skill**. `/firecrawl:update --check` reports CLI
  version drift and upstream skill-source drift read-only; the full update
  path puts `npm install` and any skill-content integration behind explicit
  approval gates, with a recorded rollback version in `upstream.md`. It lives
  as a sibling skill so the wrapper stays user-facing.

## Revisit condition

`parse` (local-file extraction) is one of the fourteen subcommands behind the single
`/firecrawl:firecrawl` skill. Consolidation over per-subcommand proliferation.
Split it into a dedicated `parse` skill only if local-file extraction discovery
demonstrably fails under the general skill, or a non-credit extraction backend
appears worth its own skill.

## Requirements

- `firecrawl-cli` on PATH (`npm install -g firecrawl-cli`). The skill flags a
  missing CLI in its status line; the install is one command when first needed.
- An authenticated CLI: `firecrawl --status` reports authenticated. Prefer a
  `FIRECRAWL_API_KEY` from the [Firecrawl dashboard](https://firecrawl.dev), set
  as an OS user environment variable or injected into the CLI process by a
  wrapper, over `firecrawl login`/`firecrawl config`, which write a second
  source of truth.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install firecrawl@melodic-software
```

Then verify prerequisites with `/firecrawl:setup check`.

## Configuration

This plugin has no `userConfig`. The CLI reads `FIRECRAWL_API_KEY`,
`FIRECRAWL_API_URL` (self-hosted override), and `FIRECRAWL_NO_TELEMETRY` from
the environment; everything else is per-call flags. Normal skill invocations
call the Firecrawl API through the CLI; the maintainer-facing update script
additionally reaches `registry.npmjs.org` and `www.firecrawl.dev`.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `cli_update_hint` | string | *(none)* | Optional text shown when the daily check finds this plugin's CLI behind its latest release, such as how your machines update it. Empty shows only the version line. |

### How to set these

Set the options above for `firecrawl@<marketplace>`, replacing `<marketplace>` with the
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
