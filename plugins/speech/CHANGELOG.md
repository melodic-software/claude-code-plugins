# Changelog

All notable changes to the `speech` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0] - 2026-10-10

### Changed

- **`/speech:check` offers the fixes.** After the report it offers each failed row's fix and runs it only on the user's yes: the Python package repair line as printed, a system install through a shown script, and the model download by asking the user to type `/speech:setup apply install-model`. An unattended run still reports and stops.

## [0.3.0] - 2026-10-10

### Added

- **The elevenlabs backend gets its key through `vault-exec`.** With `ELEVENLABS_API_KEY` unset and `vault-exec` on `PATH`, `elevenlabs.py` runs itself under `vault-exec --env ELEVENLABS_API_KEY=elevenlabs-api-key`, so the key lives only in that process. A secret `vault-exec` cannot resolve exits 2 with the remedy.
- **A content-hash cache** in the plugin data directory: a repeated identical request (text, voice, model, voice settings, output format) returns the stored audio and timings with no API call. `--no-cache` forces a new call.
- **Retries:** HTTP 429 and 5xx are retried with jittered exponential backoff, honoring `Retry-After`; 401 and 422 are not. Errors show the API's `detail.code` (or the older `detail.status`) and message.
- `words.json` from the elevenlabs backend records `request_id` and `character_cost` from the response headers, plus `voice_settings` and `cached`. `--setting NAME=VALUE` sends voice settings.
- `eleven_v4` in the `MODELS` table, confirmed on the with-timestamps endpoint by a live call.
- **Options:** `elevenlabs_model` picks the elevenlabs default model from the `MODELS` ids; `model_dir` moves the Kokoro model folder, honored by `narrate.py`, `assets.py` and `check.py`, and `check` reports which source set it (#6373).
- `reference/elevenlabs.md`: pointers to the live ElevenLabs docs.

### Changed

- **The elevenlabs default model is `eleven_v4`**, the more expressive voice; `eleven_multilingual_v2` stays selectable for a steadier delivery.
- **The cost gate states quota, not prices.** The hard-coded rates are gone. Before a call the script prints the character count against the plan's remaining quota from `GET /v1/user/subscription` and links the pricing page; `--proceed` still gates the call.

### Fixed

- An empty audio payload is a clear error, and the word-timing mapping accepts multi-character and dictionary-shaped alignment entries and `normalized_alignment`.
- A `vault-exec` that cannot start exits 2 with the remedy instead of a traceback.
- A word end in `words.json` never runs past the audio duration: the elevenlabs backend clamps it.

## [0.2.10] - 2026-10-07

### Changed

- **Upstream records ([#6498](https://github.com/melodic-software/claude-code-plugins/issues/6498)).** The shared `hook-utils.sh` copy picks up recheck triggers on its upstream records.

## [0.2.9] - 2026-10-07

### Changed

- **Test suite only; nothing shipped changes.** `test_assets.py` removes its temp dir after each test.

## [0.2.8] - 2026-10-04

### Changed

- **Shared `hook-utils.sh` synced; no change to this plugin's hooks.** Two comments no longer cite the retired statusline tee.

## [0.2.7] - 2026-10-04

### Changed

- **Python package notices go to the user only (#6225).** The SessionStart notices for a missing Python or a failed package install are shorter and no longer reach the model: `/speech:narrate` prints the repair line itself when it runs.

## [0.2.6] - 2026-10-04

### Changed

- The SessionStart node-notice rows now match `startup|resume|clear|fork`, so a compaction no longer starts them; the session and its notice latches survive a compaction, so a re-fire printed nothing (#6251).
- The shared `exec-bash.mjs` launcher copy gains the `--skip-if-all-false` and `--skip-unless-stdin-contains` flags; no row in this plugin uses them (#6252, #6253).

### Fixed

- The `pydeps.py` helper is now passed to native Python as a Windows path (#6250).

## [0.2.5] - 2026-10-04

### Changed

- **Shared `hook-utils.sh` synced ([#5924](https://github.com/melodic-software/claude-code-plugins/issues/5924)); no change to this plugin's hooks.**

## [0.2.4] - 2026-10-04

### Changed

- **Shared hook notice text ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)).** Skip notices from the shared hook helpers are never renewed: each tells the model once per agent and the user once per session, and says the notice will not repeat. A missing-tool notice no longer carries the hook's PATH; that goes to the debug log. The SessionStart notice for a missing node goes to the user only, in one shorter line.

## [0.2.3] - 2026-10-03

### Fixed

- **The `SessionStart` node-notice row no longer runs `powershell` on Linux.** It stopped at `${BASH_VERSION:+exit}`, which only bash sets; Claude Code runs hooks with `/bin/sh`, which is dash on Debian and Ubuntu (WSL included), so every session printed `powershell: not found`. The row now stops at `${PPID:+exit}`, which every POSIX shell sets.

## [0.2.2] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.2.1] - 2026-10-03

### Changed

- `scripts/speech.test.sh` declares the files it reads without naming them in a `# test-scope:` header, so CI's test selection runs it when one of them changes. Nothing the plugin runs changed.

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

## [0.1.5] - 2026-10-03

### Changed

- **Shared `hook-utils.sh` synced ([#5838](https://github.com/melodic-software/claude-code-plugins/issues/5838)); no change to this plugin's hooks.**
  It is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copy.

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
