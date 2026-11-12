#!/usr/bin/env python3
"""Shared opening for the guarded-mutation CLIs.

``refresh_pr_branch.py``, ``manage_feedback_ledger.py``, and
``request_review.py`` open each mutating run here. The contract below is what
a caller is allowed to rely on.

What is checked
    When ``args.apply`` is true, the worker lease for ``owner/repo#number``
    must exist, be unexpired, and carry ``args.lease_token``. A renew passes
    that same ownership check and then extends the lease. Durable state must
    already hold a snapshot record for that PR. ``args.expected_head_sha``
    must be the stored head SHA, or a hex prefix of at least
    ``MIN_HEAD_SHA_PREFIX_LENGTH`` characters that matches it.

What is permitted
    A dry run (``args.apply`` false) skips the lease check and still resolves
    the snapshot and the head pin. On success the returned ``pr_state`` is the
    live record inside ``state``, not a copy, so a later write to it is what
    ``write_state`` persists.

What is refused
    A missing lease token, a missing or expired lease, or a token that is not
    the current owner. No snapshot for the PR. A stored head that is missing,
    malformed, or does not match the pin.

How the caller learns the outcome
    Success is the returned :class:`GuardedMutation`. Refusal is an
    exception: ``ValueError`` when the token is absent,
    ``LeaseHeldError`` when the token is not the owner's, and ``RuntimeError``
    for every other refusal. There is no status flag. Callers do not catch the
    refusal inside this helper; they let it propagate.
"""

from __future__ import annotations

import argparse
from collections.abc import Callable
from pathlib import Path
from typing import Any, NamedTuple, TypeVar

import babysit_lease as leases
from babysit_gh import parse_repo_number
from babysit_state import (
    load_state,
    require_pr_state,
    resolve_expected_head_sha,
    resolve_state_dir,
    state_lock,
    state_path_for,
)
from babysit_util import MIN_HEAD_SHA_PREFIX_LENGTH

T = TypeVar("T")


class GuardedMutation(NamedTuple):
    """The snapshot a guarded CLI is allowed to mutate, already pin-checked."""

    repo: str
    number: int
    key: str
    state: dict[str, Any]
    pr_state: dict[str, Any]
    head_sha: str


def require_worker_lease(
    args: argparse.Namespace,
    state_dir: Path,
    repo: str,
    number: int,
    *,
    renew: bool = False,
) -> None:
    """Refuse a mutating run that does not hold the worker lease.

    Dry runs return without reading the lease. ``renew`` is the same
    ownership check followed by a heartbeat; a renew that does not own the
    lease raises, it does not acquire one.
    """
    if not args.apply:
        return
    path = leases.lease_path(state_dir, "worker", f"{repo}#{number}")
    with state_lock(path):
        token = getattr(args, "lease_token", None)
        if renew:
            leases.heartbeat(path, token, None, leases.DEFAULT_WORKER_TTL_SECONDS)
        else:
            leases.require_owned_lease(path, token)


def begin_guarded_mutation(
    args: argparse.Namespace,
    state_dir: Path,
    state_path: Path,
) -> GuardedMutation:
    """Open one guarded mutation: lease, snapshot, head pin.

    See the module docstring for what this permits and what it refuses.
    """
    repo, number = parse_repo_number(args.pr)
    key = f"{repo}#{number}"
    require_worker_lease(args, state_dir, repo, number)
    state = load_state(state_path)
    pr_state = require_pr_state(state, key)
    head_sha = resolve_expected_head_sha(
        str(pr_state.get("head_sha") or ""), args.expected_head_sha
    )
    return GuardedMutation(repo, number, key, state, pr_state, head_sha)


def run_under_state_lock(
    args: argparse.Namespace,
    run_locked: Callable[[argparse.Namespace, Path, Path], T],
) -> T:
    """Resolve ``--state-dir``, hold the state lock, and call ``run_locked``."""
    state_dir = resolve_state_dir(args.state_dir)
    state_path = state_path_for(state_dir)
    with state_lock(state_path):
        return run_locked(args, state_dir, state_path)


def add_head_pin_arguments(parser: argparse.ArgumentParser) -> None:
    """Add ``--pr`` and ``--expected-head-sha``."""
    parser.add_argument("--pr", required=True, help="PR URL or owner/repo#number")
    parser.add_argument(
        "--expected-head-sha",
        required=True,
        help=(
            "snapshot head SHA, full or a hex prefix of at least "
            f"{MIN_HEAD_SHA_PREFIX_LENGTH} characters"
        ),
    )


def add_worker_arguments(parser: argparse.ArgumentParser, apply_help: str) -> None:
    """Add ``--state-dir``, ``--lease-token`` and ``--apply``."""
    parser.add_argument(
        "--state-dir",
        required=True,
        help=(
            "Durable state directory. Required: state-dir resolution is "
            "flag-only, with no environment fallback."
        ),
    )
    parser.add_argument("--lease-token", help="opaque token for this PR's worker lease")
    parser.add_argument("--apply", action="store_true", help=apply_help)
