#!/usr/bin/env python3
"""Policy for the unattended merge path of the babysit merge gate.

The readers here answer whether `babysit_merge.py --unattended` may merge in one
repository: the pipeline config at the base SHA, the effective rung, the kill
switch, the human-set rung cap, the demotion record, the agent identity, a pull
request's eligibility, and whether an earlier unattended merge is still in
flight. Every reader fails closed: an unreadable or unexpected answer is off,
refuse or not clear, never permissive.

`resolve()`, which `babysit_merge.py` calls, returns `assess()`, which composes
the readers and never enables the path: no merge is connected to them yet.

`recheck` (the CLI, `recheck()` here) is the merge-group backstop that
pr-require-checks.yml's `unattended-recheck` job runs from the queue's base: it
fails a queued pull request that a non-human enqueued unless every term holds.

`self_logins`, wherever a reader takes it, names only lane or bot self
identities. Every login in it is non-human, as the Design's "Human" definition
says, so a caller that passed the operator's own login would make the operator
non-human for opt-in, class provenance and demotion clears.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import ntpath
import os
import posixpath
import re
import sys
import tempfile
from collections.abc import Callable, Collection, Mapping
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote

import babysit_repo_config as repo_config
from babysit_classify import (
    actor_kind,
    has_blocking_severity,
    has_blocking_text,
    is_dependency_author,
)
from babysit_gh import (
    flatten_paginated_items,
    gh_capture,
    gh_http_status,
    is_owner_repo_pair,
)
from babysit_risk import ChangedFile, RiskInput, Rung, score
from babysit_util import (
    is_json_array,
    is_json_object,
    json_array,
    json_object,
    run_command,
)

AUTHORITY_UNCONFIGURED = "authority-unconfigured"
MERGE_UNCONNECTED = "merge-unconnected"

CONFIG_PATH = "docs/conventions/pr-pipeline.yaml"
SOURCE_CONTROL_PATH = repo_config.CONFIG_PATH
LOOP_MERGE_KEY = "babysit_loop_merge"
PARSER = Path(__file__).resolve().parents[3] / "lib" / "parse-concern-value.sh"

RUNG_RANK = {"off": 0, "C2": 2, "C3": 3}
CLASS_RANK = {"C1": 1, "C2": 2, "C3": 3}
# `babysit_loop_merge` values as a rung; C4 and C5 never merge unattended.
LOOP_MERGE_RUNG = {
    "human-only": "off",
    "c2-mechanical": "C2",
    "c3-autonomous": "C3",
    "full-autonomy": "C3",
}
WORK_CLASS_LABELS = {
    "work-class: read-only": "C1",
    "work-class: mechanical": "C2",
    "work-class: scoped": "C3",
    "work-class: structural": "C4",
    "work-class: untrusted-provenance": "C5",
}
WORK_CLASS_PREFIX = "work-class:"

OPT_IN_LABEL = "merge: agent-allowed"
RUNG_CAP_VARIABLE = "CLAUDE_LANES_MERGE_RUNG_CAP"
ORG_SWITCH = "CLAUDE_LANES_DISABLED"
REPO_SWITCH = "CLAUDE_LANES_REPO_DISABLED"
DEMOTION_MARKER = "<!-- babysit-merge-demotion"
DEMOTION_FILER = "github-actions[bot]"
LEASE_MARKER = "<!-- work-item-lease v1 "

# `merge.agent-identity` must be a dedicated GitHub App's bot login; the shared
# GitHub bots are never one (pr-pipeline.schema.json `$defs.merge`).
IDENTITY_RE = re.compile(r"^[A-Za-z0-9]+(-[A-Za-z0-9]+)*\[bot\]$")
SHARED_BOTS = frozenset({"github-actions", "dependabot"})
USER_LOGIN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$")
AUTOMATION_LOGINS = frozenset({"github-actions"})
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
# C0 and C1 controls and the Unicode line and paragraph separators.
_SEPARATOR = re.compile(r"[\x00-\x1f\x7f-\x9f\u2028\u2029]")
WRITE_PERMISSIONS = frozenset({"admin", "write"})
# The merged-PR read for the in-flight rule: pages of 100, at most 10 pages.
# A history it cannot read to its end (or to the merged-since floor) is not clear.
MERGED_PAGE_SIZE = 100
MERGED_PAGE_LIMIT = 10
# The demotion candidates read per filer: at most 10 pages of 100 issues. A
# filer whose issues run past it holds the rung off.
ISSUES_PAGE_LIMIT = 10


class PolicyReadError(RuntimeError):
    """A policy input could not be read; callers fail closed."""


@dataclass(frozen=True)
class UnattendedPolicy:
    """The unattended merge policy for one repository.

    `reason` names the refusal that keeps the path inert; only None enables it,
    and it has no default, so no policy is enabled by omission.
    `agent_identity` is the configured `merge.agent-identity` login, stripped of
    surrounding whitespace, or None when unset or blank. `details` carries the
    readers' answers for the report.
    """

    reason: str | None
    agent_identity: str | None = None
    details: Mapping[str, Any] | None = None

    def __post_init__(self) -> None:
        identity = (self.agent_identity or "").strip() or None
        object.__setattr__(self, "agent_identity", identity)

    @property
    def enabled(self) -> bool:
        return self.reason is None

    def report(self) -> dict[str, Any]:
        return {"enabled": self.enabled, "reason": self.reason, **(self.details or {})}


def resolve(repo: str) -> UnattendedPolicy:
    """The unattended policy for `repo` at its default branch head: `assess()`,
    so inert in every case. Raises `PolicyReadError` when the pipeline config
    cannot be read or parsed."""
    return assess(repo)


# --- Bash, for the shared YAML reader -----------------------------------------
# A port of `lib/exec-bash.mjs`'s `resolveBash`: on Windows a bare `bash` can be
# the WSL relay, which never runs the reader the way Git Bash does.

_SHELL_NAMES = frozenset({"bash.exe", "sh.exe", "bash", "sh"})


def _is_wsl_relay(path: str) -> bool:
    folded = path.replace("/", "\\").lower()
    return (
        folded.endswith("\\system32\\bash.exe")
        or folded.endswith("\\sysnative\\bash.exe")
        or "\\windowsapps\\" in folded
    )


def _accept_bash(
    path: str | None, windows: bool, exists: Callable[[str], bool]
) -> bool:
    if not path or not exists(path):
        return False
    base = (ntpath if windows else posixpath).basename(path).lower()
    return base in _SHELL_NAMES and not (windows and _is_wsl_relay(path))


def _path_candidates(env: Mapping[str, str], windows: bool) -> list[str]:
    raw = env.get("PATH")
    raw = env.get("Path", "") if raw is None else raw
    candidates = []
    for entry in raw.split(";" if windows else ":"):
        if windows:
            entry = re.sub(r'^"(.*)"$', r"\1", entry)
            if re.match(r"^(?:[A-Za-z]:)?[\\/]", entry):
                candidates.append(ntpath.join(entry, "bash.exe"))
        elif entry.startswith("/"):
            candidates.append(posixpath.join(entry, "bash"))
    return candidates


def resolve_bash(
    env: Mapping[str, str], platform: str, exists: Callable[[str], bool]
) -> str | None:
    """The bash to run the shared reader with, or None.

    On Windows: `CLAUDE_CODE_GIT_BASH_PATH` when it names bash.exe, sh.exe,
    bash or sh; then Git's `bin\\bash.exe` and `usr\\bin\\bash.exe` under
    Program Files, Program Files (x86) and LOCALAPPDATA\\Programs; then bash.exe
    in each absolute PATH entry. System32, Sysnative and WindowsApps are never
    accepted. Elsewhere: bash in each absolute PATH entry, then /bin/bash and
    /usr/bin/bash.
    """
    windows = platform == "win32"
    if windows:
        configured = env.get("CLAUDE_CODE_GIT_BASH_PATH")
        if _accept_bash(configured, windows, exists):
            return configured
        roots = [env.get("ProgramFiles"), env.get("ProgramFiles(x86)")]
        if env.get("LOCALAPPDATA"):
            roots.append(ntpath.join(env["LOCALAPPDATA"], "Programs"))
        candidates = [
            ntpath.join(root, "Git", *tail, "bash.exe")
            for root in roots
            if root
            for tail in (("bin",), ("usr", "bin"))
        ]
        candidates += _path_candidates(env, windows)
    else:
        candidates = [*_path_candidates(env, windows), "/bin/bash", "/usr/bin/bash"]
    return next((c for c in candidates if _accept_bash(c, windows, exists)), None)


def _concern_values(
    text: str, keys: list[tuple[str, bool]]
) -> dict[str, list[str]] | None:
    """Each key's values from a YAML document through the shared reader.

    None when the reader rejects the document (`--strict` exit 3). Any other
    failure raises.
    """
    platform = "win32" if os.name == "nt" else sys.platform
    bash = resolve_bash(os.environ, platform, os.path.isfile)
    if bash is None:
        raise PolicyReadError("no usable bash found to run the shared YAML reader")
    values: dict[str, list[str]] = {}
    with tempfile.TemporaryDirectory() as tmp:
        document = Path(tmp) / "concern.yaml"
        document.write_text(text, encoding="utf-8")
        for key, as_list in keys:
            argv = [bash, str(PARSER), "--strict", *(["--list"] if as_list else [])]
            try:
                proc = run_command(
                    [*argv, str(document), key],
                    allowed_executables=(bash,),
                    check=False,
                )
            except (RuntimeError, ValueError, OSError) as exc:
                raise PolicyReadError(f"the shared YAML reader failed: {exc}") from exc
            if proc.returncode == 3:
                return None
            if proc.returncode != 0:
                raise PolicyReadError(
                    f"the shared YAML reader exited {proc.returncode}: {proc.stderr.strip()}"
                )
            # One value per "\n": splitlines() would also cut a value at U+0085
            # or U+2028, and a value carrying any such character is refused.
            found = [line for line in proc.stdout.split("\n") if line]
            if any(_SEPARATOR.search(line) for line in found):
                return None
            values[key] = found
    return values


# --- The gh seam ----------------------------------------------------------------


def _split_repo(repo: str) -> tuple[str, str]:
    owner, _, name = repo.partition("/")
    if not is_owner_repo_pair(owner, name):
        raise PolicyReadError(f"not an owner/repo pair: {repo!r}")
    return owner, name


def _get(endpoint: str) -> tuple[int | None, Any]:
    """(status, payload): 200 and the JSON on success; on failure the status gh
    reported, or None when it named none."""
    try:
        proc = gh_capture(["api", endpoint])
    except (RuntimeError, ValueError, OSError):
        return None, None
    if proc.returncode != 0:
        return gh_http_status(proc.stderr or ""), None
    try:
        return 200, json.loads(proc.stdout) if proc.stdout.strip() else None
    except ValueError:
        return None, None


def _paginated(
    endpoint: str, label: str, items_key: str | None = None
) -> list[dict[str, Any]]:
    try:
        proc = gh_capture(["api", endpoint, "--paginate", "--slurp"])
    except (RuntimeError, ValueError, OSError) as exc:
        raise PolicyReadError(f"{label}: {exc}") from exc
    if proc.returncode != 0:
        raise PolicyReadError(
            f"{label}: {(proc.stderr or '').strip() or proc.returncode}"
        )
    try:
        return flatten_paginated_items(
            json.loads(proc.stdout), label, items_key=items_key
        )
    except (ValueError, RuntimeError) as exc:
        raise PolicyReadError(f"{label}: {exc}") from exc


def _graphql(query: str, label: str, **variables: str | int | None) -> dict[str, Any]:
    args = ["api", "graphql", "-f", f"query={query}"]
    for name, value in variables.items():
        if value is not None:
            args += ["-F" if isinstance(value, int) else "-f", f"{name}={value}"]
    try:
        proc = gh_capture(args)
    except (RuntimeError, ValueError, OSError) as exc:
        raise PolicyReadError(f"{label}: {exc}") from exc
    if proc.returncode != 0:
        raise PolicyReadError(
            f"{label}: {(proc.stderr or '').strip() or proc.returncode}"
        )
    try:
        payload = json.loads(proc.stdout)
    except ValueError as exc:
        raise PolicyReadError(f"{label}: {exc}") from exc
    if (
        not is_json_object(payload)
        or payload.get("errors")
        or not is_json_object(payload.get("data"))
    ):
        raise PolicyReadError(f"{label}: the response carried no data")
    return payload["data"]


def _login_key(login: Any) -> str:
    """A login compared across REST (`app[bot]`) and GraphQL (`app`) spellings."""
    return str(login or "").strip().casefold().removesuffix("[bot]")


def _time(value: Any) -> datetime:
    """A timestamp with an offset; anything else, a naive one included, raises
    `PolicyReadError` rather than a comparison `TypeError` later."""
    try:
        parsed = datetime.fromisoformat(str(value))
    except ValueError as exc:
        raise PolicyReadError(f"not a timestamp: {value!r}") from exc
    if parsed.utcoffset() is None:
        raise PolicyReadError(f"a timestamp without an offset: {value!r}")
    return parsed


def _has_next_page(info: dict[str, Any], label: str) -> bool:
    """`pageInfo.hasNextPage`, which must be a boolean: only False ends a read."""
    more = info.get("hasNextPage")
    if not isinstance(more, bool):
        raise PolicyReadError(f"{label}: a page without a boolean hasNextPage")
    return more


def _rest_actor(actor: Any) -> dict[str, Any] | None:
    actor = json_object(actor)
    if not actor:
        return None
    return {"__typename": actor.get("type"), "login": actor.get("login")}


# --- Config at the base SHA -----------------------------------------------------


@dataclass(frozen=True)
class PipelineConfig:
    """The merge config at one base SHA. `rung` is "off" on any doubt; `error`
    names a pipeline-file parse error, which leaves every other key unread."""

    base_sha: str
    rung: str
    authority: str | None
    agent_identity: str | None
    max_changed_lines: int | None
    denied_paths: tuple[str, ...]
    loop_merge: str | None
    error: str | None = None
    notes: tuple[str, ...] = ()


def _file_at(owner: str, name: str, path: str, sha: str) -> str | None:
    """The file's text at `sha`, or None when absent from a readable tree."""
    status, payload = _get(f"repos/{owner}/{name}/contents/{path}?ref={sha}")
    if status == 404:
        root, _ = _get(f"repos/{owner}/{name}/contents?ref={sha}")
        if root == 200:
            return None
        raise PolicyReadError(
            f"{path} answered 404 and the repository contents at {sha} are not "
            "readable, so the file may exist but be hidden from this token"
        )
    if status != 200:
        raise PolicyReadError(f"{path} at {sha} could not be read (status {status})")
    try:
        if not (
            is_json_object(payload)
            and payload.get("type") == "file"
            and payload.get("encoding") == "base64"
        ):
            raise ValueError("response is not a base64 file payload")
        return base64.b64decode(str(payload.get("content") or "")).decode("utf-8")
    except (ValueError, binascii.Error) as exc:
        raise PolicyReadError(f"{path} at {sha} is unreadable: {exc}") from exc


