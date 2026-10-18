---
description: "Film production from a brief and one or more style packs: boards for the user to approve, then a shot list, rendered frames, a delivered file, and a review against the pack. Use when: 'produce this film', 'animate this brief', 'storyboard then render', 'make a short in this style', 'boards for approval', 'shot list for this film'. Not for copying a reference clip (/animation:rotoscope) or measuring a new style (/animation:learn-style)."
argument-hint: "<production dir>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Brief, boards, approval gate, shots, render, and pack review
---

# Produce

Turn a brief and one or more style packs into a film. Nothing past the boards renders until the
user approves them. `shots.json` is the only list of shot cuts.

Requirements are the plugin README's. Run each script as
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py run --data-dir "${CLAUDE_PLUGIN_DATA}" -- <script> ...`,
which uses the packages the SessionStart hook installed.
The gate script `${CLAUDE_PLUGIN_ROOT}/scripts/produce.py` needs only the standard library.
Rendering is `${CLAUDE_PLUGIN_ROOT}/scripts/render.py`; the pack check is
`${CLAUDE_PLUGIN_ROOT}/scripts/inkstats.py`.

## Production directory

One directory the user names. `produce.py init <dir>` creates each missing skeleton file and never
overwrites one. Paths in these files are relative to the production directory and stay inside it.

| Path | Who writes it | What it holds |
|---|---|---|
| `brief.md` | you | `Subject:`, `Length:`, `Audience:`, `Packs:` (comma-separated pack names), `Delivery:` |
| `boards/style-guide.md` | you | `Pack:` equal to `palette.json` `pack`. Under `Differs from the pack:`, each bullet says `measured` or `judgment` |
| `boards/palette.json` | you | `pack`, `ink` and `paper` as `#rrggbb`, `tones` as `{lv, color}` objects, optional `tolerance` |
| `boards/vibe.md` | you | reference images, each with a credit. A film with none still says `Credit:` |
| `boards/models/<name>.md` `.js` `.png` | you | at least one character sheet. The `.js` is a scene module (step 2); the `.png` is its turnaround |
| `boards/elements/<name>.md` `.js` `.png` | you | the same shape, only for elements you need |
| `boards/storyboard.json` | you | `panels`: `{shot, panel, t, png, action, camera, caption?}`. `png` is a relative path to a real file |
| `boards/approval.json` | `produce.py approve` | `{approved, note, boards_digest}`. Never hand-write it |
| `shots.json` | you, after approval | `{fps, size:[w,h], shots:[{id, t0, t1, scene, pack, audio?:{path, start}}]}`. The first `t0` is 0, and each `t1` is the next `t0` |
| `frames/render.json` | `render.py` | the delivered film. Its `fps`, `size`, and `duration` match the shot list |

## Loop

1. Write `brief.md` from the request. Put unspecified length, audience, or delivery in one defaults
   line, not a list of questions. `Packs:` names packs that exist (`styles/<name>/` or a pack the
   user points at).
2. Fill the boards. A model or element `.js` is a scene module: it sizes `canvas#c` and defines
   `window.DURATION`, `window.renderFrame(t)` and `window.renderDrawing(k)`; `--drawings` fails
   without `renderDrawing`. `skills/rotoscope/fixtures/synthetic.js` is a working per-drawing scene.
   `render.py` serves the scene's own directory, then the plugin's `scripts/` (`ink.js`), then each
   `--root`: to share drawing code between board, shot and film modules, pass
   `--root <production dir>` on every render and import by absolute path from it
   (`/boards/elements/<name>.js`). Load what a scene needs (JSON, other modules) with static imports
   or top-level `await`: capture starts once the module has finished loading, so `DURATION` must
   be final by then. Render each sheet with `render.py <scene.js> <out> --drawings 0` (or the poses it needs) and copy
   the PNG into `boards/models/` or `boards/elements/`. These stills are boards, not the film.
3. `produce.py boards <dir>` must exit 0. Fix every line it prints.
4. Stop. Show the boards and ask the user to approve them. Do not write `shots.json`, render a
   shot, or encode a file in this step.
5. After the user approves, run `produce.py approve <dir> --note "<their words>"`, with their words
   as the note. If a board changes later, the digest no longer matches and `shots` exits 2 until
   they approve again.
6. Author one shot module per shot and write `shots.json`. A shot module exports
   `drawShot(ctx, t)`, which draws film time `t` (seconds from the film's start) on the context it
   is handed, and sets no page hooks. `produce.py shots <dir>` must exit 0. `produce.py cuts <dir>`
   prints the `t0` list.
7. `render.py` takes one scene: author a film scene that imports `shots.json`, sets `DURATION` to
   the last `t1`, sizes `canvas#c` to `size`, and in `renderFrame(t)` calls `drawShot` of the shot
   whose `t0`-`t1` span holds `t`. Render it into `frames/` at `shots.json` `fps` with
   `--shots <dir>/shots.json`, which exits 1 when the film's fps, size, duration or frame count
   differs from the shot list. `--encode` writes the delivered file beside `frames/`.
8. `produce.py review <dir>` prints `inkstats.py <frames> --cuts <dir>/shots.json --pack <pack>`
   when every shot uses one pack, and one `--t <t0>-<t1> --pack <pack>` line per shot for mixed
   packs, since the check judges every frame it reads. A shipped pack resolves to its `styles/` directory. Run each line. Then read frames at
   1:1 before calling the film done. A passing check whose frames do not read as the pack is a
   fail; say which mark is wrong.
   - When a row fails, change the drawing until the frames read as the pack, then check again.
     Never add or change marks only to move a row into its band (extra specks, rougher strokes,
     re-timed holds): a row passed that way is still a fail. A change to a board file closes the
     gate, so the user approves the boards again (step 4) before the next shot render.
   - When the frames cannot read as the pack without editing its bands, stop and report the
     failing rows and marks (see Next).
9. Before delivery, hand the film to a fresh-context reviewer (a subagent that is not a fork) with
   the brief in [reference/independent-review.md](reference/independent-review.md). The builder
   never decides the film ships: fix what the review finds, render, check and review again with a
   new reviewer, and deliver only on its SHIP.

Pass `--cuts` the `shots.json` path, never a retyped list.

## Next

/animation:learn-style <work dir> <pack dir>

When the review shows the film is a different style than the pack, that is a new style study. Do
not edit the pack's bands to make this film pass.

## Gotchas

- Exit 2 from `shots` or `review` means the gate is closed; exit 1 means a field is wrong. Never
  edit `shots.json` to get past an exit 2.
- Model-sheet PNG files are allowed before approval. A shot render is not.
- `audio.path` is optional; when present it is a file inside the production directory, and
  `audio.start` is seconds into that file. `render.py --encode` does not mux it: the delivered file
  is silent until the audio is muxed in with ffmpeg.
- The approval gate is soft. Only `produce.py shots` and `review` consult the digest; `render.py`
  and writing `shots.json` are not gated, and `approve --note` carries no proof that the note came
  from the user. The gate holds only when step 5 is followed.
- A board set has one `palette.json` and one style-guide `Pack:` line, so in a film with several
  packs approval covers that one pack's board.
- A style pack's bands were learned on films of at least about a third of the source. A much
  shorter film can fail a row the pictures do not deserve; say so, and do not edit the pack.
  Verified 2026-09-29 against `skills/learn-style/reference/statistics.md` "Short films" (at least
  a third of the source, about 10 s) and the `FLOOR` constant in
  `skills/learn-style/scripts/learn.py` (`1 / 3`). Recheck when that section or `FLOOR` changes.
