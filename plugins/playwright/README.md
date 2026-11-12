# playwright

A Claude Code plugin that wraps Microsoft's
[`@playwright/cli`](https://github.com/microsoft/playwright-cli) for
token-efficient live browser automation: named sessions,
accessibility-ref snapshots (click/fill by ref, not CSS selector),
screenshots, console and network capture, network mocking, tracing, video,
and auth-state persistence. Snapshots and screenshots write to disk and only
paths come back into context, a substantial token reduction versus
Playwright MCP's in-context payloads.

Invoke it with `/playwright:playwright`, or let Claude reach for it when you
ask for an E2E test, a screenshot, or any live browser flow.

## Prerequisite

`playwright-cli` on PATH:

```shell
npm install -g @playwright/cli
```

Check it read-only with `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`; Claude can run that on its own, for example
when a prerequisites report lists `playwright-cli` as missing. It never installs.
`/playwright:setup apply install-cli` does the global install.

## What it provides

- **Quick-start conventions**: named sessions, clean start/teardown, element
  refs over selectors, disk-first artifacts.
- **Progressive disclosure**. A hub SKILL.md routes to topic reference files
  (commands, sessions, snapshots, storage/auth, tracing/video, network
  mocking, run-code, test generation) so only the relevant slice loads.
- **Original overlays**: empirically-verified Windows/Git Bash quirks (focus
  stealing, CWD-relative artifacts, anti-bot captchas) and a recipe for E2E
  against locally-orchestrated stacks (.NET Aspire, docker-compose, tilt),
  including Blazor hydration gotchas.
- **Vendored upstream baseline**. The skill directory Microsoft ships inside
  the npm package is bundled verbatim for drift detection.

## Demo videos for pull requests

`/playwright:demo-video` turns a web flow into a short produced MP4 for a PR:
it replays a written script with 4K capture, zooms in on each action, draws
the cursor and click ripples, captions each step, cuts out page loads, and
posts the result with `gh pr comment --attach` (or a CI artifact link).
`quality_control.py` checks the rendered frames (zoom share, text cut at the
frame edge, stillness, camera motion, cuts, crossfades, blank frames) and an independent
reviewer looks at the frames before anything is posted.

It needs Python 3.12+, `ffmpeg` and `ffprobe`, and `playwright-cli` for
recording. Its numpy and Pillow are hash-locked in
`skills/demo-video/requirements.txt`; a SessionStart hook installs them into
the plugin data directory, and a run before that prints the one install
command. The `demo_*` options in the reference below set the style and the
layers.

## Works in any repo

- **Self-contained.** All reference material ships inside the plugin and is
  referenced via `${CLAUDE_PLUGIN_ROOT}`.
- **Reads your conventions, assumes none.** Artifacts land in
  `.playwright-cli/` relative to the working directory. Add that to your
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
loaded via `--plugin-dir`). Consumers receive updates through
`/plugin marketplace update` once a new plugin version is published.
The marketplace also runs every vendored skill's check weekly in its
`maintenance-check-upstream-drift` workflow, which fails when upstream moves.

## Why this wraps the upstream skill

Verdict: keep the wrapper. Microsoft's own skill, `@playwright/cli` 0.1.23
(checked 2026-11-03; recheck when a newer `@playwright/cli` release changes its `SKILL.md`
description, length, or reference layout), falls short of the skill-authoring guidance this
marketplace follows:

- Its description is one short sentence with no trigger phrases, so the model
  has little to route on.
- Its `SKILL.md` body is 493 lines, close to the size the skill-authoring
  guidance tells authors to stay under, and carries the whole command reference
  inline, so every invocation loads all of it. For that size guidance, see
  [Skills: Add supporting files](https://code.claude.com/docs/en/skills#add-supporting-files).
- Seven of its ten reference files run past 100 lines (up to 433) with no
  contents list.

This wrapper is a 116-line hub with trigger phrases, routes to eleven
topic files that each carry a contents list when long, and adds gotchas
observed in the marketplace's browser-tools benchmark. Recheck when the
upstream version moves: if its skill closes these gaps, plan the switch
to it as its own change.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install playwright@melodic-software
```

Then verify prerequisites with `/playwright:setup check` or
`node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`.

## Configuration

The `demo_*` options below tune `/playwright:demo-video`. Browser behavior tuning happens through
`@playwright/cli`'s own flags and config file (documented in the upstream
README inside the npm package); the skill deliberately recommends upstream
defaults.

A repository can commit `playwright.yaml` in its convention home (default `docs/conventions`)
to set these keys, checked against
[`schemas/playwright.schema.json`](schemas/playwright.schema.json):

| Key | Values | Default | What it controls |
|---|---|---|---|
| `verification`, `verification_skills.<skill>` | `off`, `light`, `standard`, `strict` | `standard` | How much of `/playwright:demo-video`'s independent frame review (step 8) runs: `light` and `off` skip the quality judgment and report the video as not independently judged for quality, but the fresh-context check for secrets and personal data in the frames still runs and still gates posting. Read from the default branch only, through `lib/read-verification.sh`; a skill entry beats the plugin value ([verification level](../../docs/contracts/verification-level/README.md)). |

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `demo_style` | string | `"produced"` | Style of /playwright:demo-video output: produced (zoom on each action, captions, title card) or plain (the same replay and drawn cursor, no zoom, captions or title). |
| `demo_title` | boolean | `true` | Open the demo video with a title card. The plain style has none whatever this says. |
| `demo_camera` | boolean | `true` | Zoom and pan onto each action. The plain style has none whatever this says. |
| `demo_cursor` | boolean | `true` | Draw the pointer traveling to and clicking each target. |
| `demo_ripple` | boolean | `true` | Draw a ring around each clicked element. |
| `demo_captions` | boolean | `true` | Caption each step and its outcome. The plain style has none whatever this says. |
| `demo_narration` | boolean | `false` | Add a voice-over through /speech:narrate when the speech plugin is installed. Off by default. |

### How to set these

Set the options above for `playwright@<marketplace>`, replacing `<marketplace>` with the
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

This plugin's original content is MIT (SPDX-License-Identifier: MIT). The
vendored upstream skill in `vendor/` (and the reference files derived from it)
are Microsoft's `@playwright/cli` content, licensed Apache-2.0
(SPDX-License-Identifier: Apache-2.0). The upstream license text ships at
`skills/playwright/vendor/LICENSE`.
