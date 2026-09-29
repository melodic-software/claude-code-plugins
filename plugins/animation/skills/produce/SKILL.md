---
description: "Make a film from a brief and one or more style packs: pre-production boards for the user to approve, then a shot list, scenes, rendered frames, a delivered file, and a review against the pack. Use when: 'produce this film', 'animate this brief', 'storyboard then render', 'make a short in this style', 'boards for approval', 'shot list for this film'. Nothing past the storyboard renders until the user approves the boards. Not for copying a reference clip (use /animation:rotoscope) or measuring a new style pack (use /animation:learn-style)."
argument-hint: "<production dir>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Brief, boards, approval gate, shots, render, and pack review
---

# Produce

Turn a brief and one or more style packs into a film. Boards come first. The film does not render
until the user approves them. `shots.json` is the only list of shot cuts: `inkstats.py --cuts`
reads that file.

Requirements are the plugin README's. Run Python as
`uv run --with-requirements ${CLAUDE_PLUGIN_ROOT}/requirements.txt python ...`. The gate script
needs only the standard library:
`${CLAUDE_PLUGIN_ROOT}/scripts/produce.py`. Rendering is
`${CLAUDE_PLUGIN_ROOT}/scripts/render.py`. The pack check is
`${CLAUDE_PLUGIN_ROOT}/scripts/inkstats.py`.

## Production directory

One directory the user names. `produce.py init <dir>` creates each missing skeleton file and never
overwrites one that is already there.

| Path | Who writes it | What it holds |
|---|---|---|
| `brief.md` | you | `Subject:`, `Length:`, `Audience:`, `Packs:` (comma-separated pack names), `Delivery:` |
| `boards/style-guide.md` | you | `Pack:` equal to `palette.json` `pack`. Under `Differs from the pack:`, each bullet says `measured` or `judgment` |
| `boards/palette.json` | you | `pack`, `ink` and `paper` as `#rrggbb`, `tones` as `{lv, color}` objects, optional `tolerance` |
| `boards/vibe.md` | you | reference images, each with a credit. A film with none still says `Credit:` |
| `boards/models/<name>.md` `.js` `.png` | you | at least one character sheet. The `.js` is a scene module (see step 2); the `.png` is its turnaround |
| `boards/elements/<name>.md` `.js` `.png` | you | the same shape, only for elements you actually need |
| `boards/storyboard.json` | you | `panels`: `{shot, panel, t, png, action, camera, caption?}`. `png` is a relative path to a real file |
| `boards/approval.json` | `produce.py approve` | `{approved, note, boards_digest}`. You do not hand-write this |
| `shots.json` | you, after approval | `{fps, size:[w,h], shots:[{id, t0, t1, scene, pack, audio?:{path, start}}]}`. `t0` of the first shot is 0, and each `t1` is the next `t0` |
| `frames/render.json` | `render.py` | the delivered film. Its `fps`, `size`, and `duration` match the shot list |

Paths in those files are relative to the production directory and stay inside it.

## Loop

1. Write `brief.md` from the request. Unspecified length, audience, or delivery becomes one
   defaults line, not a list of questions. `Packs:` names style packs that already exist
   (`styles/<name>/` or a pack the user points at).
2. Fill the boards. A model or element `.js` is a scene module: it sizes `canvas#c` and defines
   `window.DURATION`, `window.renderFrame(t)` and `window.renderDrawing(k)`, and `--drawings` fails
   without `renderDrawing`. `skills/rotoscope/fixtures/synthetic.js` is a working per-drawing scene.
   Render each sheet with `render.py <scene.js> <out> --drawings 0` (or the poses that sheet
   needs) and copy the PNG into `boards/models/` or `boards/elements/`. Those stills are boards,
   not the film.
3. `produce.py boards <dir>` must exit 0. Fix every line it prints.
4. Stop. Show the boards and ask the user to approve them. Do not write `shots.json`, do not
   render a shot, and do not encode a file in this step.
5. After the user approves, `produce.py approve <dir> --note "<their words>"`. The note is their
   words. If they change a board later, the digest no longer matches and `shots` returns to exit
   2 until they approve again.
6. Author one scene module per shot and write `shots.json`. `produce.py shots <dir>` must exit 0.
   `produce.py cuts <dir>` prints the `t0` list.
7. `render.py` takes one scene, so author a film scene that plays each shot's module over its
   `t0`-`t1` span from `shots.json`, and render that into `frames/` at `shots.json` `fps` and
   `size`, long enough to reach the last `t1`. `--encode` writes the delivered file beside
   `frames/`.
8. `produce.py review <dir>` prints `inkstats.py <frames> --cuts <dir>/shots.json --pack <pack>`
   when every shot uses one pack. With mixed packs it prints one `--t <t0>-<t1> --pack <pack>`
   line per shot, since the check judges every frame it reads. A pack the plugin ships resolves
   to its `styles/` directory. Run each. Then read
   frames at 1:1 before calling the film done. A passing check whose frames do not read as the
   pack is a fail; say which mark is wrong.

Pass `--cuts` the `shots.json` path, not a retyped list. `inkstats.py` reads each shot's `t0`.

## Next

/animation:learn-style <work dir> <pack dir>

When the review shows the film is a different style than the pack, that is a new style study. Do not edit the pack's bands to make this film pass.

## Gotchas

- Exit 2 from `shots` or `review` means the gate is closed. Exit 1 means a field is wrong. Do not
  treat 2 as a schema error and edit `shots.json` to get past it.
- Model-sheet PNG files are allowed before approval. A shot render is not.
- `audio.path` is optional. When present it has to be a file inside the production directory, and
  `audio.start` is seconds into that file. `render.py --encode` does not mux it: the delivered
  file is silent until the audio is muxed in with ffmpeg.
- The approval gate is soft and prompt-level. Only `produce.py shots` and `review` consult the
  digest; `render.py` and writing `shots.json` are not gated, and `approve --note` carries no proof
  that the note came from the user. The gate holds only when step 5 is followed.
- A board set has one `palette.json` and one style-guide `Pack:` line, so in a film with several
  packs approval covers that one pack's board. `review` prints one check per shot for mixed packs.
- A style pack's bands were learned on films of at least about a third of the source. A much
  shorter film can fail a row the pictures do not deserve; say so, and do not edit the pack.
  Verified 2026-09-29 against `skills/learn-style/reference/statistics.md` "Short films" (at least
  a third of the source, about 10 s) and the `FLOOR` constant in
  `skills/learn-style/scripts/learn.py` (`1 / 3`). Recheck when that section or `FLOOR` changes.
