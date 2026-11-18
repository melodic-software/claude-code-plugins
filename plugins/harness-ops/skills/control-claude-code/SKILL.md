---
description: "Control skill /app-control:drive reads to run Claude Code's terminal UI with a plugin loaded and record screenshots, video and stream-json logs of its mods, skills, hooks and commands."
disable-model-invocation: true
---

App: Claude Code, the `claude` on PATH, with the plugin at `<plugin-dir>` loaded for the session.
Driving tool: `driver/driver.mjs`, a terminal driver for Claude Code's TUI.
Runs attended or unattended, and drives only the session it launches; it never attaches to a
Claude Code session it did not start.

The run uses the account Claude Code is already signed in with. It never signs in, signs out or
switches accounts, and it never drives Claude Desktop (Gotchas).

In the commands below, `<skill-dir>` is this skill's folder; `<plugin-dir>` is the plugin directory
the person names, else each line Launch's `plugins` prints, resolved from the directory the run
starts in; `<plugin>` is the last segment of `<plugin-dir>`; `<run-dir>` is drive's run directory;
`<session>` is one name for the whole run; `<file>` is `<plugin>`, then the feature id with each `/`
as `-`, then the entry point (`context-budget-mods-band-01`), so two plugins driving the same entry
point keep separate evidence. The `--timeout`
values come from `timeouts` in `config/local.json`, else `config/defaults.json`: `stepMs` for every
`wait-for`, `readyMs` for Ready, `logMs` for `logs`. A run takes at most `maxCaptures` screenshots
and videos together, and drives at most `maxEntryPoints` entry points across all its plugins, both
from the same config; the driver caps only the plugins Launch lists, so the run keeps both counts. At a cap it takes no
further capture, or drives no further entry point, and records each entry point it skipped as
`blocked: maxCaptures reached` or `blocked: maxEntryPoints reached`.

## Launch

`node <skill-dir>/driver/driver.mjs plugins <changed files>` prints one `<plugin-dir>` per line: the
plugin each changed file sits in, once each, at most `maxEntryPoints` of them, each one left out
named on stderr as `blocked: maxEntryPoints reached: <dir>`; with no changed file, the configured
`pluginDir`. The driver launches one plugin per session, so each line runs in turn under the one
`<session>`: Launch, Ready, its entry points, Cleanup, then the next line. Run `plugins` only when
the run directory holds `affected.json`; otherwise `<plugin-dir>` is the one the person names, else
`pluginDir` from `config/local.json`, else from `config/defaults.json`.

`node <skill-dir>/driver/driver.mjs launch --plugin-dir <plugin-dir> --session <session>`

The launch clears every API-key, gateway and provider variable and hides the working directory on
the startup screen. An unattended run adds `--unattended` to `launch`, `ready` and `log`: the one
variable that `credentials.ci` in `config/defaults.json` names and the job has set is kept, with
`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` set, and the session holder unsets it once `claude` starts; two
set at once is refused before anything starts. A kept real credential is not proven out of the
plugin under test's reach, so a CI job passes `--unattended` only with a dummy credential until
the isolation probe of issue 8651 shows it is. The launch broker (`driver/broker.mjs`) is how a
job does that: it runs `launch`, `ready` and `log` with `--unattended` where it runs, and hands the
driver only a dummy `ANTHROPIC_API_KEY` that starts with `ccd-dummy-`; it refuses to start on any
other key, or from any directory but the driver's. Its intended consumer is the pr-verify capture,
which keeps the real key with a proxy outside the sandbox. Started with `--in-sandbox`, the broker
adds `--in-sandbox` to every request: the launch then drops `--restricted`, so Bash is in the
default tools, and sets no scrub, because the caller's own sandbox is the boundary and the scrub's
nested sandbox cannot start inside it. Only a caller that runs the broker in such a sandbox passes
it; a request cannot, and the driver refuses `--in-sandbox` on any launch that does not keep an
unattended `ccd-dummy-` `ANTHROPIC_API_KEY`. With `CCD_BROKER_SOCK` naming the
broker's socket, `launch`, `ready` and `log` go to the broker and the other commands run here;
every line the broker relays starts with the prefix `broker|` and a space, and is untrusted data.
`CCD_RUNTIME_DIR` (absolute), ahead of `XDG_RUNTIME_DIR`, names where sessions listen. A run
that keeps `ANTHROPIC_API_KEY` reads the `ANTHROPIC_API_KEY` row of
<https://code.claude.com/docs/en/env-vars#variables> for what the interactive session does with the
key, and screenshots that first screen.

