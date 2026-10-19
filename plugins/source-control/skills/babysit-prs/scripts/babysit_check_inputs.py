"""Whether the base branch changed what a pull request's checks read.

A pull request whose checks went green on an old base can still fail in the
merge queue once its merge with the base tip is checked: the base registered a
new shared copy, a gate's allowlist or schema changed. Every queue entry built
behind it fails with it. `merge.check-inputs` in
docs/conventions/pr-pipeline.yaml lists the paths those checks read; when the
base changed one of them since the pull request's merge base, the gate updates
the branch from the base instead of enqueuing it.

The answer comes from a local clone of the base branch with its whole history
(the pr-merge lane runs from one, `.base`), never the API. A head commit the
clone lacks is fetched into it by SHA over git, with no ref written; its code
is never checked out. Any doubt (no such clone, a failed fetch or merge-base)
answers `unknown`, and the gate enqueues as it would without this check.

An input in `SCOPED_INPUTS` counts as changed only for a pull request whose
own changes since the merge base touch it or a path it registers, read at
the base tip: the shared-copy check compares each registered copy with its canonical,
so a pull request touching neither merges cleanly whatever the base
registered. Every other input counts for every pull request.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterable, Sequence
from pathlib import Path
from typing import Any

import babysit_merge_policy as merge_policy
from babysit_util import run_command

SHA_RE = re.compile(r"[0-9a-f]{40}")
BRANCH_RE = re.compile(r"[A-Za-z0-9._/-]+")
# A fetch reads one pull request's new commits; a slow remote must not hold
# the gate past its budget.
FETCH_TIMEOUT_SECONDS = 60.0


def _git(root: Path, *args: str) -> str | None:
    return merge_policy._git(root, *args)


def _registered_paths(text: str) -> set[str]:
    """Every canonical and copy path in a `scripts/shared-copies.txt` text."""
    paths: set[str] = set()
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            paths.update(line.split())
    return paths


SCOPED_INPUTS: dict[str, Callable[[str], set[str]]] = {
    "scripts/shared-copies.txt": _registered_paths,
}


def _names(out: str) -> list[str]:
    return sorted(p for p in out.split("\0") if p)


def _full_history_clone(roots: Iterable[Path], tip_ref: str) -> tuple[Path, str] | None:
    """The first clone that resolves `tip_ref` and holds its whole history."""
    for checkout in roots:
        top = _git(checkout, "rev-parse", "--show-toplevel")
        if not top or not top.strip():
            continue
        root = Path(top.strip())
        if _git(root, "rev-parse", "--is-shallow-repository") != "false\n":
            continue
        tip = (
            _git(root, "rev-parse", "--verify", "--quiet", f"{tip_ref}^{{commit}}")
            or ""
        ).strip()
        if SHA_RE.fullmatch(tip):
            return root, tip
    return None


def _has_commit(root: Path, sha: str) -> bool:
    return _git(root, "cat-file", "-e", f"{sha}^{{commit}}") is not None


def _fetch_commit(root: Path, sha: str) -> bool:
    try:
        proc = run_command(
            ["git", "-C", str(root), "fetch", "--quiet", "--no-tags"]
            + ["--no-write-fetch-head", "--no-recurse-submodules", "origin", sha],
            allowed_executables=("git",),
            check=False,
            timeout_seconds=FETCH_TIMEOUT_SECONDS,
        )
    except (RuntimeError, ValueError, OSError):
        return False
    return proc.returncode == 0 and _has_commit(root, sha)


def changed_since_merge_base(
    paths: Sequence[str],
    head: str,
    branch: str,
    roots: Iterable[Path] | None = None,
) -> dict[str, Any]:
    """Which of `paths` (git pathspecs) the base branch changed since its
    merge base with `head`.

    `state` is `off` (no paths), `stale` (`changed` lists them), `current`, or
    `unknown` (`reason` says why). The base tip is the clone's
    `origin/<branch>`, which the pr-merge lane's checkout fetched at the start
    of its run.
    """
    if not paths:
        return {"state": "off"}
    if not SHA_RE.fullmatch(head) or not BRANCH_RE.fullmatch(branch):
        return {"state": "unknown", "reason": "the head or base is not a plain name"}
    found = _full_history_clone(
        merge_policy._history_checkouts() if roots is None else roots,
        f"refs/remotes/origin/{branch}",
    )
    if found is None:
        return {
            "state": "unknown",
            "reason": f"no full-history clone of origin/{branch}",
        }
    root, tip = found
    if not _has_commit(root, head) and not _fetch_commit(root, head):
        return {"state": "unknown", "reason": f"head {head} could not be fetched"}
    base = (_git(root, "merge-base", head, tip) or "").strip()
    if not SHA_RE.fullmatch(base):
        return {"state": "unknown", "reason": "no merge base with the base tip"}
    out = _git(
        root, "diff", "--name-only", "--no-renames", "-z", base, tip, "--", *paths
    )
    if out is None:
        return {"state": "unknown", "reason": "the base's changes could not be listed"}
    changed = _names(out)
    report: dict[str, Any] = {"mergeBase": base, "baseTip": tip}
    scoped = [p for p in changed if p in SCOPED_INPUTS]
    if scoped:
        own = _git(root, "diff", "--name-only", "--no-renames", "-z", base, head)
        if own is None:
            return {
                "state": "unknown",
                "reason": "the head's changes could not be listed",
            }
        touched = set(_names(own))
        # The PR editing the registry itself overlaps whatever the base
        # changed there. A registry absent or unreadable at the tip registers
        # nothing, so the doubt falls toward enqueuing.
        skipped = [
            p
            for p in scoped
            if p not in touched
            and not touched
            & SCOPED_INPUTS[p](_git(root, "cat-file", "blob", f"{tip}:{p}") or "")
        ]
        changed = [p for p in changed if p not in skipped]
        report["notApplicable"] = skipped
    report["changed"] = changed
    return {"state": "stale" if changed else "current", **report}
