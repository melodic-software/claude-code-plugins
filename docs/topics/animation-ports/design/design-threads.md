# animation ports: design threads (round 1)

Every thread starts as a recommendation, resolved once the user decides it. Status values: **open** (needs the user),
**directional** (direction agreed or strongly implied by settled direction; details deferred),
**deferred** (waits on a trigger or research; carries a tag), **resolved**.

Order: the threads the user is most likely to redirect come first (public contracts and
user-facing surfaces), mechanical ones last. **R1** marks the threads the user must decide in round
1; the rest can ride on the recommendation until a later round.

Companion files: [domain-model.md](domain-model.md), [contracts.md](contracts.md),
[module-boundary.md](module-boundary.md), [dependency-inventory.md](dependency-inventory.md).

## Dependency graph

```text
T1 scene contract ──> T4 output formats, T10 composition root, T11 post, T12 pixel-art, T13 produce artifacts
T3 port granularity ─> T2 userConfig ─> T7 license notice
                   └─> T9 measure, T10, T14 source-in
T5 naming ──────────> T13
T6 skill set ───────> T15 prerequisite fixes
T10 ────────────────> T8 test seam, T16 SSOT owners
T14 ────────────────> T16, T17
T16 rule (R1) ──────> the per-value edits in T16's table
```

---

## T1. Scene artifact contract (R1, resolved 2026-09-24)

What crosses from craft to rendering: a seekable scene module, or finished frames?

| Option | For | Against |
|---|---|---|
| A. Seekable scene module only (`renderFrame(t)`, `DURATION`, `canvas#c`) | Already enforced by the native adapter; any frame renders independently, so capture parallelizes (`capture.mjs:42-53`) and review can re-render one drawing | pixel-art's rAF loop does not fit without an adapter; generative video has no scene at all |
| B. Frame-folder handoff only | Any producer fits, including generative models and pixel-art's rAF via screen capture | Loses per-drawing re-render; review loops re-render the whole film; HyperFrames and Remotion adapters have nothing to consume |
| C. Both, at different boundaries: scene module between craft and render; frame folder + `render.json` between render and delivery | Each boundary gets the shape its consumers need; `post` never sees a scene, so extraction is a move | Two contracts to keep documented |

Recommendation: **C**. Keep the scene contract minimal (contracts.md section 2) and keep the frame
rate out of it: fps is a render argument recorded in `render.json`. pixel-art reaches the scene
contract with a replay adapter of its own (module-boundary.md section 5), so the rAF loop is not
an incompatibility, only a missing function plus one seeded-RNG rule.

Resolved 2026-09-24: user approved recommendation.

Blocks: T4, T10, T11, T12, T13.

## T2. userConfig shape (R1, resolved 2026-09-24)

pixel-art declares one `backend` string (`native | aseprite | pixellab | retrodiffusion`, default
`native`, fallback to native with a notice) and ships no adapter code for it.

| Option | For | Against |
|---|---|---|
| A. No userConfig until the first non-native render adapter ships | Nothing to select today; avoids a key that does nothing | The key name is decided later, under time pressure |
| B. One `backend` key, same name and semantics as pixel-art | One way across both visual-arts plugins; a user who set one understands the other | Ambiguous if a second port (audio, source) ever gets a second adapter |
| C. Per-port keys (`render_backend`, later `audio_backend`) | Unambiguous as ports grow | Diverges from pixel-art; per-port keys for ports that have one adapter are speculative |

Constraints either way: `userConfig` is read only from user, `--settings` and managed settings,
never project settings (`docs/plugin-philosophy.md:344-347`); a skill-run script sees it only
through `${user_config.*}` substitution into the command (`:378-382`), so `render.py` takes
`--backend` as an argument.

Recommendation: **A now, B when the first adapter lands.** Name the key `backend` to match
pixel-art. If a second port ever gets a second adapter, rename both plugins' keys together through
a `retirements.yaml` record rather than letting them diverge.

Resolved 2026-09-24: user approved recommendation.

Blocked by: T3. Blocks: T7.

## T3. Port granularity (R1, resolved 2026-09-24)

How many ports, and which get an interface now?

