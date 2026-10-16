# Changelog

All notable changes to the `retro-audio` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.6] - 2026-10-16

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior is unchanged.

## [0.2.5] - 2026-10-13

### Changed

- **Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5.** A version or `system-lib` probe that resolves a secret or calls a network API, such as `firecrawl --status` behind a key-injecting wrapper, no longer false-fails on a slow run. A fast probe is unaffected; a hung one now costs at most 20 seconds per entry. No change to this plugin's own entries.

### Fixed

- Shared library comments that restated Claude Code hook, plugin and managed-settings behavior now point at the live docs sections, and the prerequisites probe no longer gives a wrong reason for always exiting 0.

- **The shared prerequisites checker now finds a `python-pkg` in the plugin's own installed Python
  set.** A module that the interpreter cannot import on its own is looked up in the set a plugin
  with a committed `requirements.txt` installs into its data directory
  (`<data>/python/<lock hash>-<interpreter tag>/`), imported the way that plugin's launcher runs
  it. Before, such a package was reported missing. When the data directory is unknown (no
  `--data-dir`, no `CLAUDE_PLUGIN_DATA`), the entry reports `unverified` instead of failing.
  Refs #6112.

## [0.2.4] - 2026-10-04

### Changed

- **Shared `prerequisites` checker copies synced ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)); no change to this plugin's behavior.**

## [0.2.3] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.2.2] - 2026-10-03

### Changed

- `scripts/audio.test.sh` declares the files it reads without naming them in a `# test-scope:` header, so CI's test selection runs it when one of them changes. Nothing the plugin runs changed.

## [0.2.1] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.2.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5842](https://github.com/melodic-software/claude-code-plugins/issues/5842)).

## [0.1.2] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

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
