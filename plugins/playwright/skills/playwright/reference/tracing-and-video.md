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
playwright-cli open
playwright-cli video-start demo.webm
playwright-cli goto https://example.com
playwright-cli click e1
playwright-cli video-stop
```

Add chapter markers for section transitions:

```bash
playwright-cli video-chapter "Login" --description="Entering credentials" --duration=2000
```

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
3. **Start capture** (`tracing-start` or `video-start <name>.webm`)
4. **Perform the flow** using refs from snapshot
5. **Stop capture** (`tracing-stop` or `video-stop`)
6. **Move output to a meaningful location** — don't leave artifacts named `page-<timestamp>.png` in `.playwright-cli/`; use `--filename=` or `mv` to something like `docs/evidence/issue-123.webm`

## Known costs

- Tracing adds ~50-150ms/action overhead
- Video adds real-time encoding overhead; 1280×720 WebM is ~5 MB/minute
- Both grow `.playwright-cli/` unboundedly — clean up old runs
