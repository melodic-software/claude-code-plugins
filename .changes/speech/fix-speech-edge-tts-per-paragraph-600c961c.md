---
bump: patch
---

### Fixed

- voice edge-tts one paragraph per request

  A whole-script edge-tts request for a 3-minute script took 214 s and
  380 s, past the 120 s per-call timeout, so the default chain always fell
  back to kokoro. The edge-tts backend now sends one request per
  blank-line separated paragraph, each with its own timeout and retries,
  joins the audio into one narration.wav and moves each paragraph's words
  onto the whole file's timeline. A paragraph that fails discards all
  edge-tts output and hands the whole script to the next backend.
