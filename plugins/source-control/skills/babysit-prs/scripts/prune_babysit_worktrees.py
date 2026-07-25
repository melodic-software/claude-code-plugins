#!/usr/bin/env python3
"""Prune clean ephemeral worktrees created by the babysit-prs skill."""

from __future__ import annotations

import argparse
import json
import re
import shutil
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
ALLOWED_EXECUTABLES = ("git", "gh")
# Substring `git` emits (case-insensitive) when a path is no longer a valid
# repository/worktree -- e.g. `fatal: not a git repository (or any of the
# parent directories): .git`. Used to recognize an orphaned worktree entry
# rather than an unrelated git failure (#816).
NOT_A_GIT_REPO_MARKER = "not a git repository"


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


def repo_path(worktree_path: Path) -> Path:
    """Resolve the main checkout a linked worktree belongs to, from git alone.

    A linked worktree records its repository through its gitdir/commondir
    pointer, so `git rev-parse --git-common-dir` yields the shared git directory
    with no external repo-layout tool. For a standard clone that directory is the
    main working tree's `.git`, so its parent is the checkout git worktree
    commands run from; a bare-clone hub has no working tree, so the git directory
    itself is where those commands run.
    """
    proc = run(["git", "-C", str(worktree_path), "rev-parse", "--git-common-dir"])
    common = Path(proc.stdout.strip())
    if not common.is_absolute():
        common = worktree_path / common
    common = common.resolve()
    return common.parent if common.name == ".git" else common


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


def is_missing_repo_error(exc: Exception) -> bool:
    """Whether a git failure means "this path is no longer a git repository".

    Distinguishes an orphaned worktree entry from every other git failure
    (permission errors, network issues for `gh`, etc.), which must still
    surface as a real error rather than being silently swallowed.
    """
    return NOT_A_GIT_REPO_MARKER in str(exc).lower()


def attempt_directory_removal(path: Path) -> bool:
    """Best-effort delete `path`; returns True once nothing remains there.

    Only called right after a successful `git worktree remove` (see
    `remove_worktree`), which has already established the directory's
    contents were safe to discard -- so an unconditional `rmtree` is safe
    here. One attempt is enough to clear a removal blocked only by a
    transient handle (e.g. an antivirus scan or a just-closed process); a
    lock that outlives the attempt is left for the caller to report rather
    than retried indefinitely. Never raises -- a still-locked directory is a
    normal, reportable outcome, not a crash.
    """
    if not path.exists():
        return True
    try:
        shutil.rmtree(path)
    except OSError:
        pass
    return not path.exists()


def remove_empty_orphan_directory(path: Path, root: Path) -> bool:
    """Remove `path` only if it is empty and safely contained under `root`.

    Used for orphan self-healing (`drop_orphaned_worktree`), where git never
    confirmed this path was safe to discard -- unlike `attempt_directory_removal`
    (used only after a successful `git worktree remove`), this must never
    touch directory contents: an orphan's `.git` pointer could have been
    corrupted or deleted while real, uncommitted work still sits there. A
    non-empty orphan is left in place and reported, not force-deleted.
    """
    if not path.exists():
        return True
    resolved = path.resolve()
    if root.resolve() not in resolved.parents:
        return False
    try:
        if not any(path.iterdir()):
            path.rmdir()
    except OSError:
        pass
    return not path.exists()


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


def remove_worktree(worktree: Worktree, root: Path) -> dict[str, object]:
    """Remove a worktree via `git worktree remove`, then verify the directory
    actually left disk.

    `git worktree remove` can report success (its administrative record is
    dropped from the main repo's `.git/worktrees/`) while a Windows file lock
    blocks the underlying directory deletion, leaving an empty directory
    behind (#816). One cleanup retry is attempted here; a directory that
    still survives is reported via `residual_directory` rather than left as
    a silent orphan for a future run to stumble over.
    """
    main_repo = repo_path(worktree.path)
    if not main_repo.exists():
        raise RuntimeError(f"main repo missing for {worktree.key}: {main_repo}")
    resolved = worktree.path.resolve()
    allowed_root = root.resolve()
    if allowed_root not in resolved.parents:
        raise RuntimeError(
            f"refusing to remove worktree outside babysit root: {resolved}"
        )
    run(["git", "-C", str(main_repo), "worktree", "remove", str(worktree.path)])
    removed = attempt_directory_removal(worktree.path)
    return {"residual_directory": not removed}


def drop_orphaned_worktree(
    worktree: Worktree, lease_path: Path, root: Path
) -> dict[str, object]:
    """Self-heal a worktree entry whose directory survives on disk but is no
    longer a valid git worktree (typically the residual empty directory
    `remove_worktree` reports, from a prior lock-blocked removal, #816).

    Drops any leftover worker-lease record for this key -- by the time this
    runs, `main`'s active-lease check has already established it is not a
    live/unexpired hold, the same condition `manage_babysit_lease.py reap`
    reaps independently for lease records with no matching directory at all
    -- and removes the residual directory only when it is empty (see
    `remove_empty_orphan_directory`), so the next prune run does not keep
    re-erroring on the same orphan instead of self-healing.
    """
    info: dict[str, object] = {"lease_dropped": False}
    if lease_path.exists():
        lease_path.unlink(missing_ok=True)
        info["lease_dropped"] = True
    info["directory_removed"] = remove_empty_orphan_directory(worktree.path, root)
    return info


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
                try:
                    status = git_status(worktree.path)
                except RuntimeError as exc:
                    if not is_missing_repo_error(exc):
                        raise
                    # Orphaned entry: the directory survives (matches the
                    # naming convention, so iter_worktrees still lists it)
                    # but is no longer a valid git worktree. Self-heal
                    # instead of erroring the whole prune on every run --
                    # under --apply only, since self-healing unlinks a lease
                    # record and deletes a directory, and the flagless run is
                    # a report.
                    row["action"] = "drop_orphan"
                    if args.apply:
                        row.update(drop_orphaned_worktree(worktree, lease_path, root))
                        row["dropped"] = True
                    else:
                        row["dropped"] = False
                    rows.append(row)
                    continue
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
                    removal_info = remove_worktree(worktree, root)
                    row["removed"] = True
                    row.update(removal_info)
                    if removal_info.get("residual_directory"):
                        print(
                            "WARNING: worktree directory survived removal "
                            f"for {worktree.key} (likely a file lock): "
                            f"{worktree.path}",
                            file=sys.stderr,
                        )
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
