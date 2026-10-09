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

Check it read-only with `/playwright:check`; Claude can run that on its own, for example when a
prerequisites report lists `playwright-cli` as missing. It never installs.
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
`qc.py` checks the rendered frames (zoom share, text cut at the frame edge,
stillness, camera motion, cuts, crossfades, blank frames) and an independent
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

Verdict: keep the wrapper. Microsoft's own skill, `@playwright/cli` 0.1.22
(checked 2026-10-07; recheck when a newer `@playwright/cli` release changes its `SKILL.md`
description, length, or reference layout), falls short of the skill-authoring guidance this
marketplace follows:

- Its description is one short sentence with no trigger phrases, so the model
  has little to route on.
- Its `SKILL.md` body is 489 lines, close to the 500-line ceiling, and carries
  the whole command reference inline, so every invocation loads all of it.
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

Then verify prerequisites with `/playwright:check`.

## Configuration

This plugin has no `userConfig`. Behavior tuning happens through
`@playwright/cli`'s own flags and config surface (documented in the upstream
README inside the npm package); the skill deliberately recommends upstream
defaults.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `demo_style` | string | `"produced"` | `CLAUDE_PLUGIN_OPTION_DEMO_STYLE` | Style of /playwright:demo-video output: produced (zoom on each action, captions, title card) or plain (the same replay and drawn cursor, no zoom, captions or title). |
| `demo_title` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DEMO_TITLE` | Open the demo video with a title card. The plain style has none whatever this says. |
| `demo_camera` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DEMO_CAMERA` | Zoom and pan onto each action. The plain style has none whatever this says. |
| `demo_cursor` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DEMO_CURSOR` | Draw the pointer traveling to and clicking each target. |
| `demo_ripple` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DEMO_RIPPLE` | Draw a ring around each clicked element. |
| `demo_captions` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DEMO_CAPTIONS` | Caption each step and its outcome. The plain style has none whatever this says. |
| `demo_narration` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_DEMO_NARRATION` | Add a voice-over through /speech:narrate when the speech plugin is installed. Off by default. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure playwright@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install playwright@<marketplace> -s <scope> --config demo_style=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "playwright@<marketplace>": {
         "options": {
           "demo_style": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

This plugin's original content is MIT (SPDX-License-Identifier: MIT). The
vendored upstream skill in `vendor/` (and the reference files derived from it)
are Microsoft's `@playwright/cli` content, licensed Apache-2.0
(SPDX-License-Identifier: Apache-2.0). The upstream license text ships at
`skills/playwright/vendor/LICENSE`.
