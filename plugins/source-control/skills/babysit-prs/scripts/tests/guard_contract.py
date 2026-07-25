"""The guard contract: every lane fact a consumer is allowed to rely on.

This module is the single source of truth for two artifacts that must never
disagree: the executable assertions in `test_guards.py` and the citable prose in
`../reference/guard-contract.md`. A consumer configuring a host permission
classifier cites the markdown; CI proves the markdown is what the code does.

Each row carries the prose claim it backs, so a changed guard predicate fails
with a message naming the downstream documentation claim that just became false
rather than `AssertionError: 3 != 2`.

Regenerate the markdown after editing any table:

    python tests/guard_contract.py --emit

Source anchors are `file.py::symbol`, never line numbers -- a line number in a
drift-detection artifact is the drift it exists to catch.

TODO(#1265): add an argparse flag catalogue -- every flag's name, type, and
default per entry point -- which would additionally catch a renamed flag or a
changed default that no behavior row exercises. Deferred because it needs a
`build_parser()` extraction across all nine entry points, whose parsers are
built inside `main()`. Trigger: the first time a flag rename or default change
ships without a matching update here.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
from dataclasses import dataclass, field

PLUGIN_ROOT = pathlib.Path(__file__).resolve().parents[4]
SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
GENERATED_DOC = SCRIPTS.parent / "reference" / "guard-contract.md"

MERGE_CLI = "skills/babysit-prs/scripts/babysit_merge.py"
RESOLVE_CLI = "skills/babysit-prs/scripts/babysit_resolve_thread.py"
LEASE_CLI = "skills/babysit-prs/scripts/manage_babysit_lease.py"
LEDGER_CLI = "skills/babysit-prs/scripts/manage_feedback_ledger.py"
PRUNE_CLI = "skills/babysit-prs/scripts/prune_babysit_worktrees.py"
REFRESH_CLI = "skills/babysit-prs/scripts/refresh_pr_branch.py"
REVIEW_CLI = "skills/babysit-prs/scripts/request_review.py"
SNAPSHOT_CLI = "skills/babysit-prs/scripts/pr_queue_snapshot.py"
FINDINGS_CLI = "skills/babysit-prs/scripts/babysit_findings.py"
READINESS_GATE = "scripts/babysit-readiness-gate.sh"
MERGE_WRAPPER = "bin/source-control-babysit-merge"
RESOLVE_WRAPPER = "bin/source-control-babysit-resolve-thread"

# Where a refusal is enforced. The distinction is observable: a bash-wrapper
# refusal never reaches Python, so it prints plain text to stderr and emits no
# JSON; a python-cli refusal emits the engine's JSON envelope on stdout.
BASH_WRAPPER = "bash-wrapper"
PYTHON_CLI = "python-cli"


def plugin_path(relative: str) -> pathlib.Path:
    return PLUGIN_ROOT / relative


@dataclass(frozen=True)
class Refusal:
    """A guard that rejects on argument shape alone, before any network call."""

    id: str
    claim: str
    entry_point: str
    argv: tuple[str, ...]
    exit_code: int
    error_contains: tuple[str, ...]
    refused_by: str
    enforced_at: str
    # Envelope fields a caller may branch on, asserted by identity. A consumer
    # reading `inScope` needs it present and false, not merely falsy-or-absent.
    envelope_fields: tuple[tuple[str, object], ...] = ()
    # Rows claiming the refusal precedes every network call. These are replayed
    # against a recording `gh` shim that is the only executable on PATH, and the
    # shim must never be invoked -- an emptied PATH alone would let a swallowed
    # `gh` failure fall through to the same exit code and read as proof.
    gh_free: bool = False


@dataclass(frozen=True)
class Predicate:
    """A guard whose condition is a boolean over runtime API data, not flags.

    No argument shape can reach these -- they decide per fetched thread -- so
    they are asserted by calling the classifier directly with a projected
    thread record.
    """

    id: str
    claim: str
    enforced_at: str
    thread: dict[str, object]
    flags: dict[str, bool]
    expected: str


@dataclass(frozen=True)
class Effect:
    """An observable filesystem effect, run offline against a temp state dir.

    These exist because a flag's name does not say whether an invocation
    mutates: `manage_babysit_lease.py --apply` reads "reap only", yet `acquire`
    writes a lease file with no `--apply` at all.
    """

    id: str
    claim: str
    entry_point: str
    argv: tuple[str, ...]
    fixture: str
    # WHICH way state moved, not merely that it moved: a boolean lets a reap
    # that rewrites the expired lease -- or touches an unrelated file -- pass a
    # row whose claim is deletion. See DELTA_KINDS.
    delta: str
    exit_code: int


@dataclass(frozen=True)
class Mechanism:
    """A source-level claim about HOW an entry point mutates.

    A consumer reasoning about the wrong mechanism writes the wrong permission
    rule -- `refresh_pr_branch.py` never pushes, so a push guard is irrelevant
    to it.
    """

    id: str
    claim: str
    entry_point: str
    must_contain: tuple[str, ...]
    must_not_contain: tuple[str, ...] = ()


@dataclass(frozen=True)
class EntryPoint:
    """The mutating / read-only classification a permission rule may assume."""

    path: str
    wrapper: str | None
    mutation: str
    mutates_what: str
    gate: str
    claim: str
    backed_by: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class DocCommandSource:
    """A document that spells out wrapper command lines a reader may copy.

    Every `bin/`-path wrapper command fenced in these files is validated: the
    wrapper file exists, and every flag it names is a flag the backing CLI's
    parser actually accepts.
    """

    id: str
    claim: str
    doc: str


# --------------------------------------------------------------------------
# Refusals -- fail-closed guards, asserted by invoking the entry point.
# --------------------------------------------------------------------------

REFUSALS: tuple[Refusal, ...] = (
    Refusal(
        id="merge.allowlist-absent",
        claim=(
            "The merge gate is fail-closed on scope: with no --allowed-owners it "
            "refuses every PR at exit 3 rather than defaulting to the current repo's owner."
        ),
        entry_point=MERGE_CLI,
        argv=("owner/repo#1",),
        exit_code=3,
        error_contains=("allowed-owners",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
        envelope_fields=(("inScope", False),),
        gh_free=True,
    ),
    Refusal(
        id="merge.owner-out-of-scope",
        claim=(
            "An owner outside --allowed-owners is refused at exit 3, so a permission rule "
            "may assume the gate never acts on a repository the operator did not name."
        ),
        entry_point=MERGE_CLI,
        argv=("owner/repo#1", "--allowed-owners", "someone-else"),
        exit_code=3,
        error_contains=(),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
        envelope_fields=(("inScope", False),),
        gh_free=True,
    ),
    Refusal(
        id="merge.owner-check-precedes-self-login-resolution",
        claim=(
            "The owner check runs before '@me' self-login resolution, which is a network "
            "call: an out-of-scope owner refuses at exit 3 with no gh invocation at all."
        ),
        entry_point=MERGE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "someone-else",
            "--self-logins",
            "@me",
        ),
        exit_code=3,
        error_contains=(),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
        envelope_fields=(("inScope", False),),
        gh_free=True,
    ),
    Refusal(
        id="merge.short-expected-head",
        claim=(
            "--expected-head must be a long-enough SHA prefix; a short value is a usage "
            "error at exit 2, never a loose prefix match against the live head."
        ),
        entry_point=MERGE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--merge",
            "--expected-head",
            "abc",
        ),
        exit_code=2,
        error_contains=("expected-head",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
    ),
    Refusal(
        id="merge.malformed-ref",
        claim=(
            "The PR reference must parse as owner/repo#number or a PR URL; anything else "
            "is a usage error at exit 2."
        ),
        entry_point=MERGE_CLI,
        argv=("not-a-ref", "--allowed-owners", "owner"),
        exit_code=2,
        error_contains=(),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
    ),
    Refusal(
        id="merge.autopilot-tier-without-required-sets",
        claim=(
            "The autopilot merge tier is fail-closed: the umbrella flag alone, with none "
            "of --lane-logins, --approver-bot-logins, or --block-labels, refuses at exit 3 "
            "before any network access."
        ),
        entry_point=MERGE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--autopilot-merge-tier",
        ),
        exit_code=3,
        error_contains=("--lane-logins", "--approver-bot-logins", "--block-labels"),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
    ),
    Refusal(
        id="merge.autopilot-tier-partial-config",
        claim=(
            "A partially configured autopilot tier still refuses at exit 3, naming only "
            "the missing set -- there is no partial-credit tier."
        ),
        entry_point=MERGE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--autopilot-merge-tier",
            "--lane-logins",
            "lane",
            "--approver-bot-logins",
            "bot",
        ),
        exit_code=3,
        error_contains=("--block-labels",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
    ),
    Refusal(
        id="merge.tier-params-without-umbrella",
        claim=(
            "Tier parameter sets without --autopilot-merge-tier are a usage error at "
            "exit 2, never a silent no-op that reads as configured."
        ),
        entry_point=MERGE_CLI,
        argv=("owner/repo#1", "--allowed-owners", "owner", "--lane-logins", "lane"),
        exit_code=2,
        error_contains=("--autopilot-merge-tier",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
    ),
    Refusal(
        id="merge.unpinned-head-refused-by-wrapper",
        claim=(
            "The bin/ wrapper refuses --allow-unpinned-head in bash, before Python runs: "
            "no allow-rule-covered invocation of the bare command can merge an unvetted "
            "head. The refusal prints plain text to stderr and emits no JSON envelope, "
            "which is how a caller can tell the wrapper -- not the CLI -- rejected it."
        ),
        entry_point=MERGE_WRAPPER,
        argv=("owner/repo#1", "--merge", "--allow-unpinned-head"),
        exit_code=2,
        error_contains=("--allow-unpinned-head",),
        refused_by=BASH_WRAPPER,
        enforced_at="bin/source-control-babysit-merge (argument filter loop)",
    ),
    Refusal(
        id="merge.abbreviated-unpinned-head-refused-by-wrapper",
        claim=(
            "The wrapper refusal covers every long-option PREFIX of "
            "--allow-unpinned-head, not the exact spelling alone. An "
            "equality-only filter would let `--allow-unpinned-hea` through to an "
            "abbreviation-resolving parser and reinstate the override the wrapper "
            "exists to remove, so the prefix family is refused as one."
        ),
        entry_point=MERGE_WRAPPER,
        argv=("owner/repo#1", "--merge", "--allow-unpinned-hea"),
        exit_code=2,
        error_contains=("--allow-unpinned-hea",),
        refused_by=BASH_WRAPPER,
        enforced_at="bin/source-control-babysit-merge (argument filter loop)",
    ),
    Refusal(
        id="merge.abbreviation-is-not-resolved-by-the-cli",
        claim=(
            "The wrapper's prefix filter is belt to the CLI's braces: the parser "
            "sets allow_abbrev=False, so an abbreviated flag reaching Python "
            "directly is an unrecognized argument at exit 2 rather than a silently "
            "resolved override."
        ),
        entry_point=MERGE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--merge",
            "--allow-unpinned-hea",
        ),
        exit_code=2,
        error_contains=("--allow-unpinned-hea",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
    ),
    Refusal(
        id="merge.wrapper-reaches-failclosed-cli",
        claim=(
            "The wrapper adds no capability of its own: with no --allowed-owners it hands "
            "off to the CLI, which refuses at exit 3 exactly as a direct invocation does."
        ),
        entry_point=MERGE_WRAPPER,
        argv=("owner/repo#1",),
        exit_code=3,
        error_contains=("allowed-owners",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_merge.py::main",
    ),
    Refusal(
        id="resolve.allowlist-absent",
        claim=(
            "The thread resolver is fail-closed on scope the same way the merge gate is: "
            "no --allowed-owners means exit 3."
        ),
        entry_point=RESOLVE_CLI,
        argv=("owner/repo#1",),
        exit_code=3,
        error_contains=(),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_resolve_thread.py::main",
        envelope_fields=(("inScope", False),),
        gh_free=True,
    ),
    Refusal(
        id="resolve.count-pin-without-thread-id",
        claim=(
            "--expected-comment-count without --thread-id is a usage error at exit 2: a "
            "pin with no thread to pin would silently fall through to resolving every "
            "eligible thread."
        ),
        entry_point=RESOLVE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--expected-comment-count",
            "3",
        ),
        exit_code=2,
        error_contains=("thread-id",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_resolve_thread.py::main",
    ),
    Refusal(
        id="resolve.last-updated-pin-without-thread-id",
        claim=(
            "--expected-last-updated without --thread-id is a usage error at exit 2, for "
            "the same silent-bulk-fallthrough reason as the count pin."
        ),
        entry_point=RESOLVE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--expected-last-updated",
            "2026-07-17T10:00:00Z",
        ),
        exit_code=2,
        error_contains=("thread-id",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_resolve_thread.py::main",
    ),
    Refusal(
        id="resolve.thread-id-without-pins",
        claim=(
            "A --thread-id resolve requires BOTH TOCTOU pins; supplying neither is a "
            "usage error at exit 2 naming both missing flags."
        ),
        entry_point=RESOLVE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--resolve",
            "--thread-id",
            "PRRT_abc",
        ),
        exit_code=2,
        error_contains=("--expected-comment-count", "--expected-last-updated"),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_resolve_thread.py::main",
    ),
    Refusal(
        id="resolve.autonomous-bulk-refused",
        claim=(
            "--autonomous --resolve without --thread-id is refused at exit 2: --autonomous "
            "means SINGLE PINNED THREAD, never bulk. A worker's own push marks a thread "
            "isOutdated, so a bulk autonomous resolve would clear threads with no proof "
            "the finding was addressed."
        ),
        entry_point=RESOLVE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--autonomous",
            "--resolve",
        ),
        exit_code=2,
        error_contains=("thread-id", "bulk-resolve"),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_resolve_thread.py::main",
    ),
    Refusal(
        id="resolve.autonomous-allow-unpinned-refused",
        claim=(
            "There is no unpinned autonomous resolve: --allow-unpinned-thread is an "
            "interactive-only override and is refused at exit 2 under --autonomous even "
            "with a single --thread-id."
        ),
        entry_point=RESOLVE_CLI,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--autonomous",
            "--resolve",
            "--thread-id",
            "PRRT_abc",
            "--allow-unpinned-thread",
        ),
        exit_code=2,
        error_contains=("allow-unpinned-thread",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_resolve_thread.py::main",
    ),
    Refusal(
        id="resolve.wrapper-reaches-failclosed-cli",
        claim=(
            "The resolve wrapper is a pure passthrough: no --allowed-owners refuses at "
            "exit 3 from the CLI, unchanged by the wrapper."
        ),
        entry_point=RESOLVE_WRAPPER,
        argv=("owner/repo#1",),
        exit_code=3,
        error_contains=(),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_resolve_thread.py::main",
    ),
    Refusal(
        id="resolve.wrapper-filters-nothing",
        claim=(
            "ASYMMETRY: unlike the merge wrapper, the resolve wrapper filters no argument. "
            "Its --allow-unpinned-thread refusal comes from Python -- proven by the JSON "
            "envelope on stdout -- so an operator may not assume a bash-level refusal "
            "exists on this entry point just because one exists on the other."
        ),
        entry_point=RESOLVE_WRAPPER,
        argv=(
            "owner/repo#1",
            "--allowed-owners",
            "owner",
            "--autonomous",
            "--resolve",
            "--thread-id",
            "PRRT_abc",
            "--allow-unpinned-thread",
        ),
        exit_code=2,
        error_contains=("allow-unpinned-thread",),
        refused_by=PYTHON_CLI,
        enforced_at="babysit_resolve_thread.py::main",
    ),
    Refusal(
        id="ledger.apply-requires-lease-token",
        claim=(
            "A ledger write is lease-gated: --apply without --lease-token refuses at "
            "exit 2 rather than writing an unowned entry."
        ),
        entry_point=LEDGER_CLI,
        argv=(
            "dispose",
            "--pr",
            "owner/repo#1",
            "--expected-head-sha",
            "0123456789abcdef0123456789abcdef01234567",
            "--feedback-id",
            "F1",
            "--reason",
            "contract-row",
            "--state-dir",
            "{state_dir}",
            "--apply",
        ),
        exit_code=2,
        error_contains=("lease token",),
        refused_by=PYTHON_CLI,
        enforced_at="manage_feedback_ledger.py::main",
    ),
    Refusal(
        id="prune.root-is-required",
        claim=(
            "prune_babysit_worktrees.py has no default root: omitting --root is a usage "
            "error at exit 2, so it can never sweep an unintended directory."
        ),
        entry_point=PRUNE_CLI,
        argv=("--state-dir", "{state_dir}"),
        exit_code=2,
        error_contains=("--root",),
        refused_by=PYTHON_CLI,
        enforced_at="prune_babysit_worktrees.py::main",
    ),
    Refusal(
        id="lease.state-dir-is-required",
        claim=(
            "State-dir resolution is flag-only with no environment fallback: omitting "
            "--state-dir is a usage error at exit 2."
        ),
        entry_point=LEASE_CLI,
        argv=("reap",),
        exit_code=2,
        error_contains=("--state-dir",),
        refused_by=PYTHON_CLI,
        enforced_at="manage_babysit_lease.py::main",
    ),
    Refusal(
        id="lease.scope-required-for-non-reap",
        claim=(
            "--scope is required for acquire, heartbeat, and release; only reap runs "
            "without it."
        ),
        entry_point=LEASE_CLI,
        argv=("acquire", "--state-dir", "{state_dir}"),
        exit_code=2,
        error_contains=("--scope",),
        refused_by=PYTHON_CLI,
        enforced_at="manage_babysit_lease.py::main",
    ),
)


# --------------------------------------------------------------------------
# Predicates -- guards over runtime API data, asserted against the classifier.
# --------------------------------------------------------------------------

CLASSIFY_ANCHOR = "babysit_resolve_thread.py::classify"


def _thread(*, resolved: bool, bot_only: bool, outdated: bool) -> dict[str, object]:
    return {"isResolved": resolved, "botOnly": bot_only, "isOutdated": outdated}


PREDICATES: tuple[Predicate, ...] = (
    Predicate(
        id="classify.human-thread-refused-by-default",
        claim=(
            "Bot-only is a bright line, not a heuristic: a thread with ANY human "
            "participant is skipped whenever --include-human is absent, regardless of "
            "every other flag."
        ),
        enforced_at=CLASSIFY_ANCHOR,
        thread=_thread(resolved=False, bot_only=False, outdated=True),
        flags={"autonomous": False, "only_outdated": False, "include_human": False},
        expected="skipped-human-thread",
    ),
    Predicate(
        id="classify.include-human-opts-in",
        claim=(
            "--include-human is the ONLY thing that lifts the bot-only line. A permission "
            "rule asserting 'bot threads only' is false for any invocation carrying it."
        ),
        enforced_at=CLASSIFY_ANCHOR,
        thread=_thread(resolved=False, bot_only=False, outdated=True),
        flags={"autonomous": False, "only_outdated": False, "include_human": True},
        expected="eligible",
    ),
    Predicate(
        id="classify.autonomous-requires-outdated",
        claim=(
            "--autonomous requires the deterministic isOutdated 'addressed' signal: a "
            "still-current bot thread is skipped so an unattended worker cannot resolve "
            "a live finding and self-satisfy the merge gate."
        ),
        enforced_at=CLASSIFY_ANCHOR,
        thread=_thread(resolved=False, bot_only=True, outdated=False),
        flags={"autonomous": True, "only_outdated": False, "include_human": False},
        expected="skipped-not-outdated",
    ),
    Predicate(
        id="classify.only-outdated-requires-outdated",
        claim=(
            "--only-outdated imposes the same isOutdated requirement as --autonomous, "
            "independently of it."
        ),
        enforced_at=CLASSIFY_ANCHOR,
        thread=_thread(resolved=False, bot_only=True, outdated=False),
        flags={"autonomous": False, "only_outdated": True, "include_human": False},
        expected="skipped-not-outdated",
    ),
    Predicate(
        id="classify.interactive-does-not-require-outdated",
        claim=(
            "THE CLAIM CONSUMERS GET WRONG: 'resolves only outdated bot threads' is TRUE "
            "ONLY under --autonomous or --only-outdated. With neither flag, a current "
            "(not outdated) bot thread is eligible."
        ),
        enforced_at=CLASSIFY_ANCHOR,
        thread=_thread(resolved=False, bot_only=True, outdated=False),
        flags={"autonomous": False, "only_outdated": False, "include_human": False},
        expected="eligible",
    ),
    Predicate(
        id="classify.include-human-does-not-lift-outdated",
        claim=(
            "--include-human lifts only the bot-only line. Under --autonomous the "
            "isOutdated requirement still applies, so the two guards are independent and "
            "neither flag opens the other."
        ),
        enforced_at=CLASSIFY_ANCHOR,
        thread=_thread(resolved=False, bot_only=False, outdated=False),
        flags={"autonomous": True, "only_outdated": False, "include_human": True},
        expected="skipped-not-outdated",
    ),
    Predicate(
        id="classify.already-resolved-precedes-every-guard",
        claim=(
            "An already-resolved thread is skipped before any other guard is consulted, "
            "so a re-run never re-resolves and never reports a human thread it declined."
        ),
        enforced_at=CLASSIFY_ANCHOR,
        thread=_thread(resolved=True, bot_only=False, outdated=False),
        flags={"autonomous": True, "only_outdated": False, "include_human": False},
        expected="skipped-already-resolved",
    ),
)


# --------------------------------------------------------------------------
# Effects -- what actually touches disk, run offline against a temp state dir.
# --------------------------------------------------------------------------

EMPTY_STATE = "empty"
EXPIRED_WORKER_LEASE = "expired-worker-lease"

# Observed movement of the state directory's file set, asserted over the
# fingerprint's keys rather than named paths -- a path literal here would couple
# the contract to the lease writer's internal layout, which is exactly the drift
# this module refuses to encode.
UNCHANGED = "unchanged"
ADDED = "files added"
REMOVED = "files removed"
REWRITTEN = "same files, new contents"
DELTA_KINDS = (UNCHANGED, ADDED, REMOVED, REWRITTEN)

EFFECTS: tuple[Effect, ...] = (
    Effect(
        id="lease.acquire-writes-without-apply",
        claim=(
            "THE TRAP: manage_babysit_lease.py's --apply help reads 'reap only', but "
            "acquire writes a lease file unconditionally, with no --apply and no network. "
            "A permission rule that derives read-only from flag names classifies acquire "
            "wrong."
        ),
        entry_point=LEASE_CLI,
        argv=(
            "acquire",
            "--scope",
            "worker",
            "--pr",
            "owner/repo#1",
            "--state-dir",
            "{state_dir}",
        ),
        fixture=EMPTY_STATE,
        delta=ADDED,
        exit_code=0,
    ),
    Effect(
        id="lease.reap-without-apply-is-a-dry-run",
        claim=(
            "--apply gates reap alone: a reap without it reports which lease files are "
            "expired and deletes none of them."
        ),
        entry_point=LEASE_CLI,
        argv=("reap", "--state-dir", "{state_dir}"),
        fixture=EXPIRED_WORKER_LEASE,
        delta=UNCHANGED,
        exit_code=0,
    ),
    Effect(
        id="lease.reap-with-apply-deletes",
        claim=(
            "reap --apply deletes expired worker lease files. This is the one action on "
            "this script the --apply flag actually gates."
        ),
        entry_point=LEASE_CLI,
        argv=("reap", "--state-dir", "{state_dir}", "--apply"),
        fixture=EXPIRED_WORKER_LEASE,
        delta=REMOVED,
        exit_code=0,
    ),
)


# --------------------------------------------------------------------------
# Mechanisms -- HOW an entry point mutates, asserted against its source.
# --------------------------------------------------------------------------

MECHANISMS: tuple[Mechanism, ...] = (
    Mechanism(
        id="refresh.uses-server-side-update-branch",
        claim=(
            "refresh_pr_branch.py never pushes. It asks GitHub to update the branch "
            "server-side via PUT repos/{repo}/pulls/{number}/update-branch, pinned with "
            "expected_head_sha. A consumer reasoning about push guards for this script is "
            "reasoning about the wrong mechanism -- it needs no local write access to the "
            "branch at all."
        ),
        entry_point=REFRESH_CLI,
        must_contain=('pulls/{number}/update-branch', 'expected_head_sha='),
        must_not_contain=('"push"', "'push'"),
    ),
    Mechanism(
        id="review.posts-a-comment",
        claim=(
            "request_review.py --apply performs a GitHub write: it POSTs an issue comment "
            "carrying the review-trigger phrase. It is a mutating helper despite its "
            "read-sounding name."
        ),
        entry_point=REVIEW_CLI,
        must_contain=('"--method"', '"POST"'),
    ),
    Mechanism(
        id="prune.removes-worktrees-via-git",
        claim=(
            "prune_babysit_worktrees.py --apply runs `git worktree remove`, a destructive "
            "local filesystem operation. Its dry-run default is what makes the flagless "
            "form safe, not anything about the name."
        ),
        entry_point=PRUNE_CLI,
        must_contain=('"worktree", "remove"',),
    ),
    Mechanism(
        id="snapshot.write-state-gates-the-only-write",
        claim=(
            "pr_queue_snapshot.py's only queue-state write is the local snapshot, and "
            "--write-state is the only thing that reaches it. Nothing on any path writes "
            "to GitHub, so a flagless invocation reads the queue and persists nothing of "
            "it. Housekeeping is out of scope per the entry-point table's mutation "
            "definition: this script loads state unconditionally, so load_state may "
            "quarantine an already-corrupt state file whatever the flags say."
        ),
        entry_point=SNAPSHOT_CLI,
        must_contain=("if args.write_state:", "save_state("),
    ),
    Mechanism(
        id="merge.wrapper-filters-unpinned-head-in-bash",
        claim=(
            "The merge wrapper's refusal is a bash argument loop over \"$@\" that exits "
            "before the interpreter shim is sourced -- it is not, and must not become, "
            "an argparse flag on the Python side."
        ),
        entry_point=MERGE_WRAPPER,
        must_contain=('for arg in "$@"', "--allow-unpinned-head"),
    ),
    Mechanism(
        id="merge.parser-refuses-abbreviation",
        claim=(
            "babysit_merge.py builds its parser with allow_abbrev=False. Argparse's "
            "default would resolve any unambiguous prefix, so a permission rule "
            "written against a flag's exact spelling would not cover the prefixes "
            "that reach the same flag."
        ),
        entry_point=MERGE_CLI,
        must_contain=("allow_abbrev=False",),
    ),
    Mechanism(
        id="resolve.parser-refuses-abbreviation",
        claim=(
            "babysit_resolve_thread.py sets allow_abbrev=False for the same reason, "
            "and it carries more weight here: the resolve wrapper filters nothing, "
            "so the parser is the only layer refusing an abbreviated "
            "--allow-unpinned-thread."
        ),
        entry_point=RESOLVE_CLI,
        must_contain=("allow_abbrev=False",),
    ),
    Mechanism(
        id="resolve.wrapper-carries-no-filter",
        claim=(
            "ASYMMETRY, stated at the source: the resolve wrapper contains no argument "
            "filter loop. Adding one here without a matching row is the drift this "
            "contract exists to catch."
        ),
        entry_point=RESOLVE_WRAPPER,
        must_contain=("babysit_python",),
        must_not_contain=('for arg in "$@"',),
    ),
)


# --------------------------------------------------------------------------
# Entry points -- the mutating / read-only catalogue a permission rule cites.
# --------------------------------------------------------------------------

READ_ONLY = "read-only"
MUTATING = "mutating"
CONDITIONAL = "conditionally mutating"

ENTRY_POINTS: tuple[EntryPoint, ...] = (
    EntryPoint(
        path=MERGE_CLI,
        wrapper=MERGE_WRAPPER,
        mutation=CONDITIONAL,
        mutates_what="merges the PR on GitHub",
        gate="--merge (absent: readiness check only, exit 0 ready / 10 not ready)",
        claim=(
            "Without --merge this is a readiness reporter. With it, the TOCTOU guard "
            "requires --expected-head unless --allow-unpinned-head is passed -- and the "
            "bin/ wrapper refuses that override outright."
        ),
        backed_by=(
            "merge.allowlist-absent",
            "merge.unpinned-head-refused-by-wrapper",
            "merge.abbreviated-unpinned-head-refused-by-wrapper",
            "merge.abbreviation-is-not-resolved-by-the-cli",
            "merge.wrapper-filters-unpinned-head-in-bash",
            "merge.parser-refuses-abbreviation",
        ),
    ),
    EntryPoint(
        path=RESOLVE_CLI,
        wrapper=RESOLVE_WRAPPER,
        mutation=CONDITIONAL,
        mutates_what="marks review threads resolved on GitHub",
        gate="--resolve (absent: classification report only)",
        claim=(
            "Which threads it may touch is decided per fetched thread by the classifier, "
            "not by the argument shape -- see the predicate rows. The wrapper adds no "
            "refusal of its own."
        ),
        backed_by=(
            "resolve.allowlist-absent",
            "resolve.autonomous-bulk-refused",
            "classify.interactive-does-not-require-outdated",
            "resolve.wrapper-carries-no-filter",
            "resolve.parser-refuses-abbreviation",
        ),
    ),
    EntryPoint(
        path=LEASE_CLI,
        wrapper=None,
        mutation=MUTATING,
        mutates_what="writes, renews, and deletes lease files under --state-dir",
        gate=(
            "none for acquire / heartbeat / release -- they write unconditionally; "
            "--apply gates reap's deletion ONLY"
        ),
        claim=(
            "Local filesystem writes only, no GitHub write. The --apply flag does not "
            "make this script read-only in its other three actions."
        ),
        backed_by=(
            "lease.acquire-writes-without-apply",
            "lease.reap-without-apply-is-a-dry-run",
        ),
    ),
    EntryPoint(
        path=LEDGER_CLI,
        wrapper=None,
        mutation=CONDITIONAL,
        mutates_what="records feedback dispositions and fix rounds in queue state",
        gate="--apply, additionally requiring --lease-token",
        claim=(
            "Local state only, no GitHub write. The lease token requirement means an "
            "--apply invocation still refuses without proof of lease ownership."
        ),
        backed_by=("ledger.apply-requires-lease-token",),
    ),
    EntryPoint(
        path=PRUNE_CLI,
        wrapper=None,
        mutation=CONDITIONAL,
        mutates_what="runs `git worktree remove` on eligible worktrees under --root",
        gate="--apply (absent: dry run)",
        claim=(
            "The most destructive local helper in the lane. --root is required, so it "
            "cannot sweep a directory the caller did not name."
        ),
        backed_by=("prune.root-is-required", "prune.removes-worktrees-via-git"),
    ),
    EntryPoint(
        path=REFRESH_CLI,
        wrapper=None,
        mutation=CONDITIONAL,
        mutates_what="asks GitHub to update the PR branch server-side; writes queue state",
        gate="--apply",
        claim=(
            "Mutates the PR branch on GitHub WITHOUT pushing: the update is a pinned "
            "server-side update-branch API call."
        ),
        backed_by=("refresh.uses-server-side-update-branch",),
    ),
    EntryPoint(
        path=REVIEW_CLI,
        wrapper=None,
        mutation=CONDITIONAL,
        mutates_what="POSTs an issue comment requesting an AI re-review; writes queue state",
        gate="--apply",
        claim="A GitHub write despite the read-sounding name.",
        backed_by=("review.posts-a-comment",),
    ),
    EntryPoint(
        path=SNAPSHOT_CLI,
        wrapper=None,
        mutation=CONDITIONAL,
        mutates_what="writes the queue snapshot to local state",
        gate="--write-state (absent: reports the snapshot without persisting it)",
        claim=(
            "No GitHub write on any path. The only domain-state mutation is the local "
            "snapshot file."
        ),
        backed_by=("snapshot.write-state-gates-the-only-write",),
    ),
    EntryPoint(
        path=FINDINGS_CLI,
        wrapper=None,
        mutation=READ_ONLY,
        mutates_what="nothing",
        gate="n/a",
        claim="Pure classification over supplied input; no write of any kind.",
        backed_by=(),
    ),
    EntryPoint(
        path=READINESS_GATE,
        wrapper=None,
        mutation=READ_ONLY,
        mutates_what="nothing",
        gate="n/a",
        claim=(
            "The lane's one entry point outside the skill's own scripts directory, "
            "invoked by name from SKILL.md. It counts findings and classification "
            "rows over fetched comments and reports READINESS_OK / "
            "READINESS_BLOCKED; it writes no file and performs no GitHub write."
        ),
        backed_by=(),
    ),
)


# --------------------------------------------------------------------------
# Documents that spell out copyable wrapper command lines.
# --------------------------------------------------------------------------

DOC_COMMAND_SOURCES: tuple[DocCommandSource, ...] = (
    DocCommandSource(
        id="safety.pinned-command-degradation",
        claim=(
            "reference/safety.md hard-codes fully-argument-pinned bin/-path wrapper "
            "command lines for the operator to run when the runtime denies a mutation the "
            "gate already proved ready. Every wrapper path in it resolves, and every flag "
            "it names is one the backing CLI's parser accepts."
        ),
        doc="skills/babysit-prs/reference/safety.md",
    ),
    DocCommandSource(
        id="orchestration.worker-dispatch-commands",
        claim=(
            "reference/orchestration.md spells out the same bin/-path wrapper commands "
            "for the dispatched-worker and thread-resolve paths. It is a second copy of "
            "the same argument shapes and drifts independently of safety.md."
        ),
        doc="skills/babysit-prs/reference/orchestration.md",
    ),
)


# --------------------------------------------------------------------------
# Markdown emission.
# --------------------------------------------------------------------------

WRAPPER_BACKING_CLI = {
    MERGE_WRAPPER: MERGE_CLI,
    RESOLVE_WRAPPER: RESOLVE_CLI,
}

_PREAMBLE = """# Guard contract

