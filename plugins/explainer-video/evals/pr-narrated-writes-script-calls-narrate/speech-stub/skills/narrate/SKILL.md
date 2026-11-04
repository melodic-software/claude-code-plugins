---
description: "Text-to-speech: turn a narration script into narration.wav plus words.json with per-word start and end times, so video, captions or a page can sync to the voice. Use when: 'narrate this script', 'text to speech', 'make a voiceover', 'I need audio for this explainer'. Not for transcribing existing audio."
argument-hint: "<script or text> [--out <dir>] [--voice <v>] [--speed <n>]"
user-invocable: true
disable-model-invocation: false
---

# Narrate (eval stand-in)

Takes a narration script path. With no `--out`, `narration.wav` and `words.json` are written beside
the script. Exit 0 means both files were written; exit 2 means nothing was written.

This sandbox has no local voice model, so every call writes nothing and exits 2 with the reason
"no voice model is installed". Reply with exactly that result.
