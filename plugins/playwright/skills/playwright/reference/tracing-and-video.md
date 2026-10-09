# Tracing and video recording

## Contents

- [Tracing](#tracing)
- [Reading a failed `@playwright/test` run](#reading-a-failed-playwrighttest-run)
- [Video basics](#video-basics)
- [Frame size (two levers, not one)](#frame-size-two-levers-not-one)
- [Video hero scripts (via `run-code`)](#video-hero-scripts-via-run-code)
- [Capturing for a PR or bug report](#capturing-for-a-pr-or-bug-report)
- [Known costs](#known-costs)

Two complementary capture mechanisms:

| Feature | Trace | Video |
|---|---|---|
| Output | `.trace` file (Trace Viewer) | `.webm` file |
| Captures | DOM snapshots, network, console, actions, timing | Visual recording only |
| Size | Medium | Large |
| Best for | Debugging, step-by-step replay | Demos, evidence, documentation |

## Tracing

```bash
playwright-cli tracing-start
playwright-cli open https://example.com
playwright-cli click e1
playwright-cli fill e2 "test"
playwright-cli tracing-stop
```

Creates `.playwright-cli/traces/` with:

- `trace-<ts>.trace`: action log + DOM snapshots before/after + screenshots + timing + console
- `trace-<ts>.network`: full HTTP requests/responses, headers, bodies, timing, failures
- `resources/`: cached images/fonts/stylesheets needed to reconstruct page state

View with `npx playwright show-trace trace-<ts>.trace`.

**Tip: start tracing before the problem, not at it.** Trace the whole flow so pre-failure state is captured, not just the failing step.

**Cleanup:** traces accumulate. Periodically:

```bash
find .playwright-cli/traces -mtime +7 -delete
```

## Reading a failed `@playwright/test` run

The sections above trace a `playwright-cli` session. A committed `@playwright/test` suite records
its own traces, videos and screenshots per test, and keeps them only when its config says to.
Read a failure from that evidence first, before re-running the test or attaching a debugger.

**Terminal trace loop.** `npx playwright show-trace` opens a GUI for a human. An agent reads the
same trace in the terminal with `npx playwright trace` (Playwright 1.59+), one step at a time, so
only the failing step enters context:

1. `npx playwright trace open <trace.zip>` on the trace the failing test left in its result folder
2. `npx playwright trace actions` to list the recorded actions and find the one that failed
3. `npx playwright trace action <n>` for that action's detail
4. `npx playwright trace snapshot ...` for the page at that action, when the action detail does
   not explain the failure
5. `npx playwright trace close`

Read the failure's error context beside the trace: from 1.60 it carries the aria snapshot of the
element an `expect` matcher failed on, which often answers "what was on the page" without the
trace.

**Retention modes.** Set these in the `use` block of `playwright.config.*`, or per project. Our
choice per situation:

| Situation | Setting |
|---|---|
| An agent or developer iterating locally, wanting evidence for every failure | `trace: 'retain-on-failure'`, `screenshot: 'only-on-failure'` |
| CI with retries enabled, keeping recording cost down | `trace: 'on-first-retry'`, upstream's CI recommendation. Only the retry is recorded, so a suite with no retries leaves no trace |
| Chasing a flaky test, where the retry passes and the failing attempt is the evidence | `trace: 'retain-on-failure-and-retries'` |
| A human needs to watch the failure (a visual or timing bug) | add `video: 'retain-on-failure'`; leave video off otherwise, it is the heaviest artifact |

`retain-on-failure` records every test and discards the artifact when the test passes, so green
runs pay the recording overhead too. Exact mode semantics, the full mode list (it has more than
these) and the `trace` subcommands' arguments change between releases, so read them live:

- **Pointer**: modes in
  [test-use-options, Recording options](https://playwright.dev/docs/test-use-options#recording-options);
  the CI recommendation and what a trace holds in [Trace viewer](https://playwright.dev/docs/trace-viewer);
  the trace CLI in Version 1.59 ("CLI trace analysis for agents") and `errorContext` in Version
  1.60 of the [release notes](https://playwright.dev/docs/release-notes); arguments via
  `npx playwright trace --help` live. **As of**: 2026-10-06, Playwright 1.63. **Recheck
  trigger**: a Playwright release whose notes touch tracing, reporters or recording options, or a
  `trace` subcommand above failing as unknown.

## Video basics

```bash
PLAYWRIGHT_MCP_VIEWPORT_SIZE=1440x900 playwright-cli -s=demo open
playwright-cli -s=demo video-start demo.webm --size "1440x900" --fps=60 --cursor
playwright-cli -s=demo goto https://example.com
playwright-cli -s=demo click e1
playwright-cli -s=demo video-stop
```

Always pass `--size`, matched to the viewport set on `open`: without it the recording is scaled to
fit 800×800, whatever the viewport. See [Frame size](#frame-size-two-levers-not-one) below. Pick
whatever resolution your evidence needs; `1440x900` here is only an illustration.

For a demo a reviewer will watch, pass `--size`, `--fps=60` and `--cursor` to `video-start`, as
above, so the viewer sees smooth motion and what caused each change on screen.

Add a chapter card at section transitions:

```bash
playwright-cli -s=demo video-chapter "Login" --description="Entering credentials" --duration=2000
```

Annotate subsequent actions (click, type, ...) with a callout naming each action. For simple demos
this is cheaper than hand-building overlays via `run-code`:

```bash
playwright-cli -s=demo video-show-actions --duration=800 --position=top-right \
  --highlight-style="outline: 2px solid #333" \
  --point-style="width: 20px; height: 20px; border-radius: 50%; background: rgba(255,0,0,.7)"
playwright-cli -s=demo click e1
playwright-cli -s=demo fill e2 "test"
playwright-cli -s=demo video-hide-actions
```

For a demo, pass `--highlight-style` (and `--point-style` when clicks should show) so the viewer
can see which element each action targets.

- **Pointer**: when you need the exact flags or default values of `video-start`, `video-chapter` or
  `video-show-actions`, run `playwright-cli <command> --help` live; for what changed, fetch the
  [v0.1.21 release notes](https://github.com/microsoft/playwright-cli/releases/tag/v0.1.21).
  **As of**: 2026-10-04. **Recheck trigger**: the frontmatter `upstream-version` moves.

## Frame size (two levers, not one)

**A bare `video-start <name>.webm` does not record at your viewport size.** Upstream's default is
"the size of the recorded video will fit 800x800" (`playwright-cli video-start --help`), so the CLI's
default 1280×720 viewport records as **800×450**. Playwright's own docs say the same thing and give
the same fallback number ([recordVideo.size](https://playwright.dev/docs/api/class-browser#browser-new-context),
[Videos](https://playwright.dev/docs/videos): *"You may need to set the viewport size to match your
desired video size."*).

Two independent levers control the result. A full-resolution recording needs **both**, matched:

| Lever | Where it goes | What it governs |
|---|---|---|
| Context viewport | `PLAYWRIGHT_MCP_VIEWPORT_SIZE=<W>x<H>` prefixed on the `open` command | What the page actually renders at |
| Video frame | `video-start <name>.webm --size "<W>x<H>"` | The output file's pixel dimensions |

The viewport must be set on `open`, because that is the command that creates the browser context the
recorder derives its geometry from.

The `VAR=value <command>` prefix shown here is POSIX shell syntax (Git Bash, WSL, macOS, Linux).
PowerShell has no inline env prefix. Set `$env:PLAYWRIGHT_MCP_VIEWPORT_SIZE = '<W>x<H>'` on its own
line before the `open`, then clear it afterwards if later sessions should use the default.

Measured outcomes. Claim: the sizes below are what each combination actually produces.
Basis: ffprobe on the resulting `.webm` for each row. As of 2026-07-26, on
`@playwright/cli` 0.1.14; not re-measured on 0.1.22, whose `video-start --help` still states the
800×800 fit default. Recheck when the frontmatter `upstream-version` moves, or when a
recording comes back at a size this table does not predict.

| What you do | What you get |
|---|---|
| `open`, then bare `video-start` | 800×450, the default viewport fitted into an 800 box |
| `open`, `resize <w> <h>`, then bare `video-start` | still 800×450. **`resize` does not change the video frame size** |
| `PLAYWRIGHT_MCP_VIEWPORT_SIZE=1920x1200 open`, bare `video-start` | 800×500, a bigger viewport is still fitted into 800 |
| `open`, `video-start --size "1920x1200"` | a 1920×1200 file, but the 1280×720 render sits in the top-left corner and the rest is padded grey |
| both levers, matched | the size you asked for |

`resize` is for exercising responsive layout; it is not a video lever. If a recording came back
smaller than expected, the fix is at `open` time, not after it.

**Not the same thing as `saveVideo`.** The config file (`.playwright/cli.config.json`) has a
top-level `saveVideo: { width, height }` that auto-saves a video of the *whole session* to the output
directory, and a `browser.contextOptions` block that accepts a `viewport`, per the `@playwright/cli`
README schema. That is a different mechanism from on-demand `video-start`/`video-stop`; treat the
config route as unverified until you have measured it yourself.

## Video hero scripts (via `run-code`)

For polished recordings (demos, PR evidence), build a single `run-code` script with typing delays, overlays, and chapter cards. For the execution mechanism, see [running-code.md](running-code.md). Upstream ships a detailed pattern at `../vendor/references/video-recording.md` covering:

- `page.screencast.showChapter(title, { description, duration })`: full-screen chapter card with blurred backdrop
- `page.screencast.showOverlay(html, { duration })`: custom HTML callouts/labels/highlights
- `page.screencast.start({ path, size, fps })` and `page.screencast.showActions({ cursor, duration, position, style })`:
  the in-script equivalents of `video-start --size --fps` and `video-show-actions`
- `pressSequentially(text, { delay: 60 })`: realistic typing
- Bounding-box-driven overlays for element highlighting

**Overlay invariant:** overlays are `pointer-events: none`, so they are safe to layer over the page without blocking clicks.

## Capturing for a PR or bug report

Two mechanics the flow does not make obvious. Set `PLAYWRIGHT_MCP_VIEWPORT_SIZE` on the
`open` command before `video-start --size`, because the recorder derives its geometry when
the browser context is created; see [Frame size](#frame-size-two-levers-not-one). Then give
the output a descriptive name with `--filename=` or `mv`, so evidence does not sit in
`.playwright-cli/` as `page-<timestamp>.png`.

Attach the `.webm` with `gh pr comment <n> --attach ./demo.webm`, and keep the script focused so
the file stays small.

- **Pointer**: when an attach fails or you need the `gh` version or size limits, fetch the
  [`gh` v2.99.0 release notes](https://github.com/cli/cli/releases/tag/v2.99.0) and run
  `gh pr comment --help` live. **As of**: 2026-10-04. **Recheck trigger**: `gh pr comment --help`
  stops listing `--attach`, or an upload is rejected for size.

## Known costs

- Tracing adds ~50-150ms/action overhead
- Video adds real-time encoding overhead. WebM file size scales with frame area and with how much of
  the screen moves, so raising `--size` raises cost roughly in proportion. Measure your own flow
  rather than budgeting from a rule of thumb
- Both grow `.playwright-cli/` unboundedly, so clean up old runs
