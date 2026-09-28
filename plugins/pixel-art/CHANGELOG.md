# Changelog

All notable changes to the `pixel-art` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Added

- Bundled palette presets in `palettes/`: `pico-8`, `nes` (jsnes NTSC table), `game-boy` (mGBA
  DMG Green), and the CC0 Lospec sets `retro-8-bit`, `deep-sea`, and `cosmic-space` (#4401). Each
  file records its source and license. A spec `palette` string names a preset or a project palette
  file; the inline object form is unchanged.
- `render.py --snap` maps an 8-bit RGB or RGBA PNG onto a palette (nearest sRGB color, alpha below
  128 transparent). `--dither` adds 4x4 Bayer ordered dither. `--emit-frames` writes spec rows.

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
