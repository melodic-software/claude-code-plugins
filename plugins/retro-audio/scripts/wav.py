"""16-bit mono WAV read and write. Python standard library only."""
import pathlib
import struct
import wave


def write_wav(path, samples, rate):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for sample in samples:
        clipped = max(-1.0, min(1.0, float(sample)))
        frames += struct.pack("<h", int(clipped * 32767))
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
        count = handle.getnframes()
        frames = handle.readframes(count)
    samples = [struct.unpack_from("<h", frames, i)[0] / 32767 for i in range(0, len(frames), 2)]
    return rate, samples
