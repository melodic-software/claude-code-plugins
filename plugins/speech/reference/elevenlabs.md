# ElevenLabs: where to read the live specifics

`scripts/elevenlabs.py` is the elevenlabs backend. This file holds no ElevenLabs facts of its own:
each entry states what the plugin decided and where to read the upstream specifics live.

## Models

The script keeps a `MODELS` table with each model's per-request limit and whether the
with-timestamps endpoint is confirmed for it. `eleven_v4` stays unverified there, and the default
model does not move to it, until a live run confirms word timings for it.

- **Pointer**: when choosing a model or rechecking a limit, fetch
  <https://elevenlabs.io/docs/overview/models> live.
- **As of**: 2026-10-04
- **Recheck trigger**: that page changes a model's character limit, or lists `eleven_v4` under
  Text to Speech.

## Writing a script for a voice

Script wording, pauses, pronunciation and the tags newer models read belong to the script author,
not the plugin.

- **Pointer**: when writing or fixing a script for ElevenLabs, fetch
  <https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices> live, and for
  the newer models its sections
  [Prompting Eleven v4](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices#prompting-eleven-v4)
  and
  [Prompting Eleven v3](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices#prompting-eleven-v3).
- **As of**: 2026-10-04
- **Recheck trigger**: either section is renamed or removed, or a new model gets its own prompting
  section.

## Voice cloning

The plugin takes a voice id and never creates voices. A cloned voice is made in ElevenLabs and its
id passed with `--voice`.

- **Pointer**: when the user wants their own voice, fetch
  [Instant Voice Cloning](https://elevenlabs.io/docs/eleven-creative/voices/voice-cloning/instant-voice-cloning)
  or
  [Professional Voice Cloning](https://elevenlabs.io/docs/eleven-creative/voices/voice-cloning/professional-voice-cloning)
  live.
- **As of**: 2026-10-04
- **Recheck trigger**: either page moves, or the plugin starts creating voices itself.

## Cost and quota

The script states no prices. It prints the request's character count against the plan's
remaining quota and links the pricing page; the `character-cost` header it records in
`words.json` is what ElevenLabs counted for the call.

- **Pointer**: when the user asks what a run costs, fetch <https://elevenlabs.io/pricing> live.
- **As of**: 2026-10-04
- **Recheck trigger**: the pricing page moves, or ElevenLabs stops billing text to speech by
  characters.

## The API the script calls

The script calls `POST /v1/text-to-speech/{voice_id}/with-timestamps`, reads the quota from
`GET /v1/user/subscription`, records the `request-id` and `character-cost` response headers, and
retries only HTTP 429 and 5xx.

- **Pointer**: when changing the request, the headers read, or the retry policy, fetch the
  [API reference introduction](https://elevenlabs.io/docs/api-reference/introduction), the
  [with-timestamps endpoint](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps),
  the [subscription endpoint](https://elevenlabs.io/docs/api-reference/user/subscription/get) and
  [errors](https://elevenlabs.io/docs/eleven-api/resources/errors) live, and the machine-readable
  spec at <https://api.elevenlabs.io/openapi.json> (download it with curl; it is too large to read
  through a page fetch).
- **As of**: 2026-10-04
- **Recheck trigger**: a call fails with a status or body shape the script does not handle, or the
  spec changes the with-timestamps request body.

## Finding anything else

- **Pointer**: when a topic is not above, fetch the docs index <https://elevenlabs.io/docs/llms.txt>
  live.
- **As of**: 2026-10-04
- **Recheck trigger**: the index moves.

## ElevenLabs' own agent tooling

The plugin does not depend on ElevenLabs' agent skills, Claude Code plugin or hosted MCP server.
The hosted MCP server returns no word timings, so it cannot replace `elevenlabs.py`, whose
`words.json` is the point of the backend.

- **Pointer**: when comparing the plugin with ElevenLabs' own tooling, read
  <https://github.com/elevenlabs/skills>, <https://github.com/elevenlabs/plugin> and the hosted MCP
  server at <https://elevenlabs.io/mcp> live.
- **As of**: 2026-10-04
- **Recheck trigger**: the hosted MCP server gains a text-to-speech tool that returns per-character
  or per-word timings.
