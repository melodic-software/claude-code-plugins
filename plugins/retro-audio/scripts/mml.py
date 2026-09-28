#!/usr/bin/env python3
"""Render a small MML score to a mono WAV with a chip preset.

  mml.py --chip gameboy --out loop.wav "t120 o4 l4 c d e f"
  mml.py --chip nes --score tune.mml --out tune.wav

Channels are separated by |. Notes are a-g and r (rest) and n (noise).
Accidentals are # + -. Length is the denominator (4 = quarter); a dot multiplies
by 1.5. t sets tempo, o sets octave, l sets the default length, v sets volume
1-15, @0 is the chip bass wave, @1-@4 are pulse duties 12.5, 25, 50, 75.
< and > move the octave. [ ... ]N repeats.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import presets  # noqa: E402
import tone  # noqa: E402
import wav  # noqa: E402

SEMITONE = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


def _number(text, index):
    end = index
    while end < len(text) and (text[end].isdigit() or text[end] == "."):
        end += 1
    if end == index:
        return None, index
    return float(text[index:end]), end


def _seconds(tempo, length, dotted):
    span = (60 / tempo) * (4 / length)
    return span * 1.5 if dotted else span


def _hz(octave, name, accidental):
    midi = 12 * (octave + 1) + SEMITONE[name] + accidental
    return 440 * 2 ** ((midi - 69) / 12)


def _voice(state, chip):
    if state["noise"]:
        return "noise", 0.5
    if state["program"] == 0:
        return chip["bass_wave"], 0.5
    duty = chip["duties"][min(state["program"], len(chip["duties"])) - 1]
    return "pulse", duty


def _parse_channel(text, chip):
    state = {"tempo": 120.0, "octave": 4, "length": 4.0, "volume": 10.0, "program": 2, "noise": False}
    notes = []

    def parse(index):
        while index < len(text):
            char = text[index]
            if char.isspace():
                index += 1
                continue
            if char == "]":
                return index
            if char == "[":
                start = len(notes)
                index = parse(index + 1)
                if index >= len(text) or text[index] != "]":
                    raise ValueError("unclosed [ repeat")
                index += 1
                count, index = _number(text, index)
                times = int(count) if count else 2
                inner = notes[start:]
                del notes[start:]
                notes.extend(inner * times)
                continue
            if char in "tolv@":
                index += 1
                value, index = _number(text, index)
                if value is None:
                    raise ValueError(f"missing number after {char}")
                if char == "t":
                    state["tempo"] = value
                elif char == "o":
                    state["octave"] = int(value)
                elif char == "l":
                    state["length"] = value
                elif char == "v":
                    state["volume"] = value
                else:
                    state["program"] = int(value)
                    state["noise"] = False
                continue
            if char == "<":
                state["octave"] = max(0, state["octave"] - 1)
                index += 1
                continue
            if char == ">":
                state["octave"] = min(8, state["octave"] + 1)
                index += 1
                continue
            if char in SEMITONE or char in "rn":
                name = char
                index += 1
                accidental = 0
                if name in SEMITONE and index < len(text) and text[index] in "#+-":
                    accidental = 1 if text[index] in "#+" else -1
                    index += 1
                length, next_index = _number(text, index)
                if length is not None:
                    index = next_index
                else:
                    length = state["length"]
                dotted = index < len(text) and text[index] == "."
                if dotted:
                    index += 1
                seconds = _seconds(state["tempo"], length, dotted)
                if name == "n":
                    wave, duty = "noise", 0.5
                    hz = _hz(state["octave"], "c", 0)
                    state["noise"] = True
                elif name == "r":
                    wave, duty, hz = "pulse", 0.5, None
                else:
                    saved = state["noise"]
                    state["noise"] = False
                    wave, duty = _voice(state, chip)
                    state["noise"] = saved
                    hz = _hz(state["octave"], name, accidental)
                notes.append({
                    "hz": hz,
                    "seconds": seconds,
                    "wave": wave,
                    "duty": duty,
                    "volume": max(0.0, min(15.0, state["volume"])) / 15 * 0.8,
                    "noise": name == "n",
                })
                continue
            raise ValueError(f"unexpected {char!r} in score")
        return index

    parse(0)
    return notes


def render_mml(score, chip_name, rate=22050):
    if chip_name not in presets.CHIPS:
        known = ", ".join(sorted(presets.CHIPS))
        raise ValueError(f"unknown chip {chip_name!r}; choose {known}")
    chip = presets.CHIPS[chip_name]
    parts = [part.strip() for part in score.replace("\n", " ").split("|")]
    parts = [part for part in parts if part]
    if not parts:
        raise ValueError("score is empty")
    if len(parts) > chip["channels"]:
        raise ValueError(f"{chip_name} allows {chip['channels']} channels, score has {len(parts)}")
    channels = [_parse_channel(part, chip) for part in parts]
    noise_parts = sum(1 for notes in channels if any(note["noise"] for note in notes))
    if noise_parts > chip["noise_channels"]:
        raise ValueError(f"{chip_name} allows {chip['noise_channels']} noise channel")
    rendered = [_render_notes(notes, rate) for notes in channels]
    length = max(len(buffer) for buffer in rendered)
    scale = 1 / len(rendered)
    mixed = []
    for index in range(length):
        sample = 0.0
        for buffer in rendered:
            if index < len(buffer):
                sample += buffer[index]
        mixed.append(max(-1.0, min(1.0, sample * scale)))
    return mixed


def _render_notes(notes, rate):
    samples = []
    noise = tone.Noise(seed=len(notes) + 3)
    for note in notes:
        count = int(round(note["seconds"] * rate))
        phase = 0.0
        held = 0.0
        hold_for = 0
        for index in range(count):
            if note["hz"] is None:
                samples.append(0.0)
                continue
            env = 1 - 0.55 * (index / max(1, count - 1))
            if note["wave"] == "noise":
                hold_for -= 1
                if hold_for <= 0:
                    held = noise.sample()
                    hold_for = max(1, int(rate / note["hz"]))
                sample = held
            else:
                phase = (phase + note["hz"] / rate) % 1
                sample = tone.oscillate(note["wave"], phase, note["duty"])
            samples.append(sample * env * note["volume"])
    return samples


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chip", default="gameboy", choices=sorted(presets.CHIPS))
    parser.add_argument("--score", help="path to an MML file")
    parser.add_argument("--out", required=True)
    parser.add_argument("--rate", type=int, default=22050)
    parser.add_argument("text", nargs="?", help="MML text when --score is omitted")
    args = parser.parse_args(argv)
    if bool(args.score) == bool(args.text):
        print("mml.py: pass a score file or one quoted score, not both", file=sys.stderr)
        return 2
    score = Path(args.score).read_text() if args.score else args.text
    score = score.lower()
    try:
        samples = render_mml(score, args.chip, args.rate)
    except (OSError, ValueError) as exc:
        print(f"mml.py: {exc}", file=sys.stderr)
        return 1
    seconds = wav.write_wav(args.out, samples, args.rate)
    print(f"{args.out} ({seconds:.3f}s, {args.chip})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
