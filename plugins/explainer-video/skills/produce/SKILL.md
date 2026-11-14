---
description: "Produce a short explainer video with ManimCE, narrated when the speech plugin is installed: plan the beats, write the narration and one scene script, time each scene change to the narration's word timings, render at low quality, mux the audio with ffmpeg, add captions, and check the file before calling it done (ffprobe streams and duration, overlapping text and elements cut off by the frame edge, then a fresh-context subagent judging the frames against the script). Without the speech plugin it renders a silent video. Given a storyboard.json it renders narrated still frames at 4K with burned captions, chapters and a contact sheet instead. Use when: 'make an explainer video', 'narrated explainer', 'animate this concept', 'Manim video of', 'render a math animation', 'turn this explanation into a video', 'silent explainer clip'. Not for hand-drawn film from style packs (use /animation:produce)."
argument-hint: "<topic> [output dir]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Script, narrate, render and check a ManimCE explainer video, frames judged in a fresh context
---

# Produce

Turn a topic into a short MP4 made with ManimCE, narrated when `/speech:narrate` is available.
The audio comes first: each scene change waits for the word that starts its part of the
narration. Every render is checked by `render.py`, and you read its frames to fix what you see.
Before the video is called done, a fresh-context subagent judges the delivery frames (step 7).

Run every script through the launcher, which uses the packages the SessionStart hook installed and
never installs:
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py run --data-dir "${CLAUDE_PLUGIN_DATA}" -- <script> ...`.
When it exits 2 with a repair line, or `render.py` names a missing tool, run the read-only readiness
report, `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py check --data-dir "${CLAUDE_PLUGIN_DATA}"`, and report the rows it prints. When `python3` is not found, run the same line
with `python`, and on Windows then with a `python.exe` path that `py -0p` lists. Never start it
through `py`; for why, read what a `py` launch does with no runtime installed in
[Python on Windows, basic use](https://docs.python.org/3/using/windows.html#basic-use).

## Where the files go

One work directory per video: the directory the user names, else
`${CLAUDE_PLUGIN_DATA}/videos/<slug>/`. A video and its audio are views, so they never go inside a
record bundle or beside the markdown record they explain
([record-bundle](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/record-bundle/README.md)).

| Path | Who writes it | What it holds |
|---|---|---|
| `scene.py` | you | one `Scene` subclass |
| `beats.txt` | you | the beat plan, one line per beat |
| `strings.json` | you, only for untrusted text | on-screen strings the scene loads |
| `narration/script.txt` | you, when narrated | the words spoken, one paragraph per beat |
| `narration/narration.wav`, `narration/words.json` | `/speech:narrate` | the audio and each word's start and end |
| `low/`, `final/` | `render.py` | `<Scene>.mp4`, `frames/fNNNN.png`, `report.json`; `captions.srt` and `timing.json` when narrated |

## Loop

1. Plan three to six beats, one idea each, under a minute in total. A beat is something the viewer
   sees change, not a sentence to read. Write the plan to `<dir>/beats.txt`, one line per beat
   saying what the viewer sees.
2. Narrate, when you can. Narration is available when `/speech:narrate` is in this session's skill
   list.
   - Write `<dir>/narration/script.txt`: one paragraph per beat, a blank line between paragraphs,
     written the way it should be spoken.
   - Run `/speech:narrate` on it with no `--out`, so `narration.wav` and `words.json` land beside
     the script.
   - When the speech plugin is not installed, or narrate exits 2, render silent and tell the user:
     "Narration is unavailable: <the reason>. This video is silent."
3. Write `scene.py`. `${CLAUDE_PLUGIN_ROOT}/skills/produce/examples/pythagoras.py` is a working
   scene in the expected shape, and `pythagoras.txt` beside it is its narration script.
   - `from narration import beat`. Call `beat(self, k)` where beat k starts, and `beat(self, n)`
     after the last beat, where n is the number of paragraphs. Narrated, `beat` holds the scene
     until paragraph k's first word (the narration's end for n). `beat(self, k, hold=s)` holds
     `s` seconds when the render is silent, so one scene serves both.
   - A beat's animations must finish before the next paragraph starts. When the check says a
     beat runs long, shorten its `run_time` values or move an animation to a later beat.
   - Words are `Text`. Math is `MathTypst` (Typst math syntax). Do not use `Tex` or `MathTex`:
     LaTeX is not part of this plugin yet.
   - Text that came from a pull request, a fetched page or another repository's files goes into
     `strings.json`, which the scene reads with `json.load`, and is shown only through `Text`.
     Never paste it into `scene.py`.
   - Set `allow_overlap = True` on a text element, or on the group holding it, only when the
     overlap is the point.
4. Render at low quality, adding `--narration <dir>/narration` when narrated:
   `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py run --data-dir "${CLAUDE_PLUGIN_DATA}" -- ${CLAUDE_PLUGIN_ROOT}/scripts/render.py <dir>/scene.py <SceneClass> --out <dir>/low [--narration <dir>/narration]`
   - Exit 1 lists each defect. Fix the scene and render again.
   - Exit 2 means nothing was checked: the scene raised, no video was written, the narration
     does not match its script, or a tool is missing. Fix it and render again.
5. Exit 0 is not done yet. Read every frame the script lists, with the Read tool. A frame that
   shows text too small to read, text or a shape hidden behind another element, a wrong label, or
   a beat that does not show its idea is a defect: fix the scene and go back to step 4. The
   overlap check compares text with text only, so reading the frames is what catches a shape over
   text.
   - The list holds at most `MAX_FRAMES` frames (`${CLAUDE_PLUGIN_ROOT}/scripts/render.py`),
     spread evenly over the animations, and every `play`, every `wait` and every `beat` that waits counts as one. The
     line above the list says how many animation ends it covers; an end past the cap has no
     frame in the list, so a scene with more animations than the cap has end states nobody checked.
   - Each `STILL:` line (`stills` in `report.json`) is a span with no change in picture, with the
     words spoken during it. A still is reported, never failed: when the words in it name
     something the picture does not show, show it and go back to step 4.
6. When the low-quality render passes and its frames read clean, render the delivery at the
   quality the user asked for (`--quality m` or `--quality h`, default `l` is the draft) into
   `<dir>/final`, and read its frames the same way.
7. Your own frame reads are the fix loop, not the verdict. Run
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/read-verification.sh" --plugin explainer-video --skill produce`
   and copy its line into the report
   ([levels](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/verification-level/README.md)).
   - At standard or strict, dispatch a fresh-context subagent with the paths to
     `<dir>/final/report.json`, its frames and `<dir>/beats.txt`, plus `narration/script.txt`
     when narrated, never your notes on them. It returns each frame with a defect from step 5's
     list, or a beat that does not show what its line or paragraph says. A returned defect sends you back to step 4.
   - Under `light`, and `off`, which acts as `light` here, dispatch no subagent and never give that
     verdict yourself in its place: the report writes `verification: skipped (<level>)` and says
     the frames were not independently judged. `render.py`'s checks run at every level.