def _loop_merge(text: str) -> str | None:
    """The one `## babysit_loop_merge` value, or None for none, two, or a file
    the repository-config parser rejects."""
    try:
        repo_config.parse_repo_config(text)
    except repo_config.RepoConfigError:
        return None
    values: list[str] = []
    current: list[str] | None = None
    in_fence = False
    for raw in text.removeprefix("﻿").replace("\r\n", "\n").split("\n"):
        if repo_config.FENCE_RE.match(raw):
            in_fence = not in_fence
            continue
        heading = None if in_fence else repo_config.HEADING_RE.match(raw)
        if heading:
            current = None
            if (
                raw.startswith(repo_config.H2_PREFIX)
                and heading.group(1) == LOOP_MERGE_KEY
            ):
                current = []
                values.append("")
        elif current is not None and raw.strip() and not values[-1]:
            values[-1] = raw.strip().strip("`").strip()
    return values[0] if len(values) == 1 and values[0] else None


def read_config_at(repo: str, base_sha: str) -> PipelineConfig:
    """`merge:` from `docs/conventions/pr-pipeline.yaml` and `babysit_loop_merge`
    from `.claude/source-control.md`, both read at `base_sha` through the
    contents API. A pipeline file the shared reader rejects is off; an absent
    one has no merge block (rung off, authority unset). Raises
    `PolicyReadError` when the pipeline file cannot be read.
    """
    owner, name = _split_repo(repo)
    if not SHA_RE.fullmatch(base_sha or ""):
        raise PolicyReadError(f"base SHA is not a 40-hex commit id: {base_sha!r}")
    notes: list[str] = []
    try:
        source = _file_at(owner, name, SOURCE_CONTROL_PATH, base_sha)
    except PolicyReadError as exc:
        source = None
        notes.append(f"{SOURCE_CONTROL_PATH} unreadable: {exc}")
    loop_merge = _loop_merge(source) if source is not None else None

    text = _file_at(owner, name, CONFIG_PATH, base_sha)
    off = PipelineConfig(base_sha, "off", None, None, None, (), loop_merge)
    if text is None:
        return off
    values = _concern_values(
        text,
        [
            ("merge.rung", False),
            ("merge.authority", False),
            ("merge.agent-identity", False),
            ("merge.diff-check.max-changed-lines", False),
            ("merge.diff-check.denied-paths", True),
        ],
    )
    if values is None:
        return PipelineConfig(
            base_sha, "off", None, None, None, (), loop_merge, "config-parse-error"
        )

    def scalar(key: str) -> str | None:
        found = values[key]
        return found[0] if found else None

    rung = scalar("merge.rung") or "off"
    if rung not in RUNG_RANK:
        notes.append(f"merge.rung {rung!r} is not off, C2 or C3")
        rung = "off"
    lines = scalar("merge.diff-check.max-changed-lines")
    if lines is not None and not re.fullmatch(r"[0-9]+", lines):
        notes.append(f"merge.diff-check.max-changed-lines {lines!r} is not a count")
        rung, lines = "off", None
    return PipelineConfig(
        base_sha=base_sha,
        rung=rung,
        authority=scalar("merge.authority"),
        agent_identity=scalar("merge.agent-identity"),
        max_changed_lines=int(lines) if lines else None,
        denied_paths=tuple(values["merge.diff-check.denied-paths"]),
        loop_merge=loop_merge,
        notes=tuple(notes),
    )


