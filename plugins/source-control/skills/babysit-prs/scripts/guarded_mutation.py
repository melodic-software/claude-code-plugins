#!/usr/bin/env python3
"""Shared opening for the guarded-mutation CLIs.

``refresh_pr_branch.py``, ``manage_feedback_ledger.py``, and
``request_review.py`` each used to open a mutating run with the same
preamble. This module is that preamble. The contract below is what a caller
is allowed to rely on. Hoisting it does not change what is permitted.

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
    Success is the returned :class:`GuardedMutation`. Refusal is the exception
    the three scripts already raised: ``ValueError`` when the token is absent,
    ``LeaseHeldError`` when the token is not the owner's, and ``RuntimeError``
    for every other refusal. There is no status flag. Callers do not catch the
    refusal inside this helper; they let it propagate.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, NamedTuple

import babysit_lease as leases
from babysit_gh import parse_repo_number
from babysit_state import (
    load_state,
    require_pr_state,
    resolve_expected_head_sha,
    state_lock,
)


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
    return GuardedMutation(
        repo=repo,
        number=number,
        key=key,
        state=state,
        pr_state=pr_state,
        head_sha=head_sha,
    )
