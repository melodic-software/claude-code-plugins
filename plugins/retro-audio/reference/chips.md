# Chip presets

`scripts/presets.py` is what the renderer enforces. This note is why those numbers exist.

## Pulse duty

- Game Boy pulse channels use duty cycles 12.5%, 25%, 50%, and 75%.
  Basis: [Pan Docs, Audio Registers](https://gbdev.io/pandocs/Audio_Registers.html) (NR11 / NR21
  wave duty). As of 2026-09-28. Recheck when that page changes the duty table.
- NES pulse channels use the same four duties.
  Basis: [NESDev APU Pulse](https://www.nesdev.org/wiki/APU_Pulse). As of 2026-09-28. Recheck when
  that page changes the duty table.

- The pico-8 preset reuses the four Game Boy and NES duties as a shared approximation. They are
  not a PICO-8 hardware figure: the PICO-8 manual does not document them.

`@0` is the preset's bass wave (Game Boy wave channel, NES and PICO-8 triangle). `@1` through
`@4` select those four duties in the order above.

## Channels

Each preset allows 4 channels and 1 noise channel. A score with more channels, or noise on two
channels, is an error. A preset enforces only the channel count (4), the noise-part count (1), and
the `@0` bass waveform name. It does not enforce the hardware voice mix (Game Boy: two pulse, one
wave, one noise; NES: two pulse, one triangle, one noise, one DPCM), so four pulse parts or several
`@0` parts are accepted. PICO-8 music is also 4 channels in the official manual (sfx instruments
are a separate limit). Basis: [PICO-8 manual](https://www.lexaloffle.com/dl/docs/pico-8_manual.html)
music section. As of 2026-09-28. Recheck when the manual's version line moves past 0.2.7.

## MML subset

`scripts/mml.py` accepts `t` tempo, `o` octave, `l` default length, `v` volume 1-15, `@` program,
`<` `>` octave, notes `a` through `g`, rests `r`, noise `n`, accidentals `#` `+` `-`, dotted
lengths, and `[...]N` repeats. Channels are split on `|`.
