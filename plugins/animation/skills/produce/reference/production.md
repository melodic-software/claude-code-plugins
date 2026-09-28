# Production directory

One directory the user names. `skills/produce/scripts/produce.py` reads and writes only this tree.

Claim: boards are markdown the user approves by writing a non-empty `boards/APPROVED`, and
`shots.json` is the only owner of cut times. Basis: #4591 (boards before any render; `shots.json`
owns cuts, T16) and `scripts/render.py`, which writes `render.json` beside the frames. As of:
2026-09-28. Recheck: the `render.json` keys in `scripts/render.py` change, or a maintainer picks a
different approval file than `boards/APPROVED`.

## brief.md

A markdown brief. `produce.py init` writes the title and the style names.

## boards/

`storyboard.md` is one panel per shot. `boards/APPROVED` is the gate. The user writes it.
`produce.py` never does. The file must be non-empty. `produce.py gate` exits 2 until it is.
`produce.py check` prints `boards` before that and `approved` after.

## shots.json

```json
{
  "version": 1,
  "fps": 24,
  "styles": ["woodcut-ink"],
  "shots": [
    {"id": "s1", "t0": 0, "scene": "scenes/s1.js", "title": "Open"}
  ]
}
```

`version` is 1. `fps` is a positive number. `styles` is a non-empty list of pack names.
`shots` is a non-empty list. Each `id` is a unique string. `t0` is seconds, the first is 0, and
each later `t0` is greater. `scene` is a `.js` path. `title` is non-empty.
`scripts/shots.py` reads this file for `inkstats.py --shots` and for `--cuts` when the value is
a shots.json path. Do not keep a second cut list.

## scenes/ and frames/

Each scene is a Canvas module with `renderFrame(t)`, drawn with ink.js. Render with
`scripts/render.py`. It writes `render.json` beside the frames. Review with
`inkstats.py <film> --shots <production>/shots.json --pack <pack>`.
