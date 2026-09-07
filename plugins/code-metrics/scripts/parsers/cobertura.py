#!/usr/bin/env python3
"""Parse a Cobertura XML coverage report into the plugin's parser shape.

    parse(path) -> {file: {"lines": {line: hits}, "functions": [...] | None}}

Command line: `python3 cobertura.py <artifact>` prints that mapping as JSON.

The hierarchy read (gcovr's Cobertura documentation, verified 2026-09-05):

    coverage
      sources/source            roots the class filenames are relative to
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
result against the repository root and `coverage.path_prefix_strip`. A
multi-root build declares several of them and the report never says which
root a given class filename belongs to, so `_resolve` picks one; that rule,
and the scan root its on-disk probe reads, are written out there.
"""

from __future__ import annotations

import json
import os
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


def _scan_root() -> str:
    """Directory the on-disk probe in `_resolve` treats as the measured tree.

    The calling skill exports `CODE_METRICS_SCAN_ROOT` (the repository root it
    already resolved) because this parser's working directory is wherever the
    session happens to sit, which need not be the tree the report measures. A
    probe that cannot see that tree would answer "nothing exists" for every
    root and degrade to the first-root rule without saying so, so the root is
    passed rather than assumed; the working directory is the fallback for a
    direct command-line run inside the tree.
    """
    return os.environ.get("CODE_METRICS_SCAN_ROOT") or os.curdir


def _probe(path: str, prefix: str, reported: set[str]) -> bool:
    """True when `path` is present, noting once any miss that is not absence.

    `os.path.exists` answers False for a directory it may not read and for a
    file that is not there alike, so a root skipped over a permission error
    would hand its classes to a later root with nothing said. `os.stat` is the
    one syscall `os.path.exists` already makes, so telling the two apart costs
    no extra call: absence stays silent, and any other reason prints one
    stderr line per root and reason (not per class, which a large report would
    turn into a wall) and still counts as a miss, which keeps the parser
    total. stdout carries the parsed document and is never written here.
    """
    try:
        os.stat(path)
    except (FileNotFoundError, NotADirectoryError):
        return False
    except (OSError, ValueError) as exc:
        key = prefix + "\0" + type(exc).__name__
        if key not in reported:
            reported.add(key)
            print(
                f"cobertura.py: source root {prefix} not probed, "
                f"its classes may be attributed to another root: {exc}",
                file=sys.stderr,
            )
        return False
    return True


def _resolve(key: str, prefixes: list[str], scan_root: str, reported: set[str]) -> str:
    """Prefix a relative class filename with the source root it belongs to.

    The report declares its roots but never says which one a class filename
    is relative to, so the rule is, in order:

    1. An absolute or drive-qualified filename is already resolved and takes
       no prefix at all.
    2. One declared root leaves nothing to choose, so it is applied without
       touching the filesystem: the single-root case is byte-identical to the
       pre-multi-root parser and stays independent of where the parser runs.
    3. Otherwise the first root whose candidate path exists under `scan_root`
       wins. Existence is the only rule that is correct rather than merely
       plausible when two roots both yield a syntactically valid path, and
       the parser runs where the measured tree is present. An absolute root
       is probed absolutely, since joining it onto the scan root discards the
       scan root. That is the limit of the rule: roots written as absolute
       paths on the machine that produced the report (the usual coverlet,
       kcov and gcovr shape for a report built in CI) name directories the
       scanning machine does not have, so every probe misses and rule 4
       applies. Rewriting such a root onto the local tree needs a mapping the
       report does not carry, so the parser does not guess at one.
    4. No candidate on disk falls back to the first root, which preserves
       today's answer for the single-root case and keeps the parser total.
       Two candidates that both exist is a genuine ambiguity in the report:
       the first such candidate is taken and the run does not fail.
    """
    if not prefixes or key.startswith("/") or ":" in key[:3]:
        return key
    if len(prefixes) > 1:
        for prefix in prefixes:
            if _probe(os.path.join(scan_root, prefix, key), prefix, reported):
                return prefix + "/" + key
    return prefixes[0] + "/" + key


def parse(path: str) -> dict[str, dict]:
    """Read `path` and return the per-file coverage mapping."""
    root = ElementTree.parse(path).getroot()
    prefixes = _sources(root)
    scan_root = _scan_root()
    reported: set[str] = set()
    files: dict[str, dict] = {}
    for klass in root.iter("class"):
        filename = klass.attrib.get("filename") or klass.attrib.get("name")
        if not filename:
            continue
        key = _resolve(_norm(filename), prefixes, scan_root, reported)
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