| Option | For | Against |
|---|---|---|
| A. One port (render), everything else one adapter, no port | Matches the rule: an interface only where two adapters exist or are named | source-in and encode look "portish" and a reader may expect symmetry |
| B. Six ports (source-in, render, encode, measure, audio-in, preview), native adapters behind each | Symmetric, matches DIRECTION.md's list | Five interfaces with one implementation each; the brief bans speculative abstractions |
| C. Two ports (render, encode) | Encode is what moves to `post` | Encode has one adapter; HyperFrames and Remotion encode inside their own render, so they would not implement an encode port anyway |

Recommendation: **A**. Encode, source-in, audio-in and preview get a single home and a function
signature (contracts.md section 5), which is enough to make each a port later without a rewrite.

Resolved 2026-09-24: user approved recommendation.

Blocks: T2, T7, T9, T10, T14.

## T4. Output-format family (R1, resolved 2026-09-24)

mp4, webm, PNG sequence, GIF preview now; sprite sheet and Lottie later. Is format a port or an
adapter option?

Recommendation: **an argument of the encode step** (`render.py --encode none|mp4|webm|gif`). The
PNG frame folder is always written, so "PNG sequence" is `--encode none`. GIF is for the
approval gate only; DIRECTION.md and both SKILL.md bodies forbid reviewing a GIF. Sprite sheets and
Lottie are a different artifact kind (a layout of drawings, a vector runtime format), not an
encoding of frames: deferred, tag `research: what a Lottie export of an ink.js scene would keep`,
trigger: a user asks for a runtime or game asset from `animation`.

Resolved 2026-09-24: user approved recommendation.

Blocked by: T1.

## T5. Naming: `produce` and other renames (R1, resolved 2026-09-24)

`produce` is the working direction (a verb; production is the stage between pre-production boards
and post). Renames it implies, none of which this session may edit:

- `plugins/animation/README.md:13` "Planned next: `film` (...)" becomes `produce`.
- `plugin.json` keyword `film` may stay: keywords are search terms, not skill names.
- The rotoscope `## Next` names learn-style; learn-style has no `## Next`, and should gain one
  naming `/animation:produce` when it ships (`.claude/rules/skill-bodies-state-current-rules.md`).
- `rotoscope`, `learn-style` keep their names (verb phrases).

Recommendation: confirm `produce`.

Resolved 2026-09-24: user approved recommendation.

Blocks: T13.

## T6. Skill set: add `setup`, do not add `check` (R1, resolved 2026-09-24)

- `setup` (check-only): required by `docs/plugin-philosophy.md:423-428`, criterion (b) external
  prerequisites. The plugin has ffmpeg, ffprobe, node, playwright-core with Chromium and a Python
  environment, and no setup skill today. This is a conformance gap, not a preference.
- `check` for "does this film match the pack": the verb fits (deterministic pass/fail,
  `docs/plugin-philosophy.md:139`), but it is a step inside learn-style and produce, not a goal.

Recommendation: add `setup`; keep the pack check as a shared script.

Resolved 2026-09-24: user approved recommendation.

Blocks: T15.

## T7. License surfacing mechanics (resolved 2026-09-25)

Settled: the Remotion adapter surfaces its terms and does not judge who qualifies. Open mechanics:

| Option | For | Against |
|---|---|---|
| A. Static text in `reference/backends.md` only | Simple | Goes stale; the user never sees it at run time |
| B. Run-time notice read from the installed package's LICENSE (path + version), printed once per session before the first render, recorded in `render.json` | The user reads the license they actually have; a record travels with the output | A few lines per adapter |
| C. Confirm prompt before every render | Maximum friction | Blocks unattended runs; still no judgment possible |

Recommendation: **B**, plus the four-part record in `backends.md` (contracts.md section 3). A
one-time confirmation before the first call in a session, as pixel-art does for paid adapters
(`plugins/pixel-art/reference/backends.md`, Selection rule 4), applies to paid remote services,
not to a locally installed licensed library. Blocked by: T2, T3.

Resolved 2026-09-25: user approved recommendation B. Why: the notice comes from the license the
user actually installed and travels with the output in `render.json`, without blocking
unattended runs.

## T8. Test-seam posture (R1, resolved 2026-09-24)

