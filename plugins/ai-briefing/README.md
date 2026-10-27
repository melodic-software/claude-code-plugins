# ai-briefing

A repository- and organization-agnostic Claude Code plugin for source-backed AI-industry
briefings. It collects from official vendor publications, configured RSS/Atom feeds, GitHub
releases, reputable secondary reporting, and user-supplied URLs; then deduplicates, ranks,
and presents the result as markdown or an optional HTML/PPTX deck.

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

- the latest Node.js 22.x, 24.x, or 26.x release, with npm;
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

These are team-tracked profile files, not a gitignored `*.local.*` cascade
overlay. Selecting a named profile is profile selection, not cascade-layer
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

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `active_profile` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_ACTIVE_PROFILE` | Portable 1-63 character lowercase-kebab name of the ai-briefing profile to use; reserved Windows device names are not allowed. Leave unset when there is a single profile (or only the default). A per-invocation --profile <name> argument overrides this. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure ai-briefing@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install ai-briefing@<marketplace> -s <scope> --config active_profile=<value>
   ```

   Rerun the same command to change a value on an installed plugin, passing the scope
   `claude plugin list` reports for this plugin. Do **not** `claude plugin uninstall` to
   reconfigure: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
   The [`plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure) entry in the CLI reference covers applying a saved
   value. What a rerun prints and writes, and why a session started before the rerun keeps the
   old value until a fresh session starts, are recorded in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "ai-briefing@<marketplace>": {
         "options": {
           "active_profile": <value>
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
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
