# ai-briefing

A repository- and organization-agnostic Claude Code plugin for source-backed AI-industry
briefings. It collects from official vendor publications, configured RSS/Atom feeds, GitHub
releases, reputable secondary reporting, and user-supplied URLs; then deduplicates, ranks,
and presents the result as markdown or an optional HTML/PPTX deck.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install ai-briefing@melodic-software
```

## Skills

| Skill | Invoke | What it does |
|---|---|---|
| `generate` | `/ai-briefing:generate` | Collects, cites, deduplicates, ranks, and emits a briefing; also supports `retro` and archive `search`. |
| `setup` | `/ai-briefing:setup` | Verifies (`check`) or scaffolds (`apply`) a source/profile configuration, and on `apply install-build-deps` installs the presentation build toolchain. |

## Getting started

1. Enable the plugin and run `/ai-briefing:setup` to verify state, then `/ai-briefing:setup apply` to scaffold the profile.
2. Add authorized official feeds, GitHub release pages, reputable publications, and any
   user-supplied URLs to `.claude/ai-briefing/sources.md`.
3. Run `/ai-briefing:generate` for markdown output.
4. Before the first `--format html` or `--format slides` run, install the optional locked
   build toolchain with `/ai-briefing:setup apply install-build-deps`.

## Optional build prerequisites

The presentation pipeline follows Playwright's current supported environment matrix. The matrix
moves with Playwright releases, so re-check
[Playwright system requirements](https://playwright.dev/docs/intro#system-requirements)
before installing. As verified on 2026-07-18, the pipeline requires:

- the latest Node.js 24.x or 26.x release, with npm (unpdf 2.x needs Node.js 24 or later);
- Windows 11+ or Windows Server 2019+;
- macOS 14 Sonoma or later; or
- Debian 12/13 or Ubuntu 22.04/24.04/26.04 on x86-64 or arm64.

Setup preflights Node, npm, and the OS family. On Linux, Playwright's documented
`install --with-deps` flow may invoke the system package manager and require elevation.
Unsupported or missing prerequisites are reported before the existing runtime is changed.

The `setup apply install-build-deps` install step is a POSIX-shell script: it requires
Bash. On native Windows that is Git Bash (its platform gate accepts
`MINGW*`/`MSYS*`/`CYGWIN*`; install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)).
The build pipeline itself is portable Node and has no shell requirement.

## Source access policy

Automated X/Twitter collection is disabled. The plugin does not scrape profiles, timelines,
search results, or following graphs and does not configure a paid X API. If a user supplies
an X URL, the skill may preserve the URL and user-provided context but must not
programmatically retrieve the page; it should seek a non-X primary source for corroboration.
This follows the current [X Terms of Service](https://x.com/en/tos), which prohibit crawling
or scraping without prior written consent.

Playwright remains an optional local rendering dependency. It opens generated local HTML for
deterministic PDF generation and layout validation; it is not a collection provider.

## Profiles and configuration

Files at `.claude/ai-briefing/` form the default profile. Each
`.claude/ai-briefing/<name>/` directory is a named profile containing:

- `sources.md` for approved source URLs and feeds;
- optional `audience.md` for impact ranking;
- optional declarative `brand.json` and local assets for presentation branding.

These are team-tracked profile files, not a gitignored `*.local.*` personal
override. Selecting a named profile is profile selection, not cascade-layer
resolution. Select a profile through the `active_profile` plugin option or a
per-run `--profile <name>` argument. The per-run argument wins. Claude Code renders the configured
option into the skill; the skill then explicitly sets `AI_BRIEFING_PROFILE` on each launched
build process. Users do not need to export an environment variable globally.
Profile names must be portable 1-63 character lowercase-kebab slugs (for example,
`engineering-leads`) and cannot use reserved Windows device names, following Microsoft's
[cross-platform file-naming rules](https://learn.microsoft.com/windows/win32/fileio/naming-a-file#naming-conventions).
`brand.json` is strict declarative data. Logo paths must resolve to regular files inside the
selected profile directory; the resolver uses Node's
[`fs.realpathSync`](https://nodejs.org/api/fs.html#fsrealpathsyncpath-options) so symlinks
cannot escape that boundary.

Machine-local state and generated artifacts live under `${CLAUDE_PLUGIN_DATA}`, keyed by
profile. Tracked source, audience, and brand configuration always stays in the consumer
repository.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `active_profile` | string | *(none)* | Portable 1-63 character lowercase-kebab name of the ai-briefing profile to use; reserved Windows device names are not allowed. Leave unset when there is a single profile (or only the default). A per-invocation --profile <name> argument overrides this. |

### How to set these

Set the options above for `ai-briefing@<marketplace>`, replacing `<marketplace>` with the
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

As of 2026-11-04. Recheck trigger: one of these sections moves, or a Claude Code
release note changes how plugin options are set or stored.

<!-- END GENERATED: plugin options -->
