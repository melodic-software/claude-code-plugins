# speech

Text-to-speech narration for Claude Code. `/speech:narrate` turns a script into `narration.wav`
plus `words.json`, which gives a start and end time for every word. A video, a caption track or an
interactive page can then follow the voice word by word.

## Skills

| Skill | What it does |
|---|---|
| `/speech:narrate <script>` | Writes `narration.wav` (24 kHz mono) and `words.json` (one `{word, start, end}` per script word) |
| `/speech:check` | Read-only: one PASS or FAIL row per prerequisite, each FAIL with its remedy |
| `/speech:setup [check \| apply install-model]` | `check` is the same report; `apply install-model` downloads the pinned model files |

## The kokoro backend

kokoro is the default backend. It runs [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M)
(Apache-2.0) on your CPU through onnxruntime and sends nothing over the network while it speaks.
It uses the
[timestamped ONNX export](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX-timestamped),
which reports how long each input token lasts, so the word timings come from the model itself.
`scripts/kokoro-assets.json` pins the revision and the sha256 of every file: the fp32 model,
its tokenizer, and the 28 English voices.

espeak-ng turns each word into the phonemes Kokoro reads. **espeak-ng is GPL-3.0, so you install
it; the plugin never installs, downloads or ships it.** The plugin also avoids the Python packages
that bundle it (`espeakng-loader`) or wrap it under the GPL (`phonemizer`): it runs your
`espeak-ng` command directly.

## The elevenlabs backend (optional, third-party)

`scripts/elevenlabs.py` sends the script text to the [ElevenLabs](https://elevenlabs.io) REST API at
`api.elevenlabs.io` and writes the same two files. It is off unless you ask for it by name. The
official ElevenLabs MCP server is archived, so the plugin calls the REST API directly with the Python
standard library.

- **Key.** Set `ELEVENLABS_API_KEY` in your shell environment. The plugin never stores, prints or
  logs it, never takes it as an argument, and sends it only in the `xi-api-key` request header.
- **Cost estimate before every call.** The script prints the character count, the host, the model
  and voice, and the estimated cost, then stops. `--proceed` is required to send anything, and the
  skill passes it only after you agree. The rates are an estimate from the public price list (the
  `MODELS` table in the script says where and when); ElevenLabs bills credits against your plan.
- **Organization egress floor.** Managed settings can set `SPEECH_EGRESS_FLOOR=local` in `env`.
  Managed settings outrank every other settings layer, so a user cannot unset it. The backend then
  exits 4 with the reason, before it reads the key or prints an estimate. An unrecognized value is
  treated as `local`; `any` or unset allows the backend.
- **Text to speech only.** No voice cloning, speech-to-text or other ElevenLabs endpoints.

Word times come from the API's per-character alignment: a word spans its first to its last character.

## Prerequisites

| Prerequisite | Installed by | Needed for |
|---|---|---|
| `ELEVENLABS_API_KEY` (optional) | you | the elevenlabs backend only |
| Python 3.12 or later | you | the install hook and every script |
| Node.js | you | starting the SessionStart hook |
| espeak-ng | you (`apt`/`dnf`/`pacman`/`brew install espeak-ng`, `winget install eSpeak-NG.eSpeak-NG`) | `/speech:narrate` |
| numpy, onnxruntime | the SessionStart hook | `/speech:narrate` |
| Kokoro model, tokenizer, voices (about 340 MB) | `/speech:setup apply install-model` | `/speech:narrate` |

`prerequisites.json` declares the tools, with their install hints and what stops without each
one. `/speech:check` reads it.

The Python packages follow the
[on-demand dependencies convention](../../docs/conventions/on-demand-dependencies/README.md#python).
`requirements.in` pins them, `requirements.txt` hash-locks every wheel, and the SessionStart hook
installs them into `${CLAUDE_PLUGIN_DATA}/python/<lock hash>-<interpreter>/` with
`pip install --require-hashes --only-binary :all:`. Nothing else installs a package. A failed
install shows a notice at session start with the repair command.

## Output

`words.json`:

```json
{
  "audio": "narration.wav",
  "sample_rate": 24000,
  "duration": 13.625,
  "backend": "kokoro",
  "voice": "af_heart",
  "speed": 1.0,
  "words": [
    { "word": "Hello,", "start": 0.352, "end": 0.823 },
    { "word": "world.", "start": 0.939, "end": 1.62 }
  ]
}
```

Each whitespace-separated token of the script is one entry, in script order. A word's span covers
its own sounds, not the pause after its punctuation. A token that is only punctuation, such as a
dash, spans its pause.

## Tests

```bash
bash plugins/speech/scripts/speech.test.sh
bash plugins/speech/hooks/install-python-deps.test.sh
```

Set `SPEECH_E2E_DATA_DIR` to a data directory that holds the installed packages and the model, with
espeak-ng on `PATH`, to also run a real narration.
