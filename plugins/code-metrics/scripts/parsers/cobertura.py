#!/usr/bin/env python3
"""Parse a Cobertura XML coverage report into the plugin's parser shape.

    parse(path) -> {file: {"lines": {line: hits}, "functions": [...] | None}}

Command line: `python3 cobertura.py <artifact>` prints that mapping as JSON.

The hierarchy read (gcovr's Cobertura documentation, verified 2026-09-05):

    coverage
      sources/source            prefix the class filenames are relative to
      packages/package/classes/class[@filename]
        lines/line[@number,@hits]
        methods/method[@name]/lines/line[@number,@hits]

Two DTDs are both named `coverage-04.dtd` and many producers follow neither,
so nothing here validates: elements are found wherever they sit, a missing
attribute is absent rather than zero, and an unparsable `number` or `hits`
drops that one line instead of the report. `line-rate` and `branch-rate` are
never read (they are ratios in 0..1 while `condition-coverage` is a percentage
string, and mixing the two is the format's classic defect); the line hits are
counted directly instead.

`<method>` elements give the function-hit flag and the function's own line
region, so a Cobertura row joins as `artifact-region` rather than by line
range. kcov emits this format for Bash, and coverlet emits it for .NET.

A `<source>` that is neither empty nor `.` is prefixed onto a relative class
filename, which is what the element is for; the join then normalizes the
result against the repository root and `coverage.path_prefix_strip`.
"""

from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ElementTree
from typing import Any

MIN_PYTHON = (3, 9)
FORMAT = "cobertura"


def _norm(path: str) -> str:
    path = path.strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def _int(text: Any) -> int | None:
    if text is None:
        return None
    try:
        return int(str(text).strip())
    except ValueError:
        return None


def _line_map(element: ElementTree.Element) -> dict[int, int]:
    out: dict[int, int] = {}
    for line in element.iter("line"):
        number = _int(line.attrib.get("number"))
        hits = _int(line.attrib.get("hits"))
        if number is None or hits is None:
            continue
        out[number] = max(out.get(number, 0), hits)
    return out


def _sources(root: ElementTree.Element) -> list[str]:
    out = []
    for source in root.iter("source"):
        text = (source.text or "").strip().replace("\\", "/")
        if text and text != ".":
            out.append(text.rstrip("/"))
    return out


def parse(path: str) -> dict[str, dict]:
    """Read `path` and return the per-file coverage mapping."""
    root = ElementTree.parse(path).getroot()
    prefixes = _sources(root)
    files: dict[str, dict] = {}
    for klass in root.iter("class"):
        filename = klass.attrib.get("filename") or klass.attrib.get("name")
        if not filename:
            continue
        key = _norm(filename)
        if prefixes and not key.startswith("/") and ":" not in key[:3]:
            key = prefixes[0] + "/" + key
        section = files.setdefault(key, {"lines": {}, "functions": None})
        for number, hits in _line_map(klass).items():
            section["lines"][number] = max(section["lines"].get(number, 0), hits)
        for method in klass.iter("method"):
            name = method.attrib.get("name")
            if not name:
                continue
            region = _line_map(method)
            declared = _int(method.attrib.get("hits"))
            hit = declared if declared is not None else int(any(region.values()))
            entry = {
                "name": name,
                "start_line": min(region) if region else None,
                "end_line": max(region) if region else None,
                "hit": hit,
                "lines": region or None,
            }
            if section["functions"] is None:
                section["functions"] = []
            section["functions"].append(entry)
    for section in files.values():
        if section["functions"]:
            section["functions"].sort(
                key=lambda f: (f["start_line"] is None, f["start_line"] or 0)
            )
    return files


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: cobertura.py <artifact>", file=sys.stderr)
        return 2
    print(json.dumps(parse(argv[0]), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("cobertura.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ElementTree.ParseError) as exc:
        print(f"cobertura.py: {exc}", file=sys.stderr)
        sys.exit(2)
