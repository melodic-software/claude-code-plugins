# animation: domain model (design round 1)

Scope: module + integration design for `plugins/animation`. This file separates three things the
user asked to keep apart: process skills (behaviour), domain artifacts (tool-neutral stage files),
and ports with adapters (the infrastructure the process reaches through). Nothing here is decided;
open points are threads in [design-threads.md](design-threads.md).

File references were read from the working tree at `f0bd01ed0` on 2026-09-24. Another session is
editing `inkstats.py`, `learn.py` and `style.json`, so line numbers in those three files may drift.

## 1. Process skills (verbs)

| Skill | Status | In | Out | Behaviour |
|---|---|---|---|---|
| `rotoscope` | ships | reference video, work dir | traces, override file, measured replica, review crops, learnings | decode, trace, render, measure, fit, review, record, retro |
| `learn-style` | ships | rotoscope work dir | style pack | measure statistics into bands, describe judgment knobs, validate with a new scene |
| `produce` | planned (was `film`) | brief, style pack(s) | boards for approval, shot list, scenes, frames, delivered file, review | brief, pre-production boards, approval gate, shots, render, review against the pack |
| `setup` | missing, proposed | nothing | PASS/FAIL table | check-only: probes ffmpeg, ffprobe, node, playwright-core with Chromium, Python with numpy and opencv |

Why `setup` is proposed: `docs/plugin-philosophy.md:423-428` requires a `setup` skill when a
plugin has an external prerequisite (criterion b). This plugin has five (see
[dependency-inventory.md](dependency-inventory.md), section 1), and today the first sign of a
missing one is a Python traceback. It is check-only under the carve-out at
`docs/plugin-philosophy.md:566-581`: nothing it could write is owned by the plugin.

Considered and not proposed:

- `check` (a style-pack gate as its own skill). The verb table fixes `check` as a deterministic
  pass/fail gate (`docs/plugin-philosophy.md:139`), and `inkstats.py --pack` is exactly that. But
  it is a step inside `learn-style` (validate) and `produce` (review), never a user goal on its
  own. It stays a shared script both skills call. Revisit if users ask "check my film against the
  woodcut pack" outside those two flows (learn-style's description already carries that trigger).
- `render` or `deliver` as skills. Rendering is a step of every skill above, not a goal. Delivery
  is the future `post` plugin's job (module-boundary.md, section 4).

## 2. Domain artifacts (tool-neutral stage files)

Markdown for people, JSON for tools. No tool's file layout is adopted (DIRECTION.md, "Stage
artifacts use the plugin's own tool-neutral format").

### 2.1 Artifacts that exist today

| Artifact | Today's path | Written by | Read by | Schema (sketch) |
|---|---|---|---|---|
| Scene module | any `.js` served beside `render.html`; `skills/rotoscope/scripts/roto.js` is the only shipped one | the model (novel scenes), `roto.js` (traces) | native render adapter (`scripts/render.html:6-8`, `scripts/capture.mjs:35-48`) | ES module that sizes `canvas#c`, sets `window.DURATION` (s) and `window.renderFrame(t) -> Promise`; optional `window.renderDrawing(k) -> Promise` (`roto.js:88-94`) |
| Work dir index | `<work>/d/index.json` | `extract.py:44-66` | `roto.js:11`, `inkstats.py:61-63`, `measure.py:137`, `fit.py:58`, `extract.py:214` | `{w, h, duration, drawings: [[k, pts, t1], ...]}` |
| Trace | `<work>/d/dNNN.json` | `extract.py:175-201` | `roto.js:14`, `measure.py:82`, `fit.py:60`, `review.py:37`, `learn.py:45` | `{k, pts, t1, w, h, S, eps, interp, sharp, levels, ink, paper, T, t_color, gray, paths:[{d, holes}], tones:[{lv, color, paths, tint?}], brush?}` (`extract.py:9-12`) |
| Source drawings | `<work>/src/dNNN.png` | `extract.py:60` | measure, review, inkstats, learn | PNG at source size |
| Override file | `<work>/overrides.json`; shipped fixture `skills/rotoscope/fixtures/shfred0.overrides.json` | the model, `fit.py` | `extract.py:70-85` | `{overrides: [{k: n or [k0,k1], brush?: {bias, blur, grain, tones}, sharp?, levels?, tint?, why?}]}` (rotoscope `SKILL.md:36-54`) |
| Measurement table | `<work>/out/<tag>/table-K0-K1.md` | `measure.py:107-122,152` | people; `fit.py` calls `measure.measure()` in-process instead | markdown table only, no JSON |
| Review table and crops | `<work>/out/<tag>/review-K0-K1.md`, `crops/dNNN.png` | `review.py` | people | markdown table plus 1:1 PNG crops |
| Learnings log | `<work>/learnings.md` | `measure.py:155-158` (one line per run), the model | the model at retro time | free markdown, one bullet per run |
| Style pack | `styles/<name>/style.json`, `STYLE.md` | `learn.py`, then the model | `inkstats.py --pack` (`inkstats.py:242-260`), the model when authoring | keys: `name, credit, measured_from, palette, knobs, stats, timing, heldout, bands, check, segment_check, segment_min_drawings, brush, rotoscope_fits`; `knobs` holds the seven-knob schema (movement, camera, backgrounds, color, line, frame_rate, texture) |
| Film statistics | `inkstats.py --json OUT`, `--rows OUT` | `inkstats.py` | people, the model | per-statistic p10/p50/p90 plus per-segment medians |
| Frame folder | any dir of `fNNNN.png` | `capture.mjs --fps` (`capture.mjs:39-40`) | ffmpeg (encode line, `capture.mjs:4`), `inkstats.py:64-66` | PNG per frame, name index = frame number; the fps is not stored anywhere |

