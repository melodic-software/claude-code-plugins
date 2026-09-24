# animation: port contracts (design round 1)

Only one port gets an interface now: **render**. It is the only port with two adapters named in
DIRECTION.md (native today; HyperFrames and Remotion later). Every other candidate is "one adapter,
no port yet" (domain-model.md, section 3): its code gets one home and a plain function or CLI, and
becomes a port the day its second adapter is real. That keeps to the brief's ban on speculative
abstractions.

Two kinds of contract appear below:

- **File-format contract**: a file or folder shape any tool can write or read. These are the
  stable, public surfaces: they are what an adapter translates to and what `post` will consume.
- **Script CLI contract**: the command line a skill runs. Internal to the plugin; it can change in
  one PR as long as every SKILL.md calling it changes too.

## 1. Contract index

| Contract | Kind | Owner (proposed) | Consumers |
|---|---|---|---|
| Scene module | file-format (JS module) | contracts.md section 2; `scripts/render.html` comment points here | render adapters, `roto.js`, every authored scene |
| Frame folder + `render.json` | file-format | contracts.md section 4 | encode step, `inkstats.py`, review, later `post` |
| Work dir (rotoscope) | file-format | rotoscope `SKILL.md` table; code paths from `scripts/workdir.py` (dependency-inventory.md V20) | rotoscope scripts, `inkstats.py`, `learn.py` |
| Override file | file-format | rotoscope `SKILL.md`, Override file | `extract.py`, `fit.py` |
| Style pack | file-format | learn-style `SKILL.md`, Pack format | `inkstats.py --pack`, authors, `produce` |
| `shots.json`, boards, `render.json` | file-format | domain-model.md section 2.2 (sketch; settled in the `produce` design) | `produce`, render, `inkstats.py --cuts` |
| `render.py` | script CLI | section 3 | all three skills |
| `capture.mjs` | script CLI, adapter internal | its header | `render.py` only (today also `measure.py` and the SKILL.md bodies) |
| `inkstats.py`, `extract.py`, `measure.py`, `fit.py`, `review.py`, `learn.py`, `regress.py` | script CLI | each script's docstring | skills |

## 2. Scene module (file-format contract)

Taken from what the native adapter enforces today (`scripts/render.html:6-8`,
`scripts/capture.mjs:35-48`, `skills/rotoscope/scripts/roto.js:88-94`), plus the two rules today's
code leaves implicit.

- An ES module, loaded by `render.html?scene=<file>`, served from the same origin.
- It sizes `canvas#c` (width and height in pixels) before `renderFrame` first resolves.
- `window.DURATION`: seconds, a positive finite number. (Today a missing value renders zero frames
  and exits 0: dependency-inventory.md D18. The contract makes it an error.)
- `window.renderFrame(t) -> Promise`: after the promise resolves, the canvas shows time `t`.
- Optional `window.renderDrawing(k) -> Promise` for per-drawing capture (rotoscope review).
- Determinism: the pixels depend only on `t` (or `k`). No wall clock, no unseeded randomness
  (`ink.js` `rng(seed, step)` is the seeded source), no network beyond same-origin relative files.
- Imports: `./ink.js` and files beside the scene resolve; nothing else is promised.
- Frame rate is **not** part of the scene. The scene is continuous in `t`; the rate is a render
  argument recorded in `render.json`. Boil and holds are the scene's own business
  (`floor(t * 8)` is how a scene on 3s picks its drawing, `ink.js:4`).

Determinism guarantee, stated honestly: the same scene, `t` and browser build give the same pixels.
Across Chromium builds pixels can differ (the `blur()` floor measured on build 1246 is one known
case), which is why `render.json` records the build.

## 3. Render port

### Operations

| Operation | In | Out |
|---|---|---|
| frames | scene module, `--fps N` | frame folder `fNNNN.png` (frame `i` shows `t = i / N`) + `render.json` |
| drawings | scene module with `renderDrawing`, `--drawings k,k,...` | `dNNN.png` per drawing + `render.json` |
| encode (optional step, not a port) | frame folder, format | delivered file beside the folder |

### Script CLI contract (proposed `scripts/render.py`)

```text
render.py <scene.js> <out dir> (--fps N | --drawings K0-K1|k,k,...)
          [--query 'mode=b&brush=...'] [--backend native|hyperframes|remotion]
          [--encode none|mp4|webm|gif] [--workers N]
exit 0  every requested frame written, render.json written
exit 1  the scene failed: pageerror, missing or non-positive DURATION, missing renderDrawing
exit 2  a prerequisite for the native adapter is missing (remedy printed); no fallback is left
```

It absorbs `measure.py:40-58` (serve on a free loopback port, call `capture.mjs`), so `measure.py`,
`fit.py` and the SKILL.md film steps all call one entry point, and a novel scene gets a serve step
it lacks today (dependency-inventory.md D16).

### Composition root: which adapter runs

`render.py` is the one place an adapter is chosen. Order:

