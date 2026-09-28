---
description: "Render a chiptune loop from MML text to WAV with pulse, triangle, and noise presets, standard library only. Use when: 'chiptune', '8-bit music', 'retro game loop', 'MML to wav'. Not for a one-shot effect (use /retro-audio:sfx) or lyrics."
argument-hint: "<mood or score> [chip gameboy|nes|pico-8]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Render a short chiptune score to a WAV file
---

# Music

Turn a short description or a pasted score into one looping WAV.

## 1. Write the score

Use the MML subset in [`${CLAUDE_PLUGIN_ROOT}/scripts/mml.py`](${CLAUDE_PLUGIN_ROOT}/scripts/mml.py): `t` tempo, `o`
octave, `l` length, `v` volume 1-15, `@0` bass, `@1` to `@4` pulse duties 12.5, 25, 50, 75
(claim = those four duties; basis = [`chips.md`](${CLAUDE_PLUGIN_ROOT}/reference/chips.md); as of
2026-09-28; recheck when that file's Pan Docs or NESDev basis changes), `<` and
`>` for octave, `[` `]` repeats, `|` between parts, `n` for noise. Notes are `a` through `g` and
`r`. A dot after a length is 1.5 times. Pick `--chip gameboy`, `nes`, or `pico-8`. Four parts at
most, and only one part may use `n`.

A worked loop is `${CLAUDE_PLUGIN_ROOT}/examples/campfire.mml`.

## 2. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/mml.py" --chip gameboy --out <dir>/loop.wav "<score>"
```

## 3. Deliver

Give the WAV path and the score text beside it. A pixel-art scene takes the path as its audio
argument and inlines the file. Do not edit that plugin from here.

## Next

/pixel-art:scene <scene> <wav path> to play the loop in a scene.

## Gotchas

- Length numbers are denominators: `l4` is a quarter note, `l8` an eighth.
- The renderer does not write MP3. Browsers will not start the WAV until a click.
