"""Name the changed files a review can leave out: those whose change is proven
comment-only. Deleted comments live in git history only (#19088), so such a
file gives a reviewer nothing to judge.

usage: comment_only.py <base-sha> <head-sha>   (run inside the repository)

Reads candidate paths on stdin, one per line, and prints, one per line in
input order, those that qualify. A path qualifies only when all hold:

  - it is modified in place with one file mode on both sides, regular or
    executable (`:100644 100644 ... M` or `:100755 100755 ... M` in
    `git diff --raw --no-renames`);
  - code-tidying's change-shape.py `classify()` says COMMENT-ONLY or
    DOCSTRING-ONLY for its base and head blobs, through a tree-sitter grammar
    change-shape maps to its extension;
  - no removed or added line of its diff holds a DIRECTIVES token, and no
    line is both removed and added (trailing whitespace aside). change-shape
    keeps the code lines equal, so a diff that does not move one leaves every
    directive line where it was relative to the code;
  - no hunk touches the line right after a directive line, where a next-line
    directive would apply.

Exit 0 when the check ran, whether or not any path qualified; 2 usage. Any
other failure prints nothing on stdout and exits 1, so a caller keeps every
file in the review.
"""

from __future__ import annotations

import importlib.util
import re
import subprocess
import sys
import traceback
from pathlib import Path
from typing import NamedTuple

CHANGE_SHAPE = (
    Path(__file__).resolve().parents[3]
    / "plugins"
    / "code-tidying"
    / "scripts"
    / "change-shape.py"
)

DIRECTIVES = (
    "shellcheck",
    "noqa",
    "type: ignore",
    "type:ignore",
    "pyright:",
    "pylint:",
    "mypy:",
    "eslint-",
    "@ts-",
    "prettier-ignore",
    "biome-ignore",
    "nolint",
    "rubocop:",
    "istanbul ignore",
    "c8 ignore",
    "pragma",
    "coding:",
    "coding=",
    "#!",
    "#requires",
    "nosec",
    "nosemgrep",
    "gitleaks:allow",
    "codeql",
    "suppressmessage",
)
PROVEN = ("COMMENT-ONLY", "DOCSTRING-ONLY")
FILE_MODES = ("100644", "100755")


