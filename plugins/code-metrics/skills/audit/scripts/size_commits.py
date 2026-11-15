#!/usr/bin/env python3
"""Commit counts for the files a size report lists at or above the reference.

  size_commits.py add --since <date> <report.json>   add `file_commits` to the document, in place
  size_commits.py render <report.json>               print the markdown section for it

`add` counts, per file row whose `over_reference` names `file_lines`, the
commits since <date> (anything `git log --since` accepts) that touched the
file, under its earlier names too, leaving out commits whose author name
contains `[bot]`. It counts and
ranks; it sets no cutoff. Exit 2 when the report's root is not a git
repository or git refuses the date.
"""

from __future__ import annotations

import json
import subprocess
import sys

BOT_MARK = "[bot]"


def _count(root: str, since: str, path: str) -> int:
    result = subprocess.run(
        [
            "git",
            "-C",
            root,
            "log",
            "--follow",
            f"--since={since}",
            "--format=%an",
            "--",
            path,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "git log failed")
    return sum(
        1 for author in result.stdout.splitlines() if author and BOT_MARK not in author
    )


def add(document: dict, since: str) -> dict:
    root = document.get("root") or {}
    if root.get("kind") != "repository":
        raise RuntimeError("--commits-since needs a git repository")
    rows = []
    for row in document.get("measures", []):
        if row.get("function") is not None or not row.get("file"):
            continue
        if "file_lines" not in (row.get("over_reference") or []):
            continue
        rows.append(
            {
                "file": row["file"],
                "lines_non_blank": (row.get("values") or {}).get("lines_non_blank"),
                "commits": _count(root["path"], since, row["file"]),
            }
        )
    rows.sort(key=lambda r: (-r["commits"], -(r["lines_non_blank"] or 0), r["file"]))
    document["file_commits"] = {"since": since, "excludes": BOT_MARK, "rows": rows}
    return document


def render(document: dict) -> str:
    block = document.get("file_commits")
    if not block:
        return ""
    lines = [
        "",
        "## Commits to files at or above the reference",
        "",
        f"Since {block['since']}, authors containing `{block['excludes']}` left out. "
        "A count to rank by, never a bar.",
        "",
    ]
    if not block["rows"]:
        lines.append("No file is at or above the reference.")
        return "\n".join(lines)
    lines += ["| File | lines_non_blank | Commits |", "|---|---|---|"]
    lines += [
        f"| {r['file']} | {r['lines_non_blank']} | {r['commits']} |"
        for r in block["rows"]
    ]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    try:
        if len(argv) == 4 and argv[0] == "add" and argv[1] == "--since":
            with open(argv[3], encoding="utf-8") as handle:
                document = add(json.load(handle), argv[2])
            with open(argv[3], "w", encoding="utf-8") as handle:
                json.dump(document, handle, indent=2)
            return 0
        if len(argv) == 2 and argv[0] == "render":
            with open(argv[1], encoding="utf-8") as handle:
                print(render(json.load(handle)))
            return 0
    except RuntimeError as exc:
        print(f"size_commits.py: {exc}", file=sys.stderr)
        return 2
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
