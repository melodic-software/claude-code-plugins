# Let speech own the voice backends and their fallback chain

- Status: accepted
- Date: 2026-11-13
- Refs: owner decisions of 2026-11-13 (Q12, Q14, Q24, Q31, Q54, Q72; design thread T3)

## Context

Produced videos need narration. `plugins/speech/scripts/narrate.py` is kokoro-only today, and
ElevenLabs is a separate script. Voice is meant to be configurable (edge-tts, kokoro, OpenAI,
ElevenLabs, a custom command), with free defaults and no unattended paid spend. edge-tts uses an
unofficial Microsoft endpoint that has broken before.

## Decision

1. **speech owns every voice backend and the fallback chain.** `narrate.py --backend-chain
   <name,...>` takes backends `edge-tts`, `kokoro`, `openai`, `elevenlabs` and `command` (a
   `{script}` `{out}` template). It writes `narration.wav`, `words.json` and
   `voice.json {backend, voice, attempts[]}`.
2. **One voice per video.** A line that still fails after retries at 1, 2 and 4 seconds, with a
   per-call timeout, sends the whole script to the next backend; voices are never mixed.
3. **Exit codes:** 0 ok, 3 paid gate, 4 egress floor, 5 no backend produced audio. On 5 the producer
   makes a captions-only video.
4. **Default chain `edge-tts` (en-US-AndrewNeural), then `kokoro`.** Paid backends run unattended
   only when `allow_unattended_paid_voice` is set.
5. **The secret scan runs on the script before any online backend** (see
   [ADR 0107](0107-scan-every-media-upload-and-online-voice-request-against-a-fixed-floor.md)).

## Considered options

- **Each producer owns the chain and calls one backend at a time.** Rejected: duplicates the chain
  logic in every producer.

## Consequences

- `narrate.py`'s existing flags keep working for explainer-video and demo-video.
- edge-tts is pinned `==7.3.1` with hashes; Dependabot proposes bumps.

## Revisit triggers

- edge-tts fails repeatedly after release: make `kokoro` the default chain head.
- The owner narrows the provider list (Q12 was answered "probably").
