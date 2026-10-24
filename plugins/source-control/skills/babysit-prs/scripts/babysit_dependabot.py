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
- `review`: anything else, including anything this cannot read, every
  update to a dependency the standards Dependabot policy lists under
  `autoMerge.reviewOnly` (`review_only`), and an npm or pip update whose
  registry provenance changed (`provenance_reasons`, which reads the registry
  through the `get` its caller passes).

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
lanes App authored. A commit's author is text whoever creates it chooses, so
two more checks bind the pull request to Dependabot. `push_refusal()` reads
who pushed each update of the head branch (the repository activity API) and
admits only Dependabot, and the github-actions or lanes App push of such a
commit; a failure there always refuses. `content_refusal()` names any path
beyond the manifests and lock files `.github/dependabot.yml` covers, a
workflow or action file whose diff changes only `uses:` lines, and the paths
the version-bump commits touched; the caller makes such a pull request tier
`review`, for the AI review to judge. A lanes App fix commit is never counted
as checked: `fix_refusal()` (the pr-unblock lane's `fixRefusal`) requires each
of its files to be modified in place, in `in_fix_scope()`, a regular file, and
changed only by a version.
"""

from __future__ import annotations

import base64
import json
import posixpath
import re
from collections.abc import Callable, Collection, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any
from urllib.parse import quote

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
# The standards-synced Dependabot policy, read at the base.
POLICY_PATH = ".github/standards/dependabot-policy/policy.json"
POLICY_UNREADABLE = "dependabot-policy-unreadable"
# The head branch's ecosystem segment in `dependabot.yml` spelling; any other
# segment is the same in both.
BRANCH_ECOSYSTEMS = {"npm_and_yarn": "npm", "github_actions": "github-actions"}
_REVIEW_ONLY_KEYS = ("repository", "ecosystem", "directory", "dependency", "control")

_PREFIX = re.compile(r"^[a-z]+(\([^)]*\))?!?:\s*", re.I)
_SINGLE = re.compile(r"\bbump (\S+) from (\S+) to (\S+?)(?:\s+in\s.*)?$", re.I)
_GROUP = re.compile(r"\bbump the \S+ group\b.*\bwith (\d+) updates?\s*$", re.I)
_UPDATE_LINE = re.compile(r"^Updates `([^`\s]+)` from (\S+) to (\S+?)\.?$", re.M)
_VERSION = re.compile(r"^v?(\d+)(?:\.(\d+))?(?:\.\d+)*(?:[-+.][0-9A-Za-z.+-]*)?$")
_ECOSYSTEM = re.compile(r"^dependabot/([^/]+)/")
# Dependabot quotes a value YAML would misread, such as a scoped npm name.
_ENTRY = re.compile(r"""^-\s+dependency-name:\s*(["']?)([^"'\s]+)\1\s*$""")
_FIELD = re.compile(
    r"""^\s+(dependency-version|update-type):\s*(["']?)([^"'\s]+)\2\s*$"""
)
_MARKER = re.compile(
    r"^<!-- pr-unblock:review-dependency-round head=([0-9a-f]{40}) "
    r"verdict=([a-z]+) run=([0-9]+-[0-9]+) -->$"
)
_BUMP_PATH = re.compile(
    r"^plugins/[A-Za-z0-9._-]+/(\.claude-plugin/plugin\.json|CHANGELOG\.md)$"
)
# The files each ecosystem's updates edit, in the configured directory.
MANIFESTS = {
    "npm": re.compile(
        r"^(package\.json|package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml)$"
    ),
    "pip": re.compile(
        r"^(requirements[^/]*\.(txt|in)|pyproject\.toml|uv\.lock|setup\.cfg|setup\.py"
        r"|Pipfile|Pipfile\.lock|poetry\.lock|pdm\.lock)$"
    ),
}
_WORKFLOW = re.compile(r"^\.github/workflows/[^/]+\.ya?ml$")
_ACTION = re.compile(r"^(.+/)?action\.ya?ml$")
# A changed line that only repins an action: `uses:` and its ref, with an
# optional trailing comment (the version).
_USES_LINE = re.compile(r"^[+-]\s*(-\s+)?uses:\s*[^\s#]+(\s+#.*)?\s*$")
_CONFIG_ENTRY = re.compile(r"^\s*-\s+package-ecosystem:\s*[\"']?([A-Za-z0-9_-]+)")
_CONFIG_DIR = re.compile(r"^\s+directory:\s*[\"']?([^\"'#\s]+)")
_CONFIG_DIRS = re.compile(r"^\s+directories:\s*$")
_CONFIG_ITEM = re.compile(r"^\s+-\s+[\"']?([^\"'#\s]+)")
PUSH_TYPES = frozenset({"push", "force_push", "branch_creation"})


@dataclass(frozen=True)
class Update:
    name: str
    major: bool | None  # None when unreadable
    # The new version, for the provenance gate; None when unread.
    version: str | None = field(default=None, compare=False)


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
            "updates": [
                {"name": u.name, "major": u.major, "version": u.version}
                for u in self.updates
            ],
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
            entries.append({"name": entry.group(2)})
        elif (field := _FIELD.match(line)) and entries:
            entries[-1][field.group(1)] = field.group(3)
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
        updates.append(Update(entry["name"], major, entry.get("dependency-version")))
    return updates


def parse_title(title: str, body: str) -> list[Update] | None:
    """The updates the title names, or a group's body `Updates` lines when
    they add up to its count; None when neither reads."""
    subject = _PREFIX.sub("", str(title), count=1)
    if group := _GROUP.search(subject):
        found = [
            Update(m.group(1), is_major(m.group(2), m.group(3)), m.group(3))
            for m in _UPDATE_LINE.finditer(str(body))
        ]
        return found if len(found) == int(group.group(1)) else None
    if single := _SINGLE.search(subject):
        return [
            Update(
                single.group(1),
                is_major(single.group(2), single.group(3)),
                single.group(3),
            )
        ]
    return None


def title_major(title: str, update: Update) -> bool | None:
    """The jump a single-package title reads for a metadata entry with no
    `update-type` (a security update writes none): only when the title names
    the same package and its `to` version is the entry's version; None
    otherwise, a group title included."""
    subject = _PREFIX.sub("", str(title), count=1)
    if _GROUP.search(subject) or not (single := _SINGLE.search(subject)):
        return None
    if single.group(1) != update.name:
        return None
    if update.version is not None and single.group(3) != update.version:
        return None
    return is_major(single.group(2), single.group(3))


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
    if metadata:
        metadata = [
            u
            if u.major is not None
            else Update(u.name, title_major(title, u), u.version)
            for u in metadata
        ]
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


def review_only(
    policy: Any,
    repository: str,
    head_ref: str,
    updates: Sequence[Update],
    paths: Collection[str] | None,
) -> tuple[str, ...]:
    """`review-only:<dependency>` for each `autoMerge.reviewOnly` entry of the
    parsed Dependabot policy that names this repository (any case), the head
    branch's ecosystem (`BRANCH_ECOSYSTEMS`), one of `updates`, and a changed
    path the entry covers (`_entry_covers`; any path when `paths` is None), in
    entry order; `dependabot-policy-unreadable` when the policy is None, has
    no `reviewOnly` list, or holds an entry missing a string field."""
    auto = policy.get("autoMerge") if isinstance(policy, dict) else None
    entries = auto.get("reviewOnly") if isinstance(auto, dict) else None
    if not isinstance(entries, list) or not all(
        isinstance(e, dict)
        and all(isinstance(e.get(k), str) for k in _REVIEW_ONLY_KEYS)
        for e in entries
    ):
        return (POLICY_UNREADABLE,)
    found = _ECOSYSTEM.match(str(head_ref))
    segment = found.group(1) if found else ""
    ecosystem = BRANCH_ECOSYSTEMS.get(segment, segment)
    names = {u.name for u in updates}
    reasons: list[str] = []
    for entry in entries:
        reason = f"review-only:{entry['dependency']}"
        if (
            entry["repository"].casefold() == repository.casefold()
            and entry["ecosystem"] == ecosystem
            and entry["dependency"] in names
            and (paths is None or any(_entry_covers(entry, p) for p in paths))
            and reason not in reasons
        ):
            reasons.append(reason)
    return tuple(reasons)


def _entry_covers(entry: dict[str, str], path: str) -> bool:
    """Whether a review-only entry covers a changed path: the path sits in the
    entry's directory (glob-aware), or the entry is `github-actions` and the
    path is a workflow or action file it covers, as the content rule reads
    them."""
    ecosystem, directory = entry["ecosystem"], entry["directory"]
    return _directory(path, directory) or (
        ecosystem == "github-actions" and _actions_file(path, [(ecosystem, directory)])
    )


# The provenance gate, the same rule as the pr-unblock lane's
# `provenanceReasons` (`.github/scripts/pr-unblock/dependency-classify.mjs`):
# each npm or pip update's publisher identity against the newest earlier
# stable version that has one. Rule: docs/conventions/pr-pipeline/README.md,
# "Registry provenance".
PROVENANCE_TIMEOUT = 10  # seconds per registry read
PROVENANCE_CALL_CAP = 20  # registry reads per pull request
_PROVENANCE_ECOSYSTEMS = {"npm_and_yarn": "npm", "pip": "pip"}
NPM_REGISTRY = "https://registry.npmjs.org"
PYPI = "https://pypi.org"
SIMPLE_JSON = "application/vnd.pypi.simple.v1+json"
INTEGRITY_JSON = "application/vnd.pypi.integrity.v1+json"
_SLSA = re.compile(r"^https://slsa\.dev/provenance/v")
_NPM_STABLE = re.compile(r"^\d+\.\d+\.\d+$")
_PIP_STABLE = re.compile(r"^\d+(\.\d+)*(\.post\d+)?$")
_WHEEL = re.compile(r"^[^-]+-([^-]+)-.+\.whl$")
_SDIST = re.compile(r"^.+-([^-]+)\.(tar\.gz|zip)$")
# `fetch(url, accept)` returns the registry's parsed JSON, or raises.
Fetch = Callable[[str, str], Any]


class _Unreadable(Exception):
    pass


def _repo_name(url: Any) -> str:
    text = re.sub(r"^git\+", "", str(url))
    text = re.sub(r"^https://github\.com/", "", text, flags=re.I)
    return text.removesuffix(".git").lower()


def _npm_path(name: str) -> str:
    if name.startswith("@"):
        return "@" + quote(name[1:], safe="")
    return quote(name, safe="")


def _when(text: Any) -> float | None:
    try:
        return datetime.fromisoformat(str(text)).timestamp()
    except ValueError:
        return None


def _changed(name: str, before: str, now: str | None) -> str | None:
    if now is None:
        return f"provenance-missing:{name}"
    return None if now == before else f"provenance-changed:{name}"


def _npm_identity(name: str, version: str, manifest: Any, get: Fetch) -> str | None:
    """One npm version's identity: the SLSA provenance's workflow repository
    and path (never the ref), else the trusted publisher's `oidcConfigId`
    without any `oidc:` prefix, else None."""
    entry = json_object(manifest)
    attestations = json_object(json_object(entry.get("dist")).get("attestations"))
    if attestations.get("url"):
        body = json_object(
            get(
                f"{NPM_REGISTRY}/-/npm/v1/attestations/"
                f"{_npm_path(name)}@{quote(version, safe='')}",
                "application/json",
            )
        )
        listed = body.get("attestations")
        slsa = next(
            (
                item
                for item in map(json_object, listed if isinstance(listed, list) else [])
                if _SLSA.match(str(item.get("predicateType")))
            ),
            {},
        )
        payload = json_object(json_object(slsa.get("bundle")).get("dsseEnvelope")).get(
            "payload"
        )
        if not isinstance(payload, str):
            raise _Unreadable("no SLSA provenance")
        predicate = json_object(
            json_object(json.loads(base64.b64decode(payload))).get("predicate")
        )
        workflow = json_object(
            json_object(
                json_object(predicate.get("buildDefinition")).get("externalParameters")
            ).get("workflow")
        )
        repository, path = workflow.get("repository"), workflow.get("path")
        if isinstance(repository, str) and isinstance(path, str):
            return f"workflow:{_repo_name(repository)}:{path}"
        # SLSA v0.2, which npm wrote before v1: the ref follows the last `@`.
        source = json_object(
            json_object(predicate.get("invocation")).get("configSource")
        )
        uri, entry_point = source.get("uri"), source.get("entryPoint")
        if isinstance(uri, str) and isinstance(entry_point, str):
            return f"workflow:{_repo_name(re.sub(r'@[^@]*$', '', uri))}:{entry_point}"
        raise _Unreadable("no workflow in the provenance")
    trusted = json_object(json_object(entry.get("_npmUser")).get("trustedPublisher"))
    oidc = trusted.get("oidcConfigId")
    if not isinstance(oidc, str):
        return None
    return f"trusted-publisher:{trusted.get('id') or ''}:{oidc.removeprefix('oidc:')}"


def _npm_reason(update: Update, get: Fetch) -> str | None:
    version = str(update.version)
    doc = json_object(
        get(f"{NPM_REGISTRY}/{_npm_path(update.name)}", "application/json")
    )
    versions, time = json_object(doc.get("versions")), json_object(doc.get("time"))
    at = _when(time.get(version))
    if version not in versions or at is None:
        raise _Unreadable("the new version is not in the packument")
    now = _npm_identity(update.name, version, versions[version], get)
    stamped = {v: _when(time.get(v)) for v in versions if _NPM_STABLE.match(v)}
    earlier = sorted(
        (v for v, t in stamped.items() if t is not None and t < at),
        key=lambda v: -(stamped[v] or 0.0),
    )
    for v in earlier:
        before = _npm_identity(update.name, v, versions[v], get)
        if before is not None:
            return _changed(update.name, before, now)
    return None


def _pip_version(filename: str) -> str | None:
    """A distribution file's version: a wheel's second `-` field, an sdist's
    text after its last `-`."""
    found = _WHEEL.match(filename) or _SDIST.match(filename)
    return found.group(1).lower() if found else None


def _pip_identity(provenance: list[tuple[str, str]], get: Fetch) -> str | None:
    """One PyPI version's identity: the PEP 740 publisher kind, repository and
    workflow of its first file (by name) with provenance, else None."""
    if not provenance:
        return None
    url = sorted(provenance)[0][1]
    if not url.startswith(f"{PYPI}/integrity/"):
        raise _Unreadable("a provenance URL off PyPI")
    bundles = json_object(get(url, INTEGRITY_JSON)).get("attestation_bundles")
    first = json_object(bundles[0]) if isinstance(bundles, list) and bundles else {}
    publisher = json_object(first.get("publisher"))
    kind, repository, workflow = (
        publisher.get(k) for k in ("kind", "repository", "workflow")
    )
    if not all(isinstance(v, str) for v in (kind, repository, workflow)):
        raise _Unreadable("no publisher in the provenance")
    return f"{kind}:{str(repository).lower()}:{workflow}"


def _pip_reason(update: Update, get: Fetch) -> str | None:
    name = re.sub(r"[-_.]+", "-", update.name.lower())
    files = json_object(get(f"{PYPI}/simple/{name}/", SIMPLE_JSON)).get("files")
    if not isinstance(files, list):
        raise _Unreadable("no files in the simple index")
    by_version: dict[str, tuple[float | None, list[tuple[str, str]]]] = {}
    for item in map(json_object, files):
        filename = str(item.get("filename") or "")
        v = _pip_version(filename)
        if v is None or item.get("yanked"):
            continue
        at, provenance = by_version.get(v, (float("inf"), []))
        when = _when(item.get("upload-time"))
        at = None if at is None or when is None else min(at, when)
        if isinstance(item.get("provenance"), str):
            provenance.append((filename, item["provenance"]))
        by_version[v] = (at, provenance)
    current = by_version.get(str(update.version).lower())
    if current is None or current[0] is None:
        raise _Unreadable("the new version is not in the simple index")
    at = current[0]
    now = _pip_identity(current[1], get)
    earlier = sorted(
        (
            (t, provenance)
            for v, (t, provenance) in by_version.items()
            if _PIP_STABLE.match(v) and t is not None and t < at
        ),
        key=lambda row: -row[0],
    )
    for _, provenance in earlier:
        before = _pip_identity(provenance, get)
        if before is not None:
            return _changed(update.name, before, now)
    return None


def provenance_reasons(
    updates: Sequence[Update],
    segment: str,
    get: Fetch,
    cap: int = PROVENANCE_CALL_CAP,
) -> tuple[str, ...]:
    """`provenance-changed:<pkg>`, `provenance-missing:<pkg>` or
    `provenance-unreadable:<pkg>` for each update on an `npm_and_yarn` or
    `pip` branch (`segment`, the head branch's ecosystem), in update order.
    `get(url, accept)` reads the registry and raises on any failure; past
    `cap` reads in all, the rest are unreadable."""
    ecosystem = _PROVENANCE_ECOSYSTEMS.get(segment)
    if ecosystem is None:
        return ()
    reason = _npm_reason if ecosystem == "npm" else _pip_reason
    calls = 0

    def counted(url: str, accept: str) -> Any:
        nonlocal calls
        calls += 1
        if calls > cap:
            raise _Unreadable("past the call cap")
        return get(url, accept)

    reasons: list[str] = []
    for update in updates:
        try:
            if not update.version:
                raise _Unreadable("no version")
            found = reason(update, counted)
        except Exception:  # any failure to read is fail-closed, never a pass
            found = f"provenance-unreadable:{update.name}"
        if found:
            reasons.append(found)
    return tuple(reasons)


# The reasons a pull request goes to review only because the classifier could
# not read something: a parse gap, not a risk.
CLASSIFIER_GAPS = frozenset(
    {
        "unparsed-updates",
        "sources-disagree",
        "dependabot-config-unreadable",
        POLICY_UNREADABLE,
    }
)


def classifier_gaps(reasons: Sequence[str]) -> tuple[str, ...]:
    """`reasons` when every one is a classifier gap (`CLASSIFIER_GAPS` or
    `provenance-unreadable:<pkg>`), else empty."""
    gap = all(
        r in CLASSIFIER_GAPS or r.startswith("provenance-unreadable:") for r in reasons
    )
    return tuple(reasons) if reasons and gap else ()


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


def _signed(item: Any) -> tuple[Any, Any]:
    author = json_object(json_object(json_object(item).get("commit")).get("author"))
    return author.get("name"), author.get("email")


def is_dependabot_commit(item: Any) -> bool:
    return _signed(item) == DEPENDABOT_AUTHOR


def is_actions_commit(item: Any) -> bool:
    return _signed(item) == ACTIONS_AUTHOR


def parse_config(text: str) -> list[tuple[str, str]] | None:
    """(ecosystem, directory) for each directory of each `updates` entry of a
    dependabot.yml (`directory` or each `directories` item); None when no
    entry reads."""
    found: list[tuple[str, str]] = []
    ecosystem: str | None = None
    in_dirs = False
    for line in str(text).replace("\r\n", "\n").split("\n"):
        if entry := _CONFIG_ENTRY.match(line):
            ecosystem, in_dirs = entry.group(1), False
        elif ecosystem and (single := _CONFIG_DIR.match(line)):
            found.append((ecosystem, single.group(1)))
            in_dirs = False
        elif ecosystem and _CONFIG_DIRS.match(line):
            in_dirs = True
        elif in_dirs and (item := _CONFIG_ITEM.match(line)):
            found.append((ecosystem, item.group(1)))
        elif line.strip() and not line.lstrip().startswith("#"):
            in_dirs = False
    return found or None


def glob_regex(pattern: str) -> re.Pattern[str]:
    """A `directories` glob as one regex, the same rule as the pr-unblock
    lane's `globRegex` (`.github/scripts/pr-unblock/dependency-classify.mjs`):
    `*` and `?` stay inside one path segment, `**/` is zero or more whole
    segments (so `**/*` covers the root and every layer below), any other
    `**` crosses segments, and everything else is literal. Basis: the
    Dependabot options reference `directories` note and the "Defining
    multiple locations for manifest files" examples (`/lib-*`, `**/*`)."""
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out, i = out + "(?:[^/]*/)*", i + 3
        elif pattern.startswith("**", i):
            out, i = out + ".*", i + 2
        elif pattern[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif pattern[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(pattern[i]), i + 1
    return re.compile(f"^{out}$")


def _directory(path: str, directory: str) -> bool:
    """Whether `path` sits directly in `directory` (leading and trailing `/`
    stripped), or, when it holds `*` or `?`, in a folder its glob matches."""
    folder = posixpath.dirname(path)
    want = directory.strip("/")
    if "*" in want or "?" in want:
        return glob_regex(want).fullmatch(folder) is not None
    return folder == want


def _actions_file(path: str, config: Sequence[tuple[str, str]]) -> bool:
    """A workflow or action file a `github-actions` entry covers: directory
    `/` covers `.github/workflows/` and the action files under
    `.github/actions/`, any other the `action.yml` in the directory (or the
    directories its glob matches)."""
    for eco, folder in config:
        if eco != "github-actions":
            continue
        if not folder.strip("/"):
            if _WORKFLOW.match(path) or (
                path.startswith(".github/actions/") and _ACTION.match(path)
            ):
                return True
        elif _ACTION.match(path) and _directory(path, folder):
            return True
    return False


def uses_only(patch: Any) -> bool:
    """Whether a unified diff changes only `uses:` lines (an action repin)."""
    changed = [
        line
        for line in str(patch or "").split("\n")
        if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
    ]
    return bool(changed) and all(_USES_LINE.match(line) for line in changed)


def content_refusal(
    files: Sequence[Any],
    config: Sequence[tuple[str, str]],
    extra: Collection[str] = (),
) -> str | None:
    """`dependabot-content:<path>` for the first changed path (either side of
    a rename) that is neither a manifest or lock file an ecosystem in `config`
    covers, nor a workflow or action file whose diff changes only `uses:`
    lines, nor in `extra` (the paths the version-bump and lanes App fix
    commits touched, each checked on its own). `files` is the REST
    pull-request files listing, patches included."""
    for item in files:
        entry = json_object(item)
        paths = {entry.get("filename"), entry.get("previous_filename")} - {None, ""}
        for path in sorted(str(p) for p in paths):
            if path in extra:
                continue
            name = posixpath.basename(path)
            manifest = any(
                eco in MANIFESTS
                and MANIFESTS[eco].match(name)
                and _directory(path, folder)
                for eco, folder in config
            )
            if manifest or (
                _actions_file(path, config) and uses_only(entry.get("patch"))
            ):
                continue
            return f"dependabot-content:{path}"
    return None


def push_refusal(
    activities: Sequence[Any],
    head: str,
    commits: Sequence[Any],
    lane_identity: str | None = None,
) -> str | None:
    """Why the head branch's push history does not bind it to Dependabot, or
    None. `activities` is the repository activity API for the branch, newest
    first. Reading back to Dependabot's newest branch creation or force push
    (which rewrites the branch), every push must be by `dependabot[bot]`, or
    by github-actions[bot] (or, for a reviewed pull request, the lanes App)
    when the commit it pushed is that account's own commit in the pull
    request; the newest push must have pushed `head`."""
    pushes = [
        json_object(a)
        for a in activities
        if json_object(a).get("activity_type") in PUSH_TYPES
    ]
    if not pushes or pushes[0].get("after") != head:
        return "push-history-incomplete"
    by_sha = {str(json_object(c).get("sha")): c for c in commits}
    for push in pushes:
        actor = json_object(push.get("actor"))
        login = str(actor.get("login") or "").casefold()
        tip = by_sha.get(str(push.get("after")))
        if login == "dependabot[bot]" and actor.get("type") == "Bot":
            if push.get("activity_type") in ("force_push", "branch_creation"):
                return None
            continue
        if (
            login == "github-actions[bot]"
            and tip is not None
            and _signed(tip) == ACTIONS_AUTHOR
        ):
            continue
        if (
            lane_identity
            and login == lane_identity.casefold()
            and tip is not None
            and str(
                json_object(json_object(tip).get("author")).get("login") or ""
            ).casefold()
            == login
        ):
            continue
        return f"pushed-by:{login or 'unknown'}"
    # No Dependabot branch creation or force push in reach: the history is cut.
    return "push-history-incomplete"


# The lanes App fix rule, the same as the pr-unblock lane's `inFixScope` and
# `fixRefusal` (`.github/scripts/pr-unblock/dependency-classify.mjs`): what a
# lanes App commit on a reviewed Dependabot pull request may change. npm and
# pip manifests and lock files only, narrower than MANIFESTS (no setup.py,
# pyproject.toml or other file a build runs), never under `.github/`.
_FIX_MANIFESTS = {
    "npm": re.compile(r"package\.json|package-lock\.json|npm-shrinkwrap\.json"),
    "pip": re.compile(r"requirements[^/]*\.(txt|in)"),
}
# A fix changes only regular, non-executable files: no symbolic link
# (120000), submodule (160000) or executable (100755).
FIX_MODE = 0o100644
_DEPENDENCY_SECTIONS = (
    "dependencies",
    "devDependencies",
    "optionalDependencies",
    "peerDependencies",
)
_VERSION_PART = (
    r"v?([0-9]+|[xX*])(\.([0-9]+|[xX*])){0,2}(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?"
)
_RANGE_VERSION = re.compile(_VERSION_PART)
_COMPARATOR = re.compile(r"(\^|~|[<>]=?|=)?" + _VERSION_PART)
NPM_REGISTRY_TARBALL = "https://registry.npmjs.org/"
_REQUIREMENT = re.compile(
    r"[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(\[[A-Za-z0-9._,-]+\])?==[0-9][0-9A-Za-z.+!-]*"
    r"(\s*;\s*[A-Za-z0-9_.'\"<>=!~ ()]+?)?(\s+\\)?"
)
_HASH_LINE = re.compile(r"\s+--hash=sha256:[0-9a-f]{64}(\s+\\)?")
_BLANK_OR_COMMENT = re.compile(r"\s*(#.*)?")
# Every range set is bounded: no wildcard major and no lower bounds alone.
_WILD_MAJOR = re.compile(r"(\^|~|[<>]=?|=)?v?[xX*]")
# The package a lock key installs: the last `node_modules/<name>` of the path.
_LOCK_KEY = re.compile(
    r"(?:node_modules/(?:@[^/]+/)?[^/@][^/]*/)*node_modules/((?:@[^/]+/)?[^/@][^/]*)"
)
_PACKAGE_NAME = re.compile(r"(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*")
_LOCK_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?")
_INTEGRITY = re.compile(r"sha512-[A-Za-z0-9+/]+={0,2}")
_PROJECT = re.compile(r"([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)")


def in_fix_scope(path: Any, config: Sequence[tuple[str, str]] | None) -> bool:
    """Whether a lanes App fix may change `path`: a fix manifest in a
    directory of its ecosystem in `config` (the base dependabot.yml's pairs),
    never under `.github/`. No config admits nothing."""
    text = str(path or "")
    name = posixpath.basename(text)
    if re.match(r"\.github(/|$)", text, re.I):
        return False
    return any(
        eco in _FIX_MANIFESTS
        and _FIX_MANIFESTS[eco].fullmatch(name) is not None
        and isinstance(folder, str)
        and _directory(text, folder)
        for eco, folder in config or ()
    )


def is_fix_file(entry: Any) -> bool:
    """Whether a GraphQL tree entry is a regular, non-executable file."""
    item = json_object(entry)
    return item.get("type") == "blob" and item.get("mode") == FIX_MODE


def is_semver_range(value: Any) -> bool:
    """A plain semver range: comparators, a hyphen range, or `||` of either.
    No dist-tag, alias, URL, path, git or GitHub shorthand, or workspace."""
    if not isinstance(value, str) or not value or len(value) > 200:
        return False
    for part in value.split("||"):
        group = part.strip()
        hyphen = re.fullmatch(r"(\S+) - (\S+)", group)
        if hyphen:
            if not all(
                _RANGE_VERSION.fullmatch(v) and not _WILD_MAJOR.match(v)
                for v in hyphen.groups()
            ):
                return False
            continue
        comparators = re.split(r"\s+", group)
        if (
            not group
            or not all(
                _COMPARATOR.fullmatch(c) and not _WILD_MAJOR.match(c)
                for c in comparators
            )
            or all(c.startswith(">") for c in comparators)
        ):
            return False
    return True


def _json_mapping(text: Any) -> dict[str, Any] | None:
    try:
        value = json.loads(str(text))
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def package_json_refusal(before: Any, after: Any) -> str | None:
    """Only the version range of a dependency already listed in a dependency
    section changes, to a plain semver range; every other key stays."""
    old, now = _json_mapping(before), _json_mapping(after)
    if old is None or now is None:
        return "package-json-unreadable"
    for key in sorted(set(old) | set(now)):
        if key not in _DEPENDENCY_SECTIONS:
            if _canonical(old.get(key)) != _canonical(now.get(key)) or (
                (key in old) != (key in now)
            ):
                return f"package-json-key:{key}"
            continue
        was, is_ = old.get(key), now.get(key)
        if not isinstance(was, dict) or not isinstance(is_, dict):
            return f"package-json-key:{key}"
        if sorted(was) != sorted(is_):
            return f"package-json-entries:{key}"
        for name in sorted(was):
            if _canonical(was[name]) != _canonical(is_[name]) and not is_semver_range(
                is_[name]
            ):
                return f"package-json-range:{key}:{name}"
    return None


_ABSENT = object()


def _lock_entry_refusal(key: str, entry: Any, was: Any) -> str | None:
    """Why one `packages` entry is not the registry tarball of its own name
    and version with a sha512 integrity, or None. Its alias `name` is the
    before side's (`was`): a fix never adds, drops or changes one."""
    at = _LOCK_KEY.fullmatch(key)
    if not at or not isinstance(entry, dict):
        return f"lock-key:{key}"
    old_name = was.get("name", _ABSENT) if isinstance(was, dict) else _ABSENT
    if old_name != entry.get("name", _ABSENT):
        return f"lock-name:{key}"
    name = entry.get("name", at.group(1))
    version = entry.get("version")
    if not (
        isinstance(name, str)
        and _PACKAGE_NAME.fullmatch(name)
        and isinstance(version, str)
        and _LOCK_VERSION.fullmatch(version)
    ):
        return f"lock-entry:{key}"
    base = name.rsplit("/", 1)[-1]
    tarball = f"{NPM_REGISTRY_TARBALL}{name}/-/{base}-{version}.tgz"
    if "link" in entry or entry.get("resolved") != tarball:
        return f"lock-resolved:{key}"
    integrity = entry.get("integrity")
    if not isinstance(integrity, str) or not _INTEGRITY.fullmatch(integrity):
        return f"lock-integrity:{key}"
    return None


def lock_refusal(before: Any, after: Any) -> str | None:
    """Every `packages` entry but the root is the registry tarball its key
    and version name, with a sha512 integrity; the fix adds and removes no
    package (the before side is the Dependabot commit's lock, so its own
    additions stand); every other `resolved` is a registry tarball; and no
    package gains or loses an install script."""
    old, now = _json_mapping(before), _json_mapping(after)
    if old is None or now is None:
        return "lock-unreadable"
    if not isinstance(old.get("packages"), dict) or not isinstance(
        now.get("packages"), dict
    ):
        return "lock-packages"
    if sorted(now["packages"]) != sorted(old["packages"]):
        return "lock-packages-changed"
    for key in sorted(now["packages"]):
        why = (
            None
            if key == ""
            else _lock_entry_refusal(key, now["packages"][key], old["packages"][key])
        )
        if why:
            return why
    stack: list[Any] = [now]
    while stack:
        node = stack.pop()
        items = node.items() if isinstance(node, dict) else enumerate(node)
        for key, value in items:
            if key == "resolved" and not (
                isinstance(value, str) and value.startswith(NPM_REGISTRY_TARBALL)
            ):
                return "lock-resolved"
            if isinstance(value, (dict, list)):
                stack.append(value)
    was = old.get("packages") if isinstance(old.get("packages"), dict) else {}
    is_ = now.get("packages") if isinstance(now.get("packages"), dict) else {}

    def script(packages: dict[str, Any], name: str) -> bool:
        return json_object(packages.get(name)).get("hasInstallScript") is True

    for name in sorted(set(was) | set(is_)):
        if script(was, name) != script(is_, name):
            return f"lock-install-script:{name}"
    return None


def requirements_refusal(before: Any, after: Any) -> str | None:
    """Every line the fix adds is blank, a comment, a `name==version` pin
    (extras and an environment marker allowed), or an indented
    `--hash=sha256:` continuation: no option line, URL or VCS requirement."""
    if not isinstance(before, str) or not isinstance(after, str):
        return "requirements-unreadable"
    kept: dict[str, int] = {}
    for line in before.split("\n"):
        kept[line] = kept.get(line, 0) + 1
    added: list[str | None] = []
    for line in after.split("\n"):
        if kept.get(line):
            kept[line] -= 1
            continue
        text = line.removesuffix("\r")
        if not (
            _BLANK_OR_COMMENT.fullmatch(text)
            or _REQUIREMENT.fullmatch(text)
            or _HASH_LINE.fullmatch(text)
        ):
            return "requirements-line"
        if _REQUIREMENT.fullmatch(text):
            added.append(_project(text))
    # A fix repins; every pin it adds names a project a removed line named.
    removed = {_project(line.removesuffix("\r")) for line, n in kept.items() if n > 0}
    fresh = next((name for name in added if name not in removed), "")
    return f"requirements-new-package:{fresh}" if fresh else None


def _project(line: str) -> str | None:
    """A requirement line's project name, normalized (PEP 503), or None."""
    found = _PROJECT.match(line)
    return re.sub(r"[-_.]+", "-", found.group(1).lower()) if found else None


def fix_content_refusal(path: Any, before: Any, after: Any) -> str | None:
    """Why the fix's change to `path` (each side's text) is not a version
    change, or None."""
    name = posixpath.basename(str(path or ""))
    if name == "package.json":
        return package_json_refusal(before, after)
    if name in ("package-lock.json", "npm-shrinkwrap.json"):
        return lock_refusal(before, after)
    if re.fullmatch(r"requirements[^/]*\.(txt|in)", name):
        return requirements_refusal(before, after)
    return "content-unchecked"


def fix_refusal(
    files: Sequence[Any],
    config: Sequence[tuple[str, str]] | None,
    entry: Callable[[str], Any],
    text: Callable[[str, str], str | None],
) -> str | None:
    """The first reason a fix's changed files (a REST commit `files` listing)
    are not a lanes App fix, or None: each only modified in place, in fix
    scope, a regular file at the fix's tip (`entry(path)`, read before any
    content, since a contents read follows a symbolic link), and a version
    change from `text("before", path)` to `text("after", path)`."""
    for item in files:
        file = json_object(item)
        path = str(file.get("filename") or "")
        if file.get("status") != "modified" or file.get("previous_filename"):
            return f"fix-status:{path}"
        if not in_fix_scope(path, config):
            return f"fix-scope:{path}"
        if not is_fix_file(entry(path)):
            return f"fix-mode:{path}"
        why = fix_content_refusal(path, text("before", path), text("after", path))
        if why:
            return f"fix-content:{path}:{why}"
    return None


def plugin_json_refusal(before: Any, after: Any) -> str | None:
    """The version-bump commit's plugin.json: only `version` changes, to a
    plain version; every other key stays as it was."""
    old, now = _json_mapping(before), _json_mapping(after)
    if old is None or now is None:
        return "plugin-json-unreadable"
    version = now.get("version")
    if not isinstance(version, str) or not _LOCK_VERSION.fullmatch(version):
        return "plugin-json-version"
    rest = [
        _canonical({k: v for k, v in side.items() if k != "version"})
        for side in (old, now)
    ]
    return None if rest[0] == rest[1] else "plugin-json-key"


def bump_refusal(
    files: Sequence[Any],
    entry: Callable[[str], Any],
    text: Callable[[str, str], str | None],
) -> str | None:
    """The first reason the repository's version-bump commit is more than a
    version bump, or None (the pr-unblock lane's `bumpRefusal`): each file a
    plugin's plugin.json or CHANGELOG.md, modified in place as a regular file,
    and a plugin.json changing only its `version`."""
    if not files:
        return "bump-empty"
    for item in files:
        file = json_object(item)
        path = str(file.get("filename") or "")
        if file.get("status") != "modified" or file.get("previous_filename"):
            return f"bump-status:{path}"
        if not _BUMP_PATH.match(path):
            return f"bump-path:{path}"
        if not is_fix_file(entry(path)):
            return f"bump-mode:{path}"
        if path.endswith("/plugin.json"):
            why = plugin_json_refusal(text("before", path), text("after", path))
            if why:
                return f"bump-content:{path}:{why}"
    return None
