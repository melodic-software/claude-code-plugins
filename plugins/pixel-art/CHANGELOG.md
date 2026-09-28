# Changelog

All notable changes to the `pixel-art` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Added

- `tileset`, `ui`, and `vfx` skills. Tilesets cover terrain, autotiles (RPG Maker MZ A1-A5 and B-E,
  blob-47, and 16-tile corner sets), backgrounds, and parallax. UI covers window skins, icon sets,
  HUD elements, and bitmap fonts. VFX covers sparks, spells, explosions, and other cell sheets,
  including MV-style `img/animations`. Effekseer (`.efkefc`) stays out of scope.
- Worked generators under `examples/tileset`, `examples/ui`, and `examples/vfx`, rendered by
  `scripts/render.py`. Tests check an MZ A2 sheet, a `Window.png` skin, and a five-column animation
  sheet against the grids in `engine-layouts.md`.

## [0.1.1]

### Changed

- `animate` and `scene` descriptions exclude hand-drawn or ink-style animation and general video
  output, and their trigger phrases name pixel art, so they no longer claim the `animation`
  plugin's requests.

## [0.1.0]

### Added

- `sprite`, `animate` and `scene` skills: brief, author, render, review loop, deliver.
- `scripts/render.py`: standard-library renderer from a palette-locked spec to a 1x sheet PNG,
  an upscaled preview, one looping GIF per animation, and frame data in the Aseprite json-hash shape.
- `scripts/embed.py` inlines sprite specs into a scene template; `scripts/gallery.py` writes a
  preview page for an output directory.
- Reference files: static and animation craft rules, tiles, engine layouts (RPG Maker MZ, Aseprite,
  Godot, PICO-8, Pyxel), HTML Canvas scene rules, and the backend contract.
- `output_dir` and `backend` settings.
