# Changelog

All notable changes to the `speech` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1] - 2026-10-03

### Changed

- The shared hook library's missing-prerequisite notice says to run `/harness-ops:prerequisites` if the `harness-ops` plugin is enabled, where it said installed: an installed but disabled plugin exposes no skills, and `harness-ops` now installs disabled ([#5934](https://github.com/melodic-software/claude-code-plugins/issues/5934)).

## [0.1.0] - 2026-10-02

### Added

- `/speech:narrate` turns a script into `narration.wav` and `words.json`, a start and end time for
  every word. The kokoro backend runs Kokoro-82M through onnxruntime. The word timings come from
  the model's own per-token durations.
- `/speech:check` reports each missing prerequisite with its remedy and installs nothing.
- `/speech:setup` offers `check` and `apply install-model`. The subaction downloads the pinned
  model, tokenizer and English voices and checks each file's sha256.
- A SessionStart hook installs the hash-locked numpy and onnxruntime into the plugin data directory.
- `prerequisites.json` declares Node.js, Python 3.12 or later, and espeak-ng. espeak-ng is GPL-3.0:
  the user installs it and the plugin never ships it.
