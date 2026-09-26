# animation ports: implementation plan

Status: DRAFT (Step 2 output; stress-test and approval pending). Design slice:
[design/](design/) (every thread resolved or deferred at `3eecc0385`).

## Brief

**What.** Carry the resolved animation-ports design into `plugins/animation`: one shared decode
path (T14), one render composition root (T10), one owner per value (T16), resolution and frame-rate
scaling (T17), the correctness fixes (T18), a prerequisite probe with pinned requirements and a
check-only `setup` skill (T15, T6), a synthetic CI fixture plus the pack control in `regress.py`
(T8), what licence-notice mechanics ship before any adapter exists (T7), opening `produce` (T13,
T5), pixel-art routing descriptions (T22), and two plugin-philosophy rules (T24).

**Why.** The render composition root lives inside a skill script, the decode path exists twice (a
third encode path exists in `controls.py`), a novel scene has no serve step, a missing `DURATION`
exits 0 with zero frames, a missing tool ends in a traceback, and values are respelled across up to
eight files (design/dependency-inventory.md: 27 fix-needed rows, 24 values needing an owner).

**Done when.** Every phase below is `[DONE]` with its Sanity Check green, the rotoscope regress
still reports 239/239, the frozen woodcut-ink safety net (Phase 0) reports byte-identical verdict
output after every refactor phase, and the repo validators in Phase 12 pass.

### Hard constraints (carried as Sanity Checks in every phase that could break them)

- **C1 regress:** `uv run --with numpy,opencv-python-headless python plugins/animation/skills/rotoscope/scripts/regress.py <shfred0.mp4> <empty dir>` exits 0 at 239/239. From Phase 1 on
  every C1 and C3 run pins the Phase 0 versions (`--with numpy==<v>,opencv-python-headless==<v>`);
  from Phase 3 on the same pins come from `--with-requirements plugins/animation/requirements.txt`.
- **Inputs** (unshipped, under `/home/kyle/worktrees/claude-code-plugins-pixel-art/.work/animation/`):
  shfred0 `videos/shfred0-2102495989194236158.mp4`; round 3 `prototype/film.mp4`; other-style
  clips `videos/BiosRiosz-2102523343253520764.mp4`, `videos/kevin_t_ngo-2102171059592241410.mp4`,
  `videos/kevin_t_ngo-2102437977435893771.mp4`. The `47d7ba2ae` control summaries are at
  `.work/classes/r10/ctl` in this worktree. Phase 0 step 0a copies all of these to
  `~/.local/share/animation-inputs/`, and every run reads that copy.
