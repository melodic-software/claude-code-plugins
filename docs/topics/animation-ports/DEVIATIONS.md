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

## Phase 3

- **blocked (human-decision): `check-changed-skills.sh main` exits 1.** The new `setup` skill passes
  (0 errors, 0 warnings; evals lint PASS). The six failures predate this phase: `rotoscope` and
  `learn-style` ship no `evals/evals.json` (new on this branch); `pixel-art` `animate`, `scene`,
  `sprite` ship none (from `feat/pixel-art`); `disk-hygiene` `clean` fails its own tests because
  the gate diffs against a `main` that moved past this branch's merge base (two-dot diff). Revisit:
  after the rebase onto main (Phase 10); evals for rotoscope and learn-style are outside every
  phase's file list, so they need a plan decision.
- **deviation: `--playwright-core` reaches only `render.py` commands.** Plan wires the option
  through SKILL.md into `render.py`. `measure.py`, `fit.py` and `regress.py` call `render.render`
  in-process and take no such argument, so the option does not reach the rotoscope measure/fit
  loop; those renders use the working-directory and playwright-cli lookups. The net now runs from
  the private toolchain dir so the working-directory lookup finds its playwright-core. Revisit:
  whether measure.py and fit.py should forward `--playwright-core`.
- **choice: `require()` prints the first failed row only**, so a missing ffmpeg prints one line
  (the libx264 row follows from it). `check()` still reports every row.
- **choice: a set `playwright_core` option gets its own row**, which FAILs when the directory holds
  no playwright-core, even when a fallback lookup would still find one (setup "verifies a set
  value resolves").
- **choice: a numpy/opencv version other than the pin is INFO, not FAIL**, so scripts still run;
  `require` stops only on a missing package.
- **choice: Chromium launch failure exits 2** (it was 1): a missing browser is a prerequisite.
- **discovery: `-fps_mode` minimum.** FFmpeg 5.1, recorded as a four-part record in
  `scripts/prereq.py` (basis: `doc/ffmpeg.texi` has `fps_mode` at tag `n5.1`, not at `n5.0`).
- **discovery: Python minimum** 3.12, from numpy 2.5.3's `requires_python` on PyPI; stated in
  README and `requirements.txt`.

## Phase 4

- **plan-confirmed: O5 spike misses; fallback (b).** `fixtures/synthetic.js` (480x270, 24 drawings
  on 2s and 3s, 2.5 s) rendered, encoded, re-traced and measured at the default brush: 0/24 pass,
  mean xor 0.190 % against floor 0.112 % (xor/floor about 1.7), ssim 0.9838, ssim_e 0.9669, paper_err
  1.50. `regress.py --synthetic` asserts the drawing count and the render/encode/decode contracts
  and prints the fidelity table without gating on it.
- **blocked (human-decision): follow-up issue not filed.** The phase-entry search
  `gh issue list --state all --search 'animation synthetic fixture CI in:title'` returned `[]`.
  Filing is a tracker write the routing table gives the main session; nothing was created.
- **choice: regression-case wiring.** The D18 case writes the fixture minus its `window.DURATION`
  line into the work dir and runs `render.py` as a subprocess; `./ink.js` resolves from `scripts/`.
  The drawing starts are checked against `SYN_HOLDS` in `regress.py`, a copy of the fixture's
  `HOLDS` (two sites, one test pair).
- **choice: pack control output (Phase 4).** `regress.py <shfred0>` writes the replica mp4 to
  `<work>/out/regress/replica.mp4` and prints `pack control: the replica passes woodcut-ink`; its
  exit is 1 when either the measure or the pack check fails.

## Phase 5

- **deviation: `inkstats.py` does not import `workdir`.** Plan lists it among the importers; the
  work-dir reading moved to `decode.frames` in Phase 2, so `decode.py` and `render.py` import it
  instead.
- **choice: `measure.py` loads `brush.json` as `measure.BRUSH`**; `fit.py` reads `BRUSH['bias']`
  from it (one Python load site; `roto.js` fetches the same file).
- **choice: `fit-brushes.json`, table and review file names stay in their scripts.** They are
  per-run outputs of one script each, not layout two scripts share.
- **discovery: V17 origin found.** 2576 px is the long-edge limit in the Claude vision guide's
  "Resolution and token cost" table (Claude 4.7 and later; 1568 px before). Recorded as a four-part
  record in `method.md`, Reviewing images; `review.py` has `LONG_EDGE` and `CROP = (min(500,
  LONG_EDGE // 3), 400)`, value unchanged.
- **choice: SKILL.md render rates.** The rotoscope film step says `--fps <the source's frame
  rate>`, learn-style's validate step `--fps <the pack's knobs.frame_rate.base_fps>` (V12).
- **plan-confirmed: `padStart` sites (V22).** `capture.mjs:74-75` (captured `fNNNN`/`dNNN` names)
  and `roto.js:15` (trace fetch under `?dir=`); nothing else.

## Phase 6

- **plan-confirmed: D23 red first.** The `--synthetic` case (frames f9998-f10000, traces
  d998-d1000) failed before the fix and passes after; the numeric sort lives once in
  `workdir.numbered`, used by `workdir.frames` and `workdir.traces` (so `decode.frames`,
  `render.folder` and `learn.py` all get it). `workdir.frames` now globs `f[0-9]*.png`.
- **choice: D48 applied by a one-off script** (`.work/animation-ports/utf8.py`, not committed) to
  every text `open()` and `write_text()`; JSON is written with ASCII escapes, so bytes are unchanged.
- **coordinator-requested: render.py type fixes.** `Roots.translate_path` no longer returns a
  possibly unbound `p` (it collects every root's candidate); `encode` asserts `p.stdin` before
  writing. Also fixed the verifier's `--fps 0` finding: `render` picks the mode by `drawings is
  None`, and `main` rejects a non-positive `--fps`. Remaining basedpyright errors are not defects:
  implicit sibling imports, `log_message`'s override signature, and `cv2` not installed in the
  checker's environment.
