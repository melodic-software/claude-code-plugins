---
description: "Text-to-speech: turn a narration script into narration.wav plus words.json, a start and end time in seconds for every word of the script, so a video, caption track or page can sync to the voice. Runs the kokoro backend (Kokoro-82M, local, no network at run time). Use when: 'narrate this script', 'text to speech', 'read this aloud', 'make a voiceover', 'generate narration audio', 'TTS with word timings', 'I need audio for this explainer'. Not for transcribing existing audio."
argument-hint: "<script file or text> [--out <dir>] [--voice <name>] [--speed <0.5-2.0>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Script in, narration.wav and per-word words.json out (kokoro, local)
---

# Narrate

Turn a script into speech with the kokoro backend, and write a word timing file beside it.

## Inputs

- **Script.** A path to a UTF-8 text file, or text the user gave. For given text, write it to
  `script.txt` in the output folder first, so the run is repeatable. Write the script the way it
  should be spoken: spell out abbreviations you want expanded and keep one idea per sentence.
- **Output folder** (`--out`). Default: the script file's folder. The run writes two files there and
  replaces earlier ones with the same names.
- **Voice** (`--voice`). Default `af_heart`. Names starting `af_`/`am_` speak American English,
  `bf_`/`bm_` British English. `${CLAUDE_PLUGIN_ROOT}/scripts/kokoro-assets.json` lists every
  voice the plugin pins.
- **Speed** (`--speed`). Default `1.0`, from `0.5` to `2.0`.

## Run

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py" run --data-dir "${CLAUDE_PLUGIN_DATA}" -- \
  "${CLAUDE_PLUGIN_ROOT}/scripts/narrate.py" --data-dir "${CLAUDE_PLUGIN_DATA}" \
  --script <script file> --out <output folder> [--voice <name>] [--speed <x>]
```

`narrate.py` owns the behavior: how words are split, how timings are measured, and the
`words.json` fields. Read its docstring when you need the details.

- **Exit 0:** it prints the audio path with its length and word count, then the `words.json` path.
  Report both paths and the length.
- **Exit 2:** a prerequisite is missing. The message names it: espeak-ng, the model files, or the
  Python packages. Report the message as written and stop. Do not install anything.
  `/speech:check` lists every gap with its remedy.
- **Exit 1:** report the error. An unknown voice or a speed out of range is the caller's to fix.

## Outputs

- `narration.wav`: 24 kHz mono, 16-bit PCM.
- `words.json`: `audio`, `sample_rate`, `duration`, `backend`, `voice`, `speed`, and `words`, a
  list with one `{word, start, end}` per whitespace-separated token of the script, in script order.
  A token with only punctuation, such as a dash, spans its pause.

## Next

/speech:check

Run it when the run stopped with exit 2. It names each missing prerequisite with its remedy.

## Gotchas

- espeak-ng is GPL-3.0. The user installs it. Never install it, download it, or suggest a
  package that bundles it.
- The first run of a session loads a 325 MB model. On a desktop CPU the model makes audio faster
  than real time (about 0.4 s of compute for each second of audio, measured on a 32-thread x86
  CPU).
- Each word is phonemized on its own, so a function word can carry more stress than it would in
  running speech. Rewrite the sentence if one sounds wrong.