The seam today: `regress.py` (decode, trace, native render, fidelity measure), 239/239 on shfred0.
It cannot run in CI or on a fresh machine: the clip is not shipped (dependency-inventory.md D44).

| Option | For | Against |
|---|---|---|
| A. `regress.py` stays the one seam, gains a synthetic fixture mode (a committed tiny scene rendered, encoded, decoded, measured) runnable in CI; shfred0 stays the manual calibration run, and also runs `inkstats.py --pack` on its replica as the same-style control | One seam, both fixtures; covers render, encode and source-in contracts; each new render adapter proves itself on the same scene | The synthetic scene is a second fixture to maintain |
| B. Per-port unit tests (pixel-art has `test_render.py`) | Fast, narrow | Many seams for one pipeline; the failures that mattered in this plugin (border rows, blur floor, codec noise) only show end to end |
| C. Leave as is | No work | The plugin's contracts have no automated test |

Recommendation: **A**.

Resolved 2026-09-24: user approved recommendation.

Blocked by: T10 (the fixture calls `render.py`).

## T9. Measure: one "compare" port or two operations? (resolved 2026-09-25)

`measure.py` compares a replica to its source drawing by drawing (XOR against a floor, SSIM).
`inkstats.py` profiles one film and checks the profile against a pack's bands. Different inputs,
outputs and questions; no external tool computes either. Recommendation: **two core operations,
no port**. What they genuinely share (frame loading, repeat-drawing rule, gray modes) moves to
`scripts/decode.py` (T14). Blocked by: T3.

Resolved 2026-09-25: user approved recommendation. Why: a port needs two adapters (T3), and no
external tool computes either operation; only the decode path is shared.

## T10. Composition root location (resolved 2026-09-25)

Recommendation: a shared `scripts/render.py` absorbs `measure.py:40-58`, serves the scene's dir and
`scripts/` as two roots (no more copying plugin files into the work dir), chooses the adapter,
encodes, writes `render.json` (contracts.md section 3). Fixes D16 (no serve step for novel scenes)
and D18 (zero-frame exit 0). Blocked by: T1, T3. Blocks: T8, T16.

Resolved 2026-09-25: user approved recommendation. Why: rotoscope, learn-style and produce all
render; one entry point is the only place adapter choice, encode and the render record can live
once.

## T11. `post` extraction mechanics (deferred)

Tag: `trigger: a second producer needs an mp4`. Open when it fires: learn-style validation encodes
to match the source's codec softening; after extraction, keep a minimal encode in `animation`, or
declare `post` a dependency, or presence-gate it with "frames only" as the reduced result.
Recommendation when triggered: presence-gate, with validation falling back to measuring the frame
folder and a visible note that `soft` may read low without codec softening. Blocked by: T1.

## T12. pixel-art emitting the scene artifact (deferred)

Tag: `trigger: pixel-art asks for mp4 or frame export`. Shape in module-boundary.md section 5:
replay adapter plus a seeded-RNG rule in `scene-canvas.md`; render code shared as a registered
synced copy. Blocked by: T1.

## T13. `produce` stage artifacts (resolved 2026-09-25)

Schemas sketched in domain-model.md section 2.2 (brief, boards, storyboard, shot list, render
manifest). Settled in the `produce` design session, not here. One decision worth taking now: the
shot list owns shot cuts, so `inkstats.py --cuts` reads `shots.json` rather than a typed list.
Blocked by: T1, T5.

Resolved 2026-09-25: user approved recommendation: the sketched schemas are the starting shape,
and `shots.json` owns shot cuts. Why: one owner per value (T16); the cut list is a shot-list fact.
Field-level schema detail is decided while building `produce`, inside the plan.

## T14. Source-in consolidation (resolved 2026-09-25)

The decode path exists twice (`extract.py:35-68`, `inkstats.py:58-80`) with the same ffprobe and
ffmpeg argument lists and the same repeat-drawing rule. Recommendation: one `scripts/decode.py`,
imported by both. Blocked by: T3. Blocks: T16, T17.

Resolved 2026-09-25: user approved recommendation. Why: the same code twice is the duplication the
user ruled out; the two copies already drift risk on the repeat-drawing rule.

