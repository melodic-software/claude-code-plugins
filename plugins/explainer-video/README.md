# explainer-video

A Claude Code plugin for short silent explainer videos made with
[ManimCE](https://docs.manim.community/). Claude writes one scene script, renders it, and checks the
file it rendered before calling the video done.

## Skills

| Skill | What it does |
|---|---|
| `/explainer-video:produce <topic> [output dir]` | Plans three to six beats, writes `scene.py` (`Text` for words, `MathTypst` for math), renders it at low quality with `scripts/render.py`, fixes and re-renders until every check passes, reads the extracted frames back, then renders the delivery quality. |
| `/explainer-video:check` | Read-only: one PASS/FAIL row each for Python 3.12 or 3.13, the installed ManimCE packages, ffmpeg and ffprobe. Installs nothing. |

## What every render checks

`scripts/render.py` renders one scene and fails the run (exit 1, each defect listed in
`report.json`) when:

- ffprobe does not find exactly one video stream, finds an audio stream, or reads a duration that
  differs from the scene's own timeline by more than a frame per animation;
- a frame extracted at the end of an animation is blank while something is on screen;
- two text elements overlap at the end of an animation (an element marked `allow_overlap = True`
  is skipped);
- an element is partly past the frame edge at the end of an animation.

It extracts one frame per animation (at most 24, evenly sampled) into `frames/`, and the skill
reads each one as an image, which is what catches a shape covering text or a label that says the
wrong thing.

Videos are views: they are written to the directory the user names or to
`${CLAUDE_PLUGIN_DATA}/videos/<slug>/`, never inside a
[record bundle](../../docs/conventions/record-bundle/README.md).

Narration, captions and the final mux are not part of this plugin yet.

## Requirements

`/explainer-video:check` reports each of these. `prerequisites.json` declares them.

- Python 3.12 or 3.13 with pip. Python 3.14 is not supported: moderngl and glcontext publish no
  3.14 wheel. ManimCE is not vendored and never fetched while a skill runs: a SessionStart hook
  installs the hash-locked set in `requirements.txt` into the plugin data directory
  (`pip install --require-hashes`) and does nothing once it loads. A failed install is reported as
  a notice with the repair line. The first install takes a few minutes.
- Three packages build from their hash-pinned source archives, because no wheel exists for the
  platform: `srt` everywhere, `pycairo` on Linux and macOS, `manimpango` on Linux. Every other
  package installs from wheels only. The build needs a C compiler, `pkg-config`, and the cairo
  and pango development packages, which the plugin never installs:
  - Debian and Ubuntu: `sudo apt install build-essential pkg-config libcairo2-dev libpango1.0-dev`
  - Fedora: `sudo dnf install gcc pkgconf-pkg-config cairo-devel pango-devel`
  - macOS (pycairo only): `brew install pkg-config cairo`
  - Windows needs none of these: pycairo and manimpango have Windows wheels, and `srt` is pure
    Python.
- `ffmpeg` and `ffprobe` on PATH.
- Node, which runs the SessionStart hook.

The wheel-availability facts above come from the release files of
[pycairo](https://pypi.org/project/pycairo/#files), [manimpango](https://pypi.org/project/manimpango/#files)
and [moderngl](https://pypi.org/project/moderngl/#files). As of 2026-10-03. Recheck when a Dependabot
PR bumps any of them or when a new Python release ships; widen the Python range in `pydeps.py` and
`prerequisites.json` once a 3.14 wheel set exists.

To change a pin, edit `requirements.in` and regenerate the lock from this directory:
`uv pip compile requirements.in --universal --generate-hashes --python-version 3.12 -o requirements.txt`.
The lock carries a hash for every wheel and source archive; `scripts/pydeps.py` passes pip
`--only-binary` for every package except the three above.

## Tests

`scripts/explainer-video.test.sh` runs the installer and check-function suites with the standard
library. The two real renders in `test_explainer_video_render.py` need ManimCE, ffmpeg and ffprobe, and skip
without them; run them through the launcher with `EXPLAINER_VIDEO_REQUIRE_DEPS=1` so a missing
dependency fails instead. `hooks/install-python-deps.test.sh` covers the install hook against a
local fixture wheel.
