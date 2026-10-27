---
description: "Control skill /app-control:drive reads to run Claude Code's terminal UI with a plugin loaded and record screenshots, video and stream-json logs of its mods, skills, hooks and commands."
disable-model-invocation: true
---

App: Claude Code, the `claude` on PATH, with the plugin at `<plugin-dir>` loaded for the session.
Driving tool: `driver/driver.mjs`, a terminal driver for Claude Code's TUI.
Attended runs only.

The run uses the account Claude Code is already signed in with. It never signs in, signs out or
switches accounts.

In the commands below, `<skill-dir>` is this skill's folder; `<plugin-dir>` is the plugin directory
the person names, else `pluginDir` from `config/local.json`, else from `config/defaults.json`,
resolved from the directory the run starts in; `<run-dir>` is drive's run directory; `<session>` is
one name for the whole run; `<file>` is the feature id with each `/` as `-`, then the entry point
(`mods-band-01`). The `--timeout` values come from `timeouts` in the same config: `stepMs` for every
`wait-for`, `readyMs` for Ready, `logMs` for `logs`.

## Launch

`node <skill-dir>/driver/driver.mjs launch --plugin-dir <plugin-dir> --session <session>`

## Ready

`node <skill-dir>/driver/driver.mjs ready --plugin-dir <plugin-dir> --session <session> --out <run-dir>/ready-init.jsonl --timeout <readyMs>`

It prints the driver's doctor lines (engine, signatures, font) and whether the session answers, then
starts one print-mode turn with the launch's flags and environment and stops it at the init event,
whose `claude_code_version` is the build, `plugins` the data and `apiKeySource` the key in use. It
exits 0 only when `apiKeySource` is `none` and the plugin under test is listed; any other exit
means drive nothing. Telemetry: the stream-json files `logs` writes. The init event's fields and
key sources: <https://code.claude.com/docs/en/agent-sdk/typescript#sdksystemmessage> and
<https://code.claude.com/docs/en/agent-sdk/typescript#apikeysource> (as of 2026-10-26; recheck
when either section renames a field or changes the values `apiKeySource` reports).

## Capture

- `screenshot`: `node <skill-dir>/driver/driver.mjs screenshot <run-dir>/<file>.png --session <session>`
- `video`: `node <skill-dir>/driver/driver.mjs record start <run-dir>/<file>.mp4 --session <session>`,
  and `record stop --session <session>` when the steps are done
- `logs`: `node <skill-dir>/driver/driver.mjs log "<prompt>" --plugin-dir <plugin-dir> --out <run-dir>/<file>.jsonl --timeout <logMs>`,
  a print-mode run of the prompt kept as stream-json
- `trace`, `cpu`, `heap`, `threads`, `aria`: none

## Cleanup

`node <skill-dir>/driver/driver.mjs stop --session <session>`, after `record stop` when a recording
is running. It stops the session this run launched; the evidence files stay.

## Next

/app-control:drive claude-code <feature>

## Gotchas

- Claude Desktop takes no input from this skill: every Desktop entry point is
  `not driven: terms`, and Desktop coverage comes only from `desktop/mod-harness`. Basis: the
  Consumer Terms, section 3 "Use of our Services", on access through automated means,
  <https://www.anthropic.com/legal/consumer-terms> (as of 2026-10-26; recheck when that section
  changes).
- Wait for a step's text with `wait-for` before each screenshot: a capture taken first shows the
  frame before the redraw.
- A status glyph drawn as a box is the missing font doctor names, not the plugin under test.
- Ready stops before any request, so it does not show the session is signed in; the launched
  session's first screen does. Screenshot it before the first step.

## Features

- Mod band | features/mods/band/README.md | entry points: 2 | sources: plugins/*/hooks/register.tsx
- Mod toast | features/mods/toast/README.md | entry points: 2 | sources: plugins/*/hooks/register.tsx
- Mod panel | features/mods/panel/README.md | entry points: 2 | sources: plugins/*/hooks/register.tsx
- Skill invocation | features/skills/invoke/README.md | entry points: 4 | sources: plugins/*/skills/*/SKILL.md
- Hook output | features/hooks/output/README.md | entry points: 3 | sources: plugins/*/hooks/hooks.json
- Slash commands | features/commands/slash/README.md | entry points: 3 | sources: plugins/*/skills/*/SKILL.md, plugins/*/hooks/register.tsx
- Permission dialog | features/dialogs/permission/README.md | entry points: 3 | sources: plugins/*/hooks/hooks.json, plugins/*/skills/*/SKILL.md
- Desktop through the mod test harness | features/desktop/mod-harness/README.md | entry points: 2 | sources: plugins/*/hooks/*.test.ts
