#!/usr/bin/env python3
"""Render one sound effect from an sfxr-style parameter object.

  sfx.py --preset coin --out coin.wav
  sfx.py --params effect.json --out effect.wav

Parameters (all optional except wave and freq): wave (square, saw, sine,
noise), freq (Hz), freq_slide (Hz/second), freq_limit, duty (0-1), duty_slide,
vibrato_depth (Hz), vibrato_rate (Hz), attack, sustain, decay (seconds),
punch (0-1), volume (0-1), repeat (seconds, 0 off), arp_time (seconds),
arp_ratio (frequency multiplier), lpf and hpf (Hz, 0 off).
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import presets  # noqa: E402
import tone  # noqa: E402
import wav  # noqa: E402


def render_sfx(params, rate=44100):
    wave_name = params.get("wave", "square")
    if wave_name not in ("square", "saw", "sine", "noise", "pulse"):
        raise ValueError(f"wave {wave_name!r} is not square, saw, sine, or noise")
    freq = float(params.get("freq", 440))
    if freq <= 0:
        raise ValueError("freq must be positive")
    attack = float(params.get("attack", 0))
    sustain = float(params.get("sustain", 0.1))
    decay = float(params.get("decay", 0.1))
    duration = attack + sustain + decay
    if duration <= 0:
        raise ValueError("attack + sustain + decay must be positive")
    total = int(rate * duration)
    slide = float(params.get("freq_slide", 0))
    limit = params.get("freq_limit")
    duty = float(params.get("duty", 0.5))
    duty_slide = float(params.get("duty_slide", 0))
    vib_depth = float(params.get("vibrato_depth", 0))
    vib_rate = float(params.get("vibrato_rate", 0))
    punch = float(params.get("punch", 0))
    volume = float(params.get("volume", 0.5))
    repeat = float(params.get("repeat", 0))
    arp_time = float(params.get("arp_time", 0))
    arp_ratio = float(params.get("arp_ratio", 1))
    lpf = float(params.get("lpf", 0))
    hpf = float(params.get("hpf", 0))
    noise = tone.Noise()
    held = 0.0
    phase = 0.0
    low = 0.0
    high_low = 0.0
    samples = []
    for index in range(total):
        time = index / rate
        local = time % repeat if repeat > 0 else time
        current = freq + slide * local
        if limit is not None:
            current = min(current, float(limit)) if slide > 0 else max(current, float(limit)) if slide < 0 else current
        if arp_time > 0 and local >= arp_time:
            current *= arp_ratio
        current = max(1.0, current)
        if vib_depth and vib_rate:
            lfo_phase = (local * vib_rate) % 1
            current += vib_depth * (4 * abs(lfo_phase - 0.5) - 1)
        current_duty = min(0.95, max(0.05, duty + duty_slide * local))
        if wave_name == "noise":
            if index % max(1, int(rate / current)) == 0:
                held = noise.sample()
            sample = held
        else:
            phase = (phase + current / rate) % 1
            sample = tone.oscillate(wave_name, phase, current_duty)
        level = tone.envelope(local if repeat > 0 else time, attack, sustain, decay)
        if punch and time < 0.01:
            level = min(1.0, level + punch)
        sample *= level * volume
        if lpf:
            low, sample = tone.one_pole(low, sample, lpf, rate)
        if hpf:
            high_low, lowpassed = tone.one_pole(high_low, sample, hpf, rate)
            sample -= lowpassed
        samples.append(sample)
    return samples


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset", choices=sorted(presets.SFX_PRESETS))
    parser.add_argument("--params", help="JSON object of parameters")
    parser.add_argument("--out", required=True)
    parser.add_argument("--rate", type=int, default=44100)
    args = parser.parse_args(argv)
    if bool(args.preset) == bool(args.params):
        print("sfx.py: pass exactly one of --preset or --params", file=sys.stderr)
        return 2
    try:
        if args.preset:
            params = dict(presets.SFX_PRESETS[args.preset])
        else:
            raw = args.params.strip()
            params = json.loads(raw) if raw.startswith("{") else json.loads(Path(raw).read_text())
        samples = render_sfx(params, args.rate)
    except (OSError, ValueError, KeyError) as exc:
        print(f"sfx.py: {exc}", file=sys.stderr)
        return 1
    seconds = wav.write_wav(args.out, samples, args.rate)
    print(f"{args.out} ({seconds:.3f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
