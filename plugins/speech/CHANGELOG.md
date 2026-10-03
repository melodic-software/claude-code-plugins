# Changelog

All notable changes to the `speech` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0] - 2026-10-03

### Added

- **Optional elevenlabs backend for `/speech:narrate`** ([#5860](https://github.com/melodic-software/claude-code-plugins/issues/5860)).
  `scripts/elevenlabs.py` calls the ElevenLabs REST API and writes the same `narration.wav` and
  `words.json`, with word times taken from the API's per-character alignment. The key is the
  `ELEVENLABS_API_KEY` environment variable; it is never stored, printed, logged or put on a command line.
- Every call is preceded by a statement of the character count, the host and the estimated cost. A run
  without `--proceed` prints it and sends nothing; the skill shows it to the user and runs again with
  `--proceed` only after they agree.
- `SPEECH_EGRESS_FLOOR=local`, which an organization sets in managed settings, forbids the backend with a
  stated reason (exit 4). kokoro stays the default.
- `prerequisites.json` declares `ELEVENLABS_API_KEY` as an optional `env` entry, and `/speech:check` reports it
  as `INFO` when unset.

## [0.1.4] - 2026-10-03

### Changed

- **SessionStart reports a missing node.** One shell-form row runs the shared node-notice, and shared `hook-utils.sh`, `prerequisites.sh`, `prerequisites.ps1` are synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)).

## [0.1.3] - 2026-10-03

### Changed

- **Shared `exec-bash.mjs` synced ([#5837](https://github.com/melodic-software/claude-code-plugins/issues/5837)); no change to this plugin's hooks.**
  It is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copy.

## [0.1.2] - 2026-10-03

### Changed

- Shared `prerequisites.mjs` synced ([#5840](https://github.com/melodic-software/claude-code-plugins/issues/5840)); no change to this plugin's lib.

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