1. The skill passes `--backend` explicitly. A skill-run script does not see
   `CLAUDE_PLUGIN_OPTION_*` (hook-only, `docs/plugin-philosophy.md:378-382`), so SKILL.md
   substitutes the configured value into the command: `--backend ${user_config.backend}` (once
   the key exists, per T2), and the user's request in the conversation overrides it.
2. Default `native`.
3. Presence: the chosen adapter's `detect()` runs. On failure: one line naming what was missing,
   then native, then continue. Never silent, never a hard stop (pixel-art `reference/backends.md`,
   Selection rule, items 1-3, cited rather than restated).
4. Licence: before the first render in a session with a non-native adapter, print that adapter's
   licence notice (below). The notice is recorded in `render.json`.
5. Native missing too: exit 2 with the remedy.

`userConfig` itself is thread T2. Until a second adapter ships there is nothing to select, so no
key is added and `--backend` accepts only `native`.

### How an adapter declares presence and licence

Two parts, the same row shape pixel-art uses (`plugins/pixel-art/reference/backends.md`: Adds,
Detect, Cost and licence, Contract):

- A row in `plugins/animation/reference/backends.md` (new) for readers and for the setup `check`.
- A `detect()` in the adapter code returning `(present, version, licence_path)`. The notice quotes
  the licence file found in the installed package, by path and version, so what the user reads is
  the licence they actually have, not a copy in the plugin.

The notice states terms and never judges whether the user qualifies (DIRECTION.md). The Remotion
facts the notice would state today, as a four-part record:

- Claim: Remotion is source-available, not OSI open source; free for individuals, for-profit
  organizations of up to 3 employees, non-profits and evaluation; a Company License otherwise; its
  LICENSE announces a change for Remotion 5.0.
- Basis: `.work/strategy/research/RESEARCH-findings.md` ("What Remotion says it is for, and its
  license"), evidence row E11, which cites Remotion's LICENSE.
- As of: 2026-09-24 (v4.0.528).
- Recheck trigger: a Remotion 5.0 release, or any change to its LICENSE file.

HyperFrames: Apache-2.0 (same basis, E12, v0.8.73, 2026-09-24; recheck on a licence change). An
Apache-2.0 adapter still prints its notice line, for uniformity.

### Errors

| Case | Native behaviour today | Contract |
|---|---|---|
| scene throws | `pageerror` logged, exit 1 at end (`capture.mjs:33,55`) | same |
| `renderFrame` never defined | 30 s timeout, Playwright error (`capture.mjs:35`) | same, with the scene name in the message |
| `DURATION` missing | zero frames, exit 0 (D18) | exit 1 |
| playwright-core missing | exit 2 with remedy (`capture.mjs:22-23`) | same |
| ffmpeg missing (encode) | traceback | exit 2 with remedy; frames stay written |
| non-native adapter missing | n/a | notice, native, continue |

## 4. Frame folder and `render.json` (file-format contract)

The handoff between craft and delivery, and the surface `post` will consume at extraction
(module-boundary.md, section 4).

- `fNNNN.png`, zero-padded to at least four digits, frame `i` at `t = i / fps`. Readers sort
  numerically (dependency-inventory.md D23).
- `render.json`: `{scene, adapter, adapter_version, browser_build, fps, size: [w, h], frames,
  duration, licence_notice?}`. It is the only place the frame rate of a frame folder is stored;
  today `inkstats.py` has to be told `--fps` separately.

## 5. Candidates with one adapter (no port yet)

| Candidate | Contract kept | Home |
|---|---|---|
| encode | function `encode(frames_dir, fmt, fps) -> path`; ffmpeg only. Format is an argument, not a port (thread T4) | `scripts/render.py` |
| source-in | function `frames(path, fps)` yielding `(rgb, t)` for a video, a frame folder or a work dir (today `inkstats.py:58-80`), plus the repeat-drawing rule and gray modes | `scripts/decode.py`, imported by `extract.py` and `inkstats.py` |
| fidelity measure | `measure.py` CLI, unchanged | rotoscope skill |
| style statistics | `inkstats.py` CLI, unchanged, plus a size check against the pack (D37) | `scripts/` |
| audio-in | `shots.json` `audio: {path, start}`; no code until `produce` or `post` needs a mux | none |
| preview | an `--encode gif` option for the approval gate only, never for review | encode step |

## 6. Test seam

One seam: `skills/rotoscope/scripts/regress.py` (thread T8). It already drives source-in, trace,
render (native adapter) and fidelity measure end to end. Proposed additions, still one script:

- A synthetic fixture that needs no unshipped clip: a small committed scene rendered through
  `render.py --fps`, encoded, then decoded and measured as if it were a reference. It proves the
  render, encode and source-in contracts together and can run in CI.
- On the shfred0 run, also `inkstats.py --pack styles/woodcut-ink` over the replica: learn-style's
  own gotcha names the replica as the same-style control a pack must pass.

A new render adapter proves itself at this seam: the same synthetic scene through `--backend
<adapter>` must match the native frames within the fidelity target.
