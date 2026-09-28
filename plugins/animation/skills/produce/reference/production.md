# Production directory

One directory the user names. `produce.py` reads and writes only this tree.

Claim: boards are markdown the user approves by writing `boards/APPROVED`, and
`shots.json` is the only owner of cut times. Basis: #4591 (the produce brief:
boards before any render; `shots.json` owns cuts, T16) and `scripts/render.py`,
which writes `render.json` beside the frames. As of: 2026-09-28. Recheck: the
`render.json` keys in `scripts/render.py` change, or a maintainer picks a
different approval file than `boards/APPROVED`.

## brief.md

Markdown with these headings, in this order:

- `## Title`
- `## Logline`
- `## Audience`
- `## Runtime` (seconds)

## boards/

| File | Holds |
|---|---|
| `style-guide.md` | how to draw in the pack: line, fill, lettering |
| `palette.md` | ink, paper, and tone, copied from the pack's `palette` keys |
| `vibe.md` | mood in words, not a second palette |
| `model-sheet.md` | characters and props, one sheet |
| `element-sheet.md` | recurring elements (border, caption, props) |
| `storyboard.md` | one panel per shot, with the shot `id` from `shots.json` |

A file whose text still contains `TODO: replace this stub.` is not filled.
`boards/APPROVED` is the gate. The user writes it. produce.py never does.

```text
approved-by: <name>
at: <ISO-8601 time>
```

Both lines are required. `produce.py check` exits 2 without them and 1 when a
board is missing or still a stub.

## shots.json

```json
{
  "version": 1,
  "fps": 12,
  "shots": [
    {"id": "opener", "start": 0, "duration": 1, "scene": "scenes/opener.js"}
  ]
}
```

`version` is 1. `fps` is a positive number. `shots` is a non-empty list. Each
`id` is a unique string. `start` is seconds, `>= 0`, in non-decreasing order.
`duration` is seconds, `> 0`. `scene` is a relative path inside the production
directory, and the file must exist. `scripts/shots.py` is what `inkstats.py
--cuts <shots.json>` reads. Do not keep a second cut list.

## scenes/ and frames/

Each `scene` is a Canvas module with `renderFrame(t)` and `DURATION`, drawn
with ink.js. `produce.py render` calls `scripts/render.py` and writes
`frames/render.json` (`scene`, `adapter`, `fps`, `size`, `frames`, `duration`)
plus `frames.mp4` when `--encode mp4`. `produce.py review` reads that manifest
and, with `--pack`, runs `inkstats.py --cuts <shots.json> --pack <pack>`.