# --- Effective rung ---------------------------------------------------------------


@dataclass(frozen=True)
class EffectiveRung:
    rung: str
    inputs: Mapping[str, str]
    limited_by: str | None


def effective_rung(
    *, config_rung: str | None, loop_merge: str | None, cap: str | None, demoted: bool
) -> EffectiveRung:
    """min(merge.rung, babysit_loop_merge, rung cap, demotion); an unknown input
    is off. `cap` None means no cap (a proven 404); `demoted` holds it off."""
    inputs = {
        "merge.rung": config_rung if config_rung in RUNG_RANK else "off",
        LOOP_MERGE_KEY: LOOP_MERGE_RUNG.get(loop_merge or "", "off"),
        "rungCap": "C3" if cap is None else (cap if cap in RUNG_RANK else "off"),
        "demotion": "off" if demoted else "C3",
    }
    limited_by = min(inputs, key=lambda name: RUNG_RANK[inputs[name]])
    rung = inputs[limited_by]
    report = dict(
        inputs, rungCap=cap or "none", demotion="active" if demoted else "none"
    )
    return EffectiveRung(rung, report, limited_by if rung == "off" else None)


# --- Repository variables ---------------------------------------------------------


@dataclass(frozen=True)
class KillSwitch:
    proceed: bool
    reason: str


def _variables_readable(owner: str, name: str) -> bool:
    status, _ = _get(f"repos/{owner}/{name}/actions/variables?per_page=1")
    return status == 200


def _variable(owner: str, name: str, variable: str) -> tuple[int | None, str | None]:
    status, payload = _get(f"repos/{owner}/{name}/actions/variables/{variable}")
    value = payload.get("value") if is_json_object(payload) else None
    return status, value if isinstance(value, str) else None


def read_kill_switch(repo: str) -> KillSwitch:
    """Proceed only when the variables surface reads, the organization's
    `CLAUDE_LANES_DISABLED` and the repository's `CLAUDE_LANES_REPO_DISABLED`
    are each exactly `false`, and no repository-level `CLAUDE_LANES_DISABLED`
    shadows the organization's."""
    owner, name = _split_repo(repo)
    if not _variables_readable(owner, name):
        return KillSwitch(False, "variables-unreadable")
    try:
        org = _paginated(
            f"repos/{owner}/{name}/actions/organization-variables?per_page=100",
            "organization variables",
            items_key="variables",
        )
    except PolicyReadError:
        return KillSwitch(False, "org-variables-unreadable")
    switches = [v.get("value") for v in org if v.get("name") == ORG_SWITCH]
    if switches != ["false"]:
        return KillSwitch(False, "org-switch-not-false")
    status, value = _variable(owner, name, REPO_SWITCH)
    if status != 200 or value != "false":
        return KillSwitch(False, "repo-switch-not-false")
    status, _ = _variable(owner, name, ORG_SWITCH)
    if status != 404:
        return KillSwitch(
            False, "repo-shadow-present" if status == 200 else "repo-shadow-unreadable"
        )
    return KillSwitch(True, "proceed")


@dataclass(frozen=True)
class RungCap:
    value: str | None
    reason: str


def read_rung_cap(repo: str) -> RungCap:
    """The human-set `CLAUDE_LANES_MERGE_RUNG_CAP`, read only. A 404 after a
    readable variables listing is no cap (None); any other failure or value is
    off."""
    owner, name = _split_repo(repo)
    if not _variables_readable(owner, name):
        return RungCap("off", "variables-unreadable")
    status, value = _variable(owner, name, RUNG_CAP_VARIABLE)
    if status == 404:
        return RungCap(None, "no-cap")
    if status == 200 and value in RUNG_RANK:
        return RungCap(value, "cap-set")
    return RungCap("off", "cap-unreadable" if status != 200 else "cap-invalid")


# --- Human ----------------------------------------------------------------------------

Permission = Callable[[str], str | None]


def permission_reader(repo: str) -> Permission:
    """A cached reader of a login's repository permission (`admin`, `write`, ...)."""
    owner, name = _split_repo(repo)
    cache: dict[str, str | None] = {}

    def read(login: str) -> str | None:
        if login not in cache:
            status, payload = _get(
                f"repos/{owner}/{name}/collaborators/{login}/permission"
            )
            value = (
                payload.get("permission")
                if status == 200 and is_json_object(payload)
                else None
            )
            cache[login] = value if isinstance(value, str) else None
        return cache[login]

    return read


def is_human(
    actor: Any,
    *,
    repo: str,
    agent_identity: str | None,
    self_logins: Collection[str] = frozenset(),
    permission: Permission | None = None,
) -> bool:
    """An actor whose GraphQL `__typename` is `User`, whose login is not the
    agent identity (in either spelling), not a self-login, not `github-actions`
    and not a `[bot]` login, and who has write or admin permission. A null actor,
    or a permission that cannot be read, is non-human.

    `self_logins` must name only lane or bot self identities, never the
    operator's personal login: each one listed is treated as non-human."""
    if not is_json_object(actor) or actor.get("__typename") != "User":
        return False
    login = actor.get("login")
    if not isinstance(login, str) or not USER_LOGIN_RE.fullmatch(login):
        return False
    excluded = AUTOMATION_LOGINS | {_login_key(s) for s in self_logins}
    if agent_identity:
        excluded |= {_login_key(agent_identity)}
    if _login_key(login) in excluded:
        return False
    try:
        return (permission or permission_reader(repo))(login) in WRITE_PERMISSIONS
    except PolicyReadError:
        return False