## T15. Prerequisite handling (resolved 2026-09-25)

From dependency-inventory.md: D1, D3, D5 (ffmpeg, ffprobe, node absent: traceback, no remedy), D2
(ffmpeg version unstated), D4 (encode is a comment), D7 (`PW_CORE` is a custom env channel), D8
(`/bin/sh` lookup), D11-D13 (unpinned packages, no Python minimum).

Recommendation: one prerequisite probe shared by `setup` check and the entry points (`render.py`,
`decode.py`); a pinned `requirements.txt`; replace `PW_CORE` with a `userConfig` `directory` option
or an install into `${CLAUDE_PLUGIN_DATA}` (research tag: whether a SessionStart install hook is
worth it for a node package); scan `PATH` in JS instead of `/bin/sh`. Blocked by: T6.

Resolved 2026-09-25: user approved recommendation. Why: a missing tool today ends in a traceback
with no remedy; one probe gives `setup` and every entry point the same message.

## T16. SSOT: one owner per value (rule is R1, resolved 2026-09-24; the table is mechanical)

The rule to decide in round 1: **code reads each value from one owner; docs cite the owner and do
not restate the number; measurement records keep their numbers as data; a volatile external
specific restated in a skill body carries the four-part record; a value both Python and JavaScript
read lives in JSON.**

Resolved 2026-09-24: user approved recommendation.

Owner decisions, from dependency-inventory.md section 2:

| Value | Owner |
|---|---|
| V1 acceptance target | `measure.py:36`; method.md keeps the one reasoned statement; README and SKILL.md cite |
| V2 239 drawings | `regress.py:16`; records keep it |
| V3 render brush defaults | new `skills/rotoscope/scripts/brush.json`, read by `roto.js`, `measure.py`, `fit.py` (also fixes D32) |
| V4-V7 tracing and fit defaults | `extract.py:28-30`, `fit.py` arguments; method.md cites |
| V8-V10 repeat rule, gray modes, decode commands | `scripts/decode.py` (T14) |
| V11 Chromium blur floor | one stamped record in method.md; both SKILL.md gotchas point to it |
| V12 24 fps | pack `knobs.frame_rate.base_fps` (style), `shots.json` `fps` or source rate (render) |
| V13, V14 ink colour, grain seed | one const in `ink.js`; the pack's `palette.ink` for styled work |
| V15 segment length | `inkstats.SEG` |
| V16 worker counts | one `WORKERS` in `render.py` |
| V17 2576 px | one stamped record (origin to be found) |
| V18 soften sigma | the pack |
| V19 Python packages | `requirements.txt` |
| V20, V22 work-dir and file naming | `scripts/workdir.py` |
| V21 Playwright lookup and remedy | `capture.mjs` |
| V23 encode settings | the encode step in `render.py` |
| V26 validation result | STYLE.md, Validation |
| V24, V25 | intentional duplicates, keep |

Blocked by: T10, T14.

## T17. Resolution and frame-rate assumptions (resolved 2026-09-25)

