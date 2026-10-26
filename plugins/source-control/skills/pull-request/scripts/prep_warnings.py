#!/usr/bin/env python3
"""Prep's advisory warnings, run through prep-warnings.sh before the first push.

Reads the working tree against the merge base of `--base` and HEAD (committed,
staged, unstaged and untracked changes alike) and prints one line per finding:

  skill-cut <path>: an existing SKILL.md or agent body loses lines and no file
    under its eval home is added or changed in the same diff (a deletion is no
    evidence): the skill's `evals/` for a
    SKILL.md, the plugin's `evals/` for an agent body. The skill criteria ship
    a cut only with eval evidence of no loss.
  protected-path <path>: a changed path in `babysit_risk.HIGH_FLOOR` or the
    configured `merge.diff-check.denied-paths` (`--denied-path`), which the
    guarded merge holds for a person, or a plugin or marketplace manifest
    (`babysit_risk.is_manifest_path`), which it compares base against head.
    The path rules are imported from babysit_risk, never restated.
  note: a configured denied-path set the merge cannot read, so it matches only
    the floor.

Exit 0 when read, whatever it found; 2 when git cannot read the diff.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "babysit-prs" / "scripts"))
import babysit_risk as risk  # noqa: E402


class GitError(Exception):
    pass


def git(*args: str) -> str:
    proc = subprocess.run(
        ["git", *args], capture_output=True, encoding="utf-8", errors="replace"
    )
    if proc.returncode != 0:
        raise GitError(f"git {args[0]} exited {proc.returncode}: {proc.stderr.strip()}")
    return proc.stdout


def changes(base: str) -> dict[str, tuple[str, int]]:
    """Each changed path -> (status letter, removed lines)."""
    merge_base = git("merge-base", base, "HEAD").strip()
    found: dict[str, tuple[str, int]] = {}
    names = git("diff", "-z", "--no-renames", "--name-status", merge_base, "--").split("\0")
    for status, path in zip(names[0::2], names[1::2]):
        found[path] = (status[:1], 0)
    for record in git("diff", "-z", "--no-renames", "--numstat", merge_base, "--").split("\0"):
        parts = record.split("\t", 2)
        if len(parts) == 3 and parts[2] in found:
            removed = int(parts[1]) if parts[1].isdigit() else 0
            found[parts[2]] = (found[parts[2]][0], removed)
    for path in git("ls-files", "-z", "--others", "--exclude-standard").split("\0"):
        if path:
            found.setdefault(path, ("A", 0))
    return found


def eval_home(path: str) -> str | None:
    """The eval directory a cut to `path` needs evidence in, None when `path`
    is no SKILL.md or agent body."""
    parts = path.split("/")
    if parts[0] != "plugins":
        return None
    if len(parts) == 5 and parts[2] == "skills" and parts[4] == "SKILL.md":
        return "/".join(parts[:4]) + "/evals/"
    if len(parts) == 4 and parts[2] == "agents" and parts[3].endswith(".md"):
        return f"plugins/{parts[1]}/evals/"
    return None


def skill_cuts(found: dict[str, tuple[str, int]]) -> list[str]:
    lines = []
    for path, (status, removed) in sorted(found.items()):
        home = eval_home(path)
        if home is None or status == "A" or removed == 0:
            continue
        if not any(
            other.startswith(home) and found[other][0] != "D" for other in found
        ):
            lines.append(
                f"skill-cut {path}: {removed} line(s) removed with no file added or"
                f" changed under {home}; a cut ships only with eval evidence of no loss"
            )
    return lines


def protected_paths(paths: list[str], denied: list[str]) -> list[str]:
    problems: list[str] = []
    # The merge's own reading of the configured set: an unreadable one matches
    # only the floor.
    configured = risk._readable_globs(denied, problems)
    lines = [f"note: {problem}; only the floor is matched" for problem in problems]
    patterns = tuple(dict.fromkeys((*risk.HIGH_FLOOR, *configured)))
    for path in sorted(paths):
        normalized, _ = risk.normalize_path(path)
        hits = [f"high-path:{p}" for p in patterns if risk.glob_match(p, normalized)]
        if hits:
            lines.append(
                f"protected-path {path}: the guarded merge holds it for a person"
                f" ({'; '.join(hits)})"
            )
        elif risk.is_manifest_path(normalized):
            lines.append(
                f"protected-path {path}: a manifest the guarded merge compares base"
                " against head, holding it when an executable key or plugin entry"
                " changes"
            )
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Prep's advisory warnings.")
    parser.add_argument("--base", required=True)
    parser.add_argument("--denied-path", action="append", default=[])
    args = parser.parse_args(argv)
    try:
        found = changes(args.base)
    except GitError as exc:
        print(f"prep-warnings: {exc}", file=sys.stderr)
        return 2
    for line in [*skill_cuts(found), *protected_paths(list(found), args.denied_path)]:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
