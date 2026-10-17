#!/usr/bin/env python3
"""The pr-merge lane's Dependabot class: the tier, the commit check, and the
review activity's merge verdict. Pure functions; the caller reads GitHub.

`classify()` sorts a Dependabot pull request by the rules both lanes share
(the pr-unblock lane's `.github/scripts/pr-unblock/dependency-classify.mjs`
uses the same; contract: docs/conventions/pr-pipeline/README.md, "Dependabot
pull requests"):

- `auto`: every update is non-major, where major means the first numeric
  version component changes or, below 1.0, the second does; every
  `github_actions` update (head branch `dependabot/github_actions/...`) comes
  from the `actions`, `github` or `anthropics` publisher; and the newest
  `ci-status` run on the head is not red.
- `review`: anything else, including anything this cannot read.

The updates come from the `updated-dependencies` metadata in Dependabot's
verified commit message when it is there, and from the title (`bump <name>
from <a> to <b>`) or a group's body `Updates` lines otherwise. When both read,
they must name the same dependencies and agree on which are major.

The lane merges a tier `auto` pull request, and a tier `review` one only when
the newest review-dependency round marker the lanes App posted names the
current head with `verdict=merge` (`merge_verdict`).

`commit_refusal()` is the merge gate's commit check: a GitHub-verified
Dependabot commit, the repository's `[dependabot skip]` version-bump commit
(github-actions[bot], touching only a plugin's `plugin.json` or `CHANGELOG.md`;
the shape `scripts/lib/changelog-fragments.sh` `dependabot_only` accepts), or,
for a reviewed pull request, a verified `[dependabot skip]` fix commit the
lanes App authored.
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
ACTIONS_PUBLISHERS = ("actions", "github", "anthropics")
RED = frozenset(
    {"failure", "cancelled", "timed_out", "action_required", "startup_failure"}
)
MARKER_PREFIX = "<!-- pr-unblock:review-dependency-round "

_PREFIX = re.compile(r"^[a-z]+(\([^)]*\))?!?:\s*", re.I)
_SINGLE = re.compile(r"\bbump (\S+) from (\S+) to (\S+?)(?:\s+in\s.*)?$", re.I)
_GROUP = re.compile(r"\bbump the \S+ group\b.*\bwith (\d+) updates?\s*$", re.I)
_UPDATE_LINE = re.compile(r"^Updates `([^`\s]+)` from (\S+) to (\S+?)\.?$", re.M)
_VERSION = re.compile(r"^v?(\d+)(?:\.(\d+))?(?:\.\d+)*(?:[-+.][0-9A-Za-z.+-]*)?$")
_ECOSYSTEM = re.compile(r"^dependabot/([^/]+)/")
_ENTRY = re.compile(r"^-\s+dependency-name:\s*(\S+)\s*$")
_FIELD = re.compile(r"^\s+(dependency-version|update-type):\s*(\S+)\s*$")
_MARKER = re.compile(
    r"^<!-- pr-unblock:review-dependency-round head=([0-9a-f]{40}) "
    r"verdict=([a-z]+) run=([0-9]+-[0-9]+) -->$"
)
_BUMP_PATH = re.compile(
    r"^plugins/[A-Za-z0-9._-]+/(\.claude-plugin/plugin\.json|CHANGELOG\.md)$"
)


@dataclass(frozen=True)
class Update:
    name: str
    major: bool | None  # None when unreadable


@dataclass(frozen=True)
class Classification:
    tier: str  # AUTO or REVIEW
    reasons: tuple[str, ...] = ()  # why REVIEW; empty for AUTO
    updates: tuple[Update, ...] = ()
    ecosystem: str = ""
    # The approving round marker's run, for a REVIEW pull request the
    # review activity passed; None otherwise.
    approved: str | None = None

    @property
    def reason(self) -> str | None:
        return ",".join(self.reasons) or None

    @property
    def mergeable(self) -> bool:
        return self.tier == AUTO or self.approved is not None

    def report(self) -> dict[str, Any]:
        return {
            "tier": self.tier,
            "reasons": list(self.reasons),
            "ecosystem": self.ecosystem,
            "approved": self.approved,
            "updates": [{"name": u.name, "major": u.major} for u in self.updates],
        }


def is_dependabot(login: Any) -> bool:
    return str(login or "").strip().casefold() in DEPENDABOT_LOGINS


def _parts(version: str) -> tuple[int, int | None] | None:
    found = _VERSION.match(str(version))
    if not found:
        return None
    second = found.group(2)
    return int(found.group(1)), int(second) if second is not None else None


def is_major(old: str, new: str) -> bool | None:
    """Whether the first numeric version component changed or, below 1.0, the
    second did; None when either side is not a version (a SHA, a branch)."""
    a, b = _parts(old), _parts(new)
    if a is None or b is None:
        return None
    return a[0] != b[0] or (a[0] == 0 and a[1] != b[1])


def parse_metadata(message: str) -> list[Update] | None:
    """The `updated-dependencies` entries of one commit message, or None when
    it has none. A `semver-minor` update to a 0.x version is major."""
    lines = str(message).replace("\r\n", "\n").split("\n")
    try:
        start = next(
            i for i, line in enumerate(lines) if line.strip() == "updated-dependencies:"
        )
    except StopIteration:
        return None
    entries: list[dict[str, str]] = []
    for line in lines[start + 1 :]:
        if line.strip() in ("...", "---") or (line and not line.startswith(("-", " "))):
            break
        if entry := _ENTRY.match(line):
            entries.append({"name": entry.group(1)})
        elif (field := _FIELD.match(line)) and entries:
            entries[-1][field.group(1)] = field.group(2)
    updates = []
    for entry in entries:
        kind = entry.get("update-type", "").removeprefix("version-update:")
        version = _parts(entry.get("dependency-version", ""))
        major: bool | None = None
        if kind == "semver-major":
            major = True
        elif kind == "semver-patch":
            major = False
        elif kind == "semver-minor" and version is not None:
            major = version[0] == 0
        updates.append(Update(entry["name"], major))
    return updates


def parse_title(title: str, body: str) -> list[Update] | None:
    """The updates the title names, or a group's body `Updates` lines when
    they add up to its count; None when neither reads."""
    subject = _PREFIX.sub("", str(title), count=1)
    if group := _GROUP.search(subject):
        found = [
            Update(m.group(1), is_major(m.group(2), m.group(3)))
            for m in _UPDATE_LINE.finditer(str(body))
        ]
        return found if len(found) == int(group.group(1)) else None
    if single := _SINGLE.search(subject):
        return [Update(single.group(1), is_major(single.group(2), single.group(3)))]
    return None


def classify(
    title: str,
    body: str,
    head_ref: str,
    ci_status: str,
    commits: Sequence[Any] = (),
) -> Classification:
    """The tier from what Dependabot wrote: its commits' metadata, the title,
    the body's `Updates` lines and the head branch, and the newest `ci-status`
    conclusion on the head."""
    found = _ECOSYSTEM.match(str(head_ref))
    ecosystem = found.group(1) if found else ""
    metadata: list[Update] | None = None
    for item in commits:
        commit = json_object(json_object(item).get("commit"))
        author = json_object(commit.get("author"))
        if (author.get("name"), author.get("email")) == DEPENDABOT_AUTHOR:
            entries = parse_metadata(str(commit.get("message") or ""))
            if entries is not None:
                metadata = (metadata or []) + entries
    titled = parse_title(title, body)
    reasons: list[str] = []
    updates = metadata if metadata else titled
    if not updates:
        reasons.append("unparsed-updates")
        updates = []
    elif metadata and titled:
        by_name = {u.name: u.major for u in titled}
        if {u.name for u in metadata} != set(by_name) or any(
            by_name[u.name] != u.major for u in metadata
        ):
            reasons.append("sources-disagree")
    for update in updates:
        if update.major is None:
            reasons.append(f"unparsed-version:{update.name}")
        elif update.major:
            reasons.append(f"major:{update.name}")
        if (
            ecosystem == "github_actions"
            and update.name.split("/")[0] not in ACTIONS_PUBLISHERS
        ):
            reasons.append(f"publisher:{update.name}")
    if ci_status in RED:
        reasons.append("ci-status-red")
    return Classification(
        AUTO if not reasons else REVIEW, tuple(reasons), tuple(updates), ecosystem
    )


def merge_verdict(
    comments: Sequence[Any], identity: str, head: str
) -> tuple[str | None, str | None]:
    """(run, None) when the newest round marker the lanes App (`identity`)
    posted names `head` with `verdict=merge`, else (None, why). A marker by
    anyone else is ignored."""
    mine = [
        comment
        for comment in map(json_object, comments)
        if json_object(comment.get("user")).get("type") == "Bot"
        and str(json_object(comment.get("user")).get("login") or "").casefold()
        == identity.casefold()
        and str(comment.get("body") or "").startswith(MARKER_PREFIX)
    ]
    if not mine:
        return None, "review-verdict-missing"
    newest = max(mine, key=lambda c: (str(c.get("created_at")), c.get("id") or 0))
    first = str(newest.get("body") or "").split("\n", 1)[0].rstrip("\r")
    marker = _MARKER.match(first)
    if not marker:
        return None, "review-verdict-unreadable"
    marked, verdict, run = marker.groups()
    if marked != head:
        return None, "review-verdict-head-moved"
    if verdict != "merge":
        return None, f"review-verdict:{verdict}"
    return run, None


def commit_refusal(
    item: Any,
    files: Callable[[str], Sequence[str] | None],
    lane_identity: str | None = None,
) -> str | None:
    """Why one REST pull-request commit may not merge, or None. `files(sha)`
    lists a commit's changed paths, or None when unreadable; it is read only
    for a github-actions[bot] commit. `lane_identity`, given for a reviewed
    pull request, admits the lanes App's `[dependabot skip]` fix commits."""
    entry = json_object(item)
    commit = json_object(entry.get("commit"))
    sha = str(entry.get("sha") or "?")[:12]
    author = json_object(commit.get("author"))
    committer = json_object(commit.get("committer"))
    message = str(commit.get("message") or "")
    if json_object(commit.get("verification")).get("verified") is not True:
        return f"commit-unverified:{sha}"
    if committer.get("email") != GITHUB_COMMITTER_EMAIL:
        return f"commit-not-committed-by-github:{sha}"
    signed = (author.get("name"), author.get("email"))
    if signed == DEPENDABOT_AUTHOR:
        return None
    login = str(json_object(entry.get("author")).get("login") or "")
    if lane_identity and login.casefold() == lane_identity.casefold():
        return None if SKIP_MARKER in message else f"commit-not-dependabot:{sha}"
    if signed != ACTIONS_AUTHOR or SKIP_MARKER not in message:
        return f"commit-not-dependabot:{sha}"
    paths = files(str(entry.get("sha") or ""))
    if not paths or any(not _BUMP_PATH.match(p) for p in paths):
        return f"commit-not-version-bump:{sha}"
    return None


def commits_refusal(
    commits: Sequence[Any],
    files: Callable[[str], Sequence[str] | None],
    lane_identity: str | None = None,
) -> str | None:
    """The first commit that may not merge, or `commits-missing`."""
    if not commits:
        return "commits-missing"
    return next(
        (r for c in commits if (r := commit_refusal(c, files, lane_identity))), None
    )