- **Branch state and merge order:** `feat/animation-plugin` is local-only (the orchestrator is
  writing a git bundle; pushing waits for the user). `feat/pixel-art` (PR #4407) merges first, then
  this branch is rebased onto main. Phase 10 and the version-bump decision assume that order.
  `[EXEC-SHAPE]`
- **C2 frozen check:** the woodcut-ink check is frozen at `47d7ba2ae` (residuals: issue #4507).
  `controls.py selftest <pack> --near <round 3 film>` exits 0; `controls.py check` reports 36/36;
  `learn.py` reports held-out 150/150 in both halves. Distilled baseline at `47d7ba2ae`: replica
  margin -0.18, source -1.00, attacks +4.80, +4.42, +11.77.
- **C3 byte-identity:** code phases (1, 2, 3, 5, 6, 7) leave the Phase 0 safety net byte-identical:
  the 36 re-measured control summaries, `check` and `selftest` stdout, the `learn.py` style.json,
  and the regress table.
- **C4 no duplicate implementation:** before adding a helper, grep the repo for an existing one
  (setup skills, probes, encode, decode). Findings so far: no cross-plugin prerequisite probe in
  `scripts/cross-plugin-source-registry.txt`; the sibling `playwright` plugin's setup installs the
  `playwright-cli` that `capture.mjs` already finds.
- **C5 never ship source:** no source video, frames or traces under `plugins/`.
  Check: `git diff --name-only main...HEAD -- plugins/animation | grep -E '\.(mp4|webm|gif|png)$|/d[0-9]{3}\.json$'` returns nothing.

## Standards grounding

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/plugin-philosophy.md` | Design boundary (no sibling imports, presence-gated cross-plugin references); Setup is explicit and repeatable (check-only carve-out, criterion b); Prerequisites and failure behavior; Cross-platform contract; Configuration ownership (`userConfig` channel, `${CLAUDE_PLUGIN_DATA}`) | team (repo) |
| `.claude/rules/skill-bodies-state-current-rules.md` | four-part record for volatile specifics; `## Next` sections | team (repo) |
| `.claude/rules/ruff-pin.md` | Python lint through `scripts/run-ruff.sh check` | team (repo) |
| `.claude/rules/pr-body-contract.md` | PR body shape (at PR time, not in this plan's phases) | team (repo) |
| `scripts/validate-plugin-contracts.mjs` | setup-skill contract gate (`disable-model-invocation: true`, `check` leading, carve-out declared) | team (repo, enforced) |

## Plan

Execution order is integration-first: the render composition root is the slice every skill passes
through, so it lands first; the test seam lands as soon as its dependencies exist so every later
phase runs under it. `[EXEC-SHAPE]`

### Phase 0: Safety-net baseline [DONE]

No plugin code changes. Build a local script in the topic memory slice (never committed; it needs
unshipped clips, D44) with two modes. `[EXEC-SHAPE]`

- Step 0a, run once before any baseline: copy every input clip and the `47d7ba2ae` ctl summaries
  out of every worktree into `~/.local/share/animation-inputs/` (worktree cleanup must not take
  them), and write `MANIFEST.sha256` there (`sha256sum`). `baseline` and `compare` verify the
  manifest first and fail on any mismatch. `[EXEC-SHAPE]`
- Toolchain frozen for every run: a private playwright-core install and a private
  `PLAYWRIGHT_BROWSERS_PATH` under `~/.local/share/animation-inputs/toolchain/`, passed to
  `capture.mjs` explicitly (through `PW_CORE` until Phase 3 removes it, then `--playwright-core`;
  the browsers path in its environment), and `node` called by absolute path. `[EXEC-SHAPE]`
- `baseline <dir>`: (1) record the numpy and opencv versions `uv run --with numpy,opencv-python-headless` resolves today, the Python version, `nproc`, `ffmpeg -version` line 1, the absolute
  `node` path and `node --version`, the playwright-core version and the Chromium build it launches,
  into `<dir>/versions.txt`; every later run pins numpy and opencv with `==` to these (C1); (2) run
  C1 into a kept work dir `<dir>/work`; (3) `controls.py measure <dir>/ctl
  --near <round 3> --other <BiosRiosz> <kevin_t_ngo-2102171059592241410>
  <kevin_t_ngo-2102437977435893771> --source <shfred0> --replica <dir>/work --tag regress` (paths
  under Inputs); (4) `controls.py check <dir>/ctl plugins/animation/styles/woodcut-ink`; (5)
  `controls.py selftest plugins/animation/styles/woodcut-ink --near <round 3>`; (6) copy the
  committed `style.json` into `<tmp>/woodcut-ink/` (the directory name is what `learn.py` writes as
  `name`) and run `learn.py <dir>/work <tmp>/woodcut-ink --cuts <style.json measured_from.cuts>
  --negative <dir>/ctl/calibration/*.json`. Save each stdout.
- `compare <baseline dir> <new dir>`: first verify the input manifest, then re-record the versions
  and fail fast if Python, `nproc`, ffmpeg, node, playwright-core or the Chromium build differ from
  `versions.txt`; then rerun steps 2-6 and compare only these: `diff -r` the control summary JSONs;
  the stdout of `check` and `selftest`; `learn.py` stdout (normalising only the temp pack path in
  its first line); `cmp` the two `style.json` files and the two `out/regress/table-*.md` files.
  Never compared: `controls.py measure` stdout (it prints `<dir>`-prefixed paths in completion
  order, `imap_unordered`, `controls.py:175-177`) and raw regress stdout (Phase 4 adds a line to
  it). Exit 0 only when all compared outputs are identical.
- `--dry-run` prints the commands; `--help` prints usage.

**Sanity Check:**

- [x] `baseline` exits 0; its `check` stdout ends with `36/36 as required`; `selftest` exits 0;
  `learn.py` stdout line 1 contains `calibration 150/150, evaluation 150/150`; regress exits 0.
- [x] `cmp` of the baseline-run `style.json` against `plugins/animation/styles/woodcut-ink/style.json` exits 0 (the check reproduces at `47d7ba2ae`).
- [x] `compare` of the baseline against a second baseline run exits 0 (the net is deterministic on
  this machine). If it does not, stop: the net cannot gate byte-identity.
- If the `style.json` `cmp` fails (a hand edit after the last `learn.py` run), the baseline-run
  output becomes the C3 reference and the mismatch is reported to the user.
  `[FALLBACK — confirm or override]`

### Phase 1: `scripts/render.py` composition root (T10; D16, D18, D29/V16, V23) [TODO]

Review: architecture

Pre-flight (first work item): grep every caller of `measure.render`, `capture.mjs` and an ffmpeg
encode: `measure.py`, `fit.py`, `controls.py` (`encode`), `learn.py` (`controls.encode`), rotoscope
and learn-style `SKILL.md` film steps, README.

- Create `plugins/animation/scripts/render.py` per design/contracts.md section 3:
  `render.py <scene.js> <out dir> (--fps N | --drawings K0-K1|k,k,...) [--query Q] [--root DIR ...]
  [--backend native] [--encode none|mp4|webm|gif] [--workers N]`.
  - Serves, over one loopback server on an OS-chosen port, the scene's directory, then `scripts/`,
    then each `--root` in order; a path resolves to the first root holding it. `scripts/` comes
    before `--root` so a stale `ink.js` or `render.html` copied into an old work dir never shadows
    the engine. `[EXEC-SHAPE]` `--root` is an
    addition to the design: `roto.js` fetches `${DIR}/index.json` relative to the page
    (`roto.js:11`) and `fit.py` serves `fit-brushes.json` from the work dir (`fit.py:67-68`), so
    the rotoscope render needs the work dir served and the design's two roots cannot serve it.
    `[EXEC-SHAPE]` No more copying `render.html`, `ink.js`, `roto.js` into the work dir (D15).
  - Calls `capture.mjs`; exit 1 when `DURATION` is missing or not a positive finite number (D18;
    `capture.mjs:40` computes `NaN` frames today), when a scene throws, or `renderDrawing` is missing.
  - `WORKERS = min(8, os.cpu_count())`, the one owner (V16, D29); `capture.mjs` receives it as an
    argument. Every other worker default routes to it: `measure.py` and `fit.py` `--workers 8`,
    `extract.py --jobs`, `controls.py --jobs 8`, and `review.py:90` `Pool()`.
  - `encode(frames, fmt, fps, out)`: the one ffmpeg write path (V23), absorbing `controls.encode`
    (`controls.py:129-147`, which `learn.py:174` uses for palette tolerance) with byte-identical
    arguments for mp4 (`libx264 -pix_fmt yuv420p -crf 16`). It keeps `controls.encode`'s input
    path: `frames` is an iterable of BGR images piped as rawvideo `bgr24` on stdin, holds expanded
    by the caller from `index.json` timing; a frame folder is one caller that reads its PNGs. This
    deviates from contracts.md:147's `encode(frames_dir, fmt, fps)`: a folder-of-PNGs input would
    change what ffmpeg reads for the replica and source encodes and break C3 (the replica and
    palette-tolerance encodes are drawings with variable holds, not a frame folder). `[EXEC-SHAPE]`
  - Writes `render.json` `{scene, adapter, adapter_version, browser_build, fps, size, frames, duration}` (contracts.md section 4; `licence_notice` absent while only native exists).
  - `--backend` accepts only `native` (contracts.md section 3).
- `measure.py`: drop `render()` and its copy step; call `render.py` with `--root <work>`.
  `fit.py`, `review.py` unchanged in behaviour.
- `controls.py`: `encode` and `replica` call `render.encode`; `learn.py` likewise.
- `inkstats.py`: when a frame folder holds `render.json`, read its fps; `--fps` stays the override.
- `capture.mjs`: header comment drops the ffmpeg line (now `render.py --encode`).
- Rotoscope and learn-style `SKILL.md` film steps call `render.py ... --encode mp4` (fixes D16).

**Files Affected:** `scripts/render.py` (create), `scripts/capture.mjs`, `scripts/inkstats.py`,
`skills/rotoscope/scripts/measure.py`, `skills/rotoscope/scripts/fit.py`,
`skills/rotoscope/scripts/extract.py`, `skills/rotoscope/scripts/review.py`,
`skills/learn-style/scripts/controls.py`, `skills/learn-style/scripts/learn.py`,
`skills/rotoscope/SKILL.md`, `skills/learn-style/SKILL.md` (11 files).

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/animation/scripts/render.py` | CREATE | composition root, encode, `WORKERS` |
| [ ] `plugins/animation/scripts/capture.mjs` | MODIFY | header drops the ffmpeg line |
| [ ] `plugins/animation/scripts/inkstats.py` | MODIFY | fps from `render.json` |
| [ ] `plugins/animation/skills/rotoscope/scripts/measure.py` | MODIFY | calls `render.py`; `WORKERS` |
| [ ] `plugins/animation/skills/rotoscope/scripts/fit.py` | MODIFY | `WORKERS` |
| [ ] `plugins/animation/skills/rotoscope/scripts/extract.py` | MODIFY | `--jobs` default from `WORKERS` |
| [ ] `plugins/animation/skills/rotoscope/scripts/review.py` | MODIFY | `Pool(WORKERS)` |
| [ ] `plugins/animation/skills/learn-style/scripts/controls.py` | MODIFY | `render.encode`; `WORKERS` |
| [ ] `plugins/animation/skills/learn-style/scripts/learn.py` | MODIFY | `render.encode` |
| [ ] `plugins/animation/skills/rotoscope/SKILL.md` | MODIFY | film step (D16) |
| [ ] `plugins/animation/skills/learn-style/SKILL.md` | MODIFY | validate step (D16) |

**Sanity Check:**

- [ ] End-to-end probe: a 2 s scene written to a temp dir (ink.js, `DURATION = 2`, a new drawing
  every frame so the repeat rule keeps them all) through `render.py <scene> <out> --fps 12 --encode
  mp4` exits 0, writes 24 `fNNNN.png`, `render.json` with `"fps": 12` and `"frames": 24`, and an
  mp4; `inkstats.py <out>` (no `--fps`) reports `2.0 s` (reading `1.0 s` means it fell back to its
  24 fps default instead of `render.json`).
- [ ] D18 probe: the same scene without `DURATION` makes `render.py` exit 1 (test-after carve-out:
  the seam that will own this case lands in Phase 4).
- [ ] `grep -rn "shutil.copy" plugins/animation/skills/rotoscope/scripts/measure.py` returns nothing.
- [ ] `grep -rln "'ffmpeg'" plugins/animation --include=*.py` lists only `scripts/render.py` and
  the decode sites Phase 2 moves (`extract.py`, `inkstats.py`).
- [ ] `grep -rnE "Pool\(\)|default=8|workers=8" plugins/animation --include=*.py` returns nothing.
- [ ] C1 239/239; C3 `compare` exits 0; C5.

### Phase 2: `scripts/decode.py` source-in (T14; V8, V9, V10) [TODO]

- Create `plugins/animation/scripts/decode.py`: `probe(video)`, `frames(film, fps)` (video, frame
  folder, work dir, or any iterable of `(rgb, t)`; today `inkstats.py:97-126`),
  `is_repeat(prev, rgb, dup_px=DUP_PX)` (the one repeat rule and the 64-level threshold; `DUP_PX =
  50` lives here; only `extract.py` will ever pass a scaled `dup_px`, in Phase 7), `modes(gray)`
  (ink and paper modes, `T`, the plus-or-minus 16 mid band).
- `extract.py` (`probe`, `decode`, `stats`), `inkstats.py` (`frames`, `drawings`, `one`),
  `measure.py` (`paper`'s `T + 16`) and `controls.py` (`inkstats.frames`) import it. Pure move:
  same argument lists, same arithmetic, same order of operations.

**Files Affected:** `scripts/decode.py` (create), `scripts/inkstats.py`,
`skills/rotoscope/scripts/extract.py`, `skills/rotoscope/scripts/measure.py`,
`skills/learn-style/scripts/controls.py`.

**Sanity Check:**

- [ ] `grep -rn "fps_mode\|'ffprobe'" plugins/animation --include=*.py` matches only `scripts/decode.py`.
- [ ] `grep -rn "> 64" plugins/animation --include=*.py` matches only `scripts/decode.py`.
- [ ] C1 239/239; C3 `compare` exits 0; C5.

### Phase 3: prerequisite probe, pinned requirements, check-only `setup` (T15, T6; D1-D5, D7, D8, D11-D13, V19, V21) [TODO]

- `plugins/animation/requirements.txt`: numpy and opencv-python-headless pinned to the exact
  versions Phase 0 recorded, so byte-identity is not broken by a library upgrade. `[EXEC-SHAPE]`
  README states the Python minimum (`requires-python` note, D13).
- `plugins/animation/scripts/prereq.py`, standard library only so it can report a missing numpy:
  rows for `ffmpeg`, `ffprobe`, `ffmpeg` with `libx264` (`ffmpeg -encoders`), the ffmpeg version
  `-fps_mode` needs (D2: research the minimum against the ffmpeg changelog and record it as a
  four-part record before stating it), `node`, playwright-core and Chromium (resolved by running
  `capture.mjs --probe`, so the runtime artifact stays the owner of its lookup, V21), numpy and
  opencv importable at the pinned versions. `check()` returns rows; `require(names)` exits 2 with
  the remedy line. Plugin-local: no cross-plugin probe exists to reuse (C4). `[EXEC-SHAPE]`
- `render.py` and `decode.py` call `prereq.require(...)` at their entry points (D1, D3, D5).
- `capture.mjs`: drop the `/bin/sh` `command -v` lookup for a JS `PATH` scan (D8); add `--probe`;
  replace `PW_CORE` (D7, O4 resolved: a `userConfig` directory) with a `--playwright-core DIR`
  argument tried first in the lookup. Remedy text names `npm i playwright-core` and, presence-gated,
  the `playwright` plugin's setup when installed.
- `plugin.json` `userConfig`: one optional `playwright_core` option of type `directory`, empty by
  default (empty keeps today's lookup). SKILL.md commands pass `--playwright-core
  ${user_config.playwright_core}` to `render.py`, which forwards it to `capture.mjs`; `render.py`
  treats an empty value or an unsubstituted literal starting with `${` as unset. Setup `check`
  verifies a set value resolves playwright-core.
- `plugins/animation/skills/setup/SKILL.md` (+ `evals/evals.json`, as sibling setup skills ship):
  check-only carve-out (external prerequisites setup can only verify), `disable-model-invocation:
  true`, `argument-hint: "check"`, runs `prereq.py` and prints the PASS/FAIL/INFO table with one
  remediation line per FAIL. `## Next`: `/animation:rotoscope`.
- Commands in README, rotoscope and learn-style `SKILL.md` become `uv run --with-requirements
  ${CLAUDE_PLUGIN_ROOT}/requirements.txt python ...`; learn-style defers to README (V19).
- `plugin.json` description and README skills table name `setup`; regenerate the catalog.

**File Inventory:**

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/animation/requirements.txt` | CREATE | V19, D11-D13 |
| [ ] `plugins/animation/scripts/prereq.py` | CREATE | one probe for setup and entry points |
| [ ] `plugins/animation/scripts/render.py` | MODIFY | entry-point `require` |
| [ ] `plugins/animation/scripts/decode.py` | MODIFY | entry-point `require` |
| [ ] `plugins/animation/scripts/capture.mjs` | MODIFY | D7, D8, `--probe` |
| [ ] `plugins/animation/skills/setup/SKILL.md` | CREATE | T6 |
| [ ] `plugins/animation/skills/setup/evals/evals.json` | CREATE | skill-quality contract |
| [ ] `plugins/animation/README.md` | MODIFY | requirements, setup row |
| [ ] `plugins/animation/skills/rotoscope/SKILL.md` | MODIFY | V19, V21 |
| [ ] `plugins/animation/skills/learn-style/SKILL.md` | MODIFY | V19 defers to README |
| [ ] `plugins/animation/.claude-plugin/plugin.json` | MODIFY | description names setup; `userConfig.playwright_core` |
| [ ] `docs/catalog.md`, `docs/skill-cheat-sheet.md` | MODIFY | regenerated, not hand-edited |

**Sanity Check:**

- [ ] `node scripts/validate-plugin-contracts.mjs` exits 0 (setup contract gate).
- [ ] `node scripts/generate-catalog.mjs --check` exits 0.
- [ ] `bash scripts/check-changed-skills.sh main` exits 0 (skill-quality contract gate; new skills need `evals/evals.json`).
- [ ] With `PATH` stripped of ffmpeg (`env PATH=<dir without ffmpeg> ...`), `render.py <scene> <out> --fps 24 --encode mp4` exits 2 and prints one remedy line, no traceback.
- [ ] `grep -n "/bin/sh\|command -v" plugins/animation/scripts/capture.mjs` returns nothing.
- [ ] `grep -rn "with numpy,opencv" plugins/animation` returns nothing.
- [ ] `grep -rn "PW_CORE" plugins/animation` returns nothing; `grep -c "playwright_core" plugins/animation/.claude-plugin/plugin.json` is 1.
- [ ] `render.py <scene> <out> --fps 12 --playwright-core '${user_config.playwright_core}'` exits 0 (unsubstituted placeholder treated as unset).
- [ ] C1 (now via `--with-requirements`) 239/239; C3 `compare` exits 0; C5.

### Phase 4: the one test seam: synthetic fixture and pack control (T8; D44) [TODO]

O3 and O5 are resolved: skip-guarded test plus a follow-up issue; spike the fidelity target first,
fall back to count plus contracts.

- `plugins/animation/skills/rotoscope/fixtures/synthetic.js`: a small committed scene (ink.js
  only, a few seconds, a known number of distinct drawings, holds of 2 and 3 frames).
- `regress.py --synthetic <empty dir>`: `render.py --fps 24 --encode mp4` the fixture, then
  `extract.py --video` the mp4, then `measure.py`. First work item is the O5 spike: if the replica
  meets the 1.2 x floor / 0.980 target, assert it with the drawing count; if not, assert the
  drawing count and the render/encode/decode contracts only, and record the measured table.
  It also runs the regression cases for fixes this plan makes: a scene without `DURATION` exits 1
  (D18), and later phases add theirs here (D23, D26).
- `regress.py <shfred0.mp4> <dir>` additionally encodes the replica with `controls.replica` (reused,
  not re-implemented) and runs `inkstats.py --pack styles/woodcut-ink` on the result: the replica
  must pass (the same-style control, design T8).
- `plugins/animation/skills/rotoscope/scripts/test_regress.py`: CI already selects it through
  `scripts/affected-tests.sh` and runs it under pytest without numpy, so the module has no
  third-party import at module level, runs `regress.py --synthetic` as a subprocess, and skips with
  a visible reason (`unittest.skipUnless`, precedent `plugins/code-tidying/scripts/test_commented_out_code.py`)
  when `prereq.check()` reports a missing tool or package. A follow-up issue tracks a CI job with
  the tools installed (O3 resolved). Phase-entry check before filing: `gh issue list --state all
  --search 'animation synthetic fixture CI in:title'`; comment on a match instead of creating one.

**Sanity Check:**

- [ ] `regress.py --synthetic <empty dir>` exits 0 locally; the fixture without `DURATION` case is
  reported as passing (exit 1 observed).
- [ ] `uv run --with-requirements plugins/animation/requirements.txt --with pytest python -m pytest plugins/animation/skills/rotoscope/scripts/test_regress.py` exits 0 with the test run
  (not skipped) on this machine.
- [ ] `python3 -m pytest plugins/animation/skills/rotoscope/scripts/test_regress.py -rs` in an
  environment without numpy exits 0 and reports the test as skipped with its reason (collection
  does not error).
- [ ] The follow-up issue number (created or pivoted-to) is recorded in the phase notes.
- [ ] C1 239/239 and its new pack-control line reports the replica passing; C3 `compare` exits 0
  (it compares `table-*.md` and the summary JSONs, not raw regress stdout, which gains this line); C5.

### Phase 5: SSOT owner table (T16; V1-V7, V11, V12 docs, V14, V15, V17/D28, V20/V22/D22, V26; D32) [TODO]

Pre-flight: grep each value's sites from design/dependency-inventory.md section 2 again (line
numbers drifted since `f0bd01ed0`; `inkstats.py` and `learn.py` changed afterwards).

- `scripts/workdir.py`: work-dir path helpers and `dNNN`/`fNNNN` names (V20, V22, D22), imported by
  `extract.py`, `measure.py`, `fit.py`, `review.py`, `regress.py`, `inkstats.py`, `learn.py`,
  `controls.py`; `roto.js` keeps `?dir=`.
- `skills/rotoscope/scripts/brush.json` `{bias, blur, grain}` (V3, D32): `roto.js` fetches it,
  `measure.py` and `fit.py` load it; `measure.BRUSH_BIAS` goes.
- `roto.js` drops its explicit `seed: 999` (V14; same value as the `ink.js` default).
- One stamped four-part record each in `skills/rotoscope/reference/method.md`: Chromium `blur()`
  floor (V11; both SKILL.md gotchas point to it) and the 2576 px long-edge limit (V17, D28; research
  its origin; if none is found, record it as judgment with a recheck trigger). `review.py` derives
  `CROP` from a named constant.
- Docs cite owners instead of restating (V1, V2, V4-V7, V12, V15, V26): README, rotoscope and
  learn-style SKILL.md, method.md, statistics.md, plugin.json description. Measurement records keep
  their numbers (V2 records, V18 gotcha, STYLE.md validation, CHANGELOG). V24 and V25 stay as
  intentional duplicates.

**File Inventory:**

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/animation/scripts/workdir.py` | CREATE | V20, V22 |
| [ ] `plugins/animation/skills/rotoscope/scripts/brush.json` | CREATE | V3 |
| [ ] `plugins/animation/scripts/inkstats.py` | MODIFY | workdir paths |
| [ ] `plugins/animation/skills/rotoscope/scripts/extract.py` | MODIFY | workdir paths |
| [ ] `plugins/animation/skills/rotoscope/scripts/measure.py` | MODIFY | workdir, brush.json |
| [ ] `plugins/animation/skills/rotoscope/scripts/fit.py` | MODIFY | workdir, brush.json |
| [ ] `plugins/animation/skills/rotoscope/scripts/review.py` | MODIFY | workdir, CROP constant |
| [ ] `plugins/animation/skills/rotoscope/scripts/regress.py` | MODIFY | workdir |
| [ ] `plugins/animation/skills/rotoscope/scripts/roto.js` | MODIFY | brush.json fetch, V14 |
| [ ] `plugins/animation/skills/learn-style/scripts/learn.py` | MODIFY | workdir |
| [ ] `plugins/animation/skills/learn-style/scripts/controls.py` | MODIFY | workdir |
| [ ] `plugins/animation/skills/rotoscope/reference/method.md` | MODIFY | V11, V17 records; cite owners |
| [ ] `plugins/animation/skills/learn-style/reference/statistics.md` | MODIFY | cite `SEG`, base rate |
| [ ] `plugins/animation/skills/rotoscope/SKILL.md` | MODIFY | V1, V2, V11 pointers |
| [ ] `plugins/animation/skills/learn-style/SKILL.md` | MODIFY | V11, V17, V12 pointers |
| [ ] `plugins/animation/README.md` | MODIFY | V1, V2, V26 |
| [ ] `plugins/animation/.claude-plugin/plugin.json` | MODIFY | V2 |
| [ ] `plugins/animation/styles/woodcut-ink/STYLE.md` | KEEP | measurement record (V26 owner) |
| [ ] `plugins/animation/CHANGELOG.md` | KEEP | history |
| [ ] `plugins/animation/skills/rotoscope/fixtures/shfred0.overrides.json` | KEEP | record |

**Sanity Check:**

- [ ] `grep -rnE "'d/index.json'|f'src/d\{|f'd/d\{|/d\{k:03d\}|rep/d|heat/d" plugins/animation --include=*.py` matches only `scripts/workdir.py` (covers `controls.py`'s `f'{folder}/d{k:03d}.png'`).
- [ ] `grep -rn "padStart" plugins/animation --include=*.js --include=*.mjs` lists only the naming sites `capture.mjs` owns for captured names and `roto.js`'s trace fetch (V22), each listed in the phase notes.
- [ ] `grep -rn "0\.12" plugins/animation/skills/rotoscope/scripts/*.py plugins/animation/skills/rotoscope/scripts/roto.js` returns nothing.
- [ ] `grep -c "239" plugins/animation/README.md plugins/animation/skills/rotoscope/SKILL.md` is 0 for both.
- [ ] `grep -n "2576" plugins/animation/skills/learn-style/SKILL.md plugins/animation/skills/rotoscope/scripts/review.py` shows no bare number without a pointer to method.md.
- [ ] C1 239/239; C3 `compare` exits 0; C5.

### Phase 6: correctness fixes (T18; D23, D41/V13, D48) [TODO]

D18, D22, D28 and D29 land in Phases 1 and 5; this phase takes the rest.

- D23: numeric sort of `fNNNN`/`dNNN` names everywhere they are globbed (`inkstats.py`
  frame-folder glob, `learn.py:55` trace glob, and any site Phase 5's pre-flight found); names stay
  zero-padded to at least four and three digits. Regression case added to `regress.py --synthetic`
  first (a frame folder with `f9999.png` and `f10000.png`), red before the fix.
- D41/V13: one `const INK = '#141211'` in `ink.js` used by its four sites; value unchanged. Scenes
  in the woodcut style pass the pack's `palette.ink` (learn-style SKILL.md authoring step says so).
- D48: `encoding='utf-8'` on every text `open()` and `write_text` in the plugin's Python; README
  records Windows and macOS as manually unverified (`docs/plugin-philosophy.md` cross-platform
  contract).

**Sanity Check:**

- [ ] `regress.py --synthetic` exits 0 including the D23 case (it failed before the fix).
- [ ] `grep -c "#141211" plugins/animation/scripts/ink.js` is 1.
- [ ] `grep -rnE "open\([^)]*\)|write_text\(|read_text\(" plugins/animation --include=*.py | grep -v "encoding=\|'rb'\|'wb'\|imread\|Popen"` returns nothing.
- [ ] C1 239/239; C3 `compare` exits 0; C5.

### Phase 7: resolution and frame-rate scaling (T17; D24-D26, D34, D35, D37, D40) [TODO]

O1 and O2 are resolved: scale only in `extract.py`; the base rate is a `--base-fps` argument
defaulting to 24. Every item is identity-preserving on the frozen check.

- D34, D35 in `extract.py`: pixel-count thresholds scale by frame area relative to the calibration
  size 1762x982, which yields today's numbers on shfred0. `extract.py` passes the scaled
  `dup_px` to `decode.is_repeat`; `inkstats.py` and `controls.py` keep the default `DUP_PX`, so
  the other-style controls (1920x1080, 1080x1080, 2160x2160) measure exactly as before. Scaling
  inside `inkstats.py` waits for the check to unfreeze (issue #4507).
- D24, D25: `learn.py --base-fps` (default 24) writes `knobs.frame_rate.base_fps`; `inkstats.py`
  counts holds on the pack's `base_fps` when `--pack` is given, else on `--fps`, through a
  `base_fps` parameter whose default is 24 (so `controls.py`, which passes no pack, is unchanged).
- D26: a single-drawing clip takes its duration from ffprobe's frame duration (regression case in
  `regress.py --synthetic`, red first).
- D37: the size appears in the printed warning line only, never in `summary()`: `controls.run`
  writes the summary verbatim, so a new field would break C3. `report()` warns when the film's
  frame size differs from the pack's `measured_from.size`; `inkstats.check()` is unchanged.
- D40: state the two-tone scope in method.md and statistics.md; `inkstats.py` report notes a weak
  mode peak (printed only, not in `summary()`).

**Sanity Check:**

- [ ] `regress.py --synthetic` exits 0 including the D26 case.
- [ ] `inkstats.py <a 1920x1080 film> --pack plugins/animation/styles/woodcut-ink` prints the size
  warning line; the same on the shfred0 work dir prints none.
- [ ] `learn.py <work> <tmp>/woodcut-ink --base-fps 24 ...` output `cmp`s equal to the default
  run; `grep -n '"base_fps": 24' <tmp>/woodcut-ink/style.json` matches; with `--base-fps 12`,
  `base_fps` reads 12.
- [ ] `grep -n "size" <any controls summary written this phase>` shows no new top-level `size`
  key (C3 covers it; this names the D37 trap).
- [ ] C1 239/239; C2 green (36/36, selftest 0, 150/150); C3 `compare` exits 0 (mandatory); C5.

### Phase 8: licence notice mechanics, what ships now (T7) [TODO]

No adapter exists, so no detection or notice code ships. `[EXEC-SHAPE]`

- `plugins/animation/reference/backends.md`: the native row in pixel-art's row shape (Adds, Detect,
  Cost and licence, Contract), the selection rule by citation of design/contracts.md section 3
  order, and the licence rule: a non-native adapter's `detect()` returns `(present, version,
  licence_path)`, the notice quotes that installed file, prints once per session before the first
  render, and is recorded in `render.json` `licence_notice`. No Remotion or HyperFrames row until
  that adapter ships; the four-part Remotion record is written then, from a fresh fetch of its
  LICENSE (its current basis is a memory-slice file that cannot be cited from shipped docs).
- `render.py` docstring points at `reference/backends.md`.

**Sanity Check:**

- [ ] `test -f plugins/animation/reference/backends.md` and `grep -c "licence_notice" plugins/animation/reference/backends.md` ≥ 1.
- [ ] `grep -ni "remotion\|hyperframes" plugins/animation/reference/backends.md` returns nothing.

### Phase 9: open the `produce` sub-topic (T13, T5) [TODO]

`produce` is promoted to its own topic `[EXEC-SHAPE]`: it has more than five work items (brief,
boards, approval gate, shot list, render manifest wiring, review), more than 300 LOC, its own
design need (T13 defers field-level schemas to building it), and an independent PR boundary. This
phase only opens it.

- Create `docs/topics/animation-produce/PLAN.md` holding a Brief only: goal, the T13 decisions
  (domain-model.md section 2.2 schemas as the starting shape; `shots.json` owns shot cuts, so
  `inkstats.py --cuts` reads it), inputs from this plan (`render.py`, `render.json`, the frame
  folder contract), and the next step (`/planning:design` for the stage artifacts).
- README line 13 "Planned next: `film`" becomes `produce` (T5). learn-style gains no `## Next` yet
  (it names `/animation:produce` when that skill ships, T5).

**Sanity Check:**

- [ ] `test -f docs/topics/animation-produce/PLAN.md` and `grep -c "## Brief" docs/topics/animation-produce/PLAN.md` is 1.
- [ ] `grep -n "film\`" plugins/animation/README.md` returns nothing; `grep -c "produce" plugins/animation/README.md` ≥ 1.

### Phase 10: pixel-art routing descriptions (T22) [TODO]

- `plugins/pixel-art/skills/animate/SKILL.md` and `scene/SKILL.md` descriptions: qualify the
  generic triggers (`'make it move'`, `'make it a little movie'`, `'pixel-art short'`) as pixel-art
  requests, and add an exclusion for hand-drawn or ink animation and video. No bare `/animation:*`
  token (a cross-plugin reference must be declared or presence-gated). `[EXEC-SHAPE]`
- `sprite/SKILL.md`: KEEP (no animation or video trigger).
- Runs after the rebase onto main that follows PR #4407's merge, so pixel-art is on main at that
  point: `check-changed-skills.sh main` compares trigger phrases against main and flags a dropped
  trigger. Keep each replaced phrase's intent in a pixel-art-qualified form, and bump pixel-art's
  version per the repo's version rule for a changed released plugin.

**Sanity Check:**

- [ ] `grep -n "'make it move'\|'make it a little movie'" plugins/pixel-art/skills/*/SKILL.md` returns nothing (the bare generic triggers are gone; their replacements are quoted as pixel-art triggers, e.g. `'make this sprite move'`).
- [ ] `grep -rn "/animation:" plugins/pixel-art` returns nothing.
- [ ] `bash scripts/check-changed-skills.sh main` exits 0 (includes the listing-budget and line caps).

### Phase 11: plugin-philosophy rules (T24) [TODO]

Written last, so each rule states what this plugin now does. `docs/plugin-philosophy.md`:

- Skill-as-process: a skill states the process (what to do, in what order, when to stop); outputs
  and tools sit behind ports and adapters, with an interface only where two adapters exist or are
  named (this plugin's render port is the example; T3).
- One owner per value inside a plugin: code reads each value from one owner; docs cite the owner;
  measurement records keep their numbers; a volatile external specific in a skill body carries the
  four-part record; a value two languages read lives in JSON (T16).
- Update the file's Contents list if the rules add a heading.

**Sanity Check:**

- [ ] `grep -c "one owner" docs/plugin-philosophy.md` ≥ 1 and `grep -ci "ports and adapters" docs/plugin-philosophy.md` ≥ 1.
- [ ] `npx --no-install markdownlint-cli2 docs/plugin-philosophy.md` exits 0.

### Phase 12: repo validation and close-out checks [TODO]

- `scripts/run-ruff.sh check plugins/animation` exits 0.
- `node scripts/validate-plugin-contracts.mjs` and `node scripts/generate-catalog.mjs --check` exit 0.
- `bash scripts/check-changed-skills.sh main` exits 0 (animation and pixel-art skills).
- CHANGELOG entries for `animation` and `pixel-art`. `animation` gets no version bump: it is still
  new relative to main after the rebase. `pixel-art` is on main by then (PR #4407 merged first), so
  Phase 10's edit carries its version bump. `[EXEC-SHAPE]`

**Sanity Check:**

- [ ] every command above exits 0; C1 239/239; C2 green; C5 returns nothing.

## Alternatives Considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Land T18 fixes, T16 and T17 as one phase (T23's "one cleanup phase") | One phase would carry more than 20 work items and one safety-net run could not say which change broke identity; the fixes are still one PR on this branch, which is what T23 set | the Phase 0 net runs in under ten minutes, making per-phase gating cheap enough to merge phases |
| Two served roots only (design T10) | `roto.js` and `fit.py` need the work dir served (`roto.js:11`, `fit.py:67-68`) | `roto.js` is changed to receive its data by query or inline JSON instead of fetching from the work dir |
| Keep `controls.encode` as a second encode | module-boundary.md: only `render.py` writes with ffmpeg; two copies drift | the replica/validation encode needs arguments the delivery encode must never take |
| Per-port unit tests for D18/D23/D26 | T8 chose one seam; the failures that mattered showed end to end | the synthetic run takes over a minute and CI needs a fast lane |
| Seam (T8) as the last code phase | later phases would run with no CI-able test | none; kept early |
| Ship the Remotion notice code now (T7) | no adapter to call it; the stamped record would decay with no consumer | a Remotion or HyperFrames adapter is scheduled for this branch |
| Build `produce` inside this plan | its schemas are unsettled (T13) and it is its own PR | the produce design session finishes before Phase 8 starts and the user wants one PR |
| Pin requirements to latest versions | changes opencv numerics under the byte-identity net | the net is re-baselined deliberately after this plan lands |

## Test Strategy

Test-first where a failing test can exist before the change; characterization (the Phase 0 net) for
pure moves.

- **Boundaries (existing):** `regress.py <clip> <dir>` (the one seam, T8); `controls.py check`,
  `controls.py selftest`, `learn.py` stdout and `style.json` (the frozen-check net); `measure.py`
  exit code; `inkstats.py --pack` exit code.
- **Boundaries (new, introduced by this plan):** `render.py` CLI and exit codes 0/1/2 (contracts.md
  section 3); `render.json` fields; `decode.frames()` and `decode.is_repeat()`;
  `prereq.check()`/`require()` and the setup `check` table; `regress.py --synthetic`;
  `test_regress.py` (subprocess wrapper, skip-guarded, no module-level third-party imports).
- **Code phases (1, 2, 3, 5, 6, 7):** no change to frozen-check output; the proof is C1 plus C3 byte-identity. A
  compare failure stops the phase; bisect by reverting the phase's commits.
- **Bug fixes:** D18 (Phase 1 probe, folded into `--synthetic` in Phase 4; test-after carve-out
  because the seam does not exist yet), D23 and D26 (red case in `--synthetic` first), D2/D1/D3/D5
  (Phase 3 PATH-stripped probe exits 2).
- **Edge cases:** a scene that throws (exit 1); a frame folder past 9,999 frames; a single-drawing
  clip; a film at another resolution (size warning); ffmpeg without libx264 (setup FAIL row).
- **Existing tests to update:** none exist in `plugins/animation`; pixel-art's `test_render.py`
  and `test_tools.py` are untouched.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The Phase 0 net is not deterministic (Chromium, ffmpeg or thread scheduling) | Low | High | Phase 0 runs baseline twice and stops if they differ |
| A pinned opencv/numpy, ffmpeg, node or Chromium differs from what the baseline used | Med | High | `==` pins from Phase 1 on; `compare` fails fast on a tool version change |
| T17 scaling moves the frozen check's control summaries (other-style clips are 1920x1080, 1080x1080, 2160x2160) | Low (O1 resolved) | High | only `extract.py` passes a scaled `dup_px`; C3 mandatory in Phase 7 |
| A new `summary()` field breaks C3 (`controls.run` writes it verbatim) | Med | High | D37 and D40 print only; Phase 7 check names the trap |
| The synthetic replica misses the fidelity target at default brush | Med | Med | Phase 4 spike first; fallback assertion per O5 |
| The full control re-measure is slow (36 films, one 2160x2160) | High | Low | run it in the background per phase; it is the only proof for the decode/measure moves |
| Setup skill fails the contract gate | Low | Low | Phase 3 runs `validate-plugin-contracts.mjs` |
| New doctrine rules flag other plugins in fleet audits | Med | Med | rules are stated as normative targets, like the setup contract; stress-test covers wording |

## Blast radius

Blast radius: **MEDIUM**. One plugin (`animation`) plus two pixel-art descriptions and the
philosophy doc, behind a byte-identity safety net. Both plugins are new on this branch with no
released consumers, and every change reverts with git. The two new doctrine rules are fleet-wide
normative targets, which is why a formal stress-test was still run.

## Stress-test summary

A fresh reviewer stress-tested the draft; the orchestrator spot-checked findings against the code.
Applied: `is_repeat` takes `dup_px` so only `extract.py` scales (C3 mandatory in Phase 7); D37 size
kept out of `summary()`; `==` version pins and a tool-version fail-fast in Phase 0; CI facts for
`test_regress.py`; `userConfig` plumbing for O4; the `woodcut-ink` temp dir name; exact trigger
grep; D29 worker sites; corrected `fit.py:67-68`; straggler and name greps; a `--base-fps` check;
exact input paths; `controls.replica` reuse.

## Execution shape

### Phase file-overlap matrix

| Phase | Files (plugin-relative unless noted) | Overlaps with |
|---|---|---|
| 0 | memory-slice script only | none |
| 1 | `scripts/render.py`, `capture.mjs`, `inkstats.py`, `measure.py`, `fit.py`, `extract.py`, `review.py`, `controls.py`, `learn.py`, rotoscope and learn-style `SKILL.md` | 2, 3, 5, 6, 7 |
| 2 | `scripts/decode.py`, `inkstats.py`, `extract.py`, `measure.py`, `controls.py` | 1, 3, 5, 7 |
| 3 | `requirements.txt`, `prereq.py`, `render.py`, `decode.py`, `capture.mjs`, `skills/setup/*`, README, SKILL.md bodies, `plugin.json`, catalog | 1, 2, 5, 9, 12 |
| 4 | `fixtures/synthetic.js`, `regress.py`, `test_regress.py` | 5, 6, 7 |
| 5 | `workdir.py`, `brush.json`, eight scripts, `roto.js`, docs, README, `plugin.json` | 1-4, 6, 7, 9 |
| 6 | `ink.js`, `inkstats.py`, `learn.py`, Python files, README, `regress.py` | 1, 2, 4, 5, 7 |
| 7 | `extract.py`, `inkstats.py`, `learn.py`, method.md, statistics.md, `regress.py` | 1, 2, 4, 5, 6 |
| 8 | `reference/backends.md`, `render.py` docstring | 1, 3 |
| 9 | `docs/topics/animation-produce/PLAN.md`, README line 13 | 3, 5 |
| 10 | `plugins/pixel-art/skills/{animate,scene}/SKILL.md` | none |
| 11 | `docs/plugin-philosophy.md` | none |
| 12 | CHANGELOGs, validation only | 3 |

### Dependency graph

- 0 → every code phase (the net gates them).
- 1 → 2 → 3 → 4 → 5 → 6 → 7: shared files (`inkstats.py`, `controls.py`, `measure.py`, README)
  and each phase's C3 compare needs the previous phase's state.
- 3 → 4 (`test_regress.py` skip guard uses `prereq`); 1, 2 → 4 (the fixture calls `render.py` and
  `decode.py`).
- 1 → 8 (docstring); 7 → 11 (rules stated after the plugin proves them); all → 12.
- 10 is independent of every other phase.

### Recommended shape

> Fully sequential: 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12. The code phases share
> files and each gates on the previous one's byte-identity run; the only file-disjoint phases (10,
> 11) are under 100 LOC together, so parallelism saves nothing material. `[EXEC-SHAPE]`

Sequential fallback: not needed (no parallel wave).

### Per-phase routing

| Phase | Surface | Basis |
|---|---|---|
| 0 | sub-agent worker (opus) | mechanical script plus long background runs; returns the distilled numbers |
| 1 | sub-agent worker (opus) + `Review: architecture` phase verifier | new composition root, several callers; brief carries the contracts.md section 3 CLI |
| 2 | sub-agent worker (opus) | pure move under a byte-identity gate |
| 3 | sub-agent worker (opus) | new skill under a contract gate |
| 4 | sub-agent worker (opus) | spike, then seam; the issue filing is main session |
| 5 | sub-agent worker (opus) | multi-file mechanical owner edits plus two research records |
| 6 | sub-agent worker (sonnet) | small mechanical fixes with a red-first case |
| 7 | sub-agent worker (opus) | scaling and base rate under the mandatory C3 gate |
| 8 | sub-agent worker (sonnet) | one doc file |
| 9 | main session | opens a topic Brief; judgment on scope |
| 10 | sub-agent worker (sonnet) | two description edits |
| 11 | main session | fleet-wide doctrine wording |
| 12 | sub-agent worker (sonnet) | validators only |

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Integration-first order with the test seam moved to Phase 4 | Phases run render.py → decode.py → probe → seam → SSOT → fixes → scaling; later phases carry `regress.py --synthetic` red cases | plan skill integration-first rule; T8 names `regress.py` the one seam; T8's fixture calls `render.py` (T10) |
| `render.py --root DIR` extra served roots | Phase 1 CLI adds `--root`; `measure.py` passes the work dir | `roto.js:11` fetches `${DIR}/index.json` relative to the page; `fit.py:67-68` writes `fit-brushes.json` into the work dir and renders with `brushes=fit-brushes.json` |
| Every worker default routes to `render.WORKERS` | Phase 1 edits `measure.py`, `fit.py`, `extract.py`, `review.py`, `controls.py` | D29 lists the five differing defaults; V16 names one owner |
| `decode.is_repeat(prev, rgb, dup_px=DUP_PX)`, scaled only by `extract.py` | Phases 2 and 7 | other-style controls are 1920x1080, 1080x1080, 2160x2160 (ffprobe); O1 resolved |
| D37 and D40 output printed only, never in `summary()` | Phase 7 | `controls.run` writes `summary()` verbatim (`controls.py:155-160`), so a new field breaks C3 |
| `test_regress.py` is a subprocess wrapper with no module-level third-party imports | Phase 4 | CI selects it through `scripts/affected-tests.sh` and runs pytest without numpy |
| `regress.py` reuses `controls.replica` for the pack control | Phase 4 | `controls.py:150-152` already encodes the replica as a scene is encoded |
| `render.py --playwright-core` treats empty or `${...}` literals as unset | Phase 3 | O4 resolved to an optional `userConfig` directory; an unset option may reach the command unsubstituted |
| Phase 0 pins tool versions and `compare` fails fast on a mismatch | Phase 0, C1 | byte-identity depends on opencv, ffmpeg and the Chromium build |
| `controls.encode` becomes `render.encode` with identical ffmpeg arguments | Phase 1 edits `controls.py` and `learn.py` | `controls.py:129-147`, `learn.py:174`; module-boundary.md section 3 "only `render.py` calls ffmpeg for writing" |
| If Phase 0's `learn.py` output differs from the committed `style.json`, the baseline output becomes the C3 reference and the mismatch is reported `[FALLBACK]` | Phase 0 gate branch | C3 compares the same code before and after each refactor, which the baseline output provides; the committed file may carry a hand edit |
| Safety-net script lives in the memory slice, never shipped | Phase 0 deliverable | it needs the unshipped shfred0, round 3 and other-style clips (D44, C5) |
| `requirements.txt` pins the versions Phase 0 recorded | Phase 3 pin values | C3 byte-identity; opencv numerics feed every statistic |
| Prerequisite probe is plugin-local, stdlib-only, in `scripts/prereq.py` | Phase 3 creates it; setup and entry points call it | no probe in `scripts/cross-plugin-source-registry.txt`; plugins cannot import sibling files (`docs/plugin-philosophy.md`, Design boundary) |
| T7 ships `reference/backends.md` with the native row and the notice rule only; no adapter rows, no detect code | Phase 8 scope | T3 (interface only with two adapters), T2 (no `backend` `userConfig` key until an adapter ships; T2 covers only that key), contracts.md "`--backend` accepts only `native`" |
| `produce` promoted to its own topic; Phase 9 only opens it | Phase 9 creates `docs/topics/animation-produce/PLAN.md` with a Brief | T13 defers field-level schemas to building `produce`; plan-template Sub-Topic Promotion Trigger (>5 items, >300 LOC, own design need, own PR) |
| pixel-art exclusion phrased without an `/animation:*` token | Phase 10 wording | `docs/plugin-philosophy.md` Design boundary: a bare unguarded cross-plugin reference is a defect |
| No `animation` version bump; `pixel-art` bumped with Phase 10 | Phases 10, 12 | `animation` is added on this branch; `pixel-art` reaches main first under the stated merge order |
| Merge order: PR #4407 (`feat/pixel-art`) first, then rebase this branch onto main | Phase 10 timing, version bumps, `check-changed-skills.sh main` base | pixel-art's files are on both branches today; the branch is local-only until the user authorizes a push |
| Step 0a: inputs and the ctl baseline copied to `~/.local/share/animation-inputs/` with a sha256 manifest verified by every run | Phase 0 | the clips live in another worktree's `.work/`, which worktree cleanup can delete |
| Frozen toolchain: private playwright-core and browsers path passed explicitly, `node` by absolute path, Python version and `nproc` recorded | Phase 0, every C3 run | byte-identity depends on the Chromium build and tool versions; `compare` fails fast on drift |
| `compare` checks summary JSONs, `check`/`selftest`/`learn.py` stdout, `style.json` and `table-*.md` only; never `controls.py measure` stdout or raw regress stdout | Phase 0 `compare` | `controls.py:175-177` prints `<dir>`-prefixed paths in `imap_unordered` completion order; Phase 4 adds a regress output line |
| `render.encode` takes an iterable of BGR frames (rawvideo `bgr24` on stdin), deviating from contracts.md:147 | Phase 1 | `controls.py:129-147` pipes drawings with variable holds; a PNG-folder input changes what ffmpeg encodes and breaks C3 |
| `render.py` serves `scripts/` before any `--root` | Phase 1 | old work dirs hold copied `ink.js` and `render.html` (`measure.py` copies them today), which must not shadow the engine |
| Fully sequential execution; routing per the table above | Handoff shape | file-overlap matrix: code phases share `inkstats.py`, `controls.py`, `measure.py`, README; the disjoint phases total under 100 LOC |

## Open questions

None open. O1-O5 below were resolved by the user on the recommendation given in each (2026-09-25);
kept for the reasoning.

- **O1 (resolved: a). Does `inkstats.py` scale its pixel thresholds by frame area (D34, D37)?** The frozen
  check's other-style controls are 1920x1080, 1080x1080 and 2160x2160 (ffprobe), so scaling changes
  their summaries and margins at a frozen check. Options: (a) scale only in `extract.py`, give
  `inkstats.py` the size warning, defer its scaling to issue #4507; (b) scale both and re-baseline
  the check, recording every moved margin. Recommendation: (a). Unblocks Phase 7.
- **O2 (resolved: a). Where does the base frame rate come from (D24, D25)?** shfred0 is variable-rate
  (`r_frame_rate` 60/1, average about 7.99 fps), so "the source's measured rate" does not yield the
  24 fps grid holds are counted on. Options: (a) `learn.py --base-fps` defaulting to 24, written to
  `knobs.frame_rate.base_fps`, and `inkstats.py` reads it from the pack, else `--fps`; (b) derive
  from the container rate; (c) keep 24 as a named constant. Recommendation: (a); identity-safe
  because the woodcut pack already holds 24. Unblocks Phase 7.
- **O3 (resolved: a). Is the synthetic fixture wired into CI now?** `ci.yml` installs only
  `.github/requirements-ci.txt`; no numpy, opencv, ffmpeg or Chromium. `affected-tests.sh` still
  selects `test_regress.py`, so it must skip cleanly there. Options: (a) ship
  `test_regress.py` skip-guarded (visible skip reason) and file a follow-up issue for a CI job; (b)
  add a CI job installing the pinned requirements, ffmpeg and Playwright Chromium on this branch.
  Recommendation: (a), since (b) is shared CI infrastructure with its own review. Unblocks Phase 4.
- **O4 (resolved: a). What replaces `PW_CORE` (D7)?** T15 left it open. Options: (a) an optional `userConfig`
  `directory` option passed as an argument through SKILL.md, verified by setup `check`; (b) a
  `SessionStart` hook installing playwright-core into `${CLAUDE_PLUGIN_DATA}` (research tag open;
  Chromium still needs `npx playwright install chromium`); (c) drop it and keep the working-dir and
  `playwright-cli` lookups. Recommendation: (a). Unblocks Phase 3's D7 item.
- **O5 (resolved: spike, prefer a, fall back to b). What does the synthetic fixture assert?** Unmeasured whether a synthetic scene, encoded,
  re-traced and re-rendered at the default brush meets the 1.2 x floor / 0.980 target. Options: (a)
  assert the fidelity target (contracts.md section 6 makes it the adapter-proof criterion), with
  fixture overrides if needed; (b) assert the drawing count and the render/encode/decode contracts
  only. Recommendation: spike it at the start of Phase 4, prefer (a), fall back to (b) if the spike
  misses. Unblocks Phase 4.

## Handoff to implementation

### User-approval gates

- Phase 0 `[FALLBACK]`: if the baseline `style.json` differs from the committed file, confirm the
  baseline output as the C3 reference.
- Phase 4 issue filing (a tracker write) runs its phase-entry duplicate search first.
- Any C3 compare failure in a refactor phase: stop and report; do not re-baseline without the user.
- Any change to `inkstats.check()`, bands, `CHECK`, or the controls: out of scope (frozen).

### Execution shape ([EXEC-SHAPE] tagged)

Fully sequential per the routing table. Every worker brief carries its phase's file list as the
ALLOWED set, forbids PLAN.md and commits outside the phase, and includes:

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief, so
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task, STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

### Mechanical work

- One commit per phase (structural moves separate from behaviour fixes, Tidy First); the phase's
  PLAN.md tag change rides that commit.
- After each code phase: C1, then the Phase 0 `compare` in the background, then the phase tag.
- Post-implementation grep for stragglers: `grep -rn "measure.render\|PW_CORE\|with numpy,opencv\|shutil.copy" plugins/animation | grep -v "regress.py:.*shutil.copy(FIXTURE"` returns nothing (the fixture copy at `regress.py:24` is legitimate).
