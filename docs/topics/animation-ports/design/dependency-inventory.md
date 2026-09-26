# animation: hardcoded dependencies, assumptions and duplicated values

Read from the working tree at `f0bd01ed0` on 2026-09-24, with another session's uncommitted edits
to `scripts/inkstats.py`, `skills/learn-style/scripts/learn.py` and `styles/woodcut-ink/style.json`
present. Line numbers in those three files may drift. Paths are relative to `plugins/animation/`.

Verdicts:

- **port**: sits behind the render port (or will, once the composition root in contracts.md lands).
- **userConfig**: a personal or admin scalar with a default.
- **presence-gated**: detected at run time, with a visible fallback or remedy.
- **documented**: a stated requirement or a stated default the user can override per run or per clip.
- **fix needed**: undocumented, silently wrong on some input, or in conflict with the plugin
  philosophy. Every fix-needed row is carried into [design-threads.md](design-threads.md): D16 and D18 under
  T10, D44 under T8, D32 under T16, the rest under T15, T17 and T18.

## 1. Dependency and assumption inventory (48 rows, 27 fix needed, 22 distinct fixes)

### Binaries and runtimes

| # | Dependency | Where (file:line) | How it is located | Verdict |
|---|---|---|---|---|
| D1 | `ffmpeg` (decode) | `skills/rotoscope/scripts/extract.py:49-50`, `scripts/inkstats.py:73-74` | bare name on PATH via `subprocess` | documented (README.md:36, rotoscope SKILL.md:19) + **fix needed**: absent, it raises `FileNotFoundError` with a traceback; `docs/plugin-philosophy.md:631` asks for a concise remedy at the entry point |
| D2 | ffmpeg minimum version | same lines: `-fps_mode passthrough` | not checked | **fix needed**: the flag needs a newer ffmpeg than many distro builds ship (judgment, unverified: recheck against the ffmpeg changelog before stating a version) and no version is documented |
| D3 | `ffprobe` | `extract.py:36,39`, `inkstats.py:69` | bare name on PATH | documented; **fix needed**, same as D1 |
| D4 | ffmpeg encode with libx264 | `scripts/capture.mjs:4` (a comment), copied by hand per rotoscope SKILL.md:78-79 and learn-style SKILL.md:48 | the model retypes it | **fix needed**: the encode step is prose, not code; libx264 needs an ffmpeg built with x264, which is not stated. Becomes the encode step of the render entry point (contracts.md, section 3) |
| D5 | `node` | `skills/rotoscope/scripts/measure.py:53`, rotoscope SKILL.md:78 | bare name on PATH | documented (README.md:37); **fix needed**, same as D1 |
| D6 | playwright-core | `scripts/capture.mjs:11-24` | chain: `PW_CORE` env, then `<cwd>/node_modules/playwright-core`, then `<cwd>/node_modules/playwright`, then `command -v playwright-cli` and `../@playwright/cli/package.json` beside its real path | presence-gated: exits 2 with a remedy (`capture.mjs:22-23`) |
| D7 | `PW_CORE` environment variable | `capture.mjs:13`, README.md:37, rotoscope SKILL.md:20 | custom env channel | **fix needed**: `docs/plugin-philosophy.md:395-396` says "Do not add an environment variable merely to create a second configuration channel". A path to installed tooling is either a `userConfig` `directory` option or an install into `${CLAUDE_PLUGIN_DATA}` (`docs/plugin-philosophy.md:341`) |
| D8 | `/bin/sh` and `command -v` | `capture.mjs:17` | POSIX shell | **fix needed**: fails on native Windows (the try/catch then falls through to the remedy, so it degrades, but a playwright-cli install is never found there). `docs/plugin-philosophy.md:703` forbids assuming a shell; either scan `PATH` in JS or declare the boundary |
| D9 | Chromium (Playwright-managed) | `capture.mjs:29` `chromium().launch()` | Playwright's default browser path; remedy `npx playwright install chromium` (`capture.mjs:22`) | documented; build-sensitive behaviour is stamped (rotoscope SKILL.md:105-107, build 1246) |
| D10 | `uv` | README.md:35,47; rotoscope SKILL.md:19; learn-style SKILL.md:21 | on PATH; the scripts themselves do not need it | documented |
| D11 | numpy | imports: `extract.py:26`, `measure.py:32`, `review.py:25`, `inkstats.py:49`, `learn.py:25` | `uv run --with numpy` | documented; **fix needed**: unpinned, and the package list is restated in three docs (V19) |
| D12 | opencv-python-headless | imports: `extract.py:25`, `measure.py:31`, `review.py:24`, `inkstats.py:48` | `uv run --with opencv-python-headless` | documented; **fix needed**, same as D11 |
| D13 | Python version | syntax such as the dict union operator (`learn.py:133`) | whatever `uv` resolves | **fix needed**: no minimum stated; one `requires-python` line (V19 fix) covers it |