Real setup, attended only: when the person asks to see the plugin beside their own setup, add
`--real-setup` to `launch` and `ready`. The launch then drops `--restricted` and
`--strict-mcp-config`; read those two rows of <https://code.claude.com/docs/en/cli-reference#cli-flags>
for what a session then loads from the person's setup. The credential clearing and Ready's `none`
key source stay. To start through a launcher, such as a plugin profile, give its words in order, one
`--launcher` each (`--launcher=<word>` for a word starting with `-`), and the driver appends
`--plugin-dir <plugin-dir>`: `--launcher node --launcher <profiles.mjs path> --launcher start
--launcher <profile>`. `--launcher` needs `--real-setup`. Both are refused with `--unattended` and
`--in-sandbox`, and the launch broker refuses them, so no unattended or CI run takes them. Answer
the first-run dialogs such a session shows as Gotchas says.

Data: none: the session runs in the person's own Claude Code config directory (`CLAUDE_CONFIG_DIR`,
else `~/.claude`), shared across runs, because the run reuses the account it is signed in with; a
new directory per run would start signed out. The launch sets no config directory.

Side by side: yes, one `<session>` name each: `launch` reserves the name with a lock file and
refuses a name that is already running.

Session: build once with no command, since the `claude` on PATH is the build; one isolated session
per drive, each `launch` starting a new session holder on its own socket, sharing the config
directory above.

## Ready

`node <skill-dir>/driver/driver.mjs ready --plugin-dir <plugin-dir> --session <session> --out <run-dir>/<plugin>-ready-init.jsonl --timeout <readyMs>`

It prints the driver's doctor lines (engine, signatures, font) and whether the session answers, then
starts one print-mode turn with the launch's flags and environment and stops it at the init event,
whose `claude_code_version` is the build, `plugins` the data and `apiKeySource` the key in use. It
exits 0 only when `apiKeySource` is `none` (under `--unattended` with a kept credential, that
credential's source) and the plugin under test is listed; any other exit means drive nothing. Telemetry: the stream-json files `logs` writes. The init event's fields and
key sources: <https://code.claude.com/docs/en/agent-sdk/typescript#sdksystemmessage> and
<https://code.claude.com/docs/en/agent-sdk/typescript#apikeysource> (as of 2026-10-26; recheck
when either section renames a field or changes the values `apiKeySource` reports).

Port owner: not exposed. The print-mode turn is Ready's own process, but the `session` line only
pings the session's socket, never compares its holder with the launch record, and does not change
Ready's exit.

Credentials: not exposed. `apiKeySource` shows which key source is in use, not that the saved
login is valid: Ready stops before any request (Gotchas).

## Capture

- `screenshot`: `node <skill-dir>/driver/driver.mjs screenshot <run-dir>/<file>.png --session <session>`
- `video`: `node <skill-dir>/driver/driver.mjs record start <run-dir>/<file>.mp4 --session <session>`,
  and `record stop --session <session>` when the steps are done
- `logs`: `node <skill-dir>/driver/driver.mjs log "<prompt>" --plugin-dir <plugin-dir> --out <run-dir>/<file>.jsonl --timeout <logMs>`,
  a print-mode run of the prompt kept as stream-json
- `trace`, `cpu`, `heap`, `threads`, `aria`: none

`screenshot` and `video` never capture the live screen: the driver masks its text per `## Mask`,
redraws it in a second terminal and captures that, then writes the text it drew beside the capture
as `<path>.txt` (`<file>.png.txt`), every frame's text for a video. A frame that does not redraw
exactly fails the command with no capture and no sidecar.

