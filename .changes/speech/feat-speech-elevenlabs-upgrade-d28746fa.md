---
bump: minor
---

### Added

- **The elevenlabs backend gets its key through `vault-exec`.** With `ELEVENLABS_API_KEY` unset and `vault-exec` on `PATH`, `elevenlabs.py` runs itself under `vault-exec --env ELEVENLABS_API_KEY=elevenlabs-api-key`, so the key lives only in that process. A secret `vault-exec` cannot resolve exits 2 with the remedy.
- **A content-hash cache** in the plugin data directory: a repeated identical request (text, voice, model, voice settings, output format) returns the stored audio and timings with no API call. `--no-cache` forces a new call.
- **Retries:** HTTP 429 and 5xx are retried with jittered exponential backoff, honoring `Retry-After`; 401 and 422 are not. Errors show the API's `detail.code` (or the older `detail.status`) and message.
- `words.json` from the elevenlabs backend records `request_id` and `character_cost` from the response headers, plus `voice_settings` and `cached`. `--setting NAME=VALUE` sends voice settings.
- `eleven_v4` in the `MODELS` table, marked unverified on the with-timestamps endpoint; the default model is unchanged.
- **Options:** `elevenlabs_model` sets the elevenlabs default model; `model_dir` moves the Kokoro model folder, honored by `narrate.py`, `assets.py` and `check.py`, and `check` reports which source set it (#6373).
- `reference/elevenlabs.md`: pointers to the live ElevenLabs docs.

### Changed

- **The cost gate states quota, not prices.** The hard-coded rates are gone. Before a call the script prints the character count against the plan's remaining quota from `GET /v1/user/subscription` and links the pricing page; `--proceed` still gates the call.

### Fixed

- An empty audio payload is a clear error, and the word-timing mapping accepts multi-character and dictionary-shaped alignment entries and `normalized_alignment`.
- A `vault-exec` that cannot start exits 2 with the remedy instead of a traceback.