### Serving, ports and render wiring

| # | Dependency | Where | Verdict |
|---|---|---|---|
| D14 | HTTP server on `127.0.0.1`, OS-chosen free port | `measure.py:49-52` (`ThreadingHTTPServer(('127.0.0.1', 0))`) | port (native adapter internal). Sound: no fixed port, loopback only, shut down after each call |
| D15 | Render files copied into the user's work dir each run | `measure.py:47-48` (`render.html`, `ink.js`, `roto.js`) | port (adapter internal), but it writes plugin files into user data; the proposed entry point serves two roots instead (module-boundary.md, section 2) |
| D16 | Novel-scene rendering has no serve step | rotoscope SKILL.md:76-79 ("serve the work directory"), learn-style SKILL.md:47-48 | **fix needed**: the only serve code is inside `measure.render()`, which hardcodes `scene=roto.js`. A novel scene (learn-style validation, `produce`) has no documented way to be served; the model improvises a server and port |
| D17 | Scene must sit beside `render.html` and import `./ink.js` | `render.html:8`, `roto.js:7` | port (scene contract, contracts.md section 2) |
| D18 | Missing `window.DURATION` renders zero frames and exits 0 | `capture.mjs:40`: `Math.round(undefined * fps)` is `NaN`, `Array.from({length: NaN})` is empty, exit code 0 at `:55` | **fix needed**: a false green. Fail when `DURATION` is not a positive number |
| D19 | 30 s wait for `renderFrame` | `capture.mjs:35` | documented enough (error surfaces as a Playwright timeout); fine |

### Paths and work-dir layout

| # | Assumption | Where | Verdict |
|---|---|---|---|
| D20 | Shared scripts found by directory depth | `measure.py:35` (`HERE.parents[2] / 'scripts'`), `learn.py:27` (`parents[3]` on `sys.path`) | documented plugin-internal layout; allowed (same plugin, `docs/plugin-philosophy.md:398-404`) |
| D21 | Sibling-module imports | `fit.py:17-18`, `review.py:27` import `measure` | fine: Python puts the script dir on `sys.path` |
| D22 | Work-dir layout `src/`, `d/`, `d/index.json`, `overrides.json`, `out/<tag>/{rep,heat,ab,crops}`, `learnings.md` | `extract.py:47-48,60,66,178,200,214-215`; `measure.py:82-83,95-96,137,144-146,152,155`; `fit.py:58,60`; `review.py:38,71`; `inkstats.py:61-63`; `learn.py:45`; `roto.js:10-14`; `regress.py:26-27` | documented contract (rotoscope SKILL.md:26-34); **fix needed** as SSOT: the strings are respelled in eight files (V20) |
| D23 | Three-digit drawing names, four-digit frame names, lexicographic sort | `d{k:03d}` at `extract.py:60,178`, `measure.py:82-83`, `review.py:38`, `inkstats.py:63`, `capture.mjs:41`; `f%04d` at `capture.mjs:2,4,40`; `sorted(glob(...))` at `inkstats.py:65`, `learn.py:45` | **fix needed**: a film over 9,999 frames (6 min 56 s at 24 fps) or a clip over 999 drawings sorts `f10000` before `f1001`, and `inkstats.py` then measures frames out of order with no error. Sort numerically |