def load_change_shape():
    spec = importlib.util.spec_from_file_location("change_shape", CHANGE_SHAPE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {CHANGE_SHAPE}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(*args: str, data: bytes | None = None) -> bytes:
    proc = subprocess.run(["git", *args], input=data, capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(
            f"git {args[0]} exited {proc.returncode}: "
            f"{proc.stderr.decode(errors='replace').strip()[:300]}"
        )
    return proc.stdout


def modified_in_place(base: str, head: str) -> dict[str, tuple[str, str]]:
    """Path -> (base blob, head blob) for each regular file modified in place."""
    out = git("diff", "--raw", "-z", "--no-abbrev", "--no-renames", base, head, "--")
    fields = out.split(b"\0")
    found: dict[str, tuple[str, str]] = {}
    for i in range(0, len(fields) - 1, 2):
        meta, path = (
            fields[i].decode(),
            fields[i + 1].decode("utf-8", "surrogateescape"),
        )
        old_mode, new_mode, old_sha, new_sha, status = meta.lstrip(":").split(" ")
        if status == "M" and old_mode == new_mode and old_mode in FILE_MODES:
            found[path] = (old_sha, new_sha)
    return found


def read_blobs(shas: set[str]) -> dict[str, bytes]:
    """Every blob through one `git cat-file --batch` process."""
    order = sorted(shas)
    out = git("cat-file", "--batch", data="".join(f"{s}\n" for s in order).encode())
    blobs: dict[str, bytes] = {}
    at = 0
    for sha in order:
        end = out.index(b"\n", at)
        header = out[at:end].decode().split(" ")
        if len(header) != 3 or header[0] != sha or header[1] != "blob":
            raise RuntimeError(f"cat-file answered {header!r} for {sha}")
        size = int(header[2])
        blobs[sha] = out[end + 1 : end + 1 + size]
        at = end + 1 + size + 1
    return blobs


class Diff(NamedTuple):
    """One file's removed and added lines, each with its `-` or `+`, and the
    1-based numbers of the lines each side's hunks touch."""

    lines: list[bytes]
    base_touched: set[int]
    head_touched: set[int]


HUNK = re.compile(rb"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def changed_lines(
    base: str, head: str, paths: list[str]
) -> dict[tuple[str, str], Diff]:
    """(base blob, head blob) -> that file's Diff.

    Keyed by blob pair from `--full-index`, so no path in a header is parsed.
    A file whose diff has no hunk maps to None, which never qualifies."""
    if not paths:
        return {}
    patch = git(
        "--literal-pathspecs",
        "diff",
        "--no-color",
        "--no-ext-diff",
        "--no-textconv",
        "--no-renames",
        "--text",
        "--full-index",
        "--unified=0",
        base,
        head,
        "--",
        *paths,
    )
    found: dict[tuple[str, str], Diff | None] = {}
    key = None
    in_hunk = False
    for line in patch.split(b"\n"):
        if line.startswith(b"diff --git "):
            key, in_hunk = None, False
        elif key is None and line.startswith(b"index ") and not in_hunk:
            pair = line.split(b" ")[1].decode().split("..")
            key = (pair[0], pair[1])
            found[key] = None
        elif line.startswith(b"@@") and key is not None:
            in_hunk = True
            diff = found[key] = found[key] or Diff([], set(), set())
            a, b, c, d = HUNK.match(line).groups()
            diff.base_touched.update(range(int(a), int(a) + int(b or 1)))
            diff.head_touched.update(range(int(c), int(c) + int(d or 1)))
        elif in_hunk and line[:1] in (b"-", b"+"):
            found[key].lines.append(line)
    return found


def holds_directive(line: bytes) -> bool:
    text = line.decode("utf-8", "replace").lower()
    return any(token in text for token in DIRECTIVES)


def touches_after_directive(blob: bytes, touched: set[int]) -> bool:
    """Whether a hunk touches the line right after a directive, which a
    next-line directive (`eslint-disable-next-line`, `@ts-expect-error`)
    would then apply to differently. A first-line shebang has no such scope."""
    return any(
        n + 1 in touched
        for n, line in enumerate(blob.split(b"\n"), 1)
        if holds_directive(line) and not (n == 1 and line.startswith(b"#!"))
    )


def moves_a_line(lines: list[bytes]) -> bool:
    """Whether one non-blank line is both removed and added: a move, which can
    carry a directive past code while the directive line itself stays put."""
    removed = {line[1:].rstrip() for line in lines if line[:1] == b"-"}
    added = {line[1:].rstrip() for line in lines if line[:1] == b"+"}
    return bool((removed & added) - {b""})


def qualifying(base: str, head: str, candidates: list[str]) -> list[str]:
    shape = load_change_shape()
    modified = modified_in_place(base, head)
    mapped = []
    for path in candidates:
        entry = shape.EXT_LANG.get(Path(path).suffix.lower())
        if path in modified and entry is not None and entry[1] is not None:
            mapped.append((path, entry))
    if not mapped:
        return []
    blobs = read_blobs({sha for path, _ in mapped for sha in modified[path]})
    diffs = changed_lines(base, head, [path for path, _ in mapped])
    grammars: dict[str, object] = {}
    proven = []
    for path, entry in mapped:
        if entry[0] not in grammars:
            grammars[entry[0]] = shape.language_for(*entry)[0]
        lang = grammars[entry[0]]
        pair = modified[path]
        diff = diffs.get(pair)
        if lang is None or diff is None or moves_a_line(diff.lines):
            continue
        if any(holds_directive(line[1:]) for line in diff.lines):
            continue
        before, after = blobs[pair[0]], blobs[pair[1]]
        if touches_after_directive(before, diff.base_touched):
            continue
        if touches_after_directive(after, diff.head_touched):
            continue
        python = entry[0] == "python"
        if shape.classify(before, after, lang, docstrings=python)[0] in PROVEN:
            proven.append(path)
    return proven


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    try:
        lines = sys.stdin.read().splitlines()
        candidates = list(dict.fromkeys(line for line in lines if line))
        proven = qualifying(argv[0], argv[1], candidates)
    except Exception:  # noqa: BLE001 - any failure must keep every file in the review
        print("comment-only: check failed; no file is left out", file=sys.stderr)
        traceback.print_exc()
        return 1
    sys.stdout.write("".join(f"{p}\n" for p in proven))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
