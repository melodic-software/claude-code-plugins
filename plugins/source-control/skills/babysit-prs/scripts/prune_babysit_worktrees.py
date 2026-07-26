#!/usr/bin/env python3
"""Prune clean ephemeral worktrees created by the babysit-prs skill."""

from __future__ import annotations

import argparse
import json
import os
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
UNRECOGNIZED_REASON = "directory name does not match <owner>__<repo>__pr-<number>"
# Substrings `git` emits (case-insensitive) when a path is no longer a usable
# repository/worktree, each observed from `rev-parse --show-toplevel` under
# `C_LOCALE_ENV`, which pins the wording. Used to recognize an orphaned entry
# rather than an unrelated git failure (#816); anything else still raises.
#   deleted pointer  -> fatal: not a git repository (or any of the parent
#                       directories): .git
#   dangling target  -> fatal: not a git repository: (NULL)
#   corrupted pointer-> fatal: invalid gitfile format: <path>
# The third is why this is a tuple: a malformed `.git` is one of the states
# this self-heal exists to clear, so matching only the first two would re-raise
# and report `action: error` forever on exactly that entry.
NOT_A_WORKTREE_MARKERS = ("not a git repository", "invalid gitfile format")
# Git localizes its diagnostics, so any probe whose result is read out of a
# message must pin the locale first. `LC_ALL` outranks the other category
# variables; `LANGUAGE` outranks `LC_ALL` for GNU gettext specifically, so it is
# cleared rather than set.
C_LOCALE_ENV = {"LC_ALL": "C", "LANGUAGE": ""}


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


@dataclass
class UnrecognizedWorktree:
    """A directory under the root whose PR identity cannot be derived."""

    path: Path
    reason: str