### Sizes, frame rates and resolutions

| # | Assumption | Where | Verdict |
|---|---|---|---|
| D24 | Holds counted in 24 fps frames regardless of `--fps` | `inkstats.py:227` (`* 24`) beside `--fps` default 24 at `:184,289`; docstring `:40` | **fix needed**: "on 2s" for a 30 fps or 12 fps source is counted against 24. Read the base rate from the pack (`knobs.frame_rate.base_fps`) or `--fps` |
| D25 | Pack's base frame rate written as a literal | `learn.py:139` (`base_fps=24`) | **fix needed**, tied to D24: write the source's measured rate |
| D26 | Single-drawing clip gets a 1/8 s duration | `extract.py:63` | **fix needed**: 8 drawings per second is shfred0's rate (on 3s at 24 fps). Use the frame duration from ffprobe |
| D27 | Canvas size comes from the scene | `render.html:6-7`, `roto.js:13` | port (scene contract); fine |
| D28 | Review crop 500x400 "so three panels stay under 2576 px" | `review.py:29`; learn-style SKILL.md:54 | **fix needed**: the origin of 2576 is unrecorded. It needs a four-part record (claim, basis, date, trigger) in one place, and `CROP` should derive from it |
| D29 | Worker counts differ: 4, 8, `min(8, cpu)`, unbounded | `capture.mjs:27` (4), `measure.py:45,134` (8), `fit.py:54` (8), `extract.py:211` (`min(8, os.cpu_count())`), `review.py:90` (`Pool()`, all cores) | **fix needed**: one default, `min(8, cpu)`, from one place (V16) |

### Thresholds tuned on shfred0 only

| # | Value | Where | Verdict |
|---|---|---|---|
| D30 | Acceptance target: floor band 4 gray levels, XOR at most 1.2 x floor, SSIM and edge SSIM at least 0.980 | `measure.py:36` | documented as shfred0-calibrated defaults (`skills/rotoscope/reference/method.md:3-6,57`). Not overridable per clip; thread T19 |
| D31 | Tracing defaults S=4, epsilon 0.25, cubic, unsharp (2.0, 0.9), tone levels 50/90/165/205 | `extract.py:28-30` | documented; `sharp` and `levels` overridable per drawing through the override file |
| D32 | Render brush defaults bias 0.12, blur 0.6, grain 0 | `roto.js:22`, mirrored at `measure.py:37` | documented (method.md:48-49), overridable per drawing; **fix needed** as SSOT (V3) |
| D33 | Bias fit step 0.04, ratio 1.3, 6 rounds, bias range -0.2 to 0.5 | `fit.py:50-52`, `fit.py:37` | documented (arguments; method.md:67-68) |
| D34 | Repeat-drawing rule: fewer than 50 pixels changed by more than 64 gray levels | `extract.py:31,57`, `inkstats.py:51,97` | **fix needed**: an absolute pixel count, tuned at 1762x982, so a 4K source treats small real changes as repeats and a 480p source keeps codec noise as new drawings; also implemented twice (V8) |
| D35 | Tint detection: R-G at least 4, a "sign" at least 6 over more than 15,000 px, regions of at least 300 px, paper above gray 200, tint levels 252/251 | `extract.py:32,149,154,160` | **fix needed**: absolute pixel counts tuned at 1762x982; scale by frame area |
| D36 | Review flags: tile 32 px, blur 3, tone difference 8, paper error 5.0, edge 2 px | `review.py:30-32` | documented as judgment (`review.py:31`); resolution-dependent tile, acceptable for a review aid |
| D37 | Style statistics in absolute pixels: islands 2-200 px (`inkstats.py:116`), contours under 50 px dropped (`:124`), approxPolyDP 4 and 1.5 px (`:127-128`), straight runs of 30 px (`:131`), mid band plus or minus 16 (`:142`), 7 px closing (`:146-147`), flat block 32 px (`:55`) | `scripts/inkstats.py` | **fix needed**: a pack records `measured_from.size`, but `check()` (`inkstats.py:242-260`) never compares it with the film's size, so a film at another resolution passes or fails on scale alone. Warn (or fail) on a size mismatch |
| D38 | Segment length 3.35 s ("nine on a 30 s clip") | `inkstats.py:9,52`, `learn.py:100` | documented default (argument `--seg`); shfred0-derived |
| D39 | Checked statistics and minimum segment size 8 | `learn.py:31-41` | documented; a pack's own `check` and `segment_min_drawings` override them |
| D40 | Two-tone assumption: ink mode below gray 128, paper mode above, T at their midpoint | `extract.py:93-95`, `inkstats.py:137-139` | **fix needed** (documentation): a scope boundary no doc states. A low-contrast, coloured or inverted-majority style measures wrong silently. State it in method.md and statistics.md, and have `inkstats.py` report when either mode histogram peak is weak |
| D41 | Engine default ink `#141211` | `scripts/ink.js:40,75,103,117` | **fix needed**: differs from the woodcut pack's ink `#13110f` (`styles/woodcut-ink/style.json`, `palette.ink`); a scene that forgets `color` renders off-palette by 1 level per channel, inside the pack's tolerance of 3, so the check hides it |
| D42 | Paper grain colours and seed 999 | `ink.js:132,136`, `roto.js:66` | documented engine defaults; woodcut-coloured. Fine until a second pack has a different paper |
| D43 | Chromium `blur()` floor about 0.8 px | `roto.js:71` (JS gaussian workaround) | documented and stamped in both SKILL.md gotchas; unstamped in method.md:49-50 (V11) |

