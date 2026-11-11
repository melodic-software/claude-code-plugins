"""16-bit mono WAV read and write. Python standard library only."""
import pathlib
import struct
import wave


def write_wav(path, samples, rate):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    values = [int(max(-1.0, min(1.0, float(sample))) * 32767) for sample in samples]
    frames = struct.pack(f"<{len(values)}h", *values)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(frames)
    return len(samples) / rate


def read_wav(path):
    with wave.open(str(path), "rb") as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2:
            raise ValueError(f"{path} is not mono 16-bit")
        rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
    samples = [value / 32767 for value in struct.unpack(f"<{len(frames) // 2}h", frames)]
    return rate, samples