def run(
    argv: list[str],
    *,
    check: bool = True,
    env_overrides: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return run_command(
        argv,
        allowed_executables=ALLOWED_EXECUTABLES,
        check=check,
        env_overrides=env_overrides,
    )


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


def iter_worktrees(root: Path) -> list[Worktree | UnrecognizedWorktree]:
    """Every directory under the root, identified or explicitly unidentified.

    A directory whose name does not carry a PR identity is reported rather than
    dropped: a caller that reads this report to answer "is anything left to
    clean up?" would otherwise get a false all-clear for a worktree it can
    neither see nor act on (#555). Unrecognized entries are never removed --
    identity is a precondition for the PR-state and lease checks that authorize
    removal.
    """
    if not root.exists():
        return []
    found: list[Worktree | UnrecognizedWorktree] = []
    for child in sorted(root.iterdir()):
        if not child.is_dir():
            continue
        match = WORKTREE_RE.match(child.name)
        if not match:
            found.append(UnrecognizedWorktree(path=child, reason=UNRECOGNIZED_REASON))
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


def worktree_toplevel(path: Path) -> Path | None:
    """The working-tree root git resolves when started in `path`, or `None`
    when no repository is reachable from there at all.

    `git -C <path>` runs *as if git were started in* that directory
    (<https://git-scm.com/docs/git#Documentation/git.txt--Cltpathgt>), so
    ordinary upward discovery still succeeds against an *ancestor* checkout
    when the babysit worktree root itself sits inside one. Callers compare
    this against the candidate path to tell "this worktree" from "some
    ancestor of it".
    """
    try:
        proc = run(
            ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
            env_overrides=C_LOCALE_ENV,
        )
    except RuntimeError as exc:
        if is_missing_repo_error(exc):
            return None
        raise
    text = proc.stdout.strip()
    return Path(text).resolve() if text else None


def is_orphaned_entry(path: Path) -> bool:
    """Whether `path` no longer is its own git worktree (#816).

    Two ways an entry orphans, and a status probe alone only catches the
    first: git reports `fatal: not a git repository`, or git silently answers
    for an ancestor checkout (see `worktree_toplevel`) whose status says
    nothing about this directory -- under which a closed PR's entry would
    reach `git worktree remove` and error, and an open PR's would be retained
    as `keep_open`, in both cases leaving the residual directory forever.
    """
    toplevel = worktree_toplevel(path)
    if toplevel is None:
        return True
    return os.path.normcase(str(toplevel)) != os.path.normcase(str(path.resolve()))


def is_missing_repo_error(exc: Exception) -> bool:
    """Whether a git failure means "this path is no longer a git repository".

    Distinguishes an orphaned worktree entry from every other git failure
    (permission errors, network issues for `gh`, etc.), which must still
    surface as a real error rather than being silently swallowed.

    Only sound for a failure produced under `C_LOCALE_ENV`. Git translates its
    diagnostics, so on a localized machine the untranslated markers would never
    match and every orphan would surface as an unrelated error instead of
    reaching the self-healing path -- the caller pins the locale rather than
    hoping the operator's is English.
    """
    text = str(exc).lower()
    return any(marker in text for marker in NOT_A_WORKTREE_MARKERS)


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

    A lone dangling `.git` **gitfile** does not count as contents. It is git's
    own bookkeeping -- the very pointer the entry orphaned around, and the one
    `registered_repo_from_gitdir_pointer` has already read by this point -- so
    counting it as user work would make every *recoverable* orphan look
    non-empty and strand the self-heal precisely where ownership is knowable.
    A `.git` **directory** is never touched: that is a standalone repository,
    not a linked worktree's pointer.
    """
    if not path.exists():
        return True
    resolved = path.resolve()
    if root.resolve() not in resolved.parents:
        return False
    try:
        children = list(path.iterdir())
        pointer = children[0] if len(children) == 1 else None
        if pointer is not None and (pointer.name != ".git" or not pointer.is_file()):
            pointer = None
        saved = pointer.read_bytes() if pointer is not None else None
        if pointer is not None:
            pointer.unlink()
            children = list(path.iterdir())
        try:
            if not children:
                path.rmdir()
        except OSError:
            # The directory outlived its pointer -- a Windows handle, most
            # likely. Put the gitfile back: it is the only record of the owning
            # repository, so discarding it would leave the next run unable to
            # prune the registration at all, turning a retryable failure into a
            # permanent `unresolved`.
            if pointer is not None and saved is not None and not pointer.exists():
                pointer.write_bytes(saved)
            raise
    except OSError:
        pass
    return not path.exists()


def registered_repo_from_gitdir_pointer(path: Path) -> Path | None:
    """The repository a linked worktree's own `.git` pointer names, if readable.

    A linked worktree's `.git` is a file holding
    `gitdir: <repo>/.git/worktrees/<name>`. That record path is the only thing
    at an orphaned entry that still names its owning repository, so it is what
    a stale-record cleanup has to read. Returns None when the pointer is gone
    or unreadable -- the case nothing local can resolve.
    """
    pointer = path / ".git"
    try:
        if not pointer.is_file():
            return None
        text = pointer.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None
    prefix = "gitdir:"
    if not text.lower().startswith(prefix):
        return None
    recorded = Path(text[len(prefix) :].strip())
    if not recorded.is_absolute():
        recorded = (path / recorded).resolve()
    # The record always sits at `<common-dir>/worktrees/<name>`, so the common
    # directory is the parent of the `worktrees` segment. Derive it from that
    # structure rather than from a `.git` ancestor: a bare-clone hub's common
    # directory is `hub.git`, which `repo_path` already supports and which no
    # `.git`-named-ancestor search would ever find.
    for parent in recorded.parents:
        if parent.name != "worktrees":
            continue
        common = parent.parent
        # Same rule `repo_path` applies: a standard clone's common directory is
        # the main working tree's `.git`, so git commands run from its parent;
        # a bare hub has no working tree, so they run from the directory itself.
        return common.parent if common.name == ".git" else common
    return None


def prune_repo_worktree_records(repo: Path, worktree_path: Path) -> str:
    """Clear `worktree_path`'s stale record in `repo`; `pruned` or `failed`.

    Removing an orphan's directory is only half the cleanup. When the entry
    orphaned because its `.git` pointer was corrupted, the repository still
    holds the registration, and `git worktree add` at the same deterministic
    path then fails with "missing but already registered worktree" -- so a bare
    directory removal is not the self-heal it looks like. `git worktree prune`
    is git's own command for dropping records whose directory is gone, which is
    why the caller removes the directory first and prunes second.

    The verdict comes from re-reading `worktree list`, never from the prune's
    exit status: a **locked** record (`git worktree lock`) is deliberately kept
    by prune, which still exits 0, so trusting the exit code would report a
    completed repair while the path keeps rejecting `git worktree add`.
    """
    try:
        run(["git", "-C", str(repo), "worktree", "prune"])
        listed = run(["git", "-C", str(repo), "worktree", "list", "--porcelain"])
    except (RuntimeError, OSError):
        return "failed"
    # Compare resolved paths, never raw strings: git prints POSIX separators and
    # long filenames, while the caller's path can carry native separators and a
    # Windows 8.3 short name for the same directory.
    target = os.path.normcase(str(worktree_path.resolve()))
    for line in listed.stdout.splitlines():
        if not line.startswith("worktree "):
            continue
        recorded = Path(line[len("worktree ") :].strip())
        if os.path.normcase(str(recorded.resolve())) == target:
            return "failed"
    return "pruned"


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
    worktree: Worktree, lease_path: Path, root: Path, *, preserve_lease: bool
) -> dict[str, object]:
    """Self-heal a worktree entry whose directory survives on disk but is no
    longer a valid git worktree (typically the residual empty directory
    `remove_worktree` reports, from a prior lock-blocked removal, #816).

    Drops a leftover worker-lease record for this key -- the same condition
    `manage_babysit_lease.py reap` reaps independently for lease records with
    no matching directory at all -- and removes the residual directory only
    when it is empty (see `remove_empty_orphan_directory`), so the next prune
    run does not keep re-erroring on the same orphan instead of self-healing.

    `preserve_lease` keeps the record when the caller's own unexpired lease
    authorized this cleanup (`--lease-token` matched a live hold). The
    documented cleanup order prunes while the worker lease is still held and
    releases it afterwards (`reference/orchestration.md` "Cleanup"), so
    unlinking it here would make that release fail on a lease that no longer
    exists and drop ownership early.
    """
    info: dict[str, object] = {"lease_dropped": False}
    if not preserve_lease and lease_path.exists():
        lease_path.unlink(missing_ok=True)
        info["lease_dropped"] = True
    # Read the owning repository off the pointer BEFORE the directory goes --
    # afterwards nothing at that path names it any more.
    registered_repo = registered_repo_from_gitdir_pointer(worktree.path)
    removed = remove_empty_orphan_directory(worktree.path, root)
    info["directory_removed"] = removed
    info["registration_pruned"] = orphan_registration_state(
        registered_repo, worktree.path, directory_removed=removed
    )
    return info


def orphan_registration_state(
    registered_repo: Path | None, worktree_path: Path, *, directory_removed: bool
) -> str:
    """How the owning repository's worktree record ended up, for the report.

    Three outcomes, because "the directory is gone" and "the path is reusable"
    are different claims and only the second needs a repository:

    - `skipped` -- the directory survives, so there is nothing to prune yet;
      `git worktree prune` only drops records whose directory is missing.
    - `pruned` / `failed` -- the entry's own `gitdir:` pointer named its
      repository and the prune there succeeded or did not.
    - `unresolved` -- the pointer is gone, so whether a stale record survives
      is not knowable from here, and it is reported rather than assumed.

    Recovering ownership is the *only* thing that clears the uncertainty. In
    particular an ancestor checkout answering for the path proves nothing: a
    real linked worktree nested under another checkout resolves to that
    ancestor once its pointer is lost, while its owning repository still holds
    a prunable record. "Never registered" and "registered, pointer gone" are
    indistinguishable from the path alone, so both stay `unresolved`.
    """
    if not directory_removed:
        return "skipped"
    if registered_repo is None:
        return "unresolved"
    return prune_repo_worktree_records(registered_repo, worktree_path)


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
    parser = argparse.ArgumentParser(
        description="Prune babysit-prs Git worktrees.", allow_abbrev=False
    )
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
    for entry in iter_worktrees(root):
        if isinstance(entry, UnrecognizedWorktree):
            # Reported before the --pr filter below, because an unrecognized
            # entry has no key and so could never match a target: leaving it to
            # that filter would hide it from every scoped run forever. A
            # recognized non-target entry is merely out of the caller's declared
            # scope and still appears in an unscoped run.
            rows.append(
                {
                    "path": str(entry.path),
                    "action": "unrecognized",
                    "reason": entry.reason,
                    "removed": False,
                }
            )
            continue
        worktree = entry
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
                if is_orphaned_entry(worktree.path):
                    # Orphaned entry: the directory survives (matches the
                    # naming convention, so iter_worktrees still lists it)
                    # but is no longer this path's own git worktree. Self-heal
                    # instead of erroring the whole prune on every run --
                    # under --apply only, since self-healing unlinks a lease
                    # record and deletes a directory, and the flagless run is
                    # a report.
                    row["action"] = "drop_orphan"
                    if args.apply:
                        orphan_info = drop_orphaned_worktree(
                            worktree,
                            lease_path,
                            root,
                            preserve_lease=active_lease is not None,
                        )
                        row.update(orphan_info)
                        # A non-empty orphan is deliberately never
                        # force-deleted (`remove_empty_orphan_directory`), so
                        # the entry survives at its deterministic one-per-PR
                        # path and a replacement worktree cannot be created
                        # there. Report that as unfinished, in the same
                        # `residual_directory` vocabulary `remove_worktree`
                        # uses for its own surviving directory.
                        registration = orphan_info["registration_pruned"]
                        row["dropped"] = bool(orphan_info["directory_removed"])
                        if not row["dropped"]:
                            row["residual_directory"] = True
                            print(
                                "WARNING: orphaned worktree directory is not "
                                f"empty and was left in place for {worktree.key} "
                                f"(inspect and clear it by hand): {worktree.path}",
                                file=sys.stderr,
                            )
                        elif registration != "pruned":
                            # The directory is gone but the owning repository's
                            # record was not confirmed cleared, so the path may
                            # still reject `git worktree add` as "missing but
                            # already registered". Say so instead of letting
                            # `dropped: true` read as a completed self-heal.
                            row["stale_registration"] = True
                            print(
                                "WARNING: removed the orphaned directory for "
                                f"{worktree.key}, but its owning repository's "
                                f"worktree record was not cleared ({registration})"
                                " -- a replacement worktree at that path can "
                                "still fail as 'missing but already registered'."
                                " Run `git worktree prune` in the checkout for "
                                f"{worktree.full_repo}: {worktree.path}",
                                file=sys.stderr,
                            )
                    else:
                        row["dropped"] = False
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