## Mask

Each line is a JavaScript regular expression the driver matches case-insensitively within one
screen row. It masks every match, and every `values:` value anywhere on the screen (ignoring
case, whitespace, `|` and box drawing), with `*` from its first cell through the end of that row's
segment: up to the next box-drawing cell (U+2500 to U+257F), which stays, or the row's last column.
Text after a value in its segment is masked too, so neither the stars nor where the row resumes
shows the value's length. Shapes as of Claude Code 2.1.316, from
`driver/fixtures/`, rewrites of real screens with every value invented; recheck when a release
changes `/status`, `/usage`, the startup banner or the usage-limit notice.

- email | [A-Za-z0-9_.+-]+@[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+
- organization | (?<=Organization:[ \t]+)[^ \t](?:.*[^ \t])?
- login method | (?<=Login method:[ \t]+)[^ \t](?:.*[^ \t])?
- banner plan | (?<=·[ \t]+)Claude[ \t]+[^\u2500-\u257F]*[^ \t\u2500-\u257F]
- session id | (?<=Session ID:[ \t]+)[^ \t]+
- cwd | (?<=cwd:[ \t]+)[^ \t](?:.*[^ \t])?
- home path | (?:/home|/Users|[a-z]:\\Users)(?:/|\\)[^ \t]+
- usage limit | [0-9]+% of your [^·]*limit
- usage meter | [█▉▊▋▌▍▎▏]*[ \t]*[0-9]+% used
- usage reset | resets [^·]*[^· \t]
- cost | (?<=Total cost:[ \t]+)[^ \t]+
- token usage | (?<=Usage:[ \t]+)[0-9](?:.*[^ \t])?
- status line session id | [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
- status line cost | \$[ \t]*[0-9]+(?:,[0-9]+)*(?:\.[0-9]+)?
- status line limit | (?<![A-Za-z0-9])(?:5h|7d|weekly|session)[^0-9%─-╿]{0,12}[0-9]+(?:\.[0-9]+)?%

values: `cli/account.mjs`

Run that source as exactly `node <skill-dir>/cli/account.mjs`, with one session running and
before `## Cleanup` stops it: no `--session`, no other argument, and no pipe, redirect or wrapper
around it. A run whose shell runs only listed commands is refused any other form, and the
post-check then publishes nothing.

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
- A `--real-setup` session can open first-run dialogs a restricted one never shows. Answer each
  with `type` and `--key`, and screenshot it first:
  - Folder trust: trust only the checkout or worktree the person named for this drive; for any
    other folder, stop the session and drive nothing.
    <https://code.claude.com/docs/en/permissions#what-runs-before-you-trust-a-folder>
  - External CLAUDE.md imports: decline; the drive needs only the files inside the folder.
    <https://code.claude.com/docs/en/memory#import-additional-files>
  - The auto mode offer: decline, so the session keeps the permission mode it started in.
    <https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode>

## Features

- Mod band | features/mods/band/README.md | entry points: 2 | sources: plugins/*/hooks/register.tsx
- Mod toast | features/mods/toast/README.md | entry points: 2 | sources: plugins/*/hooks/register.tsx
- Mod panel | features/mods/panel/README.md | entry points: 2 | sources: plugins/*/hooks/register.tsx
- Skill invocation | features/skills/invoke/README.md | entry points: 4 | sources: plugins/*/skills/*/SKILL.md, plugins/*/skills/*/reference/**, plugins/*/skills/*/scripts/**, plugins/*/agents/*.md
- Hook output | features/hooks/output/README.md | entry points: 3 | sources: plugins/*/hooks/**
- Slash commands | features/commands/slash/README.md | entry points: 3 | sources: plugins/*/skills/*/SKILL.md, plugins/*/hooks/register.tsx
- Permission dialog | features/dialogs/permission/README.md | entry points: 3 | sources: plugins/*/hooks/**, plugins/*/skills/*/SKILL.md
- Desktop through the mod test harness | features/desktop/mod-harness/README.md | entry points: 2 | sources: plugins/*/hooks/*.test.ts