# --- Demotion record ------------------------------------------------------------------

ISSUES_BY_AUTHOR = (
    "query PolicyIssuesByAuthor($o:String!,$r:String!,$a:String!,$c:String){"
    "repository(owner:$o,name:$r){issues(first:100,after:$c,filterBy:{createdBy:$a}){"
    "pageInfo{hasNextPage endCursor} nodes{number body lastEditedAt}}}}"
)
DEMOTION_RECORD = (
    "query PolicyDemotionRecord($o:String!,$r:String!,$n:Int!){"
    "repository(owner:$o,name:$r){issue(number:$n){number state body createdAt "
    "author{__typename login} "
    "userContentEdits(first:100){totalCount nodes{editedAt deletedAt editor{__typename login} diff}} "
    "timelineItems(itemTypes:[CLOSED_EVENT],last:1){nodes{... on ClosedEvent{"
    "actor{__typename login} closer{__typename}}}}}}}"
)


@dataclass(frozen=True)
class Demotion:
    active: bool
    reason: str | None
    records: tuple[int, ...]


def _candidate_issues(owner: str, name: str, filer: str) -> list[int]:
    """Issues `filer` opened that carry the marker now or were ever edited."""
    numbers: list[int] = []
    cursor: str | None = None
    for _ in range(ISSUES_PAGE_LIMIT):
        data = _graphql(
            ISSUES_BY_AUTHOR, f"issues by {filer}", o=owner, r=name, a=filer, c=cursor
        )
        page = json_object(json_object(data.get("repository")).get("issues"))
        nodes = page.get("nodes")
        if not is_json_array(nodes):
            raise PolicyReadError(f"issues by {filer}: no issue list")
        for node in nodes:
            node = json_object(node)
            if not isinstance(node.get("number"), int):
                raise PolicyReadError(f"issues by {filer}: an issue without a number")
            if DEMOTION_MARKER in str(node.get("body") or "") or node.get(
                "lastEditedAt"
            ):
                numbers.append(node["number"])
        info = json_object(page.get("pageInfo"))
        if not _has_next_page(info, f"issues by {filer}"):
            return numbers
        cursor = info.get("endCursor")
        if not isinstance(cursor, str) or not cursor:
            raise PolicyReadError(f"issues by {filer}: a next page with no cursor")
    raise PolicyReadError(f"issues by {filer}: more than {ISSUES_PAGE_LIMIT} pages")


def _record_hold(issue: dict[str, Any], human: Callable[[Any], bool]) -> str | None:
    """Why a demotion record still holds the rung off, or None once a human
    closed it directly and no non-human ever edited it."""
    edits = json_object(issue.get("userContentEdits"))
    nodes = [json_object(node) for node in json_array(edits.get("nodes"))]
    if edits.get("totalCount") != len(nodes):
        return "edit-history-incomplete"
    if issue.get("state") != "CLOSED":
        return "open"
    closes = json_array(json_object(issue.get("timelineItems")).get("nodes"))
    close = json_object(closes[-1]) if closes else {}
    if not close:
        return "close-unreadable"
    if close.get("closer") is not None:
        return "closed-by-reference"
    if not human(close.get("actor")):
        return "closed-by-non-human"
    if any(edit.get("deletedAt") or edit.get("diff") is None for edit in nodes):
        return "edit-history-deleted"
    # GitHub lists the original body as the author's edit at creation time,
    # newest edit first. Only the earliest revision can be that original, and
    # only when both its editor and the issue author are named.
    author = json_object(issue.get("author"))
    earliest = json_object(nodes[-1]) if nodes else {}
    editor = json_object(earliest.get("editor"))
    original_is_earliest = bool(
        earliest.get("editedAt") == issue.get("createdAt")
        and author.get("login")
        and editor.get("login")
        and editor.get("__typename") == author.get("__typename")
        and _login_key(editor.get("login")) == _login_key(author.get("login"))
        and all(
            _time(e.get("editedAt")) >= _time(earliest.get("editedAt")) for e in nodes
        )
    )
    judged = nodes[:-1] if original_is_earliest else nodes
    if any(not human(edit.get("editor")) for edit in judged):
        return "edited-by-non-human"
    return None


def read_demotion(
    repo: str,
    *,
    agent_identity: str | None,
    self_logins: Collection[str] = frozenset(),
    permission: Permission | None = None,
) -> Demotion:
    """Whether a demotion record holds the rung off.

    Records are issues the agent identity or `github-actions[bot]` opened whose
    body carries the demotion marker now or in any revision, so stripping the
    marker or the label hides none. A record holds the rung off unless its
    latest `ClosedEvent` has no `closer` and a human actor, and no non-human
    ever edited it. Any read failure holds it off.
    """
    owner, name = _split_repo(repo)
    filers = [DEMOTION_FILER, *([agent_identity.strip()] if agent_identity else [])]
    permission = permission or permission_reader(repo)
    human = lambda actor: is_human(  # noqa: E731
        actor,
        repo=repo,
        agent_identity=agent_identity,
        self_logins=self_logins,
        permission=permission,
    )
    records: list[int] = []
    try:
        candidates = sorted(
            {n for f in filers for n in _candidate_issues(owner, name, f)}
        )
        for number in candidates:
            data = _graphql(
                DEMOTION_RECORD, f"issue #{number}", o=owner, r=name, n=number
            )
            issue = json_object(json_object(data.get("repository")).get("issue"))
            if not issue:
                raise PolicyReadError(f"issue #{number} returned nothing")
            revisions = [
                json_object(e).get("diff")
                for e in json_array(
                    json_object(issue.get("userContentEdits")).get("nodes")
                )
            ]
            texts = [issue.get("body"), *revisions]
            edits = json_object(issue.get("userContentEdits"))
            # A truncated history may hide the marker in an older revision.
            truncated = edits.get("totalCount") != len(json_array(edits.get("nodes")))
            if not truncated and not any(
                t is None or DEMOTION_MARKER in str(t) for t in texts
            ):
                continue
            records.append(number)
            hold = _record_hold(issue, human)
            if hold:
                return Demotion(True, f"#{number} {hold}", tuple(records))
    except PolicyReadError as exc:
        return Demotion(True, f"demotion-unreadable: {exc}", tuple(records))
    return Demotion(False, None, tuple(records))


# --- Identity -----------------------------------------------------------------------------


@dataclass(frozen=True)
class Identity:
    login: str | None
    reason: str | None


def resolve_identity(
    configured: str | None,
    acting_login: str | None,
    self_logins: Collection[str] = frozenset(),
) -> Identity:
    """The agent identity when the token acts as exactly the configured
    `merge.agent-identity`, a dedicated App's `[bot]` login that is no
    self-login; otherwise the refusal."""
    login = (configured or "").strip()
    if not login:
        return Identity(None, "agent-identity-unconfigured")
    if not IDENTITY_RE.fullmatch(login) or _login_key(login) in SHARED_BOTS:
        return Identity(None, "agent-identity-invalid")
    selves = {_login_key(s) for s in self_logins}
    if _login_key(login) in selves:
        return Identity(None, "agent-identity-self-login")
    acting = (acting_login or "").strip()
    if not acting:
        return Identity(None, "acting-login-unreadable")
    if acting.casefold() != login.casefold():
        return Identity(None, "acting-login-mismatch")
    return Identity(login, None)


