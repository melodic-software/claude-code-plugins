# pixel-art

A Claude Code plugin for making pixel art with nothing installed beyond Python 3: sprites,
animation cycles laid out for game engines, and animated scenes that open in any browser.

| Skill | What it does |
|---|---|
| `/pixel-art:sprite` | A static sprite (character, item, icon, portrait, face) as a PNG sheet |
| `/pixel-art:animate` | Idle, walk, attack and other cycles in 1, 4 or 8 directions, as an engine sprite sheet plus GIF previews |
| `/pixel-art:scene` | A cutscene, title screen, ambient loop or short pixel film as one self-contained HTML file |

```shell
/pixel-art:sprite a 32x32 potion icon, PICO-8 palette
/pixel-art:animate a knight, walk and attack, 4 directions, RPG Maker MZ
/pixel-art:scene the knight walks to a campfire at dusk and says one line, 240x160
```

## How it works

1. The model turns the request into a spec: a locked palette and frames, written by hand for small
   sprites or by a short procedural generator for larger ones.
2. `scripts/render.py` (Python standard library only) writes the engine asset at 1x, an upscaled
   preview, a GIF per animation, and frame data. `scripts/embed.py` builds scenes into one HTML file.
3. The model looks at what it rendered and revises, usually two to four rounds. Better briefs and
   feedback on each round get closer to what you have in mind.
4. `scripts/gallery.py` writes an `index.html` showing every output on one page.

## Settings

| Setting | Default | Purpose |
|---|---|---|
| `output_dir` | unset (ask) | Where outputs go when the request and the project name no location |
| `backend` | `native` | `native`, `aseprite`, `pixellab`, or `retrodiffusion` |

A project can name its own assets folder in its `CLAUDE.md`; that wins over `output_dir`.

## Prerequisites

- **Python 3**: required. The renderer uses the standard library only.
- **A browser automation tool** (for example a Playwright CLI or MCP): optional. With one, the
  `scene` skill screenshots its own output and reviews it; without one, it says the scene was not
  reviewed visually and asks you to open it.
- **Backends other than `native`**: optional. Each is detected when selected and falls back to
  `native` with a notice when absent. See `reference/backends.md`.

## Audio

This plugin makes no sound. A scene accepts an audio file you pass in, so a separate audio tool
can supply music or effects without either plugin depending on the other.

## Example

`examples/campfire/` holds the generator for an RPG Maker MZ walking character and a cutscene that
reuses it. Copy the folder somewhere writable, then:

```shell
python3 hero_mz.py
python3 <plugin>/scripts/render.py hero_mz.json --out out --scale 4
python3 <plugin>/scripts/embed.py scene.html out/campfire.html
python3 <plugin>/scripts/gallery.py out
```

## Reference files

`reference/` holds the sourced rules the skills apply: `craft-static.md`, `craft-animation.md`,
`craft-tiles.md`, `engine-layouts.md`, `scene-canvas.md`, and `backends.md`.
