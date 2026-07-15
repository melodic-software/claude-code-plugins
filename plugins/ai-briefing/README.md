# ai-briefing

A repository- and organization-agnostic Claude Code plugin for source-backed AI-industry
briefings. It collects from official vendor publications, configured RSS/Atom feeds, GitHub
releases, reputable secondary reporting, and user-supplied URLs; then deduplicates, ranks,
and presents the result as markdown or an optional HTML/PPTX deck.

## Skills

| Skill | Invoke | What it does |
|---|---|---|
| `generate` | `/ai-briefing:generate` | Collects, cites, deduplicates, ranks, and emits a briefing; also supports `retro` and archive `search`. |
| `setup` | `/ai-briefing:setup` | Scaffolds or updates a source/profile configuration and optionally installs presentation dependencies. |

## Getting started

1. Enable the plugin and run `/ai-briefing:setup`.
2. Add authorized official feeds, GitHub release pages, reputable publications, and any
   user-supplied URLs to `.claude/ai-briefing/sources.md`.
3. Run `/ai-briefing:generate` for markdown output.
4. Before the first `--format html` or `--format slides` run, install the optional locked
   build toolchain with `/ai-briefing:setup --with-build-deps`.

## Optional build prerequisites

The presentation pipeline follows Playwright's current supported environment matrix:

- the latest Node.js 22.x, 24.x, or 26.x release, with npm;
- Windows 11+ or Windows Server 2019+;
- macOS 14 Sonoma or later; or
- Debian 12/13 or Ubuntu 22.04/24.04/26.04 on x86-64 or arm64.

Setup preflights Node, npm, and the OS family. On Linux, Playwright's documented
`install --with-deps` flow may invoke the system package manager and require elevation.
Unsupported or missing prerequisites are reported before the existing runtime is changed.
See [Playwright system requirements](https://playwright.dev/docs/intro#system-requirements).

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
`.claude/ai-briefing/<name>/` directory is a named overlay containing:

- `sources.md` for approved source URLs and feeds;
- optional `audience.md` for impact ranking;
- optional declarative `brand.json` and local assets for presentation branding.

Select a profile through the `active_profile` plugin option or a per-run
`--profile <name>` argument. The per-run argument wins. Claude Code renders the configured
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