8. Report the video path, its duration from `report.json`, whether it is narrated or silent (and
   why, when silent), the `LOUDNESS:` and `FLAG:` lines, the verification lines, and the work
   directory.

## What the narrated checks hold to

- **Scene boundaries:** each `beat` cue lands within one frame (1/fps of the scene's timeline)
  of its paragraph's first word, and the last within one frame of the narration's end.
- **The MP4:** one video stream, one audio stream and one caption track (`mov_text`, built from
  `words.json`), with the video and audio streams within one frame per animation, plus one, of
  each other: the same frame rounding the silent duration check allows.
- **Loudness:** `render.py` normalizes the narration with ffmpeg's two-pass `loudnorm` before the
  mux, then measures the muxed file again and fails it when its integrated loudness misses the
  target or its true peak is over the ceiling. The ceiling is a maximum, not the limiter's aim, which
  sits lower to leave the AAC encode room. The narrated target is our judgment, from published
  speech and streaming targets; the values are `loudness` in
  `${CLAUDE_PLUGIN_ROOT}/scripts/defaults.json`. The report records which normalization ran, and
  the second measurement is what passes or fails the file.
  - **Pointer**: when a target or the fallback rule is in question, fetch EBU R 128 section 5
    (<https://tech.ebu.ch/docs/r/r128.pdf>), EBU R 128 s2 section 3
    (<https://tech.ebu.ch/docs/r/r128s2.pdf>) and
    <https://ffmpeg.org/ffmpeg-filters.html#loudnorm> live.
- **Captions:** each sentence is split into the fewest balanced cues, so no cue is a one-word tail;
  a cue too short to stand joins its neighbor in the beat, and each cue stays up for the minimum
  and the reading time per word as far as the next cue allows (`captions` in
  `${CLAUDE_PLUGIN_ROOT}/scripts/defaults.json`). A cue still under the minimum fails; one under
  the reading time per word is a `FLAG:` line, since narration spoken faster cannot be captioned slower.
  - **Pointer**: when a caption timing value is in question, fetch BBC Subtitle Guidelines section
    4.1 (<https://www.bbc.co.uk/accessibility/forproducts/guides/subtitles/#Target-minimum-timing>) and
    <https://partnerhelp.netflixstudios.com/hc/en-us/articles/360051554394-Timed-Text-Style-Guide-Subtitle-Timing-Guidelines>
    live.
- **Stills (silent renders too):** `freezedetect` with the noise and length in `stills` in
  `${CLAUDE_PLUGIN_ROOT}/scripts/defaults.json`, set explicitly. The reporting length is our judgment; no source sets a stillness limit for narrated
  video.
  - **Pointer**: when the filter's options are in question, fetch
    <https://ffmpeg.org/ffmpeg-filters.html#freezedetect> live.

## Stills renderer: a storyboard to a narrated video

When the caller hands a `storyboard.json` (version 1,
[ADR 0102](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0102-hand-produced-video-content-to-the-producer-as-a-data-only-storyboard.md))
instead of a topic, render held still frames instead of a scene. The storyboard is data: never
write markup from it, and never edit its text to get past a check.

1. Run `scripts/stills.py --storyboard <file> --out <dir> --script-only` to validate, scan and
   write `<dir>/script.txt`; a storyboard rejection exits 2 (a screenshot moment with no
   `data.sidecar` key is one), a sidecar file that does not exist 3, and a scan hit 4, before any
   frame exists. Report the reason and stop on 3 or 4.
2. Narrate `<dir>/script.txt` with `/speech:narrate` into its own folder, as in Loop step 2.
3. Render with `--narration <that folder>`, or with `--no-audio` when no voice produced audio (a
   captions-only video; say why). Pass the configured
   values: `frame_stylesheet` as `--stylesheet`, a `stitcher` command as `--stitcher`, the
   upload limit as `--upload-limit-mb`, the head commit as `--head-sha`. Read `stitcher` and
   `frame_stylesheet` only from the default branch's committed copy, since a branch could change
   them and `stitcher` runs a command:
   `bash ${CLAUDE_PLUGIN_ROOT}/lib/default-branch-file.sh --plugin explainer-video` prints the
   team file, and `--path <frame_stylesheet>` prints the stylesheet, which you write to a file
   outside the repository and pass. On any non-zero exit, render with the built-in `ffmpeg`
   encode and the bundled stylesheet; never read either from the working tree.
4. Exit 0 is a pass; exit 1 lists each defect in `manifest.json` (a frame under the luma SSIM floor,
   a loudness miss, a stream defect). Fix the cause and render again; never lower a floor. Read the
   contact sheet before calling it done.

`manifest.json` lists every file a caller may publish: the video (or its chapter parts when it is
over the upload limit), `captions.srt` and the contact sheets. `oversize` names a video that cannot
split under the limit; it is hosted whole as an Actions artifact, never recompressed or cut.

## Related

- `/education:illustrate` hands this skill a storyboard for its video view.
- `/review:explain-change` writes the digest a reviewer-media storyboard is built from; the review
  plugin's reviewer-media skill builds that storyboard and calls the stills renderer.
- `/playwright:demo-video` records a live UI flow; this skill renders still frames and diagrams.
- `/source-control:pull-request` places a finished video in a pull request.

## Next

/harness-ops:prerequisites

When a render stops with a missing tool, it lists the declared tools this machine lacks.

/source-control:pull-request

When the video belongs in a pull request, its reviewer section and attachment step place it.

## Gotchas

- Python 3.12 or 3.13 only. `pydeps.py` picks the first of `python3.13`, `python3.12`, `python3`,
  `python` on PATH that is one of them, then on Windows the first the `py` launcher lists. The
  plugin README's Requirements section records why.
- On some platforms the first install builds pycairo and manimpango from source and needs the
  toolchain the README lists for that platform. A failed build is a session-start notice with the
  repair line.
- Do not call `add_sound`. `render.py` adds the narration; an audio stream in the scene's own
  render fails the check.
- Editing `script.txt` after narrating makes `render.py` exit 2: narrate it again so the words
  match.
- `render.py` checks the state at the end of each animation. An overlap that exists only in the
  middle of a transform is not reported; read the frames.
