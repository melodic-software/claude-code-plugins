# retro-audio

Sound effects and short chiptune loops as WAV files. Python 3 and the standard library are enough.
Nothing here is an MP3 encoder, and nothing here reads the pixel-art plugin. A scene plays a WAV
you pass in.

| Skill | What it does |
|---|---|
| `/retro-audio:sfx` | One effect from parameters or a preset (coin, jump, laser, explosion) |
| `/retro-audio:music` | A short loop from MML text, with a chip preset |

```shell
python3 scripts/sfx.py --preset jump --out jump.wav
python3 scripts/mml.py --chip gameboy --out loop.wav "t120 o4 l8 [ceg]4"
```

`examples/campfire.mml` is the loop embedded in the pixel-art campfire scene.

Pulse duties are 12.5%, 25%, 50%, and 75%. `@0` is the chip's bass wave (triangle, or the Game Boy
wave channel as a 32-step triangle). `n` is the noise channel, and a chip preset allows one noise
part. Scores use `|` between parts, up to four.