The work-dir layout is the plugin's main file-format contract today. Its path strings are spelled
out in seven files (dependency-inventory.md, V20).

### 2.2 Artifacts `produce` needs (none exist; sketches only)

All live in one production dir the user names, like a rotoscope work dir.

| Artifact | Path (proposed) | Schema (sketch) |
|---|---|---|
| Brief | `brief.md` | prose: subject, length, audience, style pack(s) or influences, delivery format |
| Style guide board | `boards/style-guide.md` | points at the pack (`styles/<name>/STYLE.md`) and lists knob values that differ from it, each marked measured or judgment |
| Palette board | `boards/palette.json` | the pack's `palette` shape: `{ink, paper, tones:[{lv, color}], tolerance}` |
| Vibe board | `boards/vibe.md` | reference images with credit and what each is for |
| Model sheets | `boards/models/<name>.md` + `<name>.js` element module + rendered `<name>.png` | turnaround poses rendered through ink.js, so an approved sheet is already code |
| Element and scenery sheets | `boards/elements/<name>.md` + `.js` + `.png` | same shape as model sheets |
| Storyboard | `boards/storyboard.json` + one PNG per panel | `[{shot, panel, t, png, action, camera, caption?}]` |
| Shot list | `shots.json` | `{fps, size:[w,h], shots:[{id, t0, t1, scene, pack, audio?:{path, start}}]}`; its `t0` values are the `--cuts` `inkstats.py` needs, so cuts have one owner |
| Render manifest | `<frames dir>/render.json` | `{scene, adapter, adapter_version, browser_build, fps, size, frames, duration, license_notice?}`; written by the render port, read by review and later by `post` |

The approval gate sits between boards and shots (DIRECTION.md: pre-production artifacts "for the
user to approve"). Nothing past the storyboard renders until the user approves.

## 3. Ports and adapters

A port gets a contract only where two adapters exist or are named in DIRECTION.md. Otherwise the
row says "one adapter, no port yet": the code stays a plain function with a clear home, and becomes
a port when its second adapter is real.

| Port candidate | Verdict | Adapters today (files) | Future adapters (named) |
|---|---|---|---|
| **render** (scene module to frames) | **port**: DIRECTION.md names HyperFrames and Remotion | native: `scripts/render.html`, `scripts/capture.mjs`, served and driven by `skills/rotoscope/scripts/measure.py:40-58` (the de facto composition root) | HyperFrames (Apache-2.0), Remotion (source-available; licence notice), both presence-gated |
| **encode** (frames to a delivered file) | one adapter, no port yet | ffmpeg, as a comment only: `scripts/capture.mjs:4`; the skills tell the model to copy that line (rotoscope `SKILL.md:77-79`, learn-style `SKILL.md:47-48`) | none named; moves to `post` at extraction. HyperFrames and Remotion encode internally, so they cover render+encode in one call |
| **source-in** (video to distinct drawings with times) | one adapter, no port yet; code duplicated | ffmpeg/ffprobe decode written twice: `skills/rotoscope/scripts/extract.py:35-68` and `scripts/inkstats.py:58-80` (which also reads frame folders and work dirs) | "source image in" is named in DIRECTION.md without a tool |
| **measure** | not a port: two different core operations | fidelity (replica vs source, per drawing): `measure.py:61-104`; style statistics (film vs pack bands): `inkstats.py` | "quality metrics" is named in DIRECTION.md without a tool. No external tool computes either, so there is nothing to invert |
| **audio-in** | none | nothing in the plugin; pixel-art has "no adapter" either (`plugins/pixel-art/reference/backends.md`, Audio) | named in DIRECTION.md; a WAV path plus start offset in `shots.json` is enough until a second source exists |
| **preview** | none | nothing; review is 1:1 crops (`review.py`), and DIRECTION.md forbids reviewing GIFs | a GIF or contact sheet for the approval gate is an encode option, not a port |
| browser runtime (find playwright-core and Chromium) | not a port: internal to the native render adapter | lookup chain `capture.mjs:11-24` | none |

Where the pixel-art pattern fits: pixel-art's `reference/backends.md` already defines the shape
this plugin should reuse for an adapter row (Adds, Detect, Cost and licence, Contract) and the
selection rule (default native; a named adapter runs only when asked or configured and detection
passes; otherwise one-line notice and native). pixel-art ships that selection with no adapter code
(`plugins/pixel-art/.claude-plugin/plugin.json`, description). [contracts.md](contracts.md) applies
the same shape to the render port and nowhere else.
