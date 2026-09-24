# animation: module boundary (design round 1)

## 1. Today

```text
plugins/animation/
  .claude-plugin/plugin.json     no userConfig
  scripts/                       shared by every skill
    ink.js                       brush engine (domain core)
    render.html, capture.mjs     native render adapter
    inkstats.py                  style statistics (core) + a second copy of video decode (source-in)
  skills/rotoscope/scripts/
    extract.py                   video decode (source-in, first copy) + tracing (core)
    measure.py                   fidelity measure (core) + serve-and-capture (render composition root)
    fit.py, review.py, regress.py
    roto.js                      a scene module (implements the scene contract for traces)
  skills/learn-style/scripts/learn.py
  styles/woodcut-ink/
```

Dependency direction today is already one-way: skill scripts reach `scripts/` (`measure.py:35`,
`learn.py:27`), and nothing in `scripts/` reaches into a skill. Two things sit in the wrong place:
the render composition root lives in a skill (`measure.py:40-58`), and source-in exists twice.

## 2. Target layout

```text
plugins/animation/
  .claude-plugin/plugin.json     userConfig `backend` only once a second render adapter ships (T2)
  requirements.txt               pinned Python packages (dependency-inventory.md V19)
  reference/backends.md          adapter rows: native now; hyperframes, remotion when they ship
  scripts/                       ports, adapters and shared core. Never imports from skills/.
    ink.js                       brush engine
    render.py                    render port: composition root, native driver, encode step
    render.html, capture.mjs     native adapter internals (called only by render.py)
    decode.py                    source-in: frames(), repeat-drawing rule, gray modes
    workdir.py                   work-dir path helpers
    inkstats.py                  style statistics
    adapters/<tool>.py           only when an adapter ships; not created now
  skills/
    rotoscope/scripts/           extract, measure (fidelity only), fit, review, regress, roto.js, brush.json
    learn-style/scripts/learn.py
    produce/                     boards, approval gate, shots, render.py, inkstats --pack
    setup/                       check-only prerequisite probe
  styles/<name>/                 style packs (data, no code)
```

No `ports/` or `adapters/` directory tree is proposed: one port does not need a folder hierarchy.
Files are named for what they do.

`render.py` serves two roots over one loopback server: the scene's own directory first, then
`scripts/` (for `render.html` and `ink.js`). That removes today's copy of plugin files into the
user's work dir (`measure.py:47-48`) and gives novel scenes the serve step they lack.

## 3. Dependency direction

```text
skills/*  (process: what to do, in what order, when to stop)
   |  call CLIs, import modules
   v
scripts/render.py, decode.py, workdir.py, inkstats.py   (ports and shared core)
   |  call
   v
adapter internals: capture.mjs + render.html + Chromium, ffmpeg, ffprobe, later HyperFrames/Remotion
```

Rules:

- A skill may import or call anything in `scripts/`. `scripts/` never imports from `skills/`.
  That is why `workdir.py` and `decode.py` sit in `scripts/`: `inkstats.py` needs both.
- Only `render.py` calls `capture.mjs` or an adapter. Skills and other scripts call `render.py`.
- Only `decode.py` calls `ffprobe` or `ffmpeg` for reading; only `render.py` calls `ffmpeg` for
  writing. After the move, a grep for `'ffmpeg'` and `capture.mjs` outside those two files is the
  check.
- Scene modules (`roto.js`, authored scenes, element modules on boards) depend on `ink.js` and the
  scene contract, never on a render adapter.
- Style packs and stage files are data. Code reads them; they never name a tool.

## 4. Extraction of `post`, and why the scene contract survives it

Trigger (settled direction): a second producer needs an mp4. Candidates named in the strategy
work: `pixel-art` exporting a scene, an audio plugin, a generative-video skill.

What moves to `post`:

- The encode step in `render.py` (frames to mp4/webm/gif), and whatever audio mux, captions and
  delivery presets have grown by then.
- The reading side of `render.json` for delivery.

What stays in `animation`:

- The scene contract, `ink.js`, style packs, all measurement.
- Scene-to-frames rendering and its adapters (native, HyperFrames, Remotion). They consume scenes,
  which is craft (`.work/strategy/position-b.md`, section 6, "keep scene-to-frames adapters ...
  craft-side").

Why it is a move, not a rewrite: `post`'s input is the frame folder + `render.json` contract
(contracts.md section 4), which `animation` already writes. Nothing in `post` reads a scene module,
so the scene contract never crosses the boundary and cannot break. The encode function moves as a
file; `produce` then calls `/post:<skill>` when installed and otherwise keeps a documented reduced
result (frames only), per the presence-gate rule at `docs/plugin-philosophy.md:102-106`.

One open point: learn-style validation encodes the new scene so its statistics carry the same codec
softening as the source's (learn-style `SKILL.md:47-49`). If encode moves out, validation either
keeps a minimal encode in `animation` or depends on `post`. Thread T11.

## 5. How pixel-art could emit the same scene artifact

pixel-art scenes run a fixed 60 Hz simulation step with an accumulator inside
`requestAnimationFrame` (`plugins/pixel-art/reference/scene-canvas.md:37`;
`plugins/pixel-art/examples/campfire/scene.html:161-163`). That loop is not seekable by time, but
it is already deterministic per tick. The adapter is small and lives in pixel-art:

- Add `window.renderFrame(t)`: reset the state to tick 0, step `floor(t * 60)` ticks, draw.
  `window.DURATION` from the beat list; `canvas#c` at the logical resolution.
- The page keeps its rAF loop for live playback; capture calls `renderFrame` instead.
- The gap: scene-canvas.md has no seeded-randomness rule. A particle pool using `Math.random`
  breaks determinism. pixel-art would add one rule (seeded RNG, reset with the state).
- Cost ceiling: replaying from tick 0 per frame is quadratic in scene length. Fine for title cards
  and cutscenes of seconds; a capture that steps forward incrementally is the upgrade if a long
  scene needs it.

Sharing the render code: plugins cannot import each other's files
(`docs/plugin-philosophy.md:95`). When pixel-art needs frames, the render scripts become a
byte-identical synced copy registered in `scripts/cross-plugin-source-registry.txt`, the fleet's
existing pattern (`.work/strategy/position-b.md`, section 3, variant B'). Not before: a one-member
sync cluster has nothing to keep in sync.