def read_acting_login() -> str:
    data = _graphql("query PolicyViewer{viewer{login}}", "acting login")
    login = json_object(data.get("viewer")).get("login")
    if not isinstance(login, str) or not login:
        raise PolicyReadError("acting login: the viewer has no login")
    return login


# --- Eligibility --------------------------------------------------------------------------

ELIGIBILITY = (
    "query PolicyEligibility($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){number createdAt lastEditedAt isCrossRepository "
    "author{__typename login} headRepositoryOwner{login} labels(first:100){totalCount nodes{name}} "
    "closingIssuesReferences(first:10){totalCount nodes{number lastEditedAt "
    "repository{nameWithOwner} labels(first:100){totalCount nodes{name}}}}}}}"
)


@dataclass(frozen=True)
class Eligibility:
    eligible: bool
    reason: str | None
    work_class: str | None = None
    issue: int | None = None


def _label_names(node: dict[str, Any]) -> list[str] | None:
    labels = json_object(node.get("labels"))
    names = [json_object(n).get("name") for n in json_array(labels.get("nodes"))]
    if labels.get("totalCount") != len(names) or not all(
        isinstance(n, str) for n in names
    ):
        return None
    return names


def _label_provenance(
    owner: str,
    name: str,
    number: int,
    label: str,
    edited_at: Any,
    human: Callable[[Any], bool],
    timelines: dict[int, list[dict[str, Any]]],
) -> str | None:
    """Why `label` on `number` is not trusted: its latest `labeled` event must
    come from a human, and the body must not be edited after it."""
    if number not in timelines:
        timelines[number] = _paginated(
            f"repos/{owner}/{name}/issues/{number}/timeline?per_page=100",
            f"#{number} timeline",
        )
    events = [
        e
        for e in timelines[number]
        if e.get("event") == "labeled"
        and json_object(e.get("label")).get("name") == label
    ]
    if not events:
        return "no-labeled-event"
    latest = max(events, key=lambda e: _time(e.get("created_at")))
    if not human(_rest_actor(latest.get("actor"))):
        return "labeler-not-human"
    if edited_at and _time(edited_at) > _time(latest.get("created_at")):
        return "body-edited-after-label"
    return None


def _claimed_before(
    owner: str, name: str, issue: int, identity: str, created: datetime
) -> bool:
    """A work-item lease comment held by the identity on `issue`, posted by the
    identity's App before `created` (server time; commit dates are
    client-set). The holder is text anyone can write, so the poster decides."""
    comments = _paginated(
        f"repos/{owner}/{name}/issues/{issue}/comments?per_page=100",
        f"#{issue} comments",
    )
    for comment in comments:
        poster = json_object(comment.get("user"))
        if poster.get("type") != "Bot" or _login_key(poster.get("login")) != _login_key(
            identity
        ):
            continue
        body = str(comment.get("body") or "").strip()
        if not (body.startswith(LEASE_MARKER) and body.endswith("-->")):
            continue
        try:
            lease = json.loads(body[len(LEASE_MARKER) : -3])
        except ValueError:
            continue
        holder = json_object(lease).get("holder")
        if (
            _login_key(holder) == _login_key(identity)
            and _time(comment.get("created_at")) < created
        ):
            return True
    return False


def eligibility(
    repo: str,
    number: int,
    *,
    agent_identity: str | None,
    self_logins: Collection[str] = frozenset(),
    permission: Permission | None = None,
) -> Eligibility:
    """Whether a pull request may be considered for an unattended merge at all.

    In order: not a fork; not a dependency manager's; authored by the agent
    identity, or carrying `merge: agent-allowed` from a human; exactly one
    linked issue, in this repository; a work class whose every `work-class:`
    label a human applied (the agent identity never counts) with no body edit
    after it, the strictest one counting; and, for a lane-authored PR, the
    identity's claim on that issue predating the PR.
    """
    owner, name = _split_repo(repo)
    permission = permission or permission_reader(repo)
    human = lambda actor: is_human(  # noqa: E731
        actor,
        repo=repo,
        agent_identity=agent_identity,
        self_logins=self_logins,
        permission=permission,
    )
    try:
        data = _graphql(ELIGIBILITY, f"#{number}", o=owner, r=name, n=number)
        pr = json_object(json_object(data.get("repository")).get("pullRequest"))
        if not pr:
            return Eligibility(False, "pull-request-unreadable")
        author = json_object(pr.get("author"))
        head_owner = json_object(pr.get("headRepositoryOwner")).get("login")
        if (
            pr.get("isCrossRepository") is not False
            or str(head_owner).casefold() != owner.casefold()
        ):
            return Eligibility(False, "fork")
        if is_dependency_author(str(author.get("login") or "")):
            return Eligibility(False, "dependency-manager")
        timelines: dict[int, list[dict[str, Any]]] = {}
        lane_authored = bool(
            agent_identity
            and author.get("__typename") == "Bot"
            and _login_key(author.get("login")) == _login_key(agent_identity)
        )
        if not lane_authored:
            labels = _label_names(pr)
            if labels is None:
                return Eligibility(False, "labels-unreadable")
            if OPT_IN_LABEL not in labels:
                return Eligibility(False, "not-lane-authored-or-opted-in")
            untrusted = _label_provenance(
                owner,
                name,
                number,
                OPT_IN_LABEL,
                pr.get("lastEditedAt"),
                human,
                timelines,
            )
            if untrusted:
                return Eligibility(False, f"opt-in-label:{untrusted}")
        linked = json_object(pr.get("closingIssuesReferences"))
        issues = [json_object(n) for n in json_array(linked.get("nodes"))]
        if linked.get("totalCount") != 1 or len(issues) != 1:
            return Eligibility(False, f"linked-issues:{linked.get('totalCount')}")
        issue = issues[0]
        issue_number = issue.get("number")
        repository = json_object(issue.get("repository")).get("nameWithOwner")
        if str(repository).casefold() != repo.casefold() or not isinstance(
            issue_number, int
        ):
            return Eligibility(False, "linked-issue-other-repository")
        labels = _label_names(issue)
        if labels is None:
            return Eligibility(False, "class-labels-unreadable")
        class_labels = [
            label for label in labels if label.startswith(WORK_CLASS_PREFIX)
        ]
        if not class_labels:
            return Eligibility(False, "class-missing")
        if any(label not in WORK_CLASS_LABELS for label in class_labels):
            return Eligibility(False, "class-unknown")
        for label in class_labels:
            untrusted = _label_provenance(
                owner,
                name,
                issue_number,
                label,
                issue.get("lastEditedAt"),
                human,
                timelines,
            )
            if untrusted:
                return Eligibility(False, f"class-provenance:{untrusted}")
        work_class = max(
            (WORK_CLASS_LABELS[label] for label in class_labels),
            key=lambda c: int(c[1]),
        )
        if lane_authored and not _claimed_before(
            owner, name, issue_number, str(agent_identity), _time(pr.get("createdAt"))
        ):
            return Eligibility(False, "claim-missing")
    except PolicyReadError as exc:
        return Eligibility(False, f"unreadable: {exc}")
    return Eligibility(True, None, work_class, issue_number)


# --- In flight -------------------------------------------------------------------------------

MERGE_QUEUE = (
    "query PolicyMergeQueue($o:String!,$r:String!,$b:String!){repository(owner:$o,name:$r){"
    "mergeQueue(branch:$b){entries(first:100){totalCount nodes{"
    "enqueuer{__typename login} pullRequest{number}}}}}}"
)
RECENT_MERGES_QUERY = (
    "query PolicyRecentMerges($o:String!,$r:String!,$b:String!,$c:String){"
    "repository(owner:$o,name:$r){pullRequests(baseRefName:$b,states:MERGED,"
    f"first:{MERGED_PAGE_SIZE},after:$c,orderBy:{{field:UPDATED_AT,direction:DESC}}){{"
    "pageInfo{hasNextPage endCursor} nodes{number mergedAt updatedAt headRefOid "
    "mergeCommit{oid} timelineItems(itemTypes:[ADDED_TO_MERGE_QUEUE_EVENT],last:1){nodes{"
    "... on AddedToMergeQueueEvent{actor{__typename login} enqueuer{__typename login}}}}}}}}"
)


