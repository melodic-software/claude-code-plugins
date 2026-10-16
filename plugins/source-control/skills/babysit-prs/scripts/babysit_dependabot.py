#!/usr/bin/env python3
"""Tier a Dependabot pull request for the pr-merge lane: `auto` or `review`.

`classify()` is a pure function over the pull request's title and its commits
as the REST pull-request commits API lists them; the caller reads GitHub and
hands them in. Tier `auto` is a pull request the lane may merge on a green
`ci-status`: every commit is a GitHub-verified Dependabot commit (or the
repository's own `[dependabot skip]` version-bump commit, below), and every
dependency it updates is a semver-patch or semver-minor update. Anything else,
including anything this module cannot read, is tier `review`: a major update,
an unknown update type, a commit by anyone else. Tier `review` never merges in
the pr-merge lane; the pr-unblock lane's review activity owns it.

The update types come from the `updated-dependencies` metadata Dependabot
writes into its commit message (the block `dependabot/fetch-metadata` parses),
which a verified signature binds to Dependabot. A single-dependency title
`Bump X from A to B` is read too: it fills an entry with no update type, and a
title that reads as a major update makes the pull request `review` whatever
the metadata says. A group title's `with N updates` must match the metadata's
count.

The one non-Dependabot commit accepted mirrors
`scripts/lib/changelog-fragments.sh` (`dependabot_only`): authored by
github-actions[bot], committed and verified by GitHub, its message carrying
`[dependabot skip]`, and touching only `plugins/<name>/.claude-plugin/plugin.json`
or `plugins/<name>/CHANGELOG.md` (pr-bump-plugin-version.yml).
"""

from __future__ import annotations

import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any

from babysit_util import json_object

AUTO = "auto"
REVIEW = "review"

# The forms the author login takes across the gh CLI, REST and GraphQL.
DEPENDABOT_LOGINS = frozenset({"app/dependabot", "dependabot[bot]", "dependabot"})
DEPENDABOT_AUTHOR = (
    "dependabot[bot]",
    "49699333+dependabot[bot]@users.noreply.github.com",
)
ACTIONS_AUTHOR = (
    "github-actions[bot]",
    "41898282+github-actions[bot]@users.noreply.github.com",
)
GITHUB_COMMITTER_EMAIL = "noreply@github.com"
SKIP_MARKER = "[dependabot skip]"
NON_MAJOR = frozenset({"semver-patch", "semver-minor"})

_ENTRY_RE = re.compile(r"^-\s+dependency-name:\s*(\S+)\s*$")
_TYPE_RE = re.compile(r"^\s+update-type:\s*(\S+)\s*$")
_TITLE_BUMP_RE = re.compile(r"\bbump\s+(\S+)\s+from\s+(\S+)\s+to\s+(\S+)", re.I)
_TITLE_GROUP_RE = re.compile(r"\bwith\s+(\d+)\s+updates?\b", re.I)
_VERSION_RE = re.compile(r"^v?(\d+)(?:\.(\d+))?")
_BUMP_PATH_RE = re.compile(
    r"^plugins/[A-Za-z0-9._-]+/(\.claude-plugin/plugin\.json|CHANGELOG\.md)$"
)


@dataclass(frozen=True)
class Update:
    name: str
    update_type: str | None  # semver-patch, semver-minor, semver-major, or None


@dataclass(frozen=True)
class Classification:
    tier: str  # AUTO or REVIEW
    reason: str | None  # why REVIEW; None for AUTO
    updates: tuple[Update, ...] = ()

    def report(self) -> dict[str, Any]:
        return {
            "tier": self.tier,
            "reason": self.reason,
            "updates": [
                {"name": u.name, "updateType": u.update_type} for u in self.updates
            ],
        }


def is_dependabot(login: Any) -> bool:
    return str(login or "").strip().casefold() in DEPENDABOT_LOGINS


