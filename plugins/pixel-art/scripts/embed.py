#!/usr/bin/env python3
"""Inline JSON and WAV files into an HTML template so a scene ships as one self-contained file.

/*EMBED:relative/path.json*/null becomes that file's JSON.
/*WAV:relative/path.wav*/null becomes a quoted data:audio/wav;base64 URL.
Paths resolve relative to the template. Usage: embed.py <template.html> <out.html>
"""
import base64
import json
import pathlib
import re
import sys

EMBED = re.compile(r"/\*EMBED:([^*]+)\*/null")
WAV = re.compile(r"/\*WAV:([^*]+)\*/null")


def embed(template, out):
    template = pathlib.Path(template)
    text = template.read_text()

    def load_json(match):
        path = (template.parent / match.group(1).strip()).resolve()
        # Escape "<" so a string holding "</script>" cannot close the inline script.
        return json.dumps(json.loads(path.read_text()), separators=(",", ":")).replace("<", "\\u003c")

    def load_wav(match):
        path = (template.parent / match.group(1).strip()).resolve()
        data = path.read_bytes()
        if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
            raise ValueError(f"{path.name} is not a WAV")
        encoded = base64.b64encode(data).decode("ascii")
        return f'"data:audio/wav;base64,{encoded}"'

    text, json_count = EMBED.subn(load_json, text)
    text, wav_count = WAV.subn(load_wav, text)
    pathlib.Path(out).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(out).write_text(text)
    return json_count + wav_count


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    try:
        n = embed(*sys.argv[1:])
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        sys.exit(f"embed.py: {exc}")
    print(f"{sys.argv[2]} ({n} embedded)")