### Anything that assumes the shfred0 clip

| # | Assumption | Where | Verdict |
|---|---|---|---|
| D44 | Regression needs the unshipped clip; expects 239 drawings | `regress.py:3,15-16` | documented; **fix needed**: the plugin's only end-to-end test cannot run in CI or on a fresh machine (thread T8) |
| D45 | Shipped fixture overrides are shfred0 fits | `skills/rotoscope/fixtures/shfred0.overrides.json` | documented, intentional |
| D46 | Paper-error flag threshold judged on the shfred0 replica | `review.py:31` | documented as judgment |

### OS and shell

| # | Assumption | Where | Verdict |
|---|---|---|---|
| D47 | POSIX shell in the Playwright lookup | `capture.mjs:17` | counted in D8 |
| D48 | Windows and macOS untested: `multiprocessing` spawn start method (`extract.py:218`, `review.py:90`), text files opened without `encoding=` (`measure.py:152,155`, `extract.py:66,72`) | several | **fix needed**: record an honest manual-verification gap (`docs/plugin-philosophy.md:706`) or verify; pass `encoding='utf-8'` explicitly |

Fix-needed rows (27): D1, D2, D3, D4, D5, D7, D8, D11, D12, D13, D16, D18, D22, D23, D24, D25,
D26, D28, D29, D32, D34, D35, D37, D40, D41, D44, D48. Some share one fix (D1/D3/D5: one entry-point
prerequisite check; D11/D12/D13: one requirements file; D24/D25: one base-rate source), so there are
22 distinct fixes. D47 repeats D8 and is not counted twice.

## 2. Duplicated values (26 values)

Rule proposed in thread T16: **code reads the value from one owner; docs cite the owner and do not
restate the number.** Two exceptions: a measurement record (a doc reporting what a run measured,
such as STYLE.md's validation or statistics.md's tables) keeps its numbers as data, and a volatile
external specific restated in a skill body carries the four-part record the skill-bodies rule
requires (`.claude/rules/skill-bodies-state-current-rules.md`). A value read by both Python and
JavaScript lives in JSON, because neither language can import the other.

