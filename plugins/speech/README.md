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

kokoro is the only backend so far. It runs [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M)
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

## Prerequisites

| Prerequisite | Installed by | Needed for |
|---|---|---|
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
