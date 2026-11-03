#!/usr/bin/env python3
"""Lift evidence for canary, revert and read-back demotion records.

`canary-block` and `revert-block` print the lift block
(`babysit_merge_policy.lift_block`) that post-merge-demotion-alert.yml writes
into a record it files: the lines the silent-revert canary attributes to a
culprit in the pushed commits (`scripts/check-silent-revert.sh`'s
DELETED_SINK), or the lines the revert commits deleted. Exit 0 with the block
on stdout; 1 when no block can be written (the scan could not run, a path is
unusable, or the block is over `LIFT_BLOCK_LIMIT`).

`close` closes each open canary, revert or read-back record that has lifted
by the merge gate's own rule (`babysit_merge_policy._lift`): a comment naming
the evidence, the human-gated role label removed, closed as completed. A
record that has not lifted, or whose read fails, is left as it is.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from collections.abc import Iterator
from pathlib import Path
from urllib.parse import quote

import babysit_merge_policy as policy
import babysit_postmerge as postmerge


def _git(repo_dir: str, *args: str) -> bytes:
    return subprocess.run(
        ["git", "-C", repo_dir, *args], check=True, capture_output=True
    ).stdout


def canary_lines(repo_dir: str, commits: list[str]) -> list[tuple[str, bytes]]:
    """`(path, line)` for each line `repo_dir`'s own canary
    (`scripts/check-silent-revert.sh`, which scans the repository it sits in)
    attributes to a culprit in `commits`, scanned one at a time. Raises when a
    scan cannot run (exit 2) or the sink names a line it cannot parse."""
    lines: list[tuple[str, bytes]] = []
    # Absolute: the scan runs with `repo_dir` as its working directory.
    script = str(Path(repo_dir).resolve() / "scripts/check-silent-revert.sh")
    with tempfile.TemporaryDirectory() as tmp:
        sink = Path(tmp) / "deleted"
        for commit in commits:
            sink.write_bytes(b"")
            proc = subprocess.run(
                ["bash", script, "--commit", commit],
                cwd=repo_dir,
                env=os.environ | {"DELETED_SINK": str(sink)},
                capture_output=True,
                check=False,
            )
            if proc.returncode not in (0, 1):
                tail = proc.stderr.decode("utf-8", "replace").strip()[-300:]
                raise RuntimeError(f"the canary could not scan {commit}: {tail}")
            for record in sink.read_bytes().split(b"\n"):
                if not record:
                    continue
                parts = record.split(b"\t", 2)
                if len(parts) != 3:
                    raise RuntimeError(f"an unreadable sink line for {commit}")
                lines.append((parts[1].decode("utf-8"), parts[2]))
    return lines


def _deleted(diff: bytes) -> Iterator[tuple[str, bytes]]:
    """`(path, line)` for each deleted line of a `git diff -U0` patch."""
    path = None
    in_hunk = False
    for line in diff.split(b"\n"):
        if line.startswith(b"diff --git "):
            path, in_hunk = None, False
        elif not in_hunk and line.startswith(b"--- "):
            name = line[4:]
            if name.startswith(b'"'):
                raise RuntimeError("a quoted path")
            path = name[2:].decode("utf-8") if name.startswith(b"a/") else None
        elif line.startswith(b"@@"):
            in_hunk = True
        elif in_hunk and line.startswith(b"-") and path is not None:
            yield path, line[1:]


def revert_lines(repo_dir: str, commits: list[str]) -> list[tuple[str, bytes]]:
    """`(path, line)` for each line the revert `commits` deleted against
    their first parent."""
    lines: list[tuple[str, bytes]] = []
    for commit in commits:
        diff = _git(
            repo_dir,
            "-c",
            "core.quotePath=false",
            "diff",
            "--no-ext-diff",
            "--no-textconv",
            "--no-renames",
            "--diff-algorithm=myers",
            "--src-prefix=a/",
            "--dst-prefix=b/",
            "-U0",
            f"{commit}^1",
            commit,
        )
        lines += _deleted(diff)
    return lines


def _api(*args: str) -> subprocess.CompletedProcess[str]:
    return policy.gh_capture(["api", *args])


def close_lifted(repo: str, identity: str | None) -> int:
    """Close each open record of either filer that has lifted; returns the
    number closed."""
    owner, name = policy._split_repo(repo)
    filers = [policy.DEMOTION_FILER, *([identity] if identity else [])]
    permission = policy.permission_reader(repo)

    def human(actor: object) -> bool:
        return policy.is_human(
            actor, repo=repo, agent_identity=identity, permission=permission
        )

    green = policy._GreenMain(owner, name)
    label = postmerge._role_label(owner, name)
    closed = 0
    seen: set[int] = set()
    for filer in filers:
        listing = _api(
            "--paginate",
            f"repos/{owner}/{name}/issues?state=open&creator={quote(filer)}&per_page=100",
            "--jq",
            ".[] | select(.pull_request == null) | {number, body}",
        )
        if listing.returncode != 0:
            print(f"::warning::could not read {filer}'s open records: none of them closed")
            continue
        for row in filter(None, listing.stdout.split("\n")):
            issue = json.loads(row)
            number = issue.get("number")
            first = str(issue.get("body") or "").lstrip().split("\n", 1)[0].rstrip()
            if (
                not isinstance(number, int)
                or number in seen
                or not policy.LIFTABLE_RECORD.fullmatch(first)
            ):
                continue
            seen.add(number)
            try:
                data = policy._graphql(
                    policy.DEMOTION_RECORD, f"issue #{number}", o=owner, r=name, n=number
                )
                record = policy.json_object(
                    policy.json_object(data.get("repository")).get("issue")
                )
                lift = policy._lift(record, human, green, identity)
            except policy.PolicyReadError as exc:
                print(f"#{number}: could not read its lift evidence ({exc}): left open")
                continue
            if lift is None:
                print(f"#{number}: has not lifted")
                continue
            comment = _api(
                "-X",
                "POST",
                f"repos/{owner}/{name}/issues/{number}/comments",
                "-f",
                "body="
                + (f"{policy.lift_evidence(lift.evidence)}\n" if lift.evidence else "")
                + f"This record lifted: {lift.why}. The lane closed it by the merge "
                "gate's own rule (babysit_merge_policy.py `_lift`).",
            )
            # The comment is the lift's evidence pin: without it the record
            # stays open and labeled for the next run to retry.
            if comment.returncode:
                print(f"::warning::could not comment on #{number}: left open")
                continue
            unlabel = _api(
                "-X",
                "DELETE",
                f"repos/{owner}/{name}/issues/{number}/labels/{quote(label, safe='')}",
            )
            close = _api(
                "-X",
                "PATCH",
                f"repos/{owner}/{name}/issues/{number}",
                "-f",
                "state=closed",
                "-f",
                "state_reason=completed",
            )
            if close.returncode:
                print(f"::warning::could not close #{number}")
                continue
            if unlabel.returncode and policy.gh_http_status(unlabel.stderr or "") != 404:
                print(f"::warning::could not remove {label} from #{number}")
            print(f"closed #{number}: {lift.why}")
            closed += 1
    return closed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="babysit_lift.py", allow_abbrev=False)
    sub = parser.add_subparsers(dest="action", required=True)
    for action in ("canary-block", "revert-block"):
        block = sub.add_parser(action, allow_abbrev=False)
        block.add_argument("--repo-dir", required=True)
        block.add_argument("commits", nargs="+")
    close = sub.add_parser("close", allow_abbrev=False)
    close.add_argument("--repo", required=True)
    close.add_argument("--identity", default="")
    args = parser.parse_args(argv)
    if args.action == "close":
        close_lifted(args.repo, args.identity.strip() or None)
        return 0
    try:
        lines = (canary_lines if args.action == "canary-block" else revert_lines)(
            args.repo_dir, args.commits
        )
    except (RuntimeError, OSError, UnicodeDecodeError, subprocess.CalledProcessError) as exc:
        print(f"no lift block: {exc}", file=sys.stderr)
        return 1
    block_line = policy.lift_block(lines)
    if block_line is None:
        print("no lift block: a path is unusable or the block is too large", file=sys.stderr)
        return 1
    print(block_line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
