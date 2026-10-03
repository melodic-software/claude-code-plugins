# Changelog

All notable changes to the `retro-audio` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5842](https://github.com/melodic-software/claude-code-plugins/issues/5842)).

## [0.1.1] - 2026-09-29

### Fixed

- `music` rejects an unmatched `]`, a zero tempo (`t0`), a zero default or per-note length, and a
  zero repeat count (`[c]0`) with an `mml.py:` error and exit 1; before, a stray `]` dropped the rest
  of the score silently, `t0` and `l0` raised `ZeroDivisionError`, and `[c]0` repeated twice.
- `sfx` rejects a `--params` value that is not a JSON object, and a null or wrongly typed field, with
  an `sfx.py:` error and exit 1 instead of a traceback.

### Changed

- The docs and the plugin description state what chip presets enforce: the channel count, the noise
  part count, and the `@0` bass waveform, not the hardware voice mix. The `pico-8` preset shares the
  Game Boy and NES pulse duties, which the PICO-8 manual does not document, so the description no
  longer calls them PICO-8 duties.

## [0.1.0] - 2026-09-28

### Added

- `sfx` renders one effect from an sfxr-style parameter object, or from the coin, jump, laser, and
  explosion presets, to a 16-bit mono WAV (#4404).
- `music` renders an MML subset (tempo, octave, length, volume, duty, repeats, a noise note) through
  Game Boy, NES, and PICO-8 channel limits.
- The pixel-art campfire scene ships a loop rendered from `examples/campfire.mml`. The scene file
  holds the WAV; neither plugin imports the other.
