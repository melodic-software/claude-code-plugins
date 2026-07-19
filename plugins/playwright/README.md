# playwright

A Claude Code plugin that wraps Microsoft's
[`@playwright/cli`](https://github.com/microsoft/playwright-cli) for
token-efficient live browser automation: named sessions,
accessibility-ref snapshots (click/fill by ref, not CSS selector),
screenshots, console and network capture, network mocking, tracing, video,
and auth-state persistence. Snapshots and screenshots write to disk and only
paths come back into context — roughly a 4x token reduction versus
Playwright MCP in upstream's measurement.

Invoke it with `/playwright:playwright`, or let Claude reach for it when you
ask for an E2E test, a screenshot, or any live browser flow.

## Prerequisite

`playwright-cli` on PATH:

```shell
npm install -g @playwright/cli
```

## What it provides

- **Quick-start conventions** — named sessions, clean start/teardown, element
  refs over selectors, disk-first artifacts.
- **Progressive disclosure** — a hub SKILL.md routes to topic reference files
  (commands, sessions, snapshots, storage/auth, tracing/video, network
  mocking, run-code, test generation) so only the relevant slice loads.
- **Original overlays** — empirically-verified Windows/Git Bash quirks (focus
  stealing, CWD-relative artifacts, anti-bot captchas) and a recipe for E2E
  against locally-orchestrated stacks (.NET Aspire, docker-compose, tilt),
  including Blazor hydration gotchas.
- **Vendored upstream baseline** — the skill directory Microsoft ships inside
  the npm package is bundled verbatim for drift detection.

## Works in any repo

- **Self-contained.** All reference material ships inside the plugin and is
  referenced via `${CLAUDE_PLUGIN_ROOT}`.
- **Reads your conventions, assumes none.** Artifacts land in
  `.playwright-cli/` relative to the working directory — add that to your
  `.gitignore`. Endpoints, orchestrators, and test placement come from your
  own project context.
- **Graceful degrade.** If your project has a broader test-orchestration
  skill or a committed `@playwright/test` suite, this skill slots in as the
  ad-hoc live driver; otherwise it stands alone.

## Update workflow (maintainers)

`/playwright:playwright update` runs the bundled drift-check script:
`--check` (default) compares the vendored baseline's recorded version against
the latest `@playwright/cli` npm release, read-only; `--apply` downloads the
tarball, refreshes `vendor/`, and bumps frontmatter metadata. Integrating
upstream changes into the distilled reference files stays a manual, reviewed
step, and the script never mutates a globally installed CLI. Run it in a
working-tree checkout of this plugin (the marketplace clone, or a directory
loaded via `--plugin-dir`) — consumers receive updates through
`/plugin marketplace update` once a new plugin version is published.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install playwright@melodic-software
```

Then verify prerequisites with `/playwright:setup check`.

## Configuration

This plugin has no `userConfig`. Behavior tuning happens through
`@playwright/cli`'s own flags and config surface (documented in the upstream
README inside the npm package); the skill deliberately recommends upstream
defaults.

## License

This plugin's original content is MIT (SPDX-License-Identifier: MIT) — see the
LICENSE file at the root of the melodic-software/claude-code-plugins
repository. The vendored upstream skill in `vendor/` (and the reference files
derived from it) are Microsoft's `@playwright/cli` content, licensed
Apache-2.0 (SPDX-License-Identifier: Apache-2.0) — the upstream license text
ships at `skills/playwright/vendor/LICENSE`.
