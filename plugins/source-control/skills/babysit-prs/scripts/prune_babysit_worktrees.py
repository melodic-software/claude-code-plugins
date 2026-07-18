#!/usr/bin/env python3
"""Prune clean ephemeral worktrees created by the babysit-prs skill."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import babysit_lease as leases
from babysit_gh import parse_repo_number
from babysit_state import resolve_state_dir, state_lock
from babysit_util import configure_stdio, run_command

WORKTREE_RE = re.compile(r"^(?P<owner>.+?)__(?P<repo>.+?)__pr-(?P<number>\d+)$")
ALLOWED_EXECUTABLES = ("git", "gh", "ghq")


@dataclass
class Worktree:
    path: Path
    owner: str
    repo: str
    number: int

    @property
    def full_repo(self) -> str:
        return f"{self.owner}/{self.repo}"

    @property
    def key(self) -> str:
        return f"{self.full_repo}#{self.number}"


def run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run_command(argv, allowed_executables=ALLOWED_EXECUTABLES, check=check)


def resolve_root(value: str | None) -> Path:
    """Resolve the required --root worktree root; flag-only by design.

    There is deliberately no default and no environment fallback. Empty and
    filesystem-root paths are hard errors -- both indicate a broken caller, and
    a root path would let worktree removal escape into arbitrary directories.
    """
    if value is None or not str(value).strip():
        raise ValueError("--root is required and must not be empty")
    path = Path(str(value)).expanduser()
    resolved = path.resolve()
    if resolved.parent == resolved:
        raise ValueError(f"--root must not be a filesystem root: {value}")
    return path


def repo_path(owner: str, repo: str) -> Path:
    # Prefer ghq so non-default roots (and prompt-configured reposRoot) resolve correctly.
    proc = run(["ghq", "list", "-p", f"{owner}/{repo}"], check=False)
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    if lines:
        return Path(lines[0])

    proc = run(["git", "config", "--get", "ghq.root"], check=False)
    root = (proc.stdout or "").strip()
    if root:
        return Path(root) / "github.com" / owner / repo

    raise RuntimeError(
        f"unable to resolve main checkout for {owner}/{repo}; install ghq or set ghq.root"
    )


def iter_worktrees(root: Path) -> list[Worktree]:
    if not root.exists():
        return []
    found: list[Worktree] = []
    for child in root.iterdir():
        if not child.is_dir():
            continue
        match = WORKTREE_RE.match(child.name)
        if not match:
            continue
        found.append(
            Worktree(
                path=child,
                owner=match.group("owner"),
                repo=match.group("repo"),
                number=int(match.group("number")),
            )
        )
    return found


def git_status(path: Path) -> list[str]:
    proc = run(["git", "-C", str(path), "status", "--short", "--branch"])
    return [line for line in proc.stdout.splitlines() if line.strip()]


def is_dirty(status: list[str]) -> bool:
    return any(not line.startswith("## ") for line in status)


def pr_state(worktree: Worktree) -> dict[str, str]:
    proc = run(
        [
            "gh",
            "pr",
            "view",
            str(worktree.number),
            "--repo",
            worktree.full_repo,
            "--json",
            "state,headRefOid,headRefName,url",
        ]
    )
    data = json.loads(proc.stdout)
    state = str(data.get("state") or "").upper()
    if state not in {"OPEN", "CLOSED", "MERGED"}:
        raise RuntimeError(
            f"unexpected PR state {state or 'MISSING'} for {worktree.key}"
        )
    return {
        "state": state,
        "headRefOid": str(data.get("headRefOid") or ""),
        "headRefName": str(data.get("headRefName") or ""),
        "url": str(data.get("url") or ""),
    }


def remove_worktree(worktree: Worktree, root: Path) -> None:
    main_repo = repo_path(worktree.owner, worktree.repo)
    if not main_repo.exists():
        raise RuntimeError(f"main repo missing for {worktree.key}: {main_repo}")
    resolved = worktree.path.resolve()
    allowed_root = root.resolve()
    if allowed_root not in resolved.parents:
        raise RuntimeError(
            f"refusing to remove worktree outside babysit root: {resolved}"
        )
    run(["git", "-C", str(main_repo), "worktree", "remove", str(worktree.path)])


def active_worker_lease(
    worktree: Worktree, state_dir: Path
) -> dict[str, object] | None:
    path = leases.lease_path(state_dir, "worker", worktree.key)
    current = leases.load_lease(path)
    if not current or leases.lease_expiry(current) <= datetime.now(UTC):
        return None
    return current


def main() -> int:
    configure_stdio()
    parser = argparse.ArgumentParser(description="Prune babysit-prs Git worktrees.")
    parser.add_argument(
        "--root",
        required=True,
        help="babysit-prs worktree root (required; no default or environment fallback)",
    )
    parser.add_argument("--pr", help="limit cleanup to one owner/repo#number")
    parser.add_argument(
        "--state-dir",
        required=True,
        help=(
            "Durable state directory for worker leases. Required: state-dir "
            "resolution is flag-only, with no environment fallback."
        ),
    )
    parser.add_argument(
        "--lease-token",
        help="worker token authorizing cleanup of the matching --pr worktree",
    )
    parser.add_argument(
        "--apply", action="store_true", help="remove eligible clean worktrees"
    )
    parser.add_argument(
        "--prune-open-clean",
        action="store_true",
        help="also remove clean worktrees for open PRs after worker tasks finish",
    )
    args = parser.parse_args()

    if args.lease_token and not args.pr:
        parser.error("--lease-token requires --pr")
    if args.prune_open_clean and not args.pr:
        parser.error("--prune-open-clean requires --pr")
    if args.prune_open_clean and not args.lease_token:
        parser.error("--prune-open-clean requires --lease-token")

    try:
        root = resolve_root(args.root)
        state_dir = resolve_state_dir(args.state_dir)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    target_key = ""
    if args.pr:
        repo, number = parse_repo_number(args.pr)
        target_key = f"{repo}#{number}"
    rows: list[dict[str, object]] = []
    exit_code = 0
    for worktree in iter_worktrees(root):
        if target_key and worktree.key.casefold() != target_key:
            continue
        row: dict[str, object] = {"key": worktree.key, "path": str(worktree.path)}
        try:
            lease_path = leases.lease_path(state_dir, "worker", worktree.key)
            # Hold the same lock used by acquire/heartbeat/release through the
            # final removal. A worker can start after cleanup, but cleanup can
            # never race past a newly acquired lease and delete its worktree.
            with state_lock(lease_path):
                active_lease = active_worker_lease(worktree, state_dir)
                if args.lease_token and not active_lease:
                    raise RuntimeError(
                        f"no unexpired worker lease exists for {worktree.key}"
                    )
                if active_lease and active_lease.get("token") != args.lease_token:
                    row["action"] = "keep_leased"
                    row["lease_run_id"] = active_lease.get("run_id") or ""
                    row["lease_expires_at"] = active_lease.get("expires_at") or ""
                    rows.append(row)
                    continue
                status = git_status(worktree.path)
                row["status"] = status
                if is_dirty(status):
                    row["action"] = "keep_dirty"
                    rows.append(row)
                    continue

                state = pr_state(worktree)
                row.update(state)
                eligible = state["state"] in {"CLOSED", "MERGED"} or (
                    state["state"] == "OPEN" and args.prune_open_clean
                )
                row["action"] = "remove" if eligible else "keep_open"
                if eligible and args.apply:
                    remove_worktree(worktree, root)
                    row["removed"] = True
                else:
                    row["removed"] = False
        except Exception as exc:
            row["action"] = "error"
            row["error"] = str(exc)
            exit_code = 1
        rows.append(row)

    print(
        json.dumps(
            {
                "root": str(root),
                "target_pr": target_key,
                "apply": args.apply,
                "worktrees": rows,
            },
            indent=2,
        )
    )
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
