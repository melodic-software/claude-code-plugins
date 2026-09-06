#!/usr/bin/env python3
"""Gitignore-style path matching at the Python 3.9 floor.

The consumer's `.claude/ecosystems/<lane>.yaml` files declare `globs` in the
gitignore dialect (`*.sh`, `src/**/*.ts`, `**/vendor/**`). `fnmatch` treats
`*` as crossing `/` and knows nothing of `**`, and `glob.translate` arrived in
3.13, so this module owns the translation.

Rules implemented (the subset the ecosystem-commands examples use):

- `*` matches within one path segment, never `/`.
- `?` matches one character other than `/`.
- `**` matches any number of segments, including none, when it stands alone
  between separators (`a/**/b`, `**/b`, `a/**`); elsewhere it behaves as `*`.
- `[...]` is a character class passed through to the regex.
- A pattern with no `/` (a trailing one aside) matches the basename at any
  depth, as gitignore does; a pattern with a `/` is anchored at the root of
  the path it is matched against.
- Paths are compared with forward slashes; a Windows path is normalized first.

Command line: `pathglob.py <pattern> <path>...` prints the matching paths one
per line and exits 0 (exit 2 on a usage error). `--any` exits 0 when at least
one path matches and 1 otherwise, printing nothing.
"""

from __future__ import annotations

import re
import sys

MIN_PYTHON = (3, 9)

_USAGE = "usage: pathglob.py [--any] <pattern> [--paths-from <file>] <path>..."


def _normalize(path: str) -> str:
    path = path.replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def translate(pattern: str) -> str:
    """Return an anchored regex for a gitignore-style glob."""
    pattern = _normalize(pattern)
    # A trailing slash names a directory, and gitignore semantics exclude
    # everything under it. Dropping the slash would leave a bare segment that
    # matches only a path literally called `vendor`, so `vendor/` would exclude
    # nothing and the whole directory would stay in scope.
    directory = pattern.endswith("/")
    pattern = pattern.rstrip("/")
    if directory and pattern:
        pattern += "/**"
    anchored = "/" in pattern
    if pattern.startswith("/"):
        pattern = pattern[1:]
    segments = pattern.split("/")
    parts: list[str] = []
    for index, segment in enumerate(segments):
        last = index == len(segments) - 1
        if segment == "**":
            parts.append("(?:.*/)?" if not last else ".*")
            continue
        piece = ""
        i = 0
        while i < len(segment):
            ch = segment[i]
            if ch == "*":
                piece += "[^/]*"
            elif ch == "?":
                piece += "[^/]"
            elif ch == "[":
                close = segment.find("]", i + 1)
                if close == -1:
                    piece += re.escape(ch)
                else:
                    body = segment[i + 1 : close]
                    if body.startswith("!"):
                        body = "^" + body[1:]
                    piece += "[" + body.replace("\\", "\\\\") + "]"
                    i = close
            else:
                piece += re.escape(ch)
            i += 1
        parts.append(piece + ("" if last else "/"))
    body = "".join(parts)
    # A `**/` part already carries its own trailing slash.
    body = body.replace("(?:.*/)?/", "(?:.*/)?")
    prefix = "^" if anchored else "^(?:.*/)?"
    return prefix + body + "$"


def matches(pattern: str, path: str) -> bool:
    return re.match(translate(pattern), _normalize(path)) is not None


def main(argv: list[str]) -> int:
    any_mode = False
    listed: list[str] = []
    args = list(argv)
    if args and args[0] == "--any":
        any_mode = True
        args = args[1:]
    # `--paths-from` reads the paths from a file, one per line. A whole
    # repository's scope does not fit in one argument vector on every platform
    # this runs on, and a file has no such ceiling.
    if len(args) >= 3 and args[1] == "--paths-from":
        try:
            with open(args[2], encoding="utf-8") as handle:
                listed = [line.rstrip("\n") for line in handle if line.strip()]
        except OSError as exc:
            print(f"pathglob.py: {exc}", file=sys.stderr)
            return 2
        args = [args[0]] + args[3:]
    if len(args) < 1 or (len(args) < 2 and not listed):
        print(_USAGE, file=sys.stderr)
        return 2
    pattern, paths = args[0], listed + args[1:]
    try:
        regex = re.compile(translate(pattern))
    except re.error as exc:
        # A consumer writes these patterns by hand in an ecosystem file, and a
        # bad character class (`[z-a]`) is a configuration mistake, not a
        # crash. Naming it beats a traceback, and the non-zero exit is what
        # stops the caller from reading "no files matched" as an answer.
        print(f"pathglob.py: {pattern!r} is not a usable glob: {exc}", file=sys.stderr)
        return 2
    hits = [p for p in paths if regex.match(_normalize(p))]
    if any_mode:
        return 0 if hits else 1
    for hit in hits:
        print(hit)
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("pathglob.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
