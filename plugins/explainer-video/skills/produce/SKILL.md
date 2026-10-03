---
description: "Produce a short silent explainer video with ManimCE: plan the beats, write one scene script, render it at low quality, and check the file before calling it done (ffprobe duration, no audio stream, a frame read back after every animation, overlapping text and elements cut off by the frame edge). Use when: 'make an explainer video', 'animate this concept', 'Manim video of', 'render a math animation', 'turn this explanation into a video', 'silent explainer clip'. Not for hand-drawn film from style packs (use /animation:produce). Narration and captions are not part of this skill."
argument-hint: "<topic> [output dir]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Script, render and self-check a silent ManimCE explainer video
---

# Produce

Turn a topic into a short silent MP4 made with ManimCE. Every render is checked by
`render.py`, and you read its frames back, before the video is called done.

Run every script through the launcher, which uses the packages the SessionStart hook installed and
never installs:
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py run --data-dir "${CLAUDE_PLUGIN_DATA}" -- <script> ...`.
When it exits 2 with a repair line, or `render.py` names a missing tool, run `/explainer-video:check`
and report what it prints.

## Where the files go

One work directory per video: the directory the user names, else
`${CLAUDE_PLUGIN_DATA}/videos/<slug>/`. A video is a view, so it never goes inside a record bundle
or beside the markdown record it explains
([record-bundle](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/record-bundle/README.md)).

| Path | Who writes it | What it holds |
|---|---|---|
| `scene.py` | you | one `Scene` subclass |
| `strings.json` | you, only for untrusted text | on-screen strings the scene loads |
| `low/`, `final/` | `render.py` | `<Scene>.mp4`, `frames/fNNNN.png`, `report.json` |

## Loop

1. Plan three to six beats, one idea each, under a minute in total. A beat is something the viewer
   sees change, not a sentence to read.
2. Write `scene.py`. `${CLAUDE_PLUGIN_ROOT}/skills/produce/examples/pythagoras.py` is a working
   scene in the expected shape.
   - Words are `Text`. Math is `MathTypst` (Typst math syntax). Do not use `Tex` or `MathTex`:
     LaTeX is not part of this plugin yet.
   - Text that came from a pull request, a fetched page or another repository's files goes into
     `strings.json`, which the scene reads with `json.load`, and is shown only through `Text`.
     Never paste it into `scene.py`.
   - The scene plays at least one animation. Use `self.wait` for holds.
   - Set `allow_overlap = True` on a text element, or on the group holding it, only when the
     overlap is the point.
3. Render at low quality:
   `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py run --data-dir "${CLAUDE_PLUGIN_DATA}" -- ${CLAUDE_PLUGIN_ROOT}/scripts/render.py <dir>/scene.py <SceneClass> --out <dir>/low`
   - Exit 1 lists each defect. Fix the scene and render again.
   - Exit 2 means nothing was checked: the scene raised, no video was written, or a tool is
     missing. Fix it and render again.
4. Exit 0 is not done yet. Read every frame the script lists, with the Read tool. A frame that
   shows text too small to read, text or a shape hidden behind another element, a wrong label, or
   a beat that does not show its idea is a defect: fix the scene and go back to step 3. The
   overlap check compares text with text only, so reading the frames is what catches a shape over
   text.
5. When the low-quality render passes and its frames read clean, render the delivery at the
   quality the user asked for (`--quality m` or `--quality h`, default `l` is the draft) into
   `<dir>/final`, and read its frames the same way.
6. Report the video path, its duration from `report.json`, and the work directory.

## Next

/explainer-video:check

When a render stops with a repair line or a missing tool.

## Gotchas

- Python 3.12 or 3.13 only. `pydeps.py` picks the first of `python3.13`, `python3.12`, `python3`,
  `python` on PATH that is one of them. The plugin README's Requirements section records why.
- On some platforms the first install builds pycairo and manimpango from source and needs the
  toolchain the README lists for that platform. A failed build is a session-start notice with the
  repair line.
- The render is silent. Do not call `add_sound`: an audio stream fails the check.
- `render.py` checks the state at the end of each animation. An overlap that exists only in the
  middle of a transform is not reported; read the frames.
