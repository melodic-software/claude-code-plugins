#!/usr/bin/env python3
"""Fail on a markdown `path:N` or `path:N-M` citation past the end of the cited file.

A citation such as `docs/foo.md:269-271` goes stale when the cited file
shrinks. Review bots flag the mechanical case, a line number past the end of
the file, again and again; this gate catches it before review does.

WHAT FIRES. In a tracked markdown file, a token `PATH:SPEC` where SPEC is one or
more comma-separated `N` or `N-M` line numbers, PATH resolves to a tracked file
(relative to the repository root or to the citing file's directory), and some
cited number exceeds that file's line count. When PATH resolves against both
bases, the citation fires only when it is past the end of every candidate.

WHAT STAYS QUIET, by construction:

  * a PATH that resolves to no tracked file: a missing file is another check's
    job, and a bare basename (`ci.yml:2639`), a time (`10:30`) or a host and
    port (`localhost:8080`) resolves to nothing;
  * a URL (`https://host:8080/x.md:12`) and an external-repository citation
    (`owner/repo:path.md:12`), because a token preceded by `:` or `/` is part
    of something larger and is never matched from its middle;
  * a citation inside a fenced code block: fences hold sample output and
    illustrative rows (`path/to/file.cs:42`), not claims about this tree;
  * a point-in-time record (an ADR, a `docs/upstream/` decision record, a
    CHANGELOG or a `.changes/` fragment): it cites the tree as it was when
    written, and rewriting its line numbers later would falsify the record;
  * whether the cited line still says what the citation claims: semantic drift
    is not mechanical, and is left to review.

The scan covers every tracked markdown file, not only a pull request's changed
files, because the usual way a citation goes stale is a change to the CITED
file that never touches the citing one.

Usage:

    scripts/check-line-citations.py

Exit codes: 0 clean, 1 at least one citation past the end, 2 could not run.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

# `from __future__ import annotations` needs 3.7; the .test.sh wrapper parses
# this tuple to pick an interpreter.
MIN_PYTHON = (3, 7)

REPO_ROOT = Path(__file__).resolve().parent.parent

# PATH:SPEC. The lookbehind keeps a token that continues a URL, an
# `owner/repo:` prefix or a longer word from matching from its middle; the
# lookahead stops `file.md:12.5`, `file.md:12:3` and `file.md:12abc` from
# reading as line 12.
CITATION = re.compile(
    r"(?<![\w./@:~-])"
    r"(?P<path>[\w.@-]+(?:/[\w.@-]+)*)"
    r":(?P<spec>\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)"
    r"(?![\w.:/-]*\w)"
)

FENCE = re.compile(r"^\s*(`{3,}|~{3,})")

# Point-in-time records, by repository-relative prefix or by basename.
RECORD_PREFIXES = ("docs/adr/", "docs/upstream/", ".changes/")
RECORD_NAMES = frozenset({"CHANGELOG.md"})


def is_record(path: str) -> bool:
    return path.startswith(RECORD_PREFIXES) or Path(path).name in RECORD_NAMES


def line_count(path: Path, cache: dict) -> int:
    if path not in cache:
        data = path.read_bytes()
        cache[path] = data.count(b"\n") + (0 if not data or data.endswith(b"\n") else 1)
    return cache[path]


def candidates(cited: str, citing: Path, tracked: set) -> list:
    out = []
    for base in (REPO_ROOT, (REPO_ROOT / citing).parent):
        target = (base / cited).resolve()
        try:
            rel = target.relative_to(REPO_ROOT).as_posix()
        except ValueError:
            continue
        if rel in tracked and target not in out:
            out.append(target)
    return out


def scan(citing: Path, tracked: set, cache: dict) -> list:
    findings = []
    fence = ""
    text = (REPO_ROOT / citing).read_text(encoding="utf-8", errors="replace")
    for lineno, line in enumerate(text.splitlines(), 1):
        opener = FENCE.match(line)
        if opener:
            run = opener[1]
            if not fence:
                fence = run
            elif (
                run[0] == fence[0]
                and len(run) >= len(fence)
                and not line.strip()[len(run) :]
            ):
                fence = ""
            continue
        if fence:
            continue
        for match in CITATION.finditer(line):
            targets = candidates(match["path"], citing, tracked)
            if not targets:
                continue
            highest = max(int(n) for n in re.split(r"[-,]", match["spec"]))
            longest = max(line_count(t, cache) for t in targets)
            if highest > longest:
                findings.append(
                    f"{citing.as_posix()}:{lineno}: `{match[0]}` cites line {highest}, "
                    f"but {targets[0].relative_to(REPO_ROOT).as_posix()} has {longest} lines"
                )
    return findings


def main() -> int:
    try:
        listed = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "ls-files", "-z"],
            check=True,
            capture_output=True,
        ).stdout.decode("utf-8")
    except (OSError, subprocess.CalledProcessError) as exc:
        print(
            f"check-line-citations: cannot list tracked files: {exc}", file=sys.stderr
        )
        return 2
    tracked = {p for p in listed.split("\0") if p and (REPO_ROOT / p).is_file()}
    files = sorted(Path(p) for p in tracked if p.endswith(".md") and not is_record(p))
    cache: dict = {}
    findings = [f for path in files for f in scan(path, tracked, cache)]
    for finding in findings:
        print(finding)
    if findings:
        print(
            f"check-line-citations: {len(findings)} citation(s) past the end of the cited file; "
            "update the line numbers or drop them.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