def _merged_since(
    owner: str, name: str, branch: str, since: datetime
) -> list[dict[str, Any]] | None:
    """Merged pull requests on `branch`, newest update first, read until one was
    last updated before `since` (a merge updates the PR, so every PR merged
    since then comes first) or the history ends. None when the page limit is
    reached first."""
    found: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(MERGED_PAGE_LIMIT):
        data = _graphql(
            RECENT_MERGES_QUERY,
            "merged pull requests",
            o=owner,
            r=name,
            b=branch,
            c=cursor,
        )
        page = json_object(json_object(data.get("repository")).get("pullRequests"))
        info = page.get("pageInfo")
        if not is_json_array(page.get("nodes")) or not is_json_object(info):
            raise PolicyReadError("merged pull requests: no page")
        for pr in map(json_object, page["nodes"]):
            if _time(pr.get("updatedAt")) < since:
                return found
            found.append(pr)
        if not _has_next_page(info, "merged pull requests"):
            return found
        cursor = info.get("endCursor")
        if not isinstance(cursor, str) or not cursor:
            raise PolicyReadError("merged pull requests: a next page with no cursor")
    return None


@dataclass(frozen=True)
class AutoMerge:
    """A merged pull request whose merge-queue enqueue was not a human's."""

    number: int
    merge_commit: str | None
    head_ref_oid: str | None
    merged_at: str | None


@dataclass(frozen=True)
class InFlight:
    clear: bool
    reason: str | None


def _queue_hold(
    owner: str, name: str, branch: str, identity: str, exclude: int | None = None
) -> str | None:
    """Why the merge queue on `branch` holds an identity merge: an entry other
    than `exclude` the agent identity enqueued, or one whose enqueuer is
    unknown (an App enqueue can read as null). None when neither is queued."""
    data = _graphql(MERGE_QUEUE, "merge queue", o=owner, r=name, b=branch)
    queue = json_object(json_object(data.get("repository")).get("mergeQueue"))
    entries = json_object(queue.get("entries"))
    nodes = [json_object(n) for n in json_array(entries.get("nodes"))]
    if not queue or entries.get("totalCount") != len(nodes):
        return "merge-queue-unreadable"
    for entry in nodes:
        number = json_object(entry.get("pullRequest")).get("number")
        if exclude is not None and number == exclude:
            continue
        enqueuer = json_object(entry.get("enqueuer"))
        if not enqueuer:
            return f"entry-enqueuer-unknown:#{number}"
        if _login_key(enqueuer.get("login")) == _login_key(identity):
            return f"identity-entry-queued:#{number}"
    return None


def in_flight(
    repo: str,
    *,
    agent_identity: str | None,
    self_logins: Collection[str] = frozenset(),
    permission: Permission | None = None,
    verified: Callable[[AutoMerge], bool] | None = None,
    branch: str = "main",
    merged_since: datetime | None = None,
) -> InFlight:
    """Clear only when no merge-queue entry is the agent identity's and every
    auto-merge (an enqueue whose event `actor` or `enqueuer` is null or
    non-human) merged into `branch` since `merged_since` is verified. With no
    floor it is not clear and reads nothing; a history the read cannot reach
    the floor or end of is not clear. `verified` judges one auto-merge;
    without it none is, so any auto-merge keeps the path not clear."""
    owner, name = _split_repo(repo)
    if not agent_identity:
        return InFlight(False, "agent-identity-unconfigured")
    if merged_since is None:
        return InFlight(False, "merged-since-unset")
    if merged_since.utcoffset() is None:
        return InFlight(False, "merged-since-not-timezone-aware")
    permission = permission or permission_reader(repo)
    human = lambda actor: is_human(  # noqa: E731
        actor,
        repo=repo,
        agent_identity=agent_identity,
        self_logins=self_logins,
        permission=permission,
    )
    try:
        held = _queue_hold(owner, name, branch, agent_identity)
        if held:
            return InFlight(False, held)
        merges = _merged_since(owner, name, branch, merged_since)
        if merges is None:
            return InFlight(False, "merged-history-truncated")
        for pr in merges:
            events = json_array(json_object(pr.get("timelineItems")).get("nodes"))
            if not events:
                continue
            event = json_object(events[-1])
            if human(event.get("actor")) and human(event.get("enqueuer")):
                continue
            merge = AutoMerge(
                number=pr.get("number"),
                merge_commit=json_object(pr.get("mergeCommit")).get("oid"),
                head_ref_oid=pr.get("headRefOid"),
                merged_at=pr.get("mergedAt"),
            )
            if verified is None or not verified(merge):
                return InFlight(False, f"unverified-auto-merge:#{merge.number}")
    except PolicyReadError as exc:
        return InFlight(False, f"unreadable: {exc}")
    return InFlight(True, None)


# --- Composition ------------------------------------------------------------------------------


def _default_branch(repo: str) -> str:
    owner, name = _split_repo(repo)
    status, payload = _get(f"repos/{owner}/{name}")
    branch = (
        payload.get("default_branch")
        if status == 200 and is_json_object(payload)
        else None
    )
    if not isinstance(branch, str) or not branch:
        raise PolicyReadError(f"{repo}: the default branch could not be read")
    return branch


def _default_branch_head(repo: str) -> tuple[str, str]:
    """The default branch's name and its head SHA."""
    owner, name = _split_repo(repo)
    branch = _default_branch(repo)
    status, payload = _get(f"repos/{owner}/{name}/commits/{quote(branch, safe='')}")
    sha = payload.get("sha") if status == 200 and is_json_object(payload) else None
    if not isinstance(sha, str) or not SHA_RE.fullmatch(sha):
        raise PolicyReadError(f"{repo}: the head of {branch} could not be read")
    return branch, sha


def assess(
    repo: str,
    *,
    base_sha: str | None = None,
    pr_number: int | None = None,
    acting_login: str | None = None,
    self_logins: Collection[str] = frozenset(),
    verified: Callable[[AutoMerge], bool] | None = None,
) -> UnattendedPolicy:
    """The readers composed into one policy, always inert in this version.

    The reason names the first reader that refuses, in order: authority,
    identity, kill switch, effective rung, in flight, then the pull request's
    eligibility and its work class against the rung when `pr_number` is given;
    with none refusing it is
    `merge-unconnected`. Raises `PolicyReadError` when the pipeline config
    cannot be read or parsed, because the agent identity is then unknown.

    `self_logins` names only lane or bot self identities (see `is_human`); it
    reaches every human test. `verified` judges one auto-merge for `in_flight`;
    without it every auto-merge counts as unverified.
    """
    branch, head = _default_branch_head(repo)
    sha = base_sha or head
    config = read_config_at(repo, sha)
    if config.error:
        raise PolicyReadError(f"{CONFIG_PATH} at {sha}: {config.error}")
    identity = config.agent_identity
    if (config.authority or "pr-merge") != "local-babysit":
        return UnattendedPolicy(AUTHORITY_UNCONFIGURED, identity)
    if acting_login is None:
        try:
            acting_login = read_acting_login()
        except PolicyReadError:
            acting_login = None
    resolved = resolve_identity(identity, acting_login, self_logins)
    if resolved.reason:
        return UnattendedPolicy(resolved.reason, identity)

    permission = permission_reader(repo)
    readers = {
        "agent_identity": identity,
        "self_logins": self_logins,
        "permission": permission,
    }
    kill = read_kill_switch(repo)
    cap = read_rung_cap(repo)
    demotion = read_demotion(repo, **readers)
    rung = effective_rung(
        config_rung=config.rung,
        loop_merge=config.loop_merge,
        cap=cap.value,
        demoted=demotion.active,
    )
    flight = in_flight(repo, **readers, verified=verified, branch=branch)
    eligible = (
        eligibility(repo, pr_number, **readers) if pr_number is not None else None
    )
    details = {
        "baseSha": sha,
        "rung": rung.rung,
        "rungInputs": dict(rung.inputs),
        "killSwitch": {"proceed": kill.proceed, "reason": kill.reason},
        "rungCap": {"value": cap.value, "reason": cap.reason},
        "demotion": {
            "active": demotion.active,
            "reason": demotion.reason,
            "records": list(demotion.records),
        },
        "identity": resolved.login,
        "inFlight": {"clear": flight.clear, "reason": flight.reason},
        "eligibility": None
        if eligible is None
        else {
            "eligible": eligible.eligible,
            "reason": eligible.reason,
            "workClass": eligible.work_class,
        },
    }
    refusals = (
        (not kill.proceed, f"kill-switch:{kill.reason}"),
        (rung.rung == "off", f"rung-off:{rung.limited_by}"),
        (not flight.clear, f"in-flight:{flight.reason}"),
        (
            eligible is not None and not eligible.eligible,
            f"ineligible:{eligible and eligible.reason}",
        ),
        # The rung is a work-class ceiling: C4 and C5 never merge unattended.
        (
            eligible is not None
            and eligible.eligible
            and CLASS_RANK.get(eligible.work_class or "", 99) > RUNG_RANK[rung.rung],
            f"class-above-rung:{eligible and eligible.work_class}>{rung.rung}",
        ),
    )
    reason = next((text for refused, text in refusals if refused), MERGE_UNCONNECTED)
    return UnattendedPolicy(reason, identity, details)


