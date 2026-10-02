#!/usr/bin/env python3
"""Per-target-repository resolution of the babysit repository-policy keys.

Seven keys are read from the TARGET repository's tracked `.claude/source-control.md`
on its default branch, through the contents API with no `ref`, so neither the
launching checkout's working tree nor a personal layer (user-global, local
overlay) can supply a value. The operator's `userConfig` value is the deprecated
fallback, merged per key by the modes `merge_repo_config` documents. The review
bot logins, settle minutes and trigger phrase stay `userConfig`-only: a
repository declaration of any of them is ignored. The fetch and the merge are
separate so the merge is unit-testable without a network seam.
"""

from __future__ import annotations

import base64
import binascii
import json
import math
import re
import subprocess
import sys
from collections.abc import Callable, Mapping
from dataclasses import dataclass

from babysit_classify import normalize_login_set
from babysit_gh import gh_capture, gh_http_status, is_owner_repo_pair
from babysit_util import is_json_object

CONFIG_PATH = ".claude/source-control.md"

UNION_KEYS = (
    "babysit_merge_block_labels",
    "babysit_extra_dependency_manager_logins",
    "babysit_approval_downgrade_logins",
)
REVIEW_BOTS = "babysit_review_bot_logins"
REVIEW_SETTLE = "babysit_review_settle_minutes"
TRIGGER_PHRASE = "babysit_review_trigger_phrase"
SKIP_DOWNGRADE = "babysit_skip_downgrade_logins"
OVERRIDE_KEYS = (
    "babysit_merge_method",
    "babysit_review_gate_context",
    "babysit_ci_gateway_context",
)
LIST_KEYS = frozenset((*UNION_KEYS, REVIEW_BOTS, SKIP_DOWNGRADE))
LOGIN_KEYS = LIST_KEYS - {"babysit_merge_block_labels"}
KEYS = (
    *UNION_KEYS,
    REVIEW_BOTS,
    REVIEW_SETTLE,
    TRIGGER_PHRASE,
    SKIP_DOWNGRADE,
    *OVERRIDE_KEYS,
)
MERGE_METHODS = ("squash", "merge", "rebase")

HEADING_RE = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
H2_PREFIX = "## "
FENCE_RE = re.compile(r"^\s*(```|~~~)")

# Each key's deprecated `userConfig` value arrives as this CLI flag's parsed dest.
FLAG_DESTS = {
    "babysit_merge_method": "method",
    "babysit_merge_block_labels": "block_labels",
    "babysit_extra_dependency_manager_logins": "extra_dependency_manager_logins",
    "babysit_approval_downgrade_logins": "approval_downgrade_logins",
    "babysit_skip_downgrade_logins": "skip_downgrade_logins",
    TRIGGER_PHRASE: "trigger_phrase",
    REVIEW_BOTS: "review_bot_logins",
    REVIEW_SETTLE: "review_settle_minutes",
    "babysit_review_gate_context": "review_gate_context",
    "babysit_ci_gateway_context": "ci_gateway_context",
}

GhRunner = Callable[[list[str]], subprocess.CompletedProcess[str]]
RepoLayer = dict[str, str | frozenset[str]]


class RepoConfigError(RuntimeError):
    """The repository layer could not be read or parsed; callers fail closed."""


@dataclass(frozen=True)
class EffectiveConfig:
    merge_method: str | None
    merge_block_labels: frozenset[str]
    extra_dependency_manager_logins: frozenset[str]
    approval_downgrade_logins: frozenset[str]
    skip_downgrade_logins: frozenset[str]
    review_trigger_phrase: str | None
    # The userConfig pair, passed through raw so the merge gate's own
    # both-or-neither refusal still sees a half-set pair.
    review_bot_logins: frozenset[str] | None
    review_settle_minutes: str | None
    review_gate_context: str | None
    ci_gateway_context: str | None
    fallback_keys_used: frozenset[str]
    notes: tuple[str, ...] = ()


def _split_list(lines: list[str]) -> frozenset[str]:
    items: set[str] = set()
    for line in lines:
        line = re.sub(r"^[-*+]\s+", "", line.strip())
        items.update(part.strip().strip("`").strip() for part in line.split(","))
    return frozenset(item for item in items if item)


def _settle_seconds(raw: str) -> int | None:
    """Whole seconds of a settle value, or None unless it is at least one second.

    Mirrors the merge gate's own check, so NaN, infinity, and sub-second values
    never reach the floor comparison.
    """
    try:
        minutes = float(raw)
    except ValueError:
        return None
    if not math.isfinite(minutes) or round(minutes * 60) < 1:
        return None
    return round(minutes * 60)


