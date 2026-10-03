---
description: "Text-to-speech: turn a narration script into narration.wav plus words.json, a start and end time in seconds for every word of the script, so a video, caption track or page can sync to the voice. The default kokoro backend is local, with no network at run time. The optional elevenlabs backend sends the script text to the third-party ElevenLabs API (api.elevenlabs.io), only after showing its character count, host and cost estimate and getting the user's go-ahead. Use when: 'narrate this script', 'text to speech', 'read this aloud', 'make a voiceover', 'generate narration audio', 'TTS with word timings', 'I need audio for this explainer', 'narrate with elevenlabs'. Not for transcribing existing audio."
argument-hint: "<script file or text> [--backend kokoro|elevenlabs] [--out <dir>] [--voice <name>] [--speed <0.5-2.0>] [--model <id>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Script in, narration.wav and words.json out (kokoro local; elevenlabs optional, third-party)
---

# Narrate

Turn a script into speech, and write a word timing file beside it. kokoro runs on this machine and is
the default. elevenlabs is a separate, optional backend that sends the text to a third party; use it
only when the user asks for it by name.

## Inputs

- **Script.** A path to a UTF-8 text file, or text the user gave. For given text, write it to
  `script.txt` in the output folder first, so the run is repeatable. Write the script the way it
  should be spoken: spell out abbreviations you want expanded and keep one idea per sentence.
- **Backend** (`--backend`). Default `kokoro`. `elevenlabs` only when the user names it; it follows
  its own section below.
- **Output folder** (`--out`). Default: the script file's folder. The run writes two files there and
  replaces earlier ones with the same names.
- **Voice** (`--voice`, kokoro). Default `af_heart`. Names starting `af_`/`am_` speak American English,
  `bf_`/`bm_` British English. `${CLAUDE_PLUGIN_ROOT}/scripts/kokoro-assets.json` lists every
  voice the plugin pins.
- **Speed** (`--speed`, kokoro). Default `1.0`, from `0.5` to `2.0`.

## Run (kokoro)

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py" run --data-dir "${CLAUDE_PLUGIN_DATA}" -- \
  "${CLAUDE_PLUGIN_ROOT}/scripts/narrate.py" --data-dir "${CLAUDE_PLUGIN_DATA}" \
  --script <script file> --out <output folder> [--voice <name>] [--speed <x>]
```

Where `python3` is not on PATH, run the same command with `python`; the SessionStart hook accepts either.

`narrate.py` owns the behavior: how words are split, how timings are measured, and the
`words.json` fields. Read its docstring when you need the details.

- **Exit 0:** it prints the audio path with its length and word count, then the `words.json` path.
  Report both paths and the length.
- **Exit 2:** a prerequisite is missing. The message names it: espeak-ng, the model files, or the
  Python packages. Report the message as written and stop. Do not install anything.
  `/speech:check` lists every gap with its remedy.
- **Exit 1:** report the error. An unknown voice or a speed out of range is the caller's to fix.

## The elevenlabs backend

Third-party egress: the script text goes to `api.elevenlabs.io`, and ElevenLabs bills it per
character. Pick this backend only when the user names ElevenLabs. Never pick it because kokoro is
slow or its output was disliked, and never switch to it after a kokoro failure.

The key is the `ELEVENLABS_API_KEY` environment variable, set by the user. Never ask the user to
paste it into the chat, never put it on a command line, and never print, echo or log it.

Two runs, with the user's answer between them:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/elevenlabs.py" --script <script file> --out <output folder> \
  [--voice <voice id>] [--model <model id>]
```

1. **Without `--proceed`**, the script prints one statement and sends nothing (exit 3): the
   character count, the host, the model and voice, and the estimated cost. Show that statement to the
   user as printed and ask whether to proceed. Stop until they answer.
2. **After a yes**, run the same command with `--proceed` added. A no, or no answer, ends the task.
   Do not add `--proceed` on your own, and do not reuse an earlier yes for a changed script, model or
   voice: run step 1 again.

The default model is `eleven_multilingual_v2`; `--model eleven_flash_v2_5` costs half and takes longer
scripts. `--voice` takes an ElevenLabs voice id. Rates and per-request limits are the script's
`MODELS` table, read from <https://elevenlabs.io/pricing/api> and
<https://elevenlabs.io/docs/overview/models> on 2026-10-03; recheck when either page changes. The
cost is an estimate: ElevenLabs bills credits against the user's plan.

- **Exit 0:** report the audio path with its length, and the `words.json` path.
- **Exit 3:** the estimate was shown and nothing was sent. Ask, as above.
- **Exit 4:** the organization's egress floor forbids this backend (`SPEECH_EGRESS_FLOOR` is
  set in the environment, usually from managed settings). Report the reason as written, use kokoro
  if the user agrees, and do not try to unset the variable.
- **Exit 2:** `ELEVENLABS_API_KEY` is not set. Tell the user to set it in their shell environment.
- **Exit 1:** report the error, such as a rejected key or a script over the model's limit.

## Outputs

- `narration.wav`: 24 kHz mono, 16-bit PCM.
- `words.json`: `audio`, `sample_rate`, `duration`, `backend`, `voice`, `speed` (kokoro) or `model`
  (elevenlabs), and `words`, a list with one `{word, start, end}` per whitespace-separated token of
  the script, in script order. A kokoro token with only punctuation, such as a dash, spans its pause.
  ElevenLabs reports a time for every character, and a word spans its first to its last character.

## Next

/speech:check

Run it when the run stopped with exit 2. It names each missing prerequisite with its remedy.

## Gotchas

- Never read, print or pass `ELEVENLABS_API_KEY` yourself. `elevenlabs.py` reads it from the
  environment, and no command, message or file you write carries its value.
- espeak-ng is GPL-3.0. The user installs it. Never install it, download it, or suggest a
  package that bundles it.
- The first run of a session loads a 325 MB model. On a desktop CPU the model makes audio faster
  than real time (about 0.4 s of compute for each second of audio, measured on a 32-thread x86
  CPU).
- Each word is phonemized on its own, so a function word can carry more stress than it would in
  running speech. Rewrite the sentence if one sounds wrong.
