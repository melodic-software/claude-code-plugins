#!/usr/bin/env python3
"""Inline JSON files into an HTML template so a scene ships as one self-contained file.

Every token /*EMBED:relative/path.json*/null in the template is replaced by that file's JSON,
resolved relative to the template. Usage: embed.py <template.html> <out.html>
"""
import json
import pathlib
import re
import sys

TOKEN = re.compile(r"/\*EMBED:([^*]+)\*/null")


def embed(template, out):
    template = pathlib.Path(template)

    def load(match):
        path = (template.parent / match.group(1).strip()).resolve()
        # Escape "<" so a string holding "</script>" cannot close the inline script.
        return json.dumps(json.loads(path.read_text()), separators=(",", ":")).replace("<", "\\u003c")

    text, count = TOKEN.subn(load, template.read_text())
    pathlib.Path(out).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(out).write_text(text)
    return count


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    try:
        n = embed(*sys.argv[1:])
    except (OSError, json.JSONDecodeError) as exc:
        sys.exit(f"embed.py: {exc}")
    print(f"{sys.argv[2]} ({n} embedded)")
