#!/usr/bin/env python3
"""Flag a hand-kept list the tree could derive, for coupling:reduce's hotspot lens.

Usage:
  derivable-list.py [--root DIR] [--paths-from FILE] [PATH...]

--paths-from reads more PATHs, one per line, from FILE (`-` is stdin), so
paths taken from pull requests never have to be spelled on a command line.
Reads each PATH (a tracked file, relative to DIR, default `.`) and finds its
lists. A JSON file's lists are its arrays and the key sets of its objects; any
other file is one list of its non-blank lines, `#` lines skipped. An entry
names a path when one of its strings, after `./` and a trailing `/` are
dropped, is a tracked file or folder of DIR, read from the list's own folder or
from DIR. A JSON entry's strings are every string inside it; a line's are its
words. Absolute spellings and spellings that leave DIR never count. Only lists
of at least MIN_ENTRIES entries are weighed; the one with the highest share of
naming entries is reported. Rows, tab-separated:

  candidate  NAMED  ENTRIES  PATH  LIST   share at or above THRESHOLD
  below      NAMED  ENTRIES  PATH  LIST   share under THRESHOLD
  no-list    0      0        PATH  -      no list of MIN_ENTRIES entries
  unnamed    PATH   LIST     ENTRY        each entry of a candidate list that
                                          names nothing (stale, or not a path)
  skip       PATH   REASON                outside-root, untracked, binary,
                                          unreadable

LIST is a JSON pointer (` (keys)` added for an object's keys) or `lines`;
ENTRY is the entry as one line of ASCII JSON, cut at 200 characters. Control,
format and line-separator characters in PATH and LIST print as \\uXXXX. Nothing
is executed or written, and entries are compared with `git ls-files`, never
stat-ed. A PATH that resolves outside DIR (a tracked symlink, say) is skipped
as outside-root before it is opened.

Exit 0 done (skip rows included), 2 no PATH, an unreadable --paths-from, or DIR
is not a git work tree.
"""

from __future__ import annotations

import argparse
import io
import json
import posixpath
from pathlib import Path
import re
import subprocess
import sys
import unicodedata

# Judgment values, stated in the skill: 80% leaves room for the stale entries a
# drifting list carries while ruling out a list whose entries mostly hold data
# the tree does not; under five entries a list matches paths by chance and costs
# little to keep by hand.
THRESHOLD = 0.8
MIN_ENTRIES = 5
WORD_SPLIT = re.compile(r"[\s()\[\]<>\"'`,;|=]+")


class UsageError(Exception):
    pass


def esc(text: str) -> str:
    return "".join(
        f"\\u{ord(c):04x}" if unicodedata.category(c) in ("Cc", "Cf", "Zl", "Zp") else c
        for c in text
    )


def tree(root: str) -> tuple[set[str], set[str]]:
    """The tracked files, and the tracked files plus every folder holding one."""
    proc = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True)
    if proc.returncode != 0:
        raise UsageError(f"not a git work tree: {root}")
    files = set(proc.stdout.decode("utf-8", "surrogateescape").split("\0")) - {""}
    names: set[str] = set()
    for rel in files:
        while rel and rel not in names:
            names.add(rel)
            rel = posixpath.dirname(rel)
    return files, names


def inside(rel: str) -> str | None:
    """The normalized relative spelling of rel, or None when it leaves the root."""
    if not rel or "\0" in rel:
        return None
    rel = rel.replace("\\", "/")
    if rel.startswith("/") or re.match(r"^[A-Za-z]:", rel):
        return None
    rel = posixpath.normpath(rel)
    if rel == "." or rel == ".." or rel.startswith("../"):
        return None
    return rel


def names_path(text: str, base: str, names: set[str]) -> bool:
    text = text.strip()
    if text.startswith("./"):
        text = text[2:]
    text = text.rstrip("/")
    for rel in (text, posixpath.join(base, text) if base else None):
        rel = inside(rel) if rel else None
        if rel and rel in names:
            return True
    return False


def strings(value) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [s for v in value for s in strings(v)]
    if isinstance(value, dict):
        return [s for k, v in value.items() for s in [k, *strings(v)]]
    return []


def json_lists(value, pointer: str = ""):
    """Yield (locator, entries, strings per entry) for every array and key set."""
    if isinstance(value, list):
        yield pointer, value, [strings(v) for v in value]
        for i, v in enumerate(value):
            yield from json_lists(v, f"{pointer}/{i}")
    elif isinstance(value, dict):
        keys = list(value)
        yield f"{pointer} (keys)", keys, [[k] for k in keys]
        for k, v in value.items():
            token = k.replace("~", "~0").replace("/", "~1")
            yield from json_lists(v, f"{pointer}/{token}")


def line_list(text: str):
    entries = [
        ln.strip()
        for ln in text.splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    ]
    yield "lines", entries, [[w for w in WORD_SPLIT.split(e) if w] for e in entries]


def check(rel: str, root: str, files: set[str], names: set[str]) -> list[str]:
    norm = inside(rel)
    if norm is None:
        return [f"skip\t{esc(rel)}\toutside-root"]
    if norm not in files:
        return [f"skip\t{esc(rel)}\tuntracked"]
    where = (Path(root) / norm).resolve()
    if not where.is_relative_to(Path(root).resolve()):
        return [f"skip\t{esc(rel)}\toutside-root"]
    try:
        with open(where, "rb") as fh:
            data = fh.read()
    except OSError:
        return [f"skip\t{esc(rel)}\tunreadable"]
    if b"\0" in data[:8192]:
        return [f"skip\t{esc(rel)}\tbinary"]
    text = data.decode("utf-8", "replace")
    try:
        lists = json_lists(json.loads(text))
    except ValueError:
        lists = line_list(text)
    base = posixpath.dirname(norm)
    best = None
    for locator, entries, words in lists:
        if len(entries) < MIN_ENTRIES:
            continue
        hits = [any(names_path(w, base, names) for w in ws) for ws in words]
        key = (sum(hits) / len(hits), len(hits))
        if best is None or key > best[0]:
            best = (key, locator, entries, hits)
    if best is None:
        return [f"no-list\t0\t0\t{esc(norm)}\t-"]
    (share, total), locator, entries, hits = best
    kind = "candidate" if share >= THRESHOLD else "below"
    rows = [f"{kind}\t{sum(hits)}\t{total}\t{esc(norm)}\t{esc(locator)}"]
    if kind == "candidate":
        for entry, hit in zip(entries, hits):
            if not hit:
                shown = json.dumps(entry)[:200]
                rows.append(f"unnamed\t{esc(norm)}\t{esc(locator)}\t{shown}")
    return rows


def main(argv: list[str] | None = None) -> int:
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(
            encoding="utf-8", errors="backslashreplace", newline="\n"
        )
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument("--root", default=".")
    parser.add_argument("--paths-from", metavar="FILE")
    parser.add_argument("paths", nargs="*", metavar="PATH")
    args = parser.parse_args(argv)
    paths = list(args.paths)
    try:
        if args.paths_from == "-":
            paths += sys.stdin.read().splitlines()
        elif args.paths_from is not None:
            with open(args.paths_from, encoding="utf-8") as fh:
                paths += fh.read().splitlines()
        paths = [p for p in paths if p]
        if not paths:
            raise UsageError("no PATH given")
        files, names = tree(args.root)
    except (UsageError, OSError, UnicodeDecodeError) as exc:
        print(f"derivable-list: {exc}", file=sys.stderr)
        return 2
    for rel in paths:
        for row in check(rel, args.root, files, names):
            print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
