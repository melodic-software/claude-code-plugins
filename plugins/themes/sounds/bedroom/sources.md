# Where the bedroom's sounds come from

Each recording below was cut from a file whose own page states CC0 or the Public Domain Mark, read on 2026-11-20.
Neither asks for credit; each page is linked so anyone can check. The freesound files are the pages' HQ MP3 previews,
not the originals. Every file is mono 16-bit PCM WAV. A bed is a 20 s loop whose last 1.5 s is faded into its start at
equal power. Loudness is integrated (EBU R 128), measured with ffmpeg's `ebur128`.

License statements, as each page shows them:

- freesound: "Creative Commons 0", linking <http://creativecommons.org/publicdomain/zero/1.0/>.
- archive.org (radio aporee): "Public Domain Mark 1.0", linking <https://creativecommons.org/publicdomain/mark/1.0/>,
  applied by the recordist.

| File | From | Range | Processing | Page | License |
|---|---|---|---|---|---|
| `cicadas/chorus.wav` (default) | the page's WAV, cicadas in a backyard | 28.25 to 49.75 s | high-pass 900 Hz; 22,050 Hz; -34 LUFS | <https://archive.org/details/aporee_30403_34990> | Public Domain Mark 1.0 |
| `cicadas/river.wav` | the page's WAV, cicadas by a river at dusk | 45.25 to 66.75 s | high-pass 900 Hz; 22,050 Hz; -34 LUFS | <https://archive.org/details/aporee_45599_51781> | Public Domain Mark 1.0 |
| `crickets/katydids.wav` (default) | `532301_2669618-hq.mp3`, crickets and katydids in woodland at night, late summer | 25.5 to 47 s | high-pass 900 Hz; 22,050 Hz; -34 LUFS | <https://freesound.org/people/widgetstudios/sounds/532301/> | Creative Commons 0 |
| `crickets/crickets.wav` | `210540_985466-hq.mp3`, crickets on a late summer night | 0 to 21.5 s | high-pass 900 Hz; 22,050 Hz; -34 LUFS | <https://freesound.org/people/Sclolex/sounds/210540/> | Creative Commons 0 |
| `rain/roof-rain.wav` | `466241_1481531-hq.mp3`, rain on a tile roof heard from the loft | 283.5 to 305 s | high-pass 90 Hz; 22,050 Hz; -30 LUFS (the rain bed chosen by ear, and the reference for the two below) | <https://freesound.org/people/richwise/sounds/466241/> | Creative Commons 0 |
| `rain/roof-downpour.wav` | the same | five 22.5 s stretches from 59.25, 175, 465, 99.25 and 142.25 s | the stretches high-passed at 90 Hz and summed; transients softened (3:1 above 1.8 times the 60 ms level); a small room's reverb (0.4 s, 35 %); low shelf +4 dB below 220 Hz; one-pole low-passes at 3,500 and 5,600 Hz; the first 1 s dropped; 16,000 Hz; -25 LUFS | as above | Creative Commons 0 |
| `rain/roof-storm.wav` | the same | nine 22.5 s stretches: those five and 329.25, 408.25, 247.5 and 306.75 s | as the downpour, softened above 1.6 times, reverb 0.45 s at 40 %, shelf +6 dB, low-passes at 3,000 and 4,800 Hz, with wind made by code at 30 % of the rain's level; 16,000 Hz; -21 LUFS | as above | Creative Commons 0 |
| `thunder/storm-near.wav` | `446753_1790434-hq.mp3`, one heavy strike with no rain | 1.7 to 7.7 s | high-pass 25 Hz; one-pole low-passes at 2,500 and 3,750 Hz; 50 ms fade in, 2.2 s fade out; 16,000 Hz; -20 LUFS | <https://freesound.org/people/BlueDelta/sounds/446753/> | Creative Commons 0 |
| `thunder/storm-mid.wav` | `347562_5481182-hq.mp3`, one gentle clap | 3.4 to 10.4 s | high-pass 25 Hz; low-passes at 1,800 and 2,700 Hz; fades as above; 16,000 Hz; -25.3 LUFS (true peak -1 dBFS) | <https://freesound.org/people/mikala_oidua/sounds/347562/> | Creative Commons 0 |
| `thunder/storm-far-1.wav`, `thunder/storm-far-2.wav` | `361401_1481531-hq.mp3`, distant rolls | 20 to 28 s; 239.5 to 247.5 s | high-pass 25 Hz; low-passes at 1,200 and 1,800 Hz; fades as above; 16,000 Hz; -22.7 and -24.4 LUFS (true peak -1 dBFS) | <https://freesound.org/people/richwise/sounds/361401/> | Creative Commons 0 |
| `thunder/distant-near.wav`, `thunder/distant-mid.wav` | `107518_43834-hq.mp3`, distant rolls | 85 to 92 s; 13.5 to 21.5 s | high-pass 25 Hz; low-passes at 1,800 and 2,700 Hz, and 1,500 and 2,250 Hz; fades as above; 16,000 Hz; -20.3 and -22.2 LUFS | <https://freesound.org/people/moxobna/sounds/107518/> | Creative Commons 0 |
| `thunder/distant-far.wav` | `361401_1481531-hq.mp3` | 91.75 to 99.75 s | as `storm-far`; -21.2 LUFS | <https://freesound.org/people/richwise/sounds/361401/> | Creative Commons 0 |
| `objects/purr.wav` | `553962_11756852-hq.mp3`, a pet cat purring | 4 to 7.5 s | high-pass 35 Hz; low-pass 1,800 Hz; 0.3 s fade in, 0.9 s fade out; 16,000 Hz; -34 LUFS | <https://freesound.org/people/clareboots/sounds/553962/> | Creative Commons 0 |

Made by code, with no recording: `tv/tube-on.wav` and `tv/tube-off.wav` (a relay click, a short degauss thump, the
flyback whine and static, at 44,100 Hz so the whine can reach the line rate), the room's things in `objects/` (the
desk lamp's push switch and the wall light's rocker, on and off; the monitor's button with a soft degauss hum, and its
off click; the console's button, a fan winding up and a two-tone chime of this plugin's own, and the fan winding down;
the tape sliding in, the motor and the mechanism's clunk, and the reverse), all at 22,050 Hz, peaks at -12 dBFS, and
`silence.wav`.

## The rain heard from the middle of the room

The downpour and the storm are the accepted rain, heavier: denser, louder and with more of the roof's and walls'
rumble, never closer. Measured over each whole file, the spectrum averaged over 4,096-point windows:

| Bed | LUFS | Crest factor (peak / RMS) | 99.9th percentile / RMS | Energy 4 to 8 kHz | Spectral centroid | Sharpest peak 1 to 5 kHz over its neighbors |
|---|---|---|---|---|---|---|
| `rain/roof-rain.wav` (reference) | -30 | 18.5 dB | 11.5 dB | 5.1 % | 1,053 Hz | 1.1 dB |
| `rain/roof-downpour.wav` | -25 | 14.7 dB | 10.5 dB | 2.3 % | 686 Hz | 3.9 dB |
| `rain/roof-storm.wav` | -21 | 13.9 dB | 10.3 dB | 1.1 % | 480 Hz | 4.2 dB |

Both heavy beds have fewer sharp taps (a lower crest factor) and less treble than the rain they are built from, so
they sit no nearer than it. A downpour recorded close to a small pane, for comparison, measures 19.8 dB crest and a
6.7 dB ring at 1,017 Hz: the metallic, close sound these beds avoid.