def parse_repo_config(text: str) -> RepoLayer:
    """The ten keys' values from a markdown body of `## <key>` H2 sections.

    Other sections (the convention and loop-lane keys) are ignored, as are
    headings inside fences. A duplicate section, a present-but-empty section, a
    near-miss heading (a key name at another level, in another case, or with
    extra text), or an invalid scalar raises `RepoConfigError`.
    """
    sections: dict[str, list[str]] = {}
    current: list[str] | None = None
    in_fence = False
    for raw in text.removeprefix("﻿").replace("\r\n", "\n").split("\n"):
        if FENCE_RE.match(raw):
            in_fence = not in_fence
            continue
        heading = None if in_fence else HEADING_RE.match(raw)
        if heading:
            title = heading.group(1)
            current = None
            if raw.startswith(H2_PREFIX) and title in KEYS:
                if title in sections:
                    raise RepoConfigError(f"duplicate `## {title}` section")
                current = sections[title] = []
            elif any(key in title.casefold() for key in KEYS):
                raise RepoConfigError(f"near-miss heading {raw.strip()!r}")
        elif current is not None and raw.strip():
            current.append(raw.strip())

    layer: RepoLayer = {}
    for key, lines in sections.items():
        if key in LIST_KEYS:
            values = _split_list(lines)
            layer[key] = normalize_login_set(values) if key in LOGIN_KEYS else values
        else:
            layer[key] = lines[0].strip("`").strip() if lines else ""
        if not layer[key]:
            raise RepoConfigError(f"`## {key}` section has no value")
    method = layer.get("babysit_merge_method")
    if method is not None and method not in MERGE_METHODS:
        raise RepoConfigError(
            f"babysit_merge_method {method!r} is not one of {MERGE_METHODS}"
        )
    settle = layer.get(REVIEW_SETTLE)
    if isinstance(settle, str) and _settle_seconds(settle) is None:
        raise RepoConfigError(f"{REVIEW_SETTLE} {settle!r} is not at least one second")
    return layer


def _fallback_set(fallback: Mapping[str, str], key: str) -> frozenset[str]:
    values = _split_list([fallback.get(key, "")])
    return normalize_login_set(values) if key in LOGIN_KEYS else values


def _repo_set(repo: RepoLayer, key: str) -> frozenset[str] | None:
    value = repo.get(key)
    return value if isinstance(value, frozenset) else None


def _repo_scalar(repo: RepoLayer, key: str) -> str | None:
    value = repo.get(key)
    return value if isinstance(value, str) else None


def merge_repo_config(
    repo: RepoLayer, raw_fallback: Mapping[str, str | None]
) -> EffectiveConfig:
    """Merge a parsed repository layer with the deprecated `userConfig` values.

    `raw_fallback` maps each key to its raw `userConfig` (CLI flag) string; a
    missing, None, or blank value is unset. Modes:

    - Hold lists (`UNION_KEYS`): add-only union, so neither side drops an entry.
    - Review pair (`babysit_review_bot_logins` + `babysit_review_settle_minutes`):
      `userConfig`-only. The merge gate clears the settle hold when ANY listed
      reviewer has reviewed the head, so a repository-writable reviewer list
      could clear the hold before the operator's reviewer ran, and replacing the
      operator's list could swap that reviewer out. Neither is decided here, so a
      repository declaration of either key is ignored with a note and the
      `userConfig` pair passes through unchanged.
    - `babysit_review_trigger_phrase`: `userConfig`-only. The phrase is the text
      the operator's account posts, and a repository must not choose it, so a
      repository declaration is ignored with a note and the `userConfig` value
      is used.
    - `babysit_skip_downgrade_logins`: remove-only. When the repository declares
      the key, the effective set is the `userConfig` set intersected with it; a
      repository can never add a login. The `userConfig` value stays the key's
      only additive source, so its use is not deprecated and raises no note.
    - `OVERRIDE_KEYS` (merge method, review gate and CI gateway contexts): the
      repository default-branch value wins; `userConfig` applies only when the
      repository declares none.
    """
    fallback = {k: v for k, v in raw_fallback.items() if v and v.strip()}
    used: set[str] = set()
    notes: list[str] = []

    unions: dict[str, frozenset[str]] = {}
    for key in UNION_KEYS:
        unions[key] = _fallback_set(fallback, key) | (
            _repo_set(repo, key) or frozenset()
        )
        if key in fallback:
            used.add(key)

    skip = _fallback_set(fallback, SKIP_DOWNGRADE)
    repo_skip = _repo_set(repo, SKIP_DOWNGRADE)
    if repo_skip is not None:
        skip &= repo_skip

    if REVIEW_BOTS in repo or REVIEW_SETTLE in repo:
        notes.append(
            f"{REVIEW_BOTS} and {REVIEW_SETTLE} are userConfig-only, so the "
            "repository's declaration is ignored"
        )
    bots = _fallback_set(fallback, REVIEW_BOTS) if REVIEW_BOTS in fallback else None
    if TRIGGER_PHRASE in repo:
        notes.append(
            f"{TRIGGER_PHRASE} is userConfig-only, so the repository's "
            "declaration is ignored"
        )

    overrides: dict[str, str | None] = {}
    for key in OVERRIDE_KEYS:
        overrides[key] = _repo_scalar(repo, key)
        if overrides[key] is None and key in fallback:
            overrides[key] = fallback[key]
            used.add(key)

    return EffectiveConfig(
        merge_method=overrides["babysit_merge_method"],
        merge_block_labels=unions["babysit_merge_block_labels"],
        extra_dependency_manager_logins=unions[
            "babysit_extra_dependency_manager_logins"
        ],
        approval_downgrade_logins=unions["babysit_approval_downgrade_logins"],
        skip_downgrade_logins=skip,
        review_trigger_phrase=fallback.get(TRIGGER_PHRASE),
        review_bot_logins=bots,
        review_settle_minutes=fallback.get(REVIEW_SETTLE),
        review_gate_context=overrides["babysit_review_gate_context"],
        ci_gateway_context=overrides["babysit_ci_gateway_context"],
        fallback_keys_used=frozenset(used),
        notes=tuple(notes),
    )


