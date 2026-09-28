"""Oscillators and an sfxr-shaped envelope. Parameter names follow that model; this loop is not a copy of sfxr or jsfxr."""


def oscillate(wave, phase, duty):
    if wave == "square" or wave == "pulse":
        return 1.0 if phase < duty else -1.0
    if wave == "saw":
        return phase * 2 - 1
    if wave == "sine" or wave == "triangle" or wave == "wave":
        # A 32-step triangle stands in for chip wave and NES triangle.
        step = int(phase * 32) / 32
        return (4 * abs(step - 0.5) - 1)
    raise ValueError(f"unknown wave {wave!r}")


def envelope(time, attack, sustain, decay):
    if time < attack:
        return 0.0 if attack <= 0 else time / attack
    if time < attack + sustain:
        return 1.0
    release = time - attack - sustain
    if decay <= 0 or release >= decay:
        return 0.0
    return 1 - release / decay


class Noise:
    def __init__(self, seed=1):
        self.state = seed or 1

    def sample(self):
        self.state = (1664525 * self.state + 1013904223) & 0xFFFFFFFF
        return self.state / 0xFFFFFFFF * 2 - 1


def one_pole(previous, sample, cutoff, rate):
    if cutoff <= 0:
        return sample, sample
    alpha = min(1.0, (cutoff / rate) * 2)
    low = previous + alpha * (sample - previous)
    return low, low
