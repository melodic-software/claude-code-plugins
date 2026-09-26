# animation ports: deviations log

Append-only. Each entry: plan said / found / chose / revisit.

## Phase 0

- **discovery: Step 0a inputs.** Plan said: copy the clips and the `47d7ba2ae` ctl summaries to
  `~/.local/share/animation-inputs/`. Found: the clips were there with a five-line manifest; the ctl
  summaries were not. Chose: copied `.work/classes/r10/ctl` to `ctl-47d7ba2ae/` and appended its
  files to `MANIFEST.sha256` (42 lines). Revisit: no.
- **deviation: `--other` order.** Plan said (Phase 0 step 3): `--other <BiosRiosz>
  <kevin_t_ngo-2102171059592241410> <kevin_t_ngo-2102437977435893771>`. Found: `controls.py measure`
  alternates calibration and evaluation by position, and the `47d7ba2ae` run put `…2102437977435893771`
  second; the plan's order swaps the two kevin clips between halves, so `learn.py` writes a
  different `negatives` list and `cmp` against the committed `style.json` fails (every one of the
  36 summaries matched `47d7ba2ae` byte for byte modulo that split). Chose: the order Bios,
  `…2102437977435893771`, `…2102171059592241410`, which reproduces the committed `style.json`.
  Revisit: no.
- **discovery: toolchain.** Private playwright-core `1.64.0-alpha-1789764292000` (the version the
  installed playwright-cli bundles) and its Chromium (headless shell 154.0.8037.0, build 1246)
  under `~/.local/share/animation-inputs/toolchain/`.

## Phase 1

- **deviation: `capture.mjs` scope.** Plan said: `capture.mjs` only drops the ffmpeg header line.
  Found: `render.py` cannot see `DURATION`, `renderDrawing` or the browser build without the page.
  Chose: `capture.mjs` exits 1 on a missing or non-positive `DURATION` (fps mode) or a missing
  `renderDrawing` (drawings mode), and prints one JSON line `{browser_build, size, frames,
  duration}` that `render.py` writes into `render.json`. Revisit: no.
- **deviation: `render.json` `adapter_version`.** Contracts.md does not say what it holds for the
  native adapter. Chose: the plugin version from `.claude-plugin/plugin.json` (the native adapter
  ships with the plugin). Revisit: when a second adapter ships.
- **deviation: `controls.encode` removed.** Plan said `controls.encode` and `replica` call
  `render.encode`. Chose: `controls.held(work, folder)` yields the held frames; `replica` and
  `learn.py` call `render.encode(held(...), 'mp4', 24, path)` directly, so no wrapper remains. The
  ffmpeg arguments are unchanged (`-framerate 24`).
- **deviation: `measure.render` renamed `measure.replicas`.** The straggler grep requires no
  `measure.render`; `fit.py` calls `measure.replicas`, and `fit.py`/`review.py` read `WORKERS`
  through `from measure import render`.
- **choice: `--encode` output path.** Contracts.md says "beside the folder"; `render.py` writes
  `<out dir>.<fmt>`. `--encode` with `--drawings` is a usage error.
- **discovery: stale docs outside the file list.** The phase verifier found `README.md:29,37` and
  `learn-style/reference/statistics.md:6,133` still name `capture.mjs` as the render or encode
  path. Left for Phase 3 (README) and Phase 5 (docs cite owners). Revisit: at those phases.

## Phase 2

- **choice: the mid band is `decode.MID = 16`.** Plan named `modes(gray)` as owning "the plus-or-minus
  16 mid band". `modes()` returns `(ink mode, paper mode, T)`; the 16 is `decode.MID`, read by
  `inkstats.one`, `extract.stats` and `measure.paper` (`T + MID`).
- **choice: `extract.decode` keeps its name** and imports `probe, frames, is_repeat, modes, MID`
  from `decode`; it probes once for `w, h, pts` (for `index.json` and its summary line) and
  `decode.frames` probes again. Two extra ffprobe runs per extract; output identical.
