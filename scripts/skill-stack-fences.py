#!/usr/bin/env python3
"""Count the stack-specific code fences in shipped skill and agent bodies.

    skill-stack-fences.py

Run from the repository root. Prints one `<path> fences=<n>` line per file
with a count above 0, sorted by path, which the per-file `skill-stack-fences`
row of .performance/ratchets.json reads. Shipped skills carry no
ecosystem-specific examples (docs/plugin-philosophy.md, "Hardcoded consumer
specifics"); the ratchet stops the count of fences that show one stack from
growing while the existing ones are cut.

The scope: tracked `.md` files under `plugins/<plugin>/skills/` and
`plugins/<plugin>/agents/`, except those under a directory named evals, tests,
test, __tests__, fixtures, testdata or vendor (eval inputs, test data, and
upstream copies a sync replaces).

A fence counts when its info string's first word, lowercased with `{`, `.` and
`}` stripped, is not in EXCLUDED_TAGS: shells the agent runs commands through,
data and prose formats a skill reads or emits, diagrams, the skill pre-compute
block (`!`), and the queries and patterns skills run against their own data
(sql, regex). Every other tag counts, so a new language is counted without an
edit here. An untagged fence does not count. Fences follow CommonMark: an
opening run of three or more backticks or tildes at any indent, closed by a
run of the same character at least as long with nothing after it; a fence
inside another fence is content and does not count.

Exit 0 with the lines printed; 2 when git cannot list files or no file is in
scope, because a count of nothing would pass any ceiling.
"""

from __future__ import annotations

import re
import subprocess
import sys

MIN_PYTHON = (3, 9)
AGENT_SHELLS = "bash sh shell zsh console powershell pwsh ps1 batch bat cmd"
DATA_AND_PROSE = (
    "text txt plaintext markdown md json jsonc jsonl yaml yml toml ini csv diff"
)
DIAGRAMS_AND_CONFIG = "mermaid gitconfig"
PRECOMPUTE_BLOCK = "!"
OWN_DATA_QUERIES = "sql regex"
EXCLUDED_TAGS = frozenset(
    " ".join(
        (
            AGENT_SHELLS,
            DATA_AND_PROSE,
            DIAGRAMS_AND_CONFIG,
            PRECOMPUTE_BLOCK,
            OWN_DATA_QUERIES,
        )
    ).split()
)
SKIPPED_DIRS = frozenset(
    {"evals", "tests", "test", "__tests__", "fixtures", "testdata", "vendor"}
)
OPENING = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")


def fail(message: str) -> int:
    print(f"skill-stack-fences: {message}", file=sys.stderr)
    return 2


def in_scope(path: str) -> bool:
    parts = path.split("/")
    return (
        len(parts) >= 4
        and parts[0] == "plugins"
        and parts[2] in ("skills", "agents")
        and path.endswith(".md")
        and not SKIPPED_DIRS.intersection(parts[3:-1])
    )


def tag_of(info: str) -> str:
    words = info.split()
    return words[0].strip("{}.").lower() if words else ""


def count_fences(text: str) -> int:
    count = 0
    fence = ""
    for line in text.splitlines():
        match = OPENING.match(line)
        if fence:
            if (
                match
                and match.group(1)[0] == fence[0]
                and len(match.group(1)) >= len(fence)
                and not match.group(2).strip()
            ):
                fence = ""
            continue
        if not match:
            continue
        marker, info = match.groups()
        if marker[0] == "`" and "`" in info:
            continue
        fence = marker
        tag = tag_of(info)
        if tag and tag not in EXCLUDED_TAGS:
            count += 1
    return count


def main() -> int:
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--", "plugins/"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if listed.returncode != 0:
        return fail(f"git ls-files failed: {listed.stderr.strip()}")
    paths = sorted(p for p in listed.stdout.split("\0") if p and in_scope(p))
    if not paths:
        return fail("no skill or agent markdown in scope")
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            count = count_fences(handle.read())
        if count:
            print(f"{path} fences={count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
