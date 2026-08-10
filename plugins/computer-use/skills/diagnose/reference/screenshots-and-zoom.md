# Screenshots, downscaling, and zoom

Why every screenshot arrives smaller than your screen, why that is not tunable, and the one
mechanism that recovers detail.

## Downscaling is automatic and has no setting

Claude Code downscales **every** screenshot before it reaches the model. Official wording
(verified 2026-08-10, [computer use from the CLI](https://code.claude.com/docs/en/computer-use)):

> There is no setting to change the target size. If on-screen text or controls are too small for
> Claude to read after downscaling, increase their size in the app rather than changing your
> display resolution.

## The target is a pixel budget, not a scale factor

This is the part that surprises people. Two very different displays converge on the same
megapixel count:

| Source display | Delivered image | Megapixels | Linear scale |
|---|---|---|---|
| 2560x1440 (Windows, measured 2026-08-10) | 1456x816 | 1.19 | 1.76x |
| 3456x2234 (upstream's MacBook example) | 1372x887 | 1.22 | 2.52x |

Same budget, different ratios, aspect ratio preserved. The practical consequence: **a smaller
monitor does not buy a sharper screenshot** — it buys the same ~1.2MP with less on it. That is
occasionally worth doing for a dense UI, but it is a trade of coverage for density, never a
quality win.

## `zoom` re-captures at full resolution

`zoom` is not a crop of the downscaled image. Upstream calls it "view a specific region of the
screen **at full resolution**" ([computer use
tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool), verified
2026-08-10).

Confirmed locally by an accident worth keeping: during a capture outage, `zoom` returned
`Screenshot capture failed after 3 attempts` rather than a blurry crop. A cropping
implementation would have succeeded and looked bad; a re-capturing one fails outright. Two
consequences follow from that single fact:

- **Zoom recovers real detail** — status-bar text, tab titles, line numbers, small labels.
- **Zoom is useless while capture is broken.** If `zoom` errors, stop zooming and go diagnose
  the capture ([failure-diagnostics.md](failure-diagnostics.md)).

Coordinates for a subsequent click always refer to the **full-screen** image, never the zoomed
one. Zoom is read-only inspection.

## Order of remedies for "Claude can't read this"

1. **`zoom` the region.** Free, immediate, no environment change.
2. **Increase the size in the app** — editor font size, browser zoom, app scaling. This is
   upstream's own recommendation and it survives across screenshots.
3. **Keyboard instead of mouse** for genuinely tiny targets (tray icons, small checkboxes).
   Upstream recommends this over trying to click them.
4. **Do not lower display resolution.** Claude Code already downscales; dropping the source
   only removes information earlier.

## Upstream's own resolution guidance, and how it applies here

The API-side computer use tool exposes display dimensions the caller chooses, and there the
guidance is concrete. The platform docs' implementation-best-practices section gives the
resolutions — 1024x768 or 1280x720 for general desktop work, avoid above 1920x1080 — and names
"resolution too low" as the cause of consistently poor accuracy
([computer use tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool),
verified 2026-08-10). The benchmarked blog post adds that pre-downscaling before sending is "the
single highest impact optimization" and that native unscaled resolution is the primary cause of
poor accuracy
([best practices](https://claude.com/blog/best-practices-for-computer-and-browser-use-with-claude),
verified 2026-08-10).

**That knob does not exist on the Claude Code surface** — the harness owns the downscale and
already does the recommended thing. The guidance is still worth knowing because it explains
*why* the harness behaves this way, and because it tells you that native unscaled resolution is
the documented primary cause of poor click accuracy. Do not translate the API advice into a
display-settings change on a Claude Code machine.

## Not pursued

`screenshot` accepts `save_to_disk: true`. On Windows it produced no file discoverable anywhere
under the user profile (searched 2026-08-10). Whether it writes elsewhere, or is a no-op on this
platform, is unresolved — do not rely on it as a full-resolution escape hatch until someone
verifies where the bytes land.
