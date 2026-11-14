---
bump: minor
---

### Added

- **`narrate.py --backend-chain`: one voice for the whole script, with fallback.** Backends `edge-tts`
  (free, default voice en-US-AndrewNeural), `kokoro`, `openai` and `elevenlabs` (paid) and `command` (a
  `{script}` `{out}` template) are tried in order; a failed call is retried after 1, 2 and 4 seconds, then the
  whole script goes to the next backend, so voices never mix; a call past its hard timeout (`--timeout`) goes to
  the next backend at once.
  `voice.json` records the backend, the voice and every attempt. Exits: 3 a paid backend without
  `--allow-paid-voice`, 4 the script failed the secret and machine-data scan (run before any online backend,
  nothing sent), 5 no backend produced audio. Without `--backend-chain`, `narrate.py` runs kokoro exactly as
  before.
- `edge-tts==7.3.1` joins the hash-locked `requirements.txt`; ffmpeg and `OPENAI_API_KEY` are listed as
  optional prerequisites.
