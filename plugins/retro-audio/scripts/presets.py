"""Chip limits and the built-in sound-effect presets.

Parameter names follow the sfxr synthesizer model. jsfxr, a JavaScript port of
that model, is Unlicense (GitHub license field on chr15m/jsfxr and
grumdrig/jsfxr, read 2026-09-28; recheck if either repository's license field
changes). This package does not copy either program. Pulse duties are 12.5%,
25%, 50%, and 75%.
"""

CHIPS = {
    "gameboy": {
        "channels": 4,
        "noise_channels": 1,
        "bass_wave": "wave",
        "duties": (0.125, 0.25, 0.5, 0.75),
    },
    "nes": {
        "channels": 4,
        "noise_channels": 1,
        "bass_wave": "triangle",
        "duties": (0.125, 0.25, 0.5, 0.75),
    },
    "pico-8": {
        "channels": 4,
        "noise_channels": 1,
        "bass_wave": "triangle",
        "duties": (0.125, 0.25, 0.5, 0.75),
    },
}

# Times are seconds. freq and freq_slide are Hz and Hz/second.
SFX_PRESETS = {
    "coin": {
        "wave": "square",
        "freq": 740,
        "duty": 0.5,
        "sustain": 0.06,
        "decay": 0.06,
        "arp_time": 0.07,
        "arp_ratio": 2,
        "volume": 0.45,
    },
    "jump": {
        "wave": "square",
        "freq": 320,
        "freq_slide": 1600,
        "freq_limit": 980,
        "duty": 0.25,
        "sustain": 0.04,
        "decay": 0.12,
        "volume": 0.4,
    },
    "laser": {
        "wave": "square",
        "freq": 1400,
        "freq_slide": -2400,
        "freq_limit": 180,
        "duty": 0.5,
        "sustain": 0.02,
        "decay": 0.16,
        "volume": 0.35,
    },
    "explosion": {
        "wave": "noise",
        "freq": 220,
        "freq_slide": -180,
        "freq_limit": 40,
        "sustain": 0.08,
        "decay": 0.4,
        "lpf": 1400,
        "volume": 0.55,
    },
}
