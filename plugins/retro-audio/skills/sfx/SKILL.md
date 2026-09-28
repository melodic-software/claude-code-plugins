---
description: "Render a retro sound effect to WAV from an sfxr-style parameter set, standard library only. Use when: 'sound effect', '8-bit sfx', 'pickup sound', 'jump sound', 'explosion sfx', 'chiptune effect'. Not for a song or loop (use /retro-audio:tune) or a picture."
argument-hint: "<effect> [preset coin|jump|laser|explosion]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Render one retro sound effect to a WAV file
---

# Sound effect

Write one WAV the user can drop into a game or hand to a scene.

## 1. Pick the sound

A preset (`coin`, `jump`, `laser`, `explosion`) is enough when the request names that kind of
effect. Otherwise write a JSON object. Parameter names and the envelope shape are in
[`${CLAUDE_PLUGIN_ROOT}/scripts/presets.py`](${CLAUDE_PLUGIN_ROOT}/scripts/presets.py) and
[`${CLAUDE_PLUGIN_ROOT}/scripts/sfx.py`](${CLAUDE_PLUGIN_ROOT}/scripts/sfx.py). State any field you default in one line.
Do not ask a list of questions for a one-shot effect.

## 2. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/sfx.py" --preset jump --out <dir>/jump.wav
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/sfx.py" --params '<json>' --out <dir>/effect.wav
```

`--params` is either an inline JSON object or a path to one. The file is 16-bit mono PCM.

## 3. Deliver

Give the WAV path. If the user wants it inside a pixel-art scene, the scene skill takes that path
as an argument. Do not open or edit the scene plugin's files from here.

## Next

/retro-audio:tune to score a loop in the same chip voice.

## Gotchas

- `attack`, `sustain`, and `decay` are seconds. Their sum is the file length.
- `volume` is 0 to 1. A value of 1 on a square wave is already full scale.
