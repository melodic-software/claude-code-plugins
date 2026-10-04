---
description: "Produce a short explainer video with ManimCE, narrated when the speech plugin is installed: plan the beats, write the narration and one scene script, time each scene change to the narration's word timings, render at low quality, mux the audio with ffmpeg, add captions, and check the file before calling it done (ffprobe streams and duration, a frame read back after every animation, overlapping text and elements cut off by the frame edge). Without the speech plugin it renders a silent video. Use when: 'make an explainer video', 'narrated explainer', 'animate this concept', 'Manim video of', 'render a math animation', 'turn this explanation into a video', 'silent explainer clip'. Not for hand-drawn film from style packs (use /animation:produce)."
argument-hint: "<topic> [output dir]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Script, narrate, render and self-check a ManimCE explainer video
---

# Produce

Turn a topic into a short MP4 made with ManimCE, narrated when `/speech:narrate` is available.
The audio comes first: each scene change waits for the word that starts its part of the
narration. Every render is checked by `render.py`, and you read its frames back, before the video
is called done.

Run every script through the launcher, which uses the packages the SessionStart hook installed and
never installs:
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py run --data-dir "${CLAUDE_PLUGIN_DATA}" -- <script> ...`.
When it exits 2 with a repair line, or `render.py` names a missing tool, run `/explainer-video:check`
and report what it prints.

## Where the files go

One work directory per video: the directory the user names, else
`${CLAUDE_PLUGIN_DATA}/videos/<slug>/`. A video and its audio are views, so they never go inside a
record bundle or beside the markdown record they explain
([record-bundle](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/record-bundle/README.md)).

| Path | Who writes it | What it holds |
|---|---|---|
| `scene.py` | you | one `Scene` subclass |
| `strings.json` | you, only for untrusted text | on-screen strings the scene loads |
| `narration/script.txt` | you, when narrated | the words spoken, one paragraph per beat |
| `narration/narration.wav`, `narration/words.json` | `/speech:narrate` | the audio and each word's start and end |
| `low/`, `final/` | `render.py` | `<Scene>.mp4`, `frames/fNNNN.png`, `report.json`; `captions.srt` and `timing.json` when narrated |

## Loop

1. Plan three to six beats, one idea each, under a minute in total. A beat is something the viewer
   sees change, not a sentence to read.
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
6. When the low-quality render passes and its frames read clean, render the delivery at the
   quality the user asked for (`--quality m` or `--quality h`, default `l` is the draft) into
   `<dir>/final`, and read its frames the same way.
7. Report the video path, its duration from `report.json`, whether it is narrated or silent (and
   why, when silent), and the work directory.

## What the narrated checks hold to

- **Scene boundaries:** each `beat` cue lands within one frame (1/fps of the scene's timeline)
  of its paragraph's first word, and the last within one frame of the narration's end.
- **The MP4:** one video stream, one audio stream and one caption track (`mov_text`, built from
  `words.json`), with the video and audio streams within one frame per animation, plus one, of
  each other: the same frame rounding the silent duration check allows.

## Next

/explainer-video:check

When a render stops with a repair line or a missing tool.

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