def fallback_from_args(args: object) -> dict[str, str | None]:
    """The `userConfig` fallback mapping from a parsed CLI namespace.

    A flag the calling script does not define reads as unset, and so does a merge
    method of `auto`, the picker's name for repo convention then squash.
    """
    fallback = {key: getattr(args, dest, None) for key, dest in FLAG_DESTS.items()}
    if fallback["babysit_merge_method"] == "auto":
        fallback["babysit_merge_method"] = None
    return fallback


def _contents_readable(gh_runner: GhRunner, owner: str, name: str) -> bool:
    try:
        return gh_runner(["api", f"repos/{owner}/{name}/contents"]).returncode == 0
    except (RuntimeError, ValueError, OSError):
        return False


def fetch_repo_config(owner_repo: str, gh_runner: GhRunner | None = None) -> RepoLayer:
    """The repository layer from the default branch; empty when the file is absent.

    A 404 that `gh` itself reported means "no file" only when the repository's
    root listing is readable: GitHub answers 404 for an existing private
    resource the token cannot read, so an unreadable root is a hidden file and
    raises. Every other failure (another status, no status, a timeout, a
    missing gh, an unexpected payload, a parse error) raises `RepoConfigError`.
    """
    gh_runner = gh_runner or gh_capture
    owner, _, name = owner_repo.partition("/")
    if not is_owner_repo_pair(owner, name):
        raise RepoConfigError(f"not an owner/repo pair: {owner_repo!r}")
    try:
        proc = gh_runner(["api", f"repos/{owner}/{name}/contents/{CONFIG_PATH}"])
    except (RuntimeError, ValueError, OSError) as exc:
        raise RepoConfigError(
            f"{owner_repo}: {CONFIG_PATH} fetch failed: {exc}"
        ) from exc
    if proc.returncode != 0:
        if gh_http_status(proc.stderr or "") == 404:
            if _contents_readable(gh_runner, owner, name):
                return {}
            raise RepoConfigError(
                f"{owner_repo}: {CONFIG_PATH} answered 404 and the repository "
                "contents are not readable, so the file may exist but be hidden "
                "from this token"
            )
        detail = (proc.stderr or "").strip() or f"exit {proc.returncode}"
        raise RepoConfigError(f"{owner_repo}: {CONFIG_PATH} fetch failed: {detail}")
    try:
        payload = json.loads(proc.stdout)
        if not (
            is_json_object(payload)
            and payload.get("type") == "file"
            and payload.get("encoding") == "base64"
            and payload.get("content")
        ):
            raise ValueError("response is not a base64 file payload")
        text = base64.b64decode(str(payload["content"])).decode("utf-8")
    except (ValueError, binascii.Error) as exc:
        raise RepoConfigError(f"{owner_repo}: {CONFIG_PATH} unreadable: {exc}") from exc
    try:
        return parse_repo_config(text)
    except RepoConfigError as exc:
        raise RepoConfigError(f"{owner_repo}: {CONFIG_PATH}: {exc}") from exc


_cache: dict[str, RepoLayer | RepoConfigError] = {}
_noted: set[str] = set()


def reset_cache() -> None:
    _cache.clear()
    _noted.clear()


def _note_once(token: str, message: str) -> None:
    if token not in _noted:
        _noted.add(token)
        print(f"babysit-prs: {message}", file=sys.stderr)


def resolve(
    owner_repo: str,
    fallback: Mapping[str, str | None],
    gh_runner: GhRunner | None = None,
) -> EffectiveConfig:
    """Effective policy for one target repository; raises `RepoConfigError`.

    The fetched layer, or its error, is cached per repository for the process,
    so one run sees one view of each repository. A deprecation note naming the
    repository key is printed once per key per process whenever a deprecated
    `userConfig` value takes effect. The review pair, the trigger phrase and
    `babysit_skip_downgrade_logins` are not deprecated and print none.
    """
    cache_key = owner_repo.casefold()
    if cache_key not in _cache:
        try:
            _cache[cache_key] = fetch_repo_config(owner_repo, gh_runner)
        except RepoConfigError as exc:
            _cache[cache_key] = exc
    layer = _cache[cache_key]
    if isinstance(layer, RepoConfigError):
        raise layer
    effective = merge_repo_config(layer, fallback)
    for note in effective.notes:
        _note_once(f"{cache_key}:{note}", f"{owner_repo}: {note}")
    for key in sorted(effective.fallback_keys_used):
        _note_once(
            key,
            f"the userConfig value for {key} is deprecated; declare `## {key}` in "
            f"each target repository's tracked {CONFIG_PATH} instead",
        )
    return effective