# --- The merge-group recheck ------------------------------------------------------------------

RECHECK_PASS, RECHECK_FAIL, RECHECK_UNREADABLE = 0, 1, 2
RECHECK_PULL_REQUEST = (
    "query RecheckPullRequest($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){number body headRefOid changedFiles "
    "labels(first:100){totalCount nodes{name}} "
    "timelineItems(itemTypes:[ADDED_TO_MERGE_QUEUE_EVENT],last:1){nodes{"
    "... on AddedToMergeQueueEvent{createdAt actor{__typename login} "
    "enqueuer{__typename login}}}}}}}"
)
# Scorer reasons that come from the review lanes' evidence. The wrapper binds
# that evidence to the head before it enqueues; a merge group has none to bind.
LANE_REASON_CODES = ("evidence-unbound:", "findings:claude-review", "security-finding")


@dataclass(frozen=True)
class Recheck:
    code: int
    reasons: tuple[str, ...]


def _tree_modes(owner: str, name: str, sha: str) -> dict[str, str] | None:
    """Each path's git mode at `sha`, or None when the listing is truncated."""
    status, payload = _get(f"repos/{owner}/{name}/git/trees/{sha}?recursive=1")
    if status != 200 or not is_json_object(payload):
        raise PolicyReadError(f"the tree at {sha} could not be read (status {status})")
    if payload.get("truncated") is not False:
        return None
    return {
        str(entry.get("path")): str(entry.get("mode"))
        for entry in map(json_object, json_array(payload.get("tree")))
    }


def _changed_files(
    owner: str, name: str, pr: dict[str, Any], base_sha: str
) -> tuple[tuple[ChangedFile, ...], bool]:
    """The pull request's files with git modes from the trees API (the files
    API carries none): the head side at its head, the previous side at the
    queue base. Complete only when every listing reads to its end."""
    number, head = pr.get("number"), pr.get("headRefOid")
    if not SHA_RE.fullmatch(str(head)):
        raise PolicyReadError(f"#{number}: no head commit")
    listing = _paginated(
        f"repos/{owner}/{name}/pulls/{number}/files?per_page=100", f"#{number} files"
    )
    head_modes = _tree_modes(owner, name, str(head))
    base_modes = _tree_modes(owner, name, base_sha)
    complete = (
        head_modes is not None
        and base_modes is not None
        and pr.get("changedFiles") == len(listing)
    )
    files = []
    for entry in listing:
        path, previous = entry.get("filename"), entry.get("previous_filename")
        status = entry.get("status")
        side = base_modes if status == "removed" else head_modes
        files.append(
            ChangedFile(
                path=path,
                previous_path=previous,
                status=status,
                additions=entry.get("additions"),
                deletions=entry.get("deletions"),
                has_patch="patch" in entry,
                mode=(side or {}).get(path),
                previous_mode=None
                if status in ("added", "removed")
                else (base_modes or {}).get(previous or path),
            )
        )
    return tuple(files), complete


def _grouping(owner: str, name: str, branch: str) -> set[str]:
    rules = _paginated(
        f"repos/{owner}/{name}/rules/branches/{quote(branch, safe='')}?per_page=100",
        f"{branch} rules",
    )
    return {
        str(json_object(rule.get("parameters")).get("grouping_strategy"))
        for rule in rules
        if rule.get("type") == "merge_queue"
    }


def _human_blockers(owner: str, name: str, number: int, identity: str) -> list[str]:
    """Logins of humans whose comment, review or inline comment on the pull
    request reads as blocking, by the autopilot tier's predicates."""
    from babysit_merge import HUMAN_MERGE_VETO_RE  # noqa: PLC0415 - import cycle

    corpus = [
        item
        for kind in ("issues/{n}/comments", "pulls/{n}/reviews", "pulls/{n}/comments")
        for item in _paginated(
            f"repos/{owner}/{name}/{kind.format(n=number)}?per_page=100",
            f"#{number} {kind.split('/')[-1]}",
        )
    ]
    found = set()
    for item in corpus:
        author = _rest_actor(item.get("user"))
        login = str((author or {}).get("login") or "")
        if actor_kind({"author": author}) != "human" or _login_key(login) in {
            _login_key(identity),
            *AUTOMATION_LOGINS,
        }:
            continue
        body = str(item.get("body") or "")
        if (
            has_blocking_text(body)
            or has_blocking_severity(body)
            or HUMAN_MERGE_VETO_RE.search(body)
        ):
            found.add(login or "unknown")
    return sorted(found)


def _opt_in_removed(
    owner: str, name: str, pr: dict[str, Any], enqueued_at: Any
) -> bool:
    """The opt-in label was on the pull request at enqueue and is gone now."""
    labels = _label_names(pr)
    if labels is None:
        raise PolicyReadError(f"#{pr.get('number')}: labels unreadable")
    if OPT_IN_LABEL in labels:
        return False
    at = _time(enqueued_at)
    timeline = _paginated(
        f"repos/{owner}/{name}/issues/{pr.get('number')}/timeline?per_page=100",
        f"#{pr.get('number')} timeline",
    )
    events = sorted(
        (
            e
            for e in timeline
            if e.get("event") in ("labeled", "unlabeled")
            and json_object(e.get("label")).get("name") == OPT_IN_LABEL
        ),
        key=lambda e: _time(e.get("created_at")),
    )
    present = False
    for event in events:
        if _time(event.get("created_at")) > at:
            break
        present = event.get("event") == "labeled"
    return present


@dataclass(frozen=True)
class VarsContext:
    """The rung cap and kill switches as a workflow's `vars` context carries
    them: `CLAUDE_LANES_MERGE_RUNG_CAP`, `CLAUDE_LANES_REPO_DISABLED` and
    `CLAUDE_LANES_DISABLED` (organization and repository merged, the
    repository's winning, so a repository shadow cannot be told apart). A
    merge-group GITHUB_TOKEN cannot read the Actions-variables API. An unset
    variable is the empty string and fails closed: the cap is off, a switch
    refuses."""

    rung_cap: str
    repo_disabled: str
    lanes_disabled: str

    def cap(self) -> RungCap:
        if self.rung_cap in RUNG_RANK:
            return RungCap(self.rung_cap, "cap-set")
        return RungCap("off", "cap-invalid" if self.rung_cap else "cap-unset")

    def kill_switch(self) -> KillSwitch:
        if self.lanes_disabled != "false":
            return KillSwitch(False, "org-switch-not-false")
        if self.repo_disabled != "false":
            return KillSwitch(False, "repo-switch-not-false")
        return KillSwitch(True, "proceed")


