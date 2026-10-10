---
description: "Produce a short demo video of a web UI change for a pull request: explore the flow unrecorded, write a replay script, replay it with 4K frame capture, build an edit plan (zoom on each action, drawn cursor, click ripples, captions, optional narration), render an H.264 MP4, gate it with frame-measured QC and an independent frame review, then attach it to the PR. Use when: 'demo video', 'record a demo of this change', 'make a PR video', 'show the change working on video', 'produced walkthrough video', 'video evidence for the PR'."
when_to_use: "PR demo video, produced screen recording of a web flow, video proof a UI change works"
argument-hint: "<url or flow to demo> [--style produced|plain]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: verify
  summary: Replay a web flow, render a produced demo video, QC it from frames, post it to the PR
---

# Demo video for a pull request

A produced demo is a short MP4 (about 12-20 s) that shows the change working: the camera zooms in
on each action, a drawn cursor travels and clicks with a ripple, captions name each step and its
outcome, and page loads are cut out. The pipeline lives in `scripts/`; every editing decision is
data in an edit-decision list (EDL), so a defect is fixed in the plan, not by hand.

Run every Python script through the launcher, which supplies the hash-locked numpy and Pillow and
never installs. Below, `RUN` stands for this prefix, written out in full in each command:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/pydeps.py" run --data-dir "${CLAUDE_PLUGIN_DATA}" -- "${CLAUDE_SKILL_DIR}/scripts/<script>.py" ...
```

When the packages are missing the launcher exits 2 and prints one install line; show it to the
user and run it after their yes. It needs Python 3.12+, `ffmpeg` and `ffprobe` on PATH, and
`node` with `playwright-cli` (or `playwright-core`) for recording; `/playwright:check` covers the
last two.

## Settings

The plugin's options set the defaults; a `--style` argument overrides the style for one run.
Claude Code substitutes only a value the user has saved; an option never set shows its literal
`${user_config...}` placeholder in the Saved value column, and then its default applies.

| Option | Saved value | Default | Effect |
|---|---|---|---|
| `demo_style` | `${user_config.demo_style}` | `produced` | `produced`, or `plain`: the same replay and cursor with no zoom, captions or title |
| `demo_title` | `${user_config.demo_title}` | `true` | title card |
| `demo_camera` | `${user_config.demo_camera}` | `true` | zoom and pan |
| `demo_cursor` | `${user_config.demo_cursor}` | `true` | drawn pointer |
| `demo_ripple` | `${user_config.demo_ripple}` | `true` | click ring |
| `demo_captions` | `${user_config.demo_captions}` | `true` | step and outcome captions |
| `demo_narration` | `${user_config.demo_narration}` | `false` | voice-over |

Substitution in skill content:
[Reference a saved value](https://code.claude.com/docs/en/plugins-reference#reference-a-saved-value);
as of 2026-10-10; recheck when that section says a manifest `default` is substituted for an unset
option.

`plain` removes the title, camera and captions whatever their toggles say; a toggle set to `false`
removes its layer in either style. Pass them to `build_edl.py` as
`--style <style> --layers title=<bool>,camera=<bool>,cursor=<bool>,ripple=<bool>,captions=<bool>`.

## Workflow

1. **Explore, unrecorded.** Drive the flow with `/playwright:playwright` until every step works and
   you know a stable locator for each target. Nothing is recorded here: agent think-time is what
   makes a raw recording unwatchable.
2. **Write the replay script.** One ES module default-exporting `async (demo) => {}`, one
   `demo.click(...)` to `demo.settle(...)` per step, step ids that key the captions. The API and the
   example over the bundled fixture: [reference/replay-script.md](reference/replay-script.md),
   [scripts/fixture/replay.mjs](scripts/fixture/replay.mjs). Write `script.json` beside it: title,
   subtitle, and per step `caption`, `outcome` (for a step that lands on a new page), and the
   narration lines.
3. **Replay with 4K capture.**
   `node ${CLAUDE_SKILL_DIR}/scripts/record.mjs [--playwright-core DIR] replay.mjs <work>/capture`.
   The viewport is 1920x1080 at device scale 2, so every frame is a 3840x2160 PNG; cursor travel and
   typing run three times slower than real time and are retimed in post, because device-pixel
   screenshots arrive at 3.6-4.0 fps (measured over eight recordings with blur disabled). Chromium's screencast stays at CSS-pixel size whatever the
   device scale, so it is not used.
4. **Narration (only when `demo_narration` is true).** When the speech plugin is installed, run
   `/speech:narrate` once per line into `<work>/audio/<step>/`, `<work>/audio/<step>.outcome/` and,
   for a typing step, `<work>/audio/<step>.results/`; each folder gets `narration.wav` and
   `words.json`. Without the speech plugin, skip narration and say so.
5. **Build the edit plan.**
   `RUN build_edl.py <work>/capture script.json <work>/edl.json --style ... --layers ... [--audio-dir <work>/audio]`.
   It refuses (exit 1, plan kept as `edl.rejected.json`) when a rule breaks: a zoom edge through
   text, a navigation cut not at 1.0x, a camera move over the limits, a caption with no empty
   anchor. Fix the replay (a tighter `block`, a pause) or the script, never the rule.
6. **Render.** `RUN produce.py <work>/edl.json <work>/demo.mp4`
   (add `--preset veryfast` for drafts). It writes `demo.render.json` beside the video.
7. **Frame QC.** `RUN qc.py <work>/edl.json <work>/demo.mp4 <work>/qc`
   measures every rule from the rendered frames and exits 1 on any FAIL. The checks and where each
   threshold comes from: [reference/qc.md](reference/qc.md). A FAIL goes back to step 2 or 5.
8. **Independent frame review.** Dispatch a fresh-context subagent that did not produce the video,
   with the brief in [reference/independent-review.md](reference/independent-review.md): the video,
   the QC sheets and the acceptance rules, and none of your reasoning about why it is fine. Fix what
   it finds and repeat 6-8. Nothing is posted on the producer's word.
9. **Post.** [reference/posting.md](reference/posting.md): locally, `gh pr comment --attach` with a
   `gh` that has `--attach`; in CI, a non-zipped Actions artifact plus a comment linking it.

## Next

/playwright:playwright

Return to it to re-run the flow when the review asks for a change to the app or the replay.

## Gotchas

- **Backdrop blur stalls capture.** A `backdrop-filter` (a DocSearch-style search modal) dropped
  software-rendered capture to about 3 fps; `record.mjs` disables it, and the caret, on every page.
- **Kokoro pads each clip.** The local voice adds about 0.35 s of silence before the first word;
  `build_edl.py` trims each clip to its first word using `words.json`, so keep that file beside
  each `narration.wav`.
- **Crossfades ghost.** Blending two page states shows both at once (double text, half-drawn
  panels). Page changes are hard cuts with the camera still; the only blend is the title dipping
  through ink, and `qc.py` fails any other.
- **Producer self-reports are not evidence.** A producer's own numbers (zoom share from the plan,
  "all checks pass") disagreed with frame measurement three times while this pipeline was built.
  Only `qc.py` output and the independent review count.
- **Block-level elements span the row.** A heading's box is as wide as its container, so a `block`
  made from it cannot be zoomed; build the block from elements that hug their content or pass an
  explicit `[x, y, w, h]`.
- **Hide partial states in the replay.** Results that re-render per keystroke flash "No results"
  states; hide them with `demo.style(css)` while typing and reveal them after, as the reference
  shows.
- **`ffmpeg -ss` in the QC sheets is approximate.** The sheets are for looking; the checks read
  every decoded frame.
