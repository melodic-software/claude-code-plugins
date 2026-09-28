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

One directory the user names. `produce.py init <dir>` creates the skeleton and does not overwrite
a `brief.md` that is already there.

| Path | Who writes it | What it holds |
|---|---|---|
| `brief.md` | you | `Subject:`, `Length:`, `Audience:`, `Packs:` (comma-separated pack names), `Delivery:` |
| `boards/style-guide.md` | you | `Pack:` equal to `palette.json` `pack`. Under `Differs from the pack:`, each bullet says `measured` or `judgment` |
| `boards/palette.json` | you | `pack`, `ink` and `paper` as `#rrggbb`, `tones` as `{lv, color}` objects, optional `tolerance` |
| `boards/vibe.md` | you | reference images, each with a credit. A film with none still says `Credit:` |
| `boards/models/<name>.md` `.js` `.png` | you | at least one character sheet. The `.js` is the ink.js element; the `.png` is its turnaround |
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
2. Fill the boards. Render each model and element sheet with `render.py <element.js> <out>
   --drawings 0` (or the poses that sheet needs) and copy the PNG into `boards/models/` or
   `boards/elements/`. Those stills are boards, not the film.
3. `produce.py boards <dir>` must exit 0. Fix every line it prints.
4. Stop. Show the boards and ask the user to approve them. Do not write `shots.json`, do not
   render a shot, and do not encode a file in this step.
5. After the user approves, `produce.py approve <dir> --note "<their words>"`. The note is their
   words. If they change a board later, the digest no longer matches and `shots` returns to exit
   2 until they approve again.
6. Author one scene module per shot and write `shots.json`. `produce.py shots <dir>` must exit 0.
   `produce.py cuts <dir>` prints the `t0` list.
7. Render the film into `frames/` with `render.py`, at `shots.json` `fps` and `size`, long enough
   to reach the last `t1`. `--encode` writes the delivered file beside `frames/`.
8. `produce.py review <dir>` prints one `inkstats.py <frames> --cuts <dir>/shots.json --pack <pack>`
line per pack. Run each. Then read frames at 1:1 before calling the film done. A passing check
whose frames do not read as the pack is a fail; say which mark is wrong.

Pass `--cuts` the `shots.json` path, not a retyped list. `inkstats.py` reads each shot's `t0`.

## Next

/animation:learn-style <work dir> <pack dir>

When the review shows the film is a different style than the pack, that is a new style study. Do not edit the pack's bands to make this film pass.

## Gotchas

- Exit 2 from `shots` or `review` means the gate is closed. Exit 1 means a field is wrong. Do not
  treat 2 as a schema error and edit `shots.json` to get past it.
- Model-sheet PNG files are allowed before approval. A shot render is not.
- `audio.path` is optional. When present it has to be a file inside the production directory, and
  `audio.start` is seconds into that file.
- A style pack's bands were learned on films of at least about a third of the source. A much
  shorter film can fail a row the pictures do not deserve; say so, and do not edit the pack.