def recheck(
    repo: str,
    number: int,
    base_sha: str,
    *,
    base_ref: str | None = None,
    lanes_disabled: str | None = None,
    vars_context: VarsContext | None = None,
) -> Recheck:
    """The merge-group backstop for one queued pull request.

    The latest `AddedToMergeQueueEvent` decides who enqueued it: when both its
    `actor` and `enqueuer` are human (`is_human`, the configured agent identity
    excluded) it passes without reading any term. Otherwise the effective rung
    and the kill switches come first, then eligibility and the class against
    the rung, another queued identity entry, ALLGREEN grouping, the scorer's
    terms except the review-lane evidence, a body hold, a human blocking
    comment and an opt-in label removed since enqueue. Config is read at
    `base_sha`; nothing is read from the merge group's tree. `lanes_disabled`,
    when given, is `vars.CLAUDE_LANES_DISABLED` and must be exactly `false`.
    With `vars_context` the rung cap and both kill switches come from it
    instead of the Actions-variables API, and `lanes_disabled` is unused.
    A read failure is `RECHECK_UNREADABLE`.
    """
    try:
        return _recheck(repo, number, base_sha, base_ref, lanes_disabled, vars_context)
    except PolicyReadError as exc:
        return Recheck(RECHECK_UNREADABLE, (f"unreadable: {exc}",))


def _recheck(
    repo: str,
    number: int,
    base_sha: str,
    base_ref: str | None,
    lanes_disabled: str | None,
    vars_context: VarsContext | None,
) -> Recheck:
    owner, name = _split_repo(repo)
    config = read_config_at(repo, base_sha)
    identity = None if config.error else config.agent_identity
    data = _graphql(RECHECK_PULL_REQUEST, f"#{number}", o=owner, r=name, n=number)
    pr = json_object(json_object(data.get("repository")).get("pullRequest"))
    events = json_array(json_object(pr.get("timelineItems")).get("nodes"))
    if not pr or not events:
        raise PolicyReadError(f"#{number}: no AddedToMergeQueueEvent, enqueuer unknown")
    event = json_object(events[-1])
    readers = {"agent_identity": identity, "permission": permission_reader(repo)}

    def human(actor: Any) -> bool:
        return is_human(actor, repo=repo, **readers)

    if human(event.get("actor")) and human(event.get("enqueuer")):
        return Recheck(RECHECK_PASS, ("human-enqueued",))

    def fail(reason: str) -> Recheck:
        return Recheck(RECHECK_FAIL, (reason,))

    cap = vars_context.cap() if vars_context else read_rung_cap(repo)
    demotion = read_demotion(repo, **readers)
    rung = effective_rung(
        config_rung=config.rung,
        loop_merge=config.loop_merge,
        cap=cap.value,
        demoted=demotion.active,
    )
    if (config.authority or "pr-merge") != "local-babysit":
        return fail("rung-off:authority")
    if rung.rung == "off":
        return fail(f"rung-off:{rung.limited_by}")
    kill = vars_context.kill_switch() if vars_context else read_kill_switch(repo)
    if not kill.proceed:
        return fail(f"kill-switch:{kill.reason}")
    if not vars_context and lanes_disabled is not None and lanes_disabled != "false":
        return fail("kill-switch:vars.CLAUDE_LANES_DISABLED")
    if not identity or not IDENTITY_RE.fullmatch(identity):
        return fail("agent-identity-unconfigured")

    reasons = []
    eligible = eligibility(repo, number, **readers)
    if not eligible.eligible:
        reasons.append(f"ineligible:{eligible.reason}")
    elif CLASS_RANK.get(eligible.work_class or "", 99) > RUNG_RANK[rung.rung]:
        reasons.append(f"class-above-rung:{eligible.work_class}>{rung.rung}")
    branch = base_ref or _default_branch(repo)
    held = _queue_hold(owner, name, branch, identity, exclude=number)
    if held:
        reasons.append(f"in-flight:{held}")
    grouping = _grouping(owner, name, branch)
    if grouping != {"ALLGREEN"}:
        reasons.append(f"grouping:{','.join(sorted(grouping)) or 'none'}")
    files, complete = _changed_files(owner, name, pr, base_sha)
    risk = score(
        RiskInput(
            work_class=eligible.work_class,
            rung=Rung[rung.rung],
            files=files,
            files_complete=complete,
            max_changed_lines=config.max_changed_lines,
            high_paths=config.denied_paths,
            lanes=(),
            blast_radius=None,
        )
    )
    reasons += [
        f"risk:{r.code}"
        for r in risk.reasons
        if not r.code.startswith(LANE_REASON_CODES)
    ]
    from babysit_merge import BODY_MERGE_HOLD_RE  # noqa: PLC0415 - import cycle

    if BODY_MERGE_HOLD_RE.search(str(pr.get("body") or "")):
        reasons.append("body-hold")
    blockers = _human_blockers(owner, name, number, identity)
    if blockers:
        reasons.append(f"human-blocking-comment:{','.join(blockers)}")
    if _opt_in_removed(owner, name, pr, event.get("createdAt")):
        reasons.append("opt-in-label-removed")
    if reasons:
        return Recheck(RECHECK_FAIL, tuple(reasons))
    return Recheck(RECHECK_PASS, ("non-human enqueue meets every term",))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="babysit_merge_policy.py",
        description="The unattended merge policy; `recheck` is the merge-group backstop.",
        allow_abbrev=False,
    )
    commands = parser.add_subparsers(dest="command", required=True)
    parse = commands.add_parser(
        "recheck",
        help="re-test one queued pull request; exit 0 pass, 1 fail, 2 unreadable",
        allow_abbrev=False,
    )
    parse.add_argument("--repo", required=True, help="owner/repo")
    parse.add_argument("--pr", type=int, required=True, help="the queued pull request")
    parse.add_argument("--base-sha", required=True, help="the merge group's base SHA")
    parse.add_argument(
        "--base-ref", help="the queue's branch (default: the default branch)"
    )
    parse.add_argument(
        "--lanes-disabled", help="vars.CLAUDE_LANES_DISABLED; must be exactly 'false'"
    )
    parse.add_argument(
        "--vars-context",
        action="store_true",
        help="take the rung cap and kill switches from --rung-cap, --repo-disabled "
        "and --lanes-disabled (a workflow's vars context), not the variables API",
    )
    parse.add_argument("--rung-cap", help="vars.CLAUDE_LANES_MERGE_RUNG_CAP")
    parse.add_argument("--repo-disabled", help="vars.CLAUDE_LANES_REPO_DISABLED")
    args = parser.parse_args(argv)
    if not args.vars_context and (
        args.rung_cap is not None or args.repo_disabled is not None
    ):
        parse.error("--rung-cap and --repo-disabled need --vars-context")
    vars_context = (
        VarsContext(
            rung_cap=args.rung_cap or "",
            repo_disabled=args.repo_disabled or "",
            lanes_disabled=args.lanes_disabled or "",
        )
        if args.vars_context
        else None
    )
    result = recheck(
        args.repo,
        args.pr,
        args.base_sha,
        base_ref=args.base_ref,
        lanes_disabled=args.lanes_disabled,
        vars_context=vars_context,
    )
    for reason in result.reasons:
        # A reason can carry a path or login; no control character may start a
        # workflow command line.
        text = _SEPARATOR.sub("?", reason)
        prefix = "" if result.code == RECHECK_PASS else "::error::"
        print(f"{prefix}#{args.pr}: {text}")
    return result.code


if __name__ == "__main__":
    sys.exit(main())