def parse_metadata(message: str) -> list[Update] | None:
    """The `updated-dependencies` entries of one commit message, or None when
    the message has no such block."""
    lines = message.replace("\r\n", "\n").split("\n")
    try:
        start = next(
            i for i, line in enumerate(lines) if line.strip() == "updated-dependencies:"
        )
    except StopIteration:
        return None
    entries: list[list[str | None]] = []
    for line in lines[start + 1 :]:
        if line.strip() in ("...", "---") or (line and not line.startswith(("-", " "))):
            break
        if entry := _ENTRY_RE.match(line):
            entries.append([entry.group(1), None])
        elif (kind := _TYPE_RE.match(line)) and entries:
            entries[-1][1] = kind.group(1).removeprefix("version-update:")
    return [Update(str(name), kind) for name, kind in entries]


def _version(text: str) -> tuple[int, int | None] | None:
    found = _VERSION_RE.match(text.strip("`'\""))
    if not found:
        return None
    minor = found.group(2)
    return int(found.group(1)), int(minor) if minor is not None else None


def title_update_type(title: str) -> str | None:
    """The update type a `Bump X from A to B` title reads as, or None. A 0.x
    minor change reads as major, since semver promises nothing below 1.0."""
    found = _TITLE_BUMP_RE.search(title)
    if not found:
        return None
    old, new = _version(found.group(2)), _version(found.group(3))
    if old is None or new is None:
        return None
    if old[0] != new[0] or (old[0] == 0 and old[1] != new[1]):
        return "semver-major"
    return "semver-minor" if old[1] != new[1] else "semver-patch"


def commit_refusal(
    item: Any, files: Callable[[str], Sequence[str] | None]
) -> str | None:
    """Why one REST pull-request commit is not Dependabot's own, or None.
    `files(sha)` lists a commit's changed paths, or None when unreadable; it
    is read only for a github-actions[bot] commit."""
    entry = json_object(item)
    commit = json_object(entry.get("commit"))
    sha = str(entry.get("sha") or "?")[:12]
    author = json_object(commit.get("author"))
    committer = json_object(commit.get("committer"))
    if json_object(commit.get("verification")).get("verified") is not True:
        return f"commit-unverified:{sha}"
    if committer.get("email") != GITHUB_COMMITTER_EMAIL:
        return f"commit-not-committed-by-github:{sha}"
    signed = (author.get("name"), author.get("email"))
    if signed == DEPENDABOT_AUTHOR:
        return None
    if signed != ACTIONS_AUTHOR or SKIP_MARKER not in str(commit.get("message") or ""):
        return f"commit-not-dependabot:{sha}"
    paths = files(str(entry.get("sha") or ""))
    if not paths or any(not _BUMP_PATH_RE.match(p) for p in paths):
        return f"commit-not-version-bump:{sha}"
    return None


def classify(
    title: str,
    commits: Sequence[Any],
    files: Callable[[str], Sequence[str] | None],
) -> Classification:
    """The tier of a Dependabot pull request from its title and its commits."""
    if not commits:
        return Classification(REVIEW, "commits-missing")
    updates: list[Update] = []
    for item in commits:
        refusal = commit_refusal(item, files)
        if refusal:
            return Classification(REVIEW, refusal)
        commit = json_object(json_object(item).get("commit"))
        author = json_object(commit.get("author"))
        if (author.get("name"), author.get("email")) == DEPENDABOT_AUTHOR:
            updates.extend(parse_metadata(str(commit.get("message") or "")) or [])
    if not updates:
        return Classification(REVIEW, "metadata-missing")
    titled = title_update_type(title)
    if len(updates) == 1 and updates[0].update_type is None and titled:
        updates = [Update(updates[0].name, titled)]
    found = tuple(updates)
    if titled == "semver-major":
        return Classification(REVIEW, "title-major", found)
    group = _TITLE_GROUP_RE.search(title)
    if group and int(group.group(1)) not in (len(found), len({u.name for u in found})):
        return Classification(
            REVIEW, f"group-count:{group.group(1)}-of:{len(found)}", found
        )
    for update in found:
        if update.update_type == "semver-major":
            return Classification(REVIEW, f"major:{update.name}", found)
        if update.update_type not in NON_MAJOR:
            return Classification(REVIEW, f"update-type-unknown:{update.name}", found)
    return Classification(AUTO, None, found)