D24, D25 (holds counted at 24 fps; pack writes a literal 24), D26 (1/8 s fallback), D34 (repeat
rule in absolute pixels), D35 (tint thresholds in absolute pixels), D37 (pack check ignores the
film's size), D40 (two-tone assumption unstated). Recommendation: take the base rate from the
source or pack; scale pixel-count thresholds by frame area relative to the calibration size; warn
when a film's size differs from `measured_from.size`; state the two-tone scope in method.md and
statistics.md. Research tag for the scaling: `validate on a second clip at another resolution`.
Blocked by: T14.

Resolved 2026-09-25: user approved recommendation. Why: every absolute pixel and 24 fps constant
is calibrated on one 1762x982 clip; scaling and a size warning keep a different film from being
judged on the wrong scale.

## T18. Correctness fixes (resolved 2026-09-25, mechanical)

D18 (missing `DURATION` exits 0 with zero frames), D22 (layout strings in eight files; with T16),
D23 (lexicographic frame sort breaks past 9,999 frames), D28 (2576 unrecorded), D29 (worker
defaults), D41 (engine ink colour differs from the pack), D48 (Windows and macOS unverified; text
files opened without `encoding=`). Recommendation: fix in the same PR as T10. No decision needed.

Resolved 2026-09-25: user approved recommendation. Why: each is a defect with one correct fix, and
most touch `render.py` or its callers, which T10 rewrites anyway.

## T19. Per-clip acceptance target (deferred)

The fidelity target (1.2 x floor, 0.980) is calibrated on one clip. Tag: `trigger: a second
reference clip`. Option when it fires: a `target` entry in the override file, which already carries
every per-clip decision.

## T20. `animation` stays the craft plugin (resolved 2026-09-24)

Decision: `animation` remains the one craft plugin.

Why: animation is a production technique and video a delivery format. The research behind it: the
Academy's animated-feature rule (75% animated running time), O*NET's separate occupations for
animators (27-1014) and video editors (27-4032), and the Emmys' separate motion-design category.

Resolved 2026-09-24: user approved recommendation.

## T21. Rendering location and delivery-plugin naming (resolved 2026-09-24)

Decision: rendering stays inside `animation` until a second producer needs mp4 output. When that
trigger fires, extraction goes to a delivery plugin named `post`, never `video`. See T11 for the
extraction mechanics themselves, which stay deferred until the trigger fires.

Why: a delivery plugin with one producer is a speculative split; `post` names the delivery stage,
while `video` would re-open the craft-versus-format confusion T20 settled.

Resolved 2026-09-24: user approved recommendation.

## T22. pixel-art routing descriptions fixed on this branch (resolved 2026-09-24)

Decision: the pixel-art skill routing descriptions are fixed on this branch. `"animate this"` and
`"make me a video"` must stop landing on `pixel-art:animate` and `pixel-art:scene`.

Why: with `animation` installed, pixel-art's descriptions claim general animation and video
requests, so the wrong skill fires. The fix belongs on the branch that introduces the overlap.

Resolved 2026-09-24: user approved recommendation.

## T23. Fix-needed items form one cleanup phase (resolved 2026-09-24)

Decision: the fix-needed items (22 fixes, plus the two bugs; see T15, T17, T18) form one cleanup
phase on this branch.

Why: the fixes share files (`render.py`, `decode.py`, the SSOT owners), so splitting them would
edit the same code twice; one phase lands them behind one verification.

Resolved 2026-09-24: user approved recommendation.

## T24. Missing plugin-philosophy rules (resolved 2026-09-24)

Decision: two plugin-philosophy rules are missing and are written after this design settles:
skill-as-process with outputs and tools behind ports and adapters, and one owner per value inside
a plugin.

Why: the user set both as fleet-wide rules (2026-09-24), and the capability matrix found neither in
`docs/plugin-philosophy.md`; writing them after this design settles means they state rules already
proven on one plugin.

Resolved 2026-09-24: user approved recommendation.

## T25. Generalized plugin-alignment audit skill (resolved 2026-09-24)

Decision: a generalized plugin-alignment audit skill is designed properly, in its own design
session, before anything is built.

Why: the user ruled that nothing is implemented twice in this repo; several existing checks already
cover parts of alignment (capability-matrix.md), so the audit must be designed to compose them.

Resolved 2026-09-24: user approved recommendation.

---

## Round 1 asks, in one place

| Thread | Question | Recommendation | Unblocks |
|---|---|---|---|
| T1 | Scene module, frame folder, or both? | Both, at different boundaries; fps out of the scene | T4, T10-T13 |
| T2 | userConfig now, and what shape? | None now; one `backend` key matching pixel-art when an adapter ships | T7 |
| T3 | How many ports get an interface? | Render only | T2, T7, T9, T10, T14 |
| T4 | Is output format a port? | No: an encode argument; sprite sheet and Lottie deferred | produce delivery |
| T5 | `produce` as the name? | Yes; README line 13 renamed with it | T13 |
| T6 | Add `setup`, add `check`? | `setup` yes (philosophy requires it), `check` no | T15 |
| T8 | Test seam? | `regress.py` stays the one seam; add a synthetic CI fixture and the pack control | CI coverage of the contracts |
| T16 | SSOT rule? | Code reads one owner, docs cite, records keep data, JSON for cross-language values | the V-table edits |