| # | Value | Sites (file:line) | Proposed owner | How the other sites get it |
|---|---|---|---|---|
| V1 | Acceptance target 1.2 x floor, SSIM 0.980, edge SSIM 0.980 | `measure.py:36` (and reads at `:18,104,113`); README.md:42-43; rotoscope SKILL.md:60; method.md:57 | `measure.py:36` | method.md keeps the one prose statement because it explains why; README and SKILL.md say "the `measure.py` target (method.md, Target)" |
| V2 | 239 drawings | `regress.py:16` (and `:5`); README.md:42,51; rotoscope SKILL.md:65,94; method.md:3,37; statistics.md:4; STYLE.md:14; fixture `:2`; `review.py:31`; plugin.json description; CHANGELOG.md:13 | `regress.py:16` (`EXPECTED`) | README and SKILL.md say "exits 0 only when every drawing passes"; method.md, statistics.md, STYLE.md, the fixture and `review.py`'s comment are measurement records and keep it; CHANGELOG is history |
| V3 | Render brush bias 0.12, blur 0.6, grain 0 | `roto.js:22`; `measure.py:37`; method.md:48-49 | new `skills/rotoscope/scripts/brush.json` | `roto.js` fetches it (it already fetches `index.json`); `fit.py` and `measure.py` `json.load` it; method.md cites the file |
| V4 | Tone levels 50, 90, 165, 205 | `extract.py:30`; method.md:45-46 | `extract.py:30` | method.md cites `extract.py` (`LEVELS`) with its reason |
| V5 | Unsharp mask (2.0, 0.9) | `extract.py:29`; method.md:33 | `extract.py:29` | method.md cites `SHARP` |
| V6 | Supersample 4, epsilon 0.25 | `extract.py:28`; method.md:29,31 | `extract.py:28` | method.md cites `S`, `EPS` |
| V7 | Fit step 0.04, ratio 1.3 | `fit.py:50-51`; method.md:67-68 | `fit.py` arguments | method.md says "`fit.py` automates this (see its `--step`, `--ratio`)" |
| V8 | Repeat rule 50 px changed by more than 64 levels | `extract.py:31,57`; `inkstats.py:19,51,97`; method.md:19-20 | one function in the shared source-in module (`scripts/decode.py`, module-boundary.md) | `extract.py` and `inkstats.py` import it; method.md cites it |
| V9 | Gray-mode split at 128, T at the mode midpoint, the plus-or-minus 16 mid band, paper mask T + 16 | `extract.py:94-95,102`; `inkstats.py:138-139,142`; `measure.py:74` | one `modes(gray)` function in `scripts/decode.py` | the three scripts import it |
| V10 | ffprobe and ffmpeg decode argument lists | `extract.py:35-41,49-50`; `inkstats.py:68-74` | `scripts/decode.py` | both import it |
| V11 | Chromium `blur()` floor about 0.8 px, build 1246 | rotoscope SKILL.md:105-107 (stamped); learn-style SKILL.md:79-80 (stamped); method.md:49-50 (unstamped); `roto.js:71` (code comment) | one stamped record in method.md | both SKILL.md gotchas point to it; the code comment stays (code comments are not governed by the rule) |
| V12 | 24 fps | `inkstats.py:40,184,227,289`; `learn.py:139`; `ink.js:4`; rotoscope SKILL.md:78; learn-style SKILL.md:48; statistics.md:36; STYLE.md:22 | style meaning: the pack's `knobs.frame_rate.base_fps`; render rate: `shots.json` `fps` (produce) or the source's rate (rotoscope) | `inkstats.py` reads the pack when `--pack` is given, else `--fps`; SKILL.md bodies say "the source's frame rate" or "the shot list's fps"; `ink.js:4` is an example comment and stays |
| V13 | Ink colour | `ink.js:40,75,103,117` (`#141211`); `style.json` `palette.ink` (`#13110f`); STYLE.md:19 | engine default: one `const INK` in `ink.js`; styled work: the pack's `palette.ink` | the four `ink.js` sites use the const; scenes pass the pack colour; STYLE.md is a record |
| V14 | Paper grain seed 999 | `ink.js:132`, `roto.js:66` | `ink.js:132` default | `roto.js` drops its explicit `seed: 999` |
| V15 | Segment length 3.35 s | `inkstats.py:9,52`; `learn.py:40,100`; statistics.md:43; `style.json` `measured_from.segment_seconds` | `inkstats.py:52` (`SEG`) | `learn.py:100` already reads it; statistics.md cites `SEG`; the pack value is a measurement record |
| V16 | Worker counts 4 / 8 / `min(8, cpu)` / all cores | `capture.mjs:1-2,27`; `measure.py:45,134`; `fit.py:54`; `extract.py:211`; `review.py:90` | one `WORKERS = min(8, os.cpu_count())` in the shared render entry point | Python scripts import it; `capture.mjs` always receives it as an argument, so its own default only matters for manual runs |
| V17 | 2576 px long-edge limit | `review.py:29` (comment); learn-style SKILL.md:54 | one stamped record (origin unrecorded today) in `skills/rotoscope/reference/method.md` | `review.py` derives `CROP` from a named constant; learn-style SKILL.md points to the record |
| V18 | Soften sigma 0.92 px | `style.json` `brush.soften_sigma_px`; learn-style SKILL.md:78; STYLE.md:42 | the pack (`brush.soften_sigma_px`) | the gotcha is a measurement record of round 3 and may keep it; otherwise cite the pack |
| V19 | Python packages and the `uv run --with ...` line | README.md:35,47; rotoscope SKILL.md:18-19; learn-style SKILL.md:20-21 | new `plugins/animation/requirements.txt` (pinned, with a `requires-python` note in README) | commands become `uv run --with-requirements ${CLAUDE_PLUGIN_ROOT}/requirements.txt python ...`; learn-style already defers to rotoscope's list and should defer to README instead |
| V20 | Work-dir path strings (`src/dNNN.png`, `d/index.json`, `d/dNNN.json`, `out/<tag>/...`, `overrides.json`, `learnings.md`) | eight files, listed at D22 | new `scripts/workdir.py` (shared, because `inkstats.py` reads work dirs and must not import from a skill) | Python scripts import path helpers; `roto.js` keeps its `?dir=` parameter; rotoscope SKILL.md's table stays as the documented contract |
| V21 | Playwright lookup order and remedy | `capture.mjs:11-24`; README.md:37-38; rotoscope SKILL.md:20-21 | `capture.mjs` (the runtime artifact) | README states the requirement and says `capture.mjs` prints the remedy; SKILL.md points to README (the setup `check` reads `capture.mjs`, per `docs/plugin-philosophy.md:490-496`) |
| V22 | Frame naming `fNNNN.png` and drawing naming `dNNN.png` | `capture.mjs:1-2,40-41`; `inkstats.py:65`; the `d{k:03d}` sites in D23 | `scripts/workdir.py` for Python; `capture.mjs` for captured names | the frame-folder contract in contracts.md cites one pattern |
| V23 | Encode settings libx264, yuv420p, crf 16 | `capture.mjs:4`; referenced (not restated) by both SKILL.md bodies | the encode step in the render entry point | SKILL.md bodies call the step instead of pointing at a comment |
| V24 | `inkFill` width 12, pitch 0.78 | `ink.js:40`; `style.json` `brush.inkFill` | intentional: the pack pins the style even if the engine default moves | keep both; no change |
| V25 | Minimum segment size 8 | `learn.py:41`; `style.json` `segment_min_drawings`; `inkstats.py:252` default 1 | intentional: `learn.py` writes it into the pack, the pack is read at check time | keep |
| V26 | Validation result 15/15 | README.md:23; STYLE.md:48; statistics.md:78; CHANGELOG.md:23 | STYLE.md, Validation | README says "passes its check (STYLE.md, Validation)"; statistics.md is a record; CHANGELOG is history |

Of the 26, V24 and V25 are intentional and need no change; 24 need an owner decision (thread T16).