<!-- Generated by scripts/tests/guard_contract.py -- edit that module, then run
     `python tests/guard_contract.py --emit`. Hand edits fail CI. -->

What a host permission classifier, an orchestration prompt, or a downstream
consumer may assume about this lane's entry points. Rows in the refusal,
predicate, effect, and documented-command tables are executed as assertions by
`scripts/tests/test_guards.py`; a guard change that falsifies one fails CI with
a message naming the claim. The columns listed under "Not covered here" are
rendered from the same data but are not asserted — read those as annotation, not
as proof.

Cite a row by its ID. IDs are stable; rows are removed only when the behavior is.

Source anchors are `file::symbol`, deliberately not line numbers.
"""


def _cell(text: str) -> str:
    return " ".join(text.split()).replace("|", "\\|")


def _argv(argv: tuple[str, ...]) -> str:
    return "`" + " ".join(argv) + "`" if argv else "(none)"


def render_markdown() -> str:
    lines = [_PREAMBLE.rstrip(), ""]

    lines += [
        "## Entry points: what mutates",
        "",
        "This table scopes `mutation` to DOMAIN state -- GitHub, the queue state file,"
        " worktrees, and leases -- and `gate` is the condition under which that domain"
        " mutation happens at all. It is deliberately not a filesystem-write audit: a"
        " state-touching script performs housekeeping under `--state-dir` whatever its"
        " flags say, so entering `state_lock` creates the state directory and a `.lock`"
        " sibling, and `load_state` quarantines an already-corrupt state file by renaming"
        " it. A classifier granting a gate-less invocation therefore still needs the"
        " script to be able to write inside `--state-dir`; what the gate withholds is the"
        " domain mutation, not every byte. A blank wrapper column means the entry point"
        " has no `bin/` wrapper and is invoked through the interpreter.",
        "",
        "| Entry point | Wrapper | Class | Mutates | Gate | Claim | Backed by |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for entry in ENTRY_POINTS:
        wrapper = f"`{entry.wrapper}`" if entry.wrapper else "--"
        backed = ", ".join(f"`{row}`" for row in entry.backed_by) or "--"
        lines.append(
            f"| `{entry.path}` | {wrapper} | {entry.mutation} | {_cell(entry.mutates_what)} "
            f"| {_cell(entry.gate)} | {_cell(entry.claim)} | {backed} |"
        )

    lines += [
        "",
        "## Refusals: guards that fire on argument shape alone",
        "",
        "Each row is executed. `Refused by` says which layer rejected the invocation."
        " On a `bin/` entry point the distinction is asserted, using the observable"
        " discriminator: a bash-wrapper refusal never reaches the interpreter, so it"
        " emits plain stderr and no JSON envelope. On a CLI entry point the layer is"
        " always `python-cli` and only the exit code and message are asserted.",
        "",
        "`No gh` marks the rows whose claim is that the refusal precedes every network"
        " call. Those are replayed a second time with a recording `gh` shim as the only"
        " executable on `PATH`, and the assertion is that the shim was never invoked --"
        " merely removing `gh` from `PATH` would let a swallowed lookup failure fall"
        " through to the same exit code and read as proof.",
        "",
        "| ID | Entry point | Invocation | Exit | Refused by | No gh | Error names"
        " | Enforced at | Claim |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in REFUSALS:
        names = ", ".join(f"`{token}`" for token in row.error_contains) or "--"
        lines.append(
            f"| `{row.id}` | `{row.entry_point}` | {_argv(row.argv)} | {row.exit_code} "
            f"| {row.refused_by} | {'asserted' if row.gh_free else '--'} | {names} "
            f"| `{row.enforced_at}` | {_cell(row.claim)} |"
        )

    lines += [
        "",
        "## Predicates: guards over runtime data, not flags",
        "",
        "These decide per fetched thread, so no argument shape can express them and no"
        " argparse introspection can recover them. `thread` is the projected thread"
        " record; `flags` are the classifier's keyword arguments.",
        "",
        "| ID | Thread | Flags | Result | Enforced at | Claim |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in PREDICATES:
        thread = ", ".join(f"{k}={v}" for k, v in row.thread.items())
        flags = ", ".join(f"{k}={v}" for k, v in row.flags.items())
        lines.append(
            f"| `{row.id}` | {thread} | {flags} | `{row.expected}` "
            f"| `{row.enforced_at}` | {_cell(row.claim)} |"
        )

    lines += [
        "",
        "## Effects: what reaches disk",
        "",
        "Executed offline against a throwaway state directory seeded with `Fixture`."
        " `State delta` is the observed before/after movement of that directory's file"
        " set, not a reading of the flag names, and it is directional rather than a"
        " changed/unchanged boolean: a row claiming deletion asserts that the file set"
        " strictly shrank, so a reap that rewrote the expired lease -- or touched some"
        " unrelated file -- fails it instead of passing on \"something changed\". The"
        " assertion is over the file set, deliberately not over named paths: a path"
        " literal here would couple this contract to the lease writer's internal"
        " layout. Advisory `.lock` siblings are excluded from the comparison.",
        "",
        "| ID | Entry point | Invocation | Fixture | Exit | State delta | Claim |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in EFFECTS:
        lines.append(
            f"| `{row.id}` | `{row.entry_point}` | {_argv(row.argv)} | {row.fixture} "
            f"| {row.exit_code} | {row.delta} | {_cell(row.claim)} |"
        )

    lines += [
        "",
        "## Mechanisms: how a mutation is performed",
        "",
        "Asserted against the entry point's source, because the mechanism -- not just"
        " the fact of mutation -- decides which permission rule is the relevant one.",
        "",
        "| ID | Entry point | Claim |",
        "| --- | --- | --- |",
    ]
    for row in MECHANISMS:
        lines.append(f"| `{row.id}` | `{row.entry_point}` | {_cell(row.claim)} |")

    lines += [
        "",
        "## Documented command lines",
        "",
        "Documents that spell out copyable `bin/`-path wrapper commands. Every wrapper"
        " path is checked to resolve and every flag against the backing CLI's own"
        " parser, so a renamed or removed flag fails here instead of in an operator's"
        " terminal.",
        "",
        "| ID | Document | Claim |",
        "| --- | --- | --- |",
    ]
    for row in DOC_COMMAND_SOURCES:
        lines.append(f"| `{row.id}` | `{row.doc}` | {_cell(row.claim)} |")

    lines += [
        "",
        "## Not covered here",
        "",
        "- Flag names, types, and defaults are not catalogued. A behavior row exercises"
        " the flags it names; a rename or default change elsewhere is not detected. See"
        " the deferral note in `scripts/tests/guard_contract.py`.",
        "- Anything requiring a live GitHub response. Every row above runs with no"
        " network access, which is what keeps the suite free of a `gh` stub.",
        "- Five rendered columns are annotation rather than assertion, and a rule"
        " must not be written against them as if CI proved them: the entry-point"
        " table's **Class**, **Mutates**, **Gate**, and **Claim**, and the refusal"
        " table's **Enforced at**. The entry-point rows assert the path and the"
        " wrapper; nothing reads the prose in those columns."
        " `Predicate.enforced_at` *is* checked -- `test_anchor_symbol_exists`"
        " resolves it -- but `Refusal.enforced_at` is not, so a refusal's location"
        " may drift without failing CI.",
        "- **Class** carries two partial bindings and one real gap, so read it"
        " precisely. Bound: a non-read-only row must name at least one backing"
        " row, and a `read-only` row may not be cited by any effect row that moves"
        " state or by any mechanism row -- so a read-only entry point that grows"
        " mutation evidence fails CI. Not bound: that a `mutating` or"
        " `conditionally mutating` row's cited evidence actually demonstrates the"
        " class it declares. It cannot be, for the four entry points whose"
        " mutation is a GitHub write -- the merge gate, the thread resolver,"
        " `refresh_pr_branch.py`, and `request_review.py`. Every row in this"
        " contract runs with no network access, by design, so no offline assertion"
        " can witness their mutation; binding the column would mean either a `gh`"
        " stub (asserting the stub, not the behavior) or a live-credential CI"
        " suite. An entry point that turns from conditional to unconditional"
        " mutation therefore still passes. Trigger to revisit: the first time a"
        " class changes without a matching row change, or the first offline-"
        "observable mutation appearing on a GitHub-writing entry point.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--emit",
        action="store_true",
        help="write the generated markdown to reference/guard-contract.md",
    )
    args = parser.parse_args()
    rendered = render_markdown()
    if args.emit:
        GENERATED_DOC.write_text(rendered, encoding="utf-8", newline="\n")
        print(f"wrote {GENERATED_DOC}")
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
