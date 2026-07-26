# Tracing and video recording

Two complementary capture mechanisms:

| Feature | Trace | Video |
|---|---|---|
| Output | `.trace` file (Trace Viewer) | `.webm` file |
| Captures | DOM snapshots, network, console, actions, timing | Visual recording only |
| Size | Medium | Large |
| Best for | Debugging — step-by-step replay | Demos, evidence, documentation |

## Tracing

```bash
playwright-cli tracing-start
playwright-cli open https://example.com
playwright-cli click e1
playwright-cli fill e2 "test"
playwright-cli tracing-stop
```

Creates `traces/` with:

- `trace-<ts>.trace` — action log + DOM snapshots before/after + screenshots + timing + console
- `trace-<ts>.network` — full HTTP requests/responses, headers, bodies, timing, failures
- `resources/` — cached images/fonts/stylesheets needed to reconstruct page state

View with `npx playwright show-trace trace-<ts>.trace`.

**Tip: start tracing before the problem, not at it.** Trace the whole flow so pre-failure state is captured, not just the failing step.

**Cleanup:** traces accumulate. Periodically:

```bash
find .playwright-cli/traces -mtime +7 -delete
```

## Video — basic

```bash
PLAYWRIGHT_MCP_VIEWPORT_SIZE=1440x900 playwright-cli -s=demo open
playwright-cli -s=demo video-start demo.webm --size "1440x900"
playwright-cli -s=demo goto https://example.com
playwright-cli -s=demo click e1
playwright-cli -s=demo video-stop
```

Both size arguments are deliberate — see [Frame size](#frame-size-two-levers-not-one) below. Pick
whatever resolution your evidence needs; `1440x900` here is only an illustration.

Add chapter markers for section transitions:

```bash
playwright-cli video-chapter "Login" --description="Entering credentials" --duration=2000
```

Auto-annotate subsequent actions (click, type, ...) with a callout naming the action and highlighting the target — cheaper than hand-building overlays via `run-code` for simple demos:

```bash
playwright-cli video-show-actions --duration=600 --position=top-right --cursor=pointer
playwright-cli click e1
playwright-cli fill e2 "test"
playwright-cli video-hide-actions
```

`--position` accepts `top-left|top|top-right|bottom-left|bottom|bottom-right` (default `top-right`); `--cursor=pointer` (default) animates a mouse pointer between action points, `--cursor=none` disables it.

## Frame size — two levers, not one

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

Measured outcomes (ffprobe on the resulting `.webm`, `@playwright/cli` 0.1.14):

| What you do | What you get |
|---|---|
| `open`, then bare `video-start` | 800×450 — the default viewport fitted into an 800 box |
| `open`, `resize <w> <h>`, then bare `video-start` | still 800×450 — **`resize` does not change the video frame size** |
| `PLAYWRIGHT_MCP_VIEWPORT_SIZE=1920x1200 open`, bare `video-start` | 800×500 — a bigger viewport is still fitted into 800 |
| `open`, `video-start --size "1920x1200"` | a 1920×1200 file, but the 1280×720 render sits in the top-left corner and the rest is padded grey |
| both levers, matched | the size you asked for |

`resize` is for exercising responsive layout; it is not a video lever. If a recording came back
smaller than expected, the fix is at `open` time, not after it.

**Not the same thing as `saveVideo`.** The config file (`.playwright/cli.config.json`) has a
top-level `saveVideo: { width, height }` that auto-saves a video of the *whole session* to the output
directory, and a `browser.contextOptions` block that accepts a `viewport` — per the `@playwright/cli`
README schema. That is a different mechanism from on-demand `video-start`/`video-stop`; treat the
config route as unverified until you have measured it yourself.

## Video — hero scripts (via `run-code`)

For polished recordings (demos, PR evidence), build a single `run-code` script with typing delays, overlays, and chapter cards. See [running-code.md](running-code.md) for execution mechanism. Upstream ships a detailed pattern at `../vendor/references/video-recording.md` covering:

- `page.screencast.showChapter(title, { description, duration })` — full-screen chapter card with blurred backdrop
- `page.screencast.showOverlay(html, { duration })` — custom HTML callouts/labels/highlights
- `pressSequentially(text, { delay: 60 })` — realistic typing
- Bounding-box-driven overlays for element highlighting

**Overlay invariant:** overlays are `pointer-events: none` — safe to layer over the page without blocking clicks.

## Workflow checklist

When capturing for a PR or bug report:

1. **Plan the flow first** — know exactly which commands and element refs you'll hit
2. **Open browser, take initial snapshot** to get refs
3. **Start capture** — `tracing-start`, or `video-start <name>.webm --size "<W>x<H>"` with the
   viewport already set on `open` (see [Frame size](#frame-size-two-levers-not-one))
4. **Perform the flow** using refs from snapshot
5. **Stop capture** (`tracing-stop` or `video-stop`)
6. **Move output to a meaningful location** — don't leave artifacts named `page-<timestamp>.png` in `.playwright-cli/`; use `--filename=` or `mv` to something like `<artifact-dir>/<descriptive-name>.webm`

## Known costs

- Tracing adds ~50-150ms/action overhead
- Video adds real-time encoding overhead. WebM file size scales with frame area and with how much of
  the screen moves, so raising `--size` raises cost roughly in proportion — measure your own flow
  rather than budgeting from a rule of thumb
- Both grow `.playwright-cli/` unboundedly — clean up old runs
