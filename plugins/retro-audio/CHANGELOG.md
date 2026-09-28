# Changelog

All notable changes to the `retro-audio` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- `sfx` renders one effect from an sfxr-style parameter object, or from the coin, jump, laser, and
  explosion presets, to a 16-bit mono WAV (#4404).
- `tune` renders an MML subset (tempo, octave, length, volume, duty, repeats, a noise note) through
  Game Boy, NES, and PICO-8 channel limits.
- The pixel-art campfire scene ships a loop rendered from `examples/campfire.mml`. The scene file
  holds the WAV; neither plugin imports the other.
