# Screenshots, downscaling, and zoom

Why every screenshot arrives smaller than your screen, why that is not tunable, and the one
mechanism that recovers detail.

## Downscaling is automatic and has no setting

We treat the downscale of **every** screenshot as fixed: no setting changes the target size, so
when a screenshot leaves text or buttons unreadably small, the remedy is larger text in the app,
never a lower display resolution.

- **Pointer**: for the downscale and the absence of a size setting, see
  [Screenshots are downscaled automatically](https://code.claude.com/docs/en/computer-use#screenshots-are-downscaled-automatically).
- **As of**: 2026-08-10
- **Recheck trigger**: that section documents a setting that changes the target size.

## The target is a pixel budget, not a scale factor

This is the part that surprises people. We read the target as a fixed pixel count, about 1.2
megapixels, with the aspect ratio preserved, rather than a fixed scale factor:

| Source display | Delivered image | Megapixels | Linear scale |
|---|---|---|---|
| 2560x1440 (Windows, measured 2026-08-10) | 1456x816 | 1.19 | 1.76x |

The worked example in the downscaling section above, on a larger display, is the second data point
we compared against. The practical consequence: **a smaller monitor does not buy a sharper
screenshot**. It buys the same ~1.2MP with less on it. That is occasionally worth doing for a dense
UI, but it is a trade of coverage for density, never a quality win.

- **Pointer**: the measurement above is our own probe; for the upstream worked example, see
  [Screenshots are downscaled automatically](https://code.claude.com/docs/en/computer-use#screenshots-are-downscaled-automatically).
- **As of**: 2026-08-10
- **Recheck trigger**: a capture on a measured display delivers a pixel count far from 1.2MP, or
  that section's worked example changes.

## `zoom` re-captures at full resolution

We treat `zoom` as a fresh capture of the region at full resolution, not a crop of the downscaled
image.

- **Pointer**: for the `zoom` action, see
  [Available actions](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool#available-actions).
- **As of**: 2026-08-10
- **Recheck trigger**: the `zoom` row in that table stops describing a full-resolution capture.

Local behavior matches: while capture is failing, `zoom` returns
`Screenshot capture failed after 3 attempts` rather than a blurry crop. A crop of the
downscaled image would succeed and look bad; a re-capture fails outright. Two consequences
follow from that single fact:

- **Zoom recovers real detail**: status-bar text, tab titles, line numbers, small labels.
- **Zoom is useless while capture is broken.** If `zoom` errors, stop zooming and go diagnose
  the capture ([failure-diagnostics.md](failure-diagnostics.md)).

Coordinates for a subsequent click always refer to the **full-screen** image, never the zoomed
one. Zoom is read-only inspection.

## Order of remedies for "Claude can't read this"

1. **`zoom` the region.** Free, immediate, no environment change.
2. **Increase the size in the app**: editor font size, browser zoom, app scaling. It survives
   across screenshots.
3. **Keyboard instead of mouse** for genuinely tiny targets (tray icons, small checkboxes), rather
   than trying to click them.
4. **Do not lower display resolution.** Claude Code already downscales; dropping the source
   only removes information earlier.

- **Pointer**: for the in-app size remedy, see
  [Screenshots are downscaled automatically](https://code.claude.com/docs/en/computer-use#screenshots-are-downscaled-automatically);
  for keyboard use on hard targets, see
  [Optimize model performance with prompting](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool#optimize-model-performance-with-prompting).
- **As of**: 2026-08-10
- **Recheck trigger**: either section drops or reverses its remedy.

## The API-side resolution guidance, and how it applies here

The API-side computer use tool takes display dimensions the caller chooses, and its docs give
concrete resolution guidance and name low resolution as a cause of poor accuracy. Read it at the
pointer; we do not restate it.

**That knob does not exist on the Claude Code surface.** The harness owns the downscale, and we
read its behavior as already following that guidance. The guidance is still worth knowing because
it explains *why* the harness downscales and why resolution affects click accuracy. Do not
translate the API advice into a display-settings change on a Claude Code machine.

- **Pointer**: for the resolution guidance, see
  [Size screenshots to fit image limits](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool#handle-coordinate-scaling-for-higher-resolutions)
  and
  [Diagnose click issues](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool#diagnose-click-issues)
  (correlate with [best practices](https://claude.com/blog/best-practices-for-computer-and-browser-use-with-claude)).
- **As of**: 2026-08-10
- **Recheck trigger**: either section changes its recommended resolutions, or the Claude Code
  computer-use page documents a setting to change the target size.

## `save_to_disk` is not an escape hatch

`screenshot` accepts `save_to_disk: true`, but on Windows no file was found anywhere under the
user profile (searched 2026-08-10; recheck if the CLI computer-use page or the tool description
documents where `save_to_disk` writes). Where it writes, or whether it is a no-op on this
platform, is unresolved, so do not rely on it for a full-resolution capture.
