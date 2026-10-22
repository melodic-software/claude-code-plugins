#!/usr/bin/env python3
"""Policy for the unattended merge path of the babysit merge gate.

The readers here answer whether `babysit_merge.py --unattended` may merge in one
repository: the pipeline config at the base SHA, the effective rung, the kill
switch, the human-set rung cap, the demotion record, the agent identity, a pull
request's eligibility, and whether an earlier unattended merge is still in
flight. Every reader fails closed: an unreadable or unexpected answer is off,
refuse or not clear, never permissive.

`assess()` composes the readers for one pull request in the wiring order and
is what `babysit_merge.py --unattended` builds its decision on; it takes the
post-merge check as a callable, because that module depends on this one.
`resolve()` reads only the config, for the plain `--merge` refusal of the
agent identity.

`self_logins`, wherever a reader takes it, names only lane or bot self
identities. Every login in it is non-human, as the Design's "Human" definition
says, so a caller that passed the operator's own login would make the operator
non-human for opt-in, class provenance and demotion clears.
"""

from __future__ import annotations

import base64
import binascii
import json
import ntpath
import os
import posixpath
import re
import sys
import tempfile
import urllib.request
from collections.abc import Callable, Collection, Iterable, Iterator, Mapping
from dataclasses import asdict, dataclass, field, replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import quote

import babysit_dependabot as dependabot
import babysit_repo_config as repo_config
import babysit_run_cache as run_cache
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
    pull_request_commits_once,
    record_pull_request_total,
)
from babysit_risk import (
    AGENT_FILES,
    DECLARATION_FILES,
    ChangedFile,
    declaration_pointers,
    case_dir,
    eval_case_dirs,
    glob_match,
    is_capability_path,
    is_case_file,
    is_manifest_path,
)
from babysit_util import (
    is_json_array,
    is_json_object,
    json_array,
    json_object,
    run_command,
)

AUTHORITY_UNCONFIGURED = "authority-unconfigured"
DEFAULT_BRANCH_UNREADABLE = "default-branch-unreadable"
# `resolve()` reads only the config: it names the identity, never permits.
NOT_ASSESSED = "not-assessed"

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
# The PR author's own hold, written in the body ("Do not merge this draft", or
# a line starting "Hold:"): the label is not the only way a PR says it must not
# merge. The hyphenated form is the label's name and is not matched, so a body
# that merely names the label does not block. A "Hold:" line may follow any
# whitespace, NBSP included, and a bare CR counts as a line break. A "Hold:"
# line holds the merge only: the pull-request ready flip ignores it.
BODY_MERGE_HOLD_RE = re.compile(
    r"\bdo(?:n['’]?t| not)\s+merge\b|(?:^|\r)[^\S\r\n]*hold:", re.I | re.M
)
# The label form of the same hold: blocks in every tier, whether or not the
# autopilot merge tier is engaged. `--block-labels` only adds to it.
MERGE_HOLD_LABELS = ("do-not-merge",)
# An `adoption.idle-hours` value outside 1 to `MAX_ADOPTION_IDLE_HOURS`, or
# none, adopts nothing.
MAX_ADOPTION_IDLE_HOURS = 720
# Whose pull requests the pr-merge lane adopts: every account on this list,
# by id (`trusted_actor_ids`).
TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json"
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
BLOCKER_ASSOCIATIONS = frozenset({"OWNER", "MEMBER", "COLLABORATOR"})
# The merged-PR read for the in-flight rule: pages of 100, at most 30 pages (about five weeks of merges here).
# A history it cannot read to its end (or to the merged-since floor) is not clear.
MERGED_PAGE_SIZE = 100
MERGED_PAGE_LIMIT = 30
# The demotion candidates read per filer: at most 10 pages of 100 issues. A
# filer whose issues run past it holds the rung off.
ISSUES_PAGE_LIMIT = 10


class PolicyReadError(RuntimeError):
    """A policy input could not be read; callers fail closed."""


class StopReadError(PolicyReadError):
    """A read whose failure stops the path (`reason`), so the identity's
    queued entries leave."""

    def __init__(self, reason: str, message: str) -> None:
        super().__init__(message)
        self.reason = reason


class _SymlinkAt(PolicyReadError):
    """A clone holds a symlink where a file was asked for. The contents API
    follows an in-repository symlink, so the caller reads it there instead."""


@dataclass(frozen=True)
class UnattendedPolicy:
    """The unattended merge policy for one pull request.

    `reason` names the first refusal of an unattended merge; only None lets
    one proceed, and it has no default, so no policy permits a merge by
    omission. `enabled` (Design T20) means the path is configured and no
    identity, credential, kill-switch or post-merge refusal stands; left None
    it follows `reason`. `promoted` is the promotion-evidence read for the
    pull request's class, None when not read; a merge needs both.
    `agent_identity` is the configured `merge.agent-identity` login, stripped
    of surrounding whitespace, or None when unset or blank. `details` carries
    the readers' answers for the report; `inputs` carries what the later steps
    (evidence, score, enqueue) read, and is not reported.
    """

    reason: str | None
    agent_identity: str | None = None
    details: Mapping[str, Any] | None = None
    enabled: bool | None = None
    promoted: bool | None = None
    inputs: Mapping[str, Any] | None = None

    def __post_init__(self) -> None:
        identity = (self.agent_identity or "").strip() or None
        object.__setattr__(self, "agent_identity", identity)
        if self.enabled is None:
            object.__setattr__(self, "enabled", self.reason is None)

    def report(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "promoted": self.promoted,
            "reason": self.reason,
            **(self.details or {}),
        }


def resolve(repo: str, number: int | None = None) -> UnattendedPolicy:
    """The configured agent identity, for the plain `--merge` refusal: the
    pipeline config at the pull request's base SHA combined with the default
    branch head's (the head's alone without a number). It never permits a
    merge. With a number, `details["agentIdentities"]` names every identity
    either side sets, so the plain path refuses each one's token. Raises
    `PolicyReadError` when a pipeline config cannot be read or parsed."""
    if number is None:
        _, sha = _default_branch_head(repo)
    else:
        sha = str(json_object(pull_request(repo, number).get("base")).get("sha"))
    config = read_config_at(repo, sha)
    if config.error:
        raise PolicyReadError(f"{CONFIG_PATH} at {sha}: {config.error}")
    configs = [config]
    if number is not None:
        configs.append(_default_branch_config(repo))
    identities: list[str] = []
    for c in configs:
        login = (c.agent_identity or "").strip()
        if login and login.casefold() not in {i.casefold() for i in identities}:
            identities.append(login)
    reason = NOT_ASSESSED if enabled_authority(config) else AUTHORITY_UNCONFIGURED
    return UnattendedPolicy(
        reason,
        identities[0] if identities else None,
        {"agentIdentities": identities} if number is not None else None,
        enabled=False,
    )


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


def _merge_names(text: str, key: str) -> bool:
    """Whether the top-level `merge` mapping holds `key` at all. The shared
    reader prints nothing for an empty or non-scalar value, as for an absent
    key; the document already parsed as the block-style subset."""
    lines = [
        line
        for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    base = len(lines[0]) - len(lines[0].lstrip(" ")) if lines else 0
    entry = re.compile(r"""(\s*)(["']?)([^"':]+)\2\s*:(\s|$)""")
    inside, child = False, None
    for line in lines:
        found = entry.match(line)
        indent = len(line) - len(line.lstrip(" "))
        if indent <= base:
            inside = indent == base and found is not None and found[3] == "merge"
            child = None
        elif inside and found is not None:
            child = indent if child is None else child
            if indent == child and found[3] == key:
                return True
    return False


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


# --- Config at the base SHA and the default branch head -----------------------------------------------------

# The default `merge.risk-escalation-minutes`: longer than a review lane's
# run, so a review still running at the head (scored MED, evidence unbound)
# finishes before its refusal is labeled (judgment).
RISK_ESCALATION_MINUTES = 60
# `merge.quarantine-days` when absent or not a whole number from 1 to
# `MAX_QUARANTINE_DAYS`.
QUARANTINE_DAYS = 7
MAX_QUARANTINE_DAYS = 30
# The default `merge.max-verify-fails`: three heads' FAILs is a pull request
# the verifier keeps refusing, not one noisy verdict (owner decision
# 2026-10-21).
MAX_VERIFY_FAILS = 3


@dataclass(frozen=True)
class PipelineConfig:
    """The merge config at one commit, `base_sha`. `rung` is "off" on any
    doubt; `error` names a pipeline-file parse error, which leaves every other
    key unread. The gate combines the base's with the default branch head's
    (`stricter_config`)."""

    base_sha: str
    rung: str
    authority: str | None
    agent_identity: str | None
    max_changed_lines: int | None
    denied_paths: tuple[str, ...]
    loop_merge: str | None
    error: str | None = None
    notes: tuple[str, ...] = ()
    # `merge.report-only`: the gate reports and writes nothing. Absent is
    # false; any value but true or false is true.
    report_only: bool = False
    # `merge.require-verifier-verdict`: the pr-merge lane refuses a pull
    # request without a passing pr-verify verdict at its head
    # (`babysit_verify_evidence`). Absent is false; any value but true or
    # false is true.
    require_verifier_verdict: bool = False
    # `merge.dependabot.mode`, the pr-merge lane's Dependabot class: `off`
    # (absent, or any other value) refuses every Dependabot pull request,
    # `report` reports it and writes nothing, and `enforce` merges it
    # whatever `merge.report-only` says.
    dependabot_mode: str = "off"
    # `merge.dependabot.majors`: `hold` (absent, or any other value) refuses a
    # Dependabot pull request with a major update, or one whose version cannot
    # be read, whatever the review verdict says, so a human merges it;
    # `review` lets the verdict merge it.
    dependabot_majors: str = "hold"
    # The pr-merge lane's risk switches under `merge.diff-check` (owner
    # decision Q624): absent, the HIGH path floor and the C2 contradictions
    # are off and there is no file cap (`max_changed_lines` None: no line
    # cap); a value other than true or false turns a switch on. The local
    # babysit lane ignores them, except that `high_path_floor` gates the floor
    # additions there too (`babysit_risk.RiskInput.floor_extensions`).
    high_path_floor: bool = False
    # `merge.diff-check.floor-paths`: globs joined to the floor (owner
    # decision Q641); they hold a pull request for a human, unlike
    # denied-paths, which makes it ineligible.
    floor_paths: tuple[str, ...] = ()
    # `merge.diff-check.floor-script-scopes`: globs inside which a `.ps1` or
    # `.cjs` file, or a file with git mode 100755, holds the same way (owner
    # decision Q646).
    floor_script_scopes: tuple[str, ...] = ()
    c2_contradictions: bool = False
    max_changed_files: int | None = None
    # `merge.max-in-flight`: lane merges in flight at once (`in_flight`).
    # Absent, or anything but a whole number of at least 1, is 1. The gate
    # reads it at the default branch head alone (`_run_max_in_flight`).
    max_in_flight: int = 1
    # `merge.max-queue-ejections`: failed-check merge-queue removals since
    # the head last changed at which the gate stops enqueuing that head.
    # Absent, or anything but a whole number from 1 to
    # `MAX_QUEUE_EJECTIONS_LIMIT`, is 2.
    max_queue_ejections: int = 2
    # `merge.risk-escalation-minutes`: how long a MED or HIGH reasons comment
    # must have stood unchanged at the head before the gate adds the
    # human-gated label; 0 is no minimum. Absent, or anything but a whole
    # number, is `RISK_ESCALATION_MINUTES`.
    risk_escalation_minutes: int = RISK_ESCALATION_MINUTES
    # `merge.max-verify-fails`: counted pr-verify FAILs at distinct heads of
    # one pull request at which it holds for a human whatever a later pass
    # says (`babysit_verify_evidence`). Absent is `MAX_VERIFY_FAILS`; anything
    # but a whole number of at least 1 is 1, so any earlier FAIL holds.
    max_verify_fails: int = MAX_VERIFY_FAILS
    # `merge.check-inputs`: git pathspecs of what the pull request checks
    # read. When the base changed one since a pull request's merge base, the
    # pr-merge lane updates its branch from the base instead of enqueuing it
    # (`babysit_check_inputs`). Absent or empty, nothing is updated.
    check_inputs: tuple[str, ...] = ()
    # The default branch head's `merge.check-inputs` not in `check_inputs`,
    # set by `stricter_config` and read on its own.
    head_check_inputs: tuple[str, ...] = ()
    # `adoption.idle-hours`: how long a person's pull request's update and
    # head commit must be idle before the pr-merge lane adopts it
    # (`adoption_refusal`). Absent, or anything but a whole number from 1 to
    # `MAX_ADOPTION_IDLE_HOURS`, is None, which adopts nothing.
    # `stricter_config` takes the default branch head's.
    adoption_idle_hours: int | None = None
    # `adoption.spec-from-body-apps`: the App ids whose pull request bodies a
    # script writes, so an adopted one closing no issue here is judged
    # against its title and body, as a person's is. Any other App needs a
    # closing issue. An entry that is not an id empties it. Main's.
    spec_from_body_apps: tuple[int, ...] = ()
    # `merge.quarantine-days`: days a quarantined suite's failures on the
    # default branch stop demoting (`babysit_postmerge`). Absent, or anything
    # but a whole number from 1 to `MAX_QUARANTINE_DAYS`, is `QUARANTINE_DAYS`.
    quarantine_days: int = QUARANTINE_DAYS


# The most `merge.max-queue-ejections` may be, and the timeline items the
# enqueue reads back. A full read with no head change in it may have missed
# older removals, so it counts as unreadable and refuses.
MAX_QUEUE_EJECTIONS_LIMIT = 20

LOCAL_BABYSIT = "local-babysit"
PR_MERGE = "pr-merge"
DEPENDABOT_MODES = ("off", "report", "enforce")
DEPENDABOT_MAJORS = ("hold", "review")
# The refusal for a major update under `merge.dependabot.majors: hold`.
MAJOR_HELD = "dependabot-major-held"


def enabled_authority(config: PipelineConfig) -> str | None:
    """The unattended authority the config enables, or None: local-babysit
    as named, or pr-merge (also the meaning of an absent authority) once an
    agent identity is set, since an unset identity leaves that path inert."""
    authority = config.authority or PR_MERGE
    if authority == LOCAL_BABYSIT or (authority == PR_MERGE and config.agent_identity):
        return authority
    return None


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


def read_config_at(
    repo: str,
    base_sha: str,
    file_at: Callable[[str, str], str | None] | None = None,
) -> PipelineConfig:
    """`merge:` from `docs/conventions/pr-pipeline.yaml` and `babysit_loop_merge`
    from `.claude/source-control.md`, both read at `base_sha` through
    `file_at(path, sha)` (text, or None when absent), by default a local clone
    holding `base_sha` (`_clones_holding`), else the contents API. A pipeline
    file the shared reader rejects is off; an absent one has no merge block
    (rung off, authority unset). Raises `PolicyReadError` when the pipeline
    file cannot be read.
    """
    owner, name = _split_repo(repo)
    if not SHA_RE.fullmatch(base_sha or ""):
        raise PolicyReadError(f"base SHA is not a 40-hex commit id: {base_sha!r}")
    if file_at is None:
        root = next(_clones_holding(base_sha), None)

        def file_at(path: str, sha: str) -> str | None:
            if root is not None:
                try:
                    return _git_file_at(root, path, sha)
                except _SymlinkAt:
                    pass
            return _file_at(owner, name, path, sha)

    notes: list[str] = []
    try:
        source = file_at(SOURCE_CONTROL_PATH, base_sha)
    except PolicyReadError as exc:
        source = None
        notes.append(f"{SOURCE_CONTROL_PATH} unreadable: {exc}")
    loop_merge = _loop_merge(source) if source is not None else None

    text = file_at(CONFIG_PATH, base_sha)
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
            ("merge.diff-check.max-changed-files", False),
            ("merge.diff-check.high-path-floor", False),
            ("merge.diff-check.c2-contradictions", False),
            ("merge.diff-check.denied-paths", True),
            ("merge.diff-check.floor-paths", True),
            ("merge.diff-check.floor-script-scopes", True),
            ("merge.report-only", False),
            ("merge.require-verifier-verdict", False),
            ("merge.dependabot.mode", False),
            ("merge.dependabot.majors", False),
            ("merge.max-in-flight", False),
            ("merge.max-queue-ejections", False),
            ("merge.risk-escalation-minutes", False),
            ("merge.max-verify-fails", False),
            ("merge.check-inputs", True),
            ("adoption.idle-hours", False),
            ("adoption.spec-from-body-apps", True),
            ("merge.quarantine-days", False),
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
    files = scalar("merge.diff-check.max-changed-files")
    if files is not None and not re.fullmatch(r"[0-9]+", files):
        notes.append(f"merge.diff-check.max-changed-files {files!r} is not a count")
        rung, files = "off", None

    def switch(key: str) -> bool:
        value = scalar(key)
        if value not in (None, "true", "false"):
            notes.append(f"{key} {value!r} is not true or false")
        return value not in (None, "false")

    high_path_floor = switch("merge.diff-check.high-path-floor")
    c2_contradictions = switch("merge.diff-check.c2-contradictions")

    report_only = scalar("merge.report-only")
    if report_only not in (None, "true", "false"):
        notes.append(f"merge.report-only {report_only!r} is not true or false")
    verdict = scalar("merge.require-verifier-verdict")
    if verdict not in (None, "true", "false"):
        notes.append(f"merge.require-verifier-verdict {verdict!r} is not true or false")
    dependabot_mode = scalar("merge.dependabot.mode") or "off"
    if dependabot_mode not in DEPENDABOT_MODES:
        notes.append(
            f"merge.dependabot.mode {dependabot_mode!r} is not off, report or enforce"
        )
        dependabot_mode = "off"
    dependabot_majors = scalar("merge.dependabot.majors") or "hold"
    if dependabot_majors not in DEPENDABOT_MAJORS:
        notes.append(
            f"merge.dependabot.majors {dependabot_majors!r} is not hold or review"
        )
        dependabot_majors = "hold"
    in_flight_cap = scalar("merge.max-in-flight")
    if in_flight_cap is not None and not re.fullmatch(r"[1-9][0-9]*", in_flight_cap):
        notes.append(
            f"merge.max-in-flight {in_flight_cap!r} is not a count of 1 or more"
        )
        in_flight_cap = None
    ejections = scalar("merge.max-queue-ejections")
    if ejections is not None and not (
        re.fullmatch(r"[1-9][0-9]?", ejections)
        and int(ejections) <= MAX_QUEUE_EJECTIONS_LIMIT
    ):
        notes.append(
            f"merge.max-queue-ejections {ejections!r} is not a count from 1 to "
            f"{MAX_QUEUE_EJECTIONS_LIMIT}"
        )
        ejections = None
    escalation_minutes = scalar("merge.risk-escalation-minutes")
    if escalation_minutes is not None and not re.fullmatch(
        r"0|[1-9][0-9]*", escalation_minutes
    ):
        notes.append(
            f"merge.risk-escalation-minutes {escalation_minutes!r} is not a whole "
            "number of minutes"
        )
        escalation_minutes = None
    verify_fails = scalar("merge.max-verify-fails")
    if verify_fails is None and _merge_names(text, "max-verify-fails"):
        verify_fails = ""
    if verify_fails is not None and not re.fullmatch(r"[1-9][0-9]*", verify_fails):
        notes.append(
            f"merge.max-verify-fails {verify_fails!r} is not a count of 1 or more"
        )
        verify_fails = "1"
    idle_text = scalar("adoption.idle-hours")
    idle_hours: int | None = None
    if idle_text is not None:
        idle_hours = (
            int(idle_text) if re.fullmatch(r"[1-9][0-9]{0,2}", idle_text) else None
        )
        if idle_hours is None or idle_hours > MAX_ADOPTION_IDLE_HOURS:
            notes.append(
                f"adoption.idle-hours {idle_text!r} is not a whole number from 1 "
                f"to {MAX_ADOPTION_IDLE_HOURS}; nothing is adopted"
            )
            idle_hours = None
    body_apps = tuple(values["adoption.spec-from-body-apps"])
    if not all(re.fullmatch(r"[1-9][0-9]*", i) for i in body_apps):
        notes.append(
            f"adoption.spec-from-body-apps {list(body_apps)!r} holds an entry that "
            "is not an account id; every App needs a closing issue"
        )
        body_apps = ()
    quarantine_days = scalar("merge.quarantine-days")
    if quarantine_days is not None and not (
        re.fullmatch(r"[1-9][0-9]?", quarantine_days)
        and int(quarantine_days) <= MAX_QUARANTINE_DAYS
    ):
        notes.append(
            f"merge.quarantine-days {quarantine_days!r} is not a count from 1 to "
            f"{MAX_QUARANTINE_DAYS}"
        )
        quarantine_days = None
    return PipelineConfig(
        base_sha=base_sha,
        rung=rung,
        authority=scalar("merge.authority"),
        agent_identity=scalar("merge.agent-identity"),
        max_changed_lines=int(lines) if lines else None,
        denied_paths=tuple(values["merge.diff-check.denied-paths"]),
        loop_merge=loop_merge,
        notes=tuple(notes),
        report_only=report_only not in (None, "false"),
        require_verifier_verdict=verdict not in (None, "false"),
        dependabot_mode=dependabot_mode,
        dependabot_majors=dependabot_majors,
        high_path_floor=high_path_floor,
        floor_paths=tuple(values["merge.diff-check.floor-paths"]),
        floor_script_scopes=tuple(values["merge.diff-check.floor-script-scopes"]),
        c2_contradictions=c2_contradictions,
        max_changed_files=int(files) if files else None,
        max_in_flight=int(in_flight_cap) if in_flight_cap else 1,
        max_queue_ejections=int(ejections) if ejections else 2,
        risk_escalation_minutes=int(escalation_minutes)
        if escalation_minutes is not None
        else RISK_ESCALATION_MINUTES,
        max_verify_fails=int(verify_fails) if verify_fails else MAX_VERIFY_FAILS,
        check_inputs=tuple(values["merge.check-inputs"]),
        adoption_idle_hours=idle_hours,
        spec_from_body_apps=tuple(int(i) for i in body_apps),
        quarantine_days=int(quarantine_days) if quarantine_days else QUARANTINE_DAYS,
    )


# An authority value that enables neither lane (`enabled_authority`): the
# combined config's when base and main enable different ones.
AUTHORITY_CONFLICT = "base-and-default-branch-differ"
# The gate's refusal for it: a stop, so the identity's queued entries leave.
AUTHORITY_DIFFERS = "authority-differs"


def _cap(a: int | None, b: int | None) -> int | None:
    """The smaller cap, None being no cap."""
    return b if a is None else a if b is None else min(a, b)


def _union(a: tuple[str, ...], b: tuple[str, ...]) -> tuple[str, ...]:
    return a + tuple(x for x in b if x not in a)


def stricter_config(base: PipelineConfig, main: PipelineConfig) -> PipelineConfig:
    """The stricter of the config at the pull request's base and at the
    default branch head, per setting. GitHub never moves a base SHA as the
    default branch advances, so a tightening on main reaches open pull
    requests here, and a pull request still cannot drop its base's
    declaration. The timing-only `risk_escalation_minutes` keeps the base's.
    An identity set on one side only switches the lane off, as a different
    authority does; raises `StopReadError` when both are set and differ."""
    identities = {(c.agent_identity or "").strip().casefold() for c in (base, main)}
    if "" not in identities and len(identities) > 1:
        raise StopReadError(
            AUTHORITY_DIFFERS,
            f"merge.agent-identity is {base.agent_identity!r} at the base "
            f"{base.base_sha} and {main.agent_identity!r} at the default branch "
            f"head {main.base_sha}",
        )

    def loop_rank(value: str | None) -> int:
        return RUNG_RANK[LOOP_MERGE_RUNG.get(value or "", "off")]

    return replace(
        base,
        rung=min(base.rung, main.rung, key=RUNG_RANK.__getitem__),
        authority=base.authority
        if enabled_authority(base) == enabled_authority(main) and len(identities) == 1
        else AUTHORITY_CONFLICT,
        max_changed_lines=_cap(base.max_changed_lines, main.max_changed_lines),
        denied_paths=_union(base.denied_paths, main.denied_paths),
        loop_merge=min(base.loop_merge, main.loop_merge, key=loop_rank),
        notes=base.notes + tuple(f"default branch head: {n}" for n in main.notes),
        report_only=base.report_only or main.report_only,
        require_verifier_verdict=base.require_verifier_verdict
        or main.require_verifier_verdict,
        dependabot_mode=min(
            base.dependabot_mode, main.dependabot_mode, key=DEPENDABOT_MODES.index
        ),
        dependabot_majors="hold"
        if "hold" in (base.dependabot_majors, main.dependabot_majors)
        else base.dependabot_majors,
        high_path_floor=base.high_path_floor or main.high_path_floor,
        floor_paths=_union(base.floor_paths, main.floor_paths),
        floor_script_scopes=_union(base.floor_script_scopes, main.floor_script_scopes),
        c2_contradictions=base.c2_contradictions or main.c2_contradictions,
        max_changed_files=_cap(base.max_changed_files, main.max_changed_files),
        max_queue_ejections=min(base.max_queue_ejections, main.max_queue_ejections),
        max_verify_fails=min(base.max_verify_fails, main.max_verify_fails),
        # Main's own list, read in a `git diff` of its own, so an exclude or a
        # bad entry on either side cannot cancel the other's paths.
        head_check_inputs=tuple(
            p for p in main.check_inputs if p not in base.check_inputs
        ),
        # The gate reads it at the head (`_run_max_in_flight`); this is only
        # the fallback when that read fails, which never exceeds main's.
        max_in_flight=min(base.max_in_flight, main.max_in_flight),
        # Read at main (owner decision Q22).
        adoption_idle_hours=main.adoption_idle_hours,
        spec_from_body_apps=main.spec_from_body_apps,
    )


DEFAULT_BRANCH_CONFIG_SECTION = "default-branch-config"
# Repositories whose default branch head config this process took from the
# run cache, with the head it was read at; `unattended_enqueue` reads the
# head again before an enqueue.
SHARED_HEAD_CONFIGS: dict[str, str] = {}


def _cached_config(value: Any) -> PipelineConfig | None:
    """A saved config, or None (a miss, read again) for anything a config
    read could not have produced."""
    if not isinstance(value, dict):
        return None
    try:
        c = PipelineConfig(
            **{k: tuple(v) if isinstance(v, list) else v for k, v in value.items()}
        )

        def texts(t: Any) -> bool:
            return isinstance(t, tuple) and all(isinstance(x, str) for x in t)

        def count(v: Any, least: int) -> bool:
            return type(v) is int and v >= least

        ok = (
            isinstance(c.base_sha, str)
            and SHA_RE.fullmatch(c.base_sha)
            and c.error is None
            and c.rung in RUNG_RANK
            and all(
                v is None or isinstance(v, str)
                for v in (c.authority, c.agent_identity, c.loop_merge)
            )
            and all(
                v is None or count(v, 0)
                for v in (c.max_changed_lines, c.max_changed_files)
            )
            and all(
                texts(t)
                for t in (
                    c.denied_paths,
                    c.notes,
                    c.floor_paths,
                    c.floor_script_scopes,
                    c.check_inputs,
                    c.head_check_inputs,
                )
            )
            and all(
                type(b) is bool
                for b in (
                    c.report_only,
                    c.require_verifier_verdict,
                    c.high_path_floor,
                    c.c2_contradictions,
                )
            )
            and c.dependabot_mode in DEPENDABOT_MODES
            and c.dependabot_majors in DEPENDABOT_MAJORS
            and count(c.max_in_flight, 1)
            and count(c.max_queue_ejections, 1)
            and count(c.risk_escalation_minutes, 0)
            and count(c.max_verify_fails, 1)
            and (
                c.adoption_idle_hours is None
                or count(c.adoption_idle_hours, 1)
                and c.adoption_idle_hours <= MAX_ADOPTION_IDLE_HOURS
            )
            and isinstance(c.spec_from_body_apps, tuple)
            and all(count(i, 1) for i in c.spec_from_body_apps)
        )
    except (TypeError, ValueError):
        return None
    return c if ok else None


def _default_branch_config(repo: str, branch: str | None = None) -> PipelineConfig:
    """The config at the default branch head, saved once per cache window
    (`run_cache.MAX_AGE`) for the run's gate processes, never saving a failed
    read; saving it saves its `merge.max-in-flight` for `_run_max_in_flight`
    too. Raises `PolicyReadError` when the head or its config cannot be read,
    `StopReadError` when the config cannot be parsed."""
    cached = _cached_config(
        run_cache.get(DEFAULT_BRANCH_CONFIG_SECTION, repo, run_cache.MAX_AGE)
    )
    if cached is not None:
        SHARED_HEAD_CONFIGS[repo] = cached.base_sha
        return cached
    _, head = _default_branch_head(repo, branch)
    config = read_config_at(repo, head)
    if config.error:
        raise StopReadError(
            DEFAULT_BRANCH_UNREADABLE,
            f"{CONFIG_PATH} at the default branch head {head}: {config.error}",
        )
    run_cache.put(DEFAULT_BRANCH_CONFIG_SECTION, repo, asdict(config))
    run_cache.put(MAX_IN_FLIGHT_SECTION, repo, config.max_in_flight)
    return config


def with_default_branch(
    repo: str, base: PipelineConfig, branch: str | None = None
) -> PipelineConfig:
    """The config a merge answers to: `stricter_config` of `base` and the
    config at the head of the default branch (`branch` when already read).
    Raises `PolicyReadError` when the head's cannot be read, `StopReadError`
    when it cannot be parsed or the agent identities differ."""
    main = _default_branch_config(repo, branch)
    return base if main.base_sha == base.base_sha else stricter_config(base, main)


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


LANE_KILL_SWITCH_PROCEED = "proceed"


def kill_switch(
    repo: str, *, authority: str, lane_value: str | None = None
) -> KillSwitch:
    """The kill switch for `authority`. The pr-merge lane's token cannot read
    Actions variables, so its workflow checks the switch and passes the result
    as `lane_value`: only the exact `proceed` proceeds, and a missing or empty
    value refuses. Local babysit reads the variables (`read_kill_switch`) and
    ignores `lane_value`."""
    if authority != PR_MERGE:
        return read_kill_switch(repo)
    if not lane_value:
        return KillSwitch(False, "lane-value-missing")
    if lane_value != LANE_KILL_SWITCH_PROCEED:
        return KillSwitch(False, "lane-value-not-proceed")
    return KillSwitch(True, LANE_KILL_SWITCH_PROCEED)


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


def rung_cap(repo: str, *, authority: str, lane_value: str | None = None) -> RungCap:
    """The rung cap for `authority`. The pr-merge lane's token cannot read
    Actions variables, so its workflow passes `vars.CLAUDE_LANES_MERGE_RUNG_CAP`
    as `lane_value`: empty (the variable unset) is no cap, a rung name is the
    cap, and a missing or any other value is off. Local babysit reads the
    variable (`read_rung_cap`) and ignores `lane_value`."""
    if authority != PR_MERGE:
        return read_rung_cap(repo)
    if lane_value is None:
        return RungCap("off", "lane-value-missing")
    if lane_value == "":
        return RungCap(None, "no-cap")
    if lane_value in RUNG_RANK:
        return RungCap(lane_value, "cap-set")
    return RungCap("off", "cap-invalid")


# --- Human ----------------------------------------------------------------------------

Permission = Callable[[str], str | None]


def permission_reader(repo: str) -> Permission:
    """A cached reader of a login's repository permission (`admin`, `write`, ...).
    A permission read in the last `run_cache.MAX_AGE` by another gate process
    of the run is reused; a failed read is never shared. Each answer notes
    when it was read (`run_cache.note`)."""
    owner, name = _split_repo(repo)
    cache: dict[str, tuple[str | None, datetime]] = {}

    def read(login: str) -> str | None:
        if login not in cache:
            key = f"{owner}/{name}|{login.casefold()}"
            shared = run_cache.get_dated("permission", key, run_cache.MAX_AGE)
            if shared is not None and isinstance(shared[0], str):
                cache[login] = shared
            else:
                at = run_cache.now()
                status, payload = _get(
                    f"repos/{owner}/{name}/collaborators/{login}/permission"
                )
                value = (
                    payload.get("permission")
                    if status == 200 and is_json_object(payload)
                    else None
                )
                cache[login] = (value if isinstance(value, str) else None, at)
                if isinstance(value, str):
                    run_cache.put("permission", key, value, at)
        value, at = cache[login]
        run_cache.note(at)
        return value

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
    "createdAt actor{__typename login} closer{__typename}}}}}}}"
)


@dataclass(frozen=True)
class Demotion:
    active: bool
    reason: str | None
    records: tuple[int, ...]
    # The newest record's creation, which restarts the promotion evidence
    # window, and the newest human close among cleared records, which restarts
    # the post-merge floor. Read only while no record holds.
    newest_created: datetime | None = None
    cleared_at: datetime | None = None


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
    created: list[datetime] = []
    cleared: list[datetime] = []
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
            created.append(_time(issue.get("createdAt")))
            closes = json_array(json_object(issue.get("timelineItems")).get("nodes"))
            cleared.append(_time(json_object(closes[-1]).get("createdAt")))
    except PolicyReadError as exc:
        return Demotion(True, f"demotion-unreadable: {exc}", tuple(records))
    return Demotion(
        False,
        None,
        tuple(records),
        max(created, default=None),
        max(cleared, default=None),
    )


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


def credential_refusal(identity: str) -> str | None:
    """Why the session's gh credentials refuse the unattended path, or None.

    `gh auth status --json hosts` must list, on every host, only the agent
    identity: any other account listed (active or not) refuses, and so does
    an entry with no login that is not the active one. The active github.com
    entry must be the identity; when gh names no login for it (an App
    installation token), `resolve_identity`'s acting-login read decides. A
    session that holds only the identity cannot act as a human anywhere, a
    thread resolution included."""
    try:
        proc = gh_capture(["auth", "status", "--json", "hosts"])
        hosts = json.loads(proc.stdout) if proc.returncode == 0 else None
    except (RuntimeError, ValueError, OSError):
        hosts = None
    hosts = json_object(json_object(hosts).get("hosts"))
    entries = [
        json_object(e) for accounts in hosts.values() for e in json_array(accounts)
    ]
    if not entries:
        return "credentials-unreadable"
    wanted = identity.strip().casefold()
    active = 0
    for entry in entries:
        login = str(entry.get("login") or "").strip().casefold()
        if login and login != wanted:
            return "other-account-listed"
        if entry.get("active") is True:
            active += entry.get("host") == "github.com"
        elif not login:
            return "unknown-account-listed"
    return None if active == 1 else "identity-not-active"


# --- Eligibility --------------------------------------------------------------------------

ELIGIBILITY = (
    "query PolicyEligibility($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){number createdAt lastEditedAt isCrossRepository baseRefName "
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
    # A Dependabot pull request's tier, in the pr-merge lane only.
    dependabot: dependabot.Classification | None = None
    # Why the pr-merge lane adopted a pull request it did not open
    # (`adoption_refusal`), else None.
    adoption: str | None = None
    # An adopted pull request whose author is a person or an App in
    # `adoption.spec-from-body-apps`: its title and body may be its intent,
    # and its own lines skip the path floor (`own_paths`). Any other App's is
    # scored whole, like the lanes App's.
    body_is_intent: bool = False


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
    come from a human acting in person (no `performed_via_github_app`: an
    agent driving a human's token through an App is not the human), and the
    body must not be edited after it."""
    events = [
        e
        for e in _timeline(owner, name, number, timelines)
        if e.get("event") == "labeled"
        and json_object(e.get("label")).get("name") == label
    ]
    if not events:
        return "no-labeled-event"
    latest = max(events, key=lambda e: _time(e.get("created_at")))
    if not human(_rest_actor(latest.get("actor"))):
        return "labeler-not-human"
    if latest.get("performed_via_github_app") is not None:
        return "labeler-via-app"
    if edited_at and _time(edited_at) > _time(latest.get("created_at")):
        return "body-edited-after-label"
    return None


def _timeline(
    owner: str, name: str, number: int, timelines: dict[int, list[dict[str, Any]]]
) -> list[dict[str, Any]]:
    if number not in timelines:
        timelines[number] = _paginated(
            f"repos/{owner}/{name}/issues/{number}/timeline?per_page=100",
            f"#{number} timeline",
        )
    return timelines[number]


def _class_removed_by_non_human(
    owner: str,
    name: str,
    number: int,
    human: Callable[[Any], bool],
    timelines: dict[int, list[dict[str, Any]]],
) -> bool:
    """A `work-class:` label was ever removed by a non-human, or through an
    App: removing a stricter class can leave a lower one standing."""
    return any(
        e.get("event") == "unlabeled"
        and str(json_object(e.get("label")).get("name") or "").startswith(
            WORK_CLASS_PREFIX
        )
        and (
            not human(_rest_actor(e.get("actor")))
            or e.get("performed_via_github_app") is not None
        )
        for e in _timeline(owner, name, number, timelines)
    )


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


def _lane_authored(pr: dict[str, Any], agent_identity: str | None) -> bool:
    author = json_object(pr.get("author"))
    return bool(
        agent_identity
        and author.get("__typename") == "Bot"
        and _login_key(author.get("login")) == _login_key(agent_identity)
    )


def _opt_in_refusal(
    owner: str,
    name: str,
    number: int,
    pr: dict[str, Any],
    agent_identity: str | None,
    human: Callable[[Any], bool],
    timelines: dict[int, list[dict[str, Any]]],
) -> str | None:
    """Why a pull request the identity did not author lacks a standing opt-in:
    the label is absent, or its latest application is not a human's in
    person with no body edit after it. None for a lane-authored one."""
    if _lane_authored(pr, agent_identity):
        return None
    labels = _label_names(pr)
    if labels is None:
        return "labels-unreadable"
    if OPT_IN_LABEL not in labels:
        return "not-lane-authored-or-opted-in"
    untrusted = _label_provenance(
        owner, name, number, OPT_IN_LABEL, pr.get("lastEditedAt"), human, timelines
    )
    return f"opt-in-label:{untrusted}" if untrusted else None


def recheck_opt_in(
    repo: str,
    number: int,
    *,
    agent_identity: str | None,
    self_logins: Collection[str] = frozenset(),
    permission: Permission | None = None,
) -> str | None:
    """The opt-in read again, presence and provenance, right before the
    enqueue: a removal (or a removal and a non-human re-add) after the
    eligibility read refuses. None when it stands or is not needed."""
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
            return "pull-request-unreadable"
        return _opt_in_refusal(owner, name, number, pr, agent_identity, human, {})
    except PolicyReadError as exc:
        return f"unreadable: {exc}"


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
    label a human applied in person (the agent identity never counts, nor an
    App acting for a human) with no body edit after it, the strictest one
    counting, and no `work-class:` label ever removed by a non-human; and, for
    a lane-authored PR, the identity's claim on that issue predating the PR.
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
        foreign = _foreign_refusal(pr, owner)
        if foreign:
            return Eligibility(False, foreign)
        timelines: dict[int, list[dict[str, Any]]] = {}
        lane_authored = _lane_authored(pr, agent_identity)
        opt_in = _opt_in_refusal(
            owner, name, number, pr, agent_identity, human, timelines
        )
        if opt_in:
            return Eligibility(False, opt_in)
        issue, linked = _closing_issue(pr, repo)
        if linked:
            return Eligibility(False, linked)
        issue_number = issue["number"]
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
        if _class_removed_by_non_human(owner, name, issue_number, human, timelines):
            return Eligibility(False, "class-label-removed-by-non-human")
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


# `_closing_issue` refusals that mean no closing issue in this repository.
NO_ISSUE_HERE = ("linked-issues:0", "linked-issue-other-repository")


def _closing_issue(pr: dict[str, Any], repo: str) -> tuple[dict[str, Any], str | None]:
    """(the issue, None) for a pull request with exactly one closing issue in
    this repository, else ({}, the refusal)."""
    linked = json_object(pr.get("closingIssuesReferences"))
    issues = [json_object(n) for n in json_array(linked.get("nodes"))]
    if linked.get("totalCount") != 1 or len(issues) != 1:
        return {}, f"linked-issues:{linked.get('totalCount')}"
    issue = issues[0]
    repository = json_object(issue.get("repository")).get("nameWithOwner")
    if str(repository).casefold() != repo.casefold() or not isinstance(
        issue.get("number"), int
    ):
        return {}, "linked-issue-other-repository"
    return issue, None


def _foreign_refusal(pr: dict[str, Any], owner: str) -> str | None:
    """`fork` for a head outside this repository, `dependency-manager` for a
    dependency manager's pull request, else None."""
    head_owner = json_object(pr.get("headRepositoryOwner")).get("login")
    if (
        pr.get("isCrossRepository") is not False
        or str(head_owner).casefold() != owner.casefold()
    ):
        return "fork"
    if is_dependency_author(str(json_object(pr.get("author")).get("login") or "")):
        return "dependency-manager"
    return None


# --- Eligibility in the pr-merge lane -----------------------------------------------------


# Every lane pull request's class, as Dependabot's is: no `work-class:` label
# is read. The diff-derived C2 checks in the risk score still apply.
LANE_CLASS = "C2"


def _base_refusal(
    owner: str, name: str, node: Mapping[str, Any], *, shared: bool = False
) -> str | None:
    """`base-not-default:<ref>` when the pull request's base is not the
    default branch, read fresh unless `shared` (`_default_branch`). A failed
    read raises, which refuses."""
    branch = _default_branch(f"{owner}/{name}", shared=shared)
    base = node.get("baseRefName")
    return None if base == branch else f"base-not-default:{base}"


def _denied_path_refusal(
    owner: str, name: str, number: int, changed: Any, denied: Collection[str]
) -> str | None:
    """Why the diff may not merge in the lane: a file listing short of the
    pull request's changed-file count, or a path (either side of a rename)
    matching a denied glob. No denied paths configured denies none (owner
    decision Q624)."""
    if not denied:
        return None
    listing = _paginated(
        f"repos/{owner}/{name}/pulls/{number}/files?per_page=100", f"#{number} files"
    )
    if not isinstance(changed, int) or changed != len(listing):
        return "changed-files-incomplete"
    paths = sorted(
        {
            path
            for entry in listing
            for path in (entry.get("filename"), entry.get("previous_filename"))
            if isinstance(path, str) and path
        }
    )
    hits = [p for p in paths if any(glob_match(glob, p) for glob in denied)]
    return f"denied-path:{','.join(hits)}" if hits else None


AUTHOR_NOT_OWNER = "author-not-owner"
# `trusted_actors` by (repo, ref), read once a run.
_TRUSTED_IDS: dict[tuple[str, ...], tuple[tuple[int, ...], tuple[int, ...]]] = {}


def trusted_actors(
    repo: str, ref: str, exclude: Collection[str] = ()
) -> tuple[tuple[int, ...], tuple[int, ...]]:
    """Every account id on `TRUSTED_ACTORS_PATH` at `ref`, people and Apps
    alike (whose pull requests the lane adopts), but those whose login
    (`_login_key`) is in `exclude`, and the ids of kind `human` (the people;
    a GitHub User may be a model's account). A list that cannot be read or
    does not match its schema is empty, which adopts nothing."""
    key = (repo, ref, *sorted(exclude))
    if key not in _TRUSTED_IDS:
        owner, name = _split_repo(repo)
        try:
            listing = json_object(
                json.loads(_file_at(owner, name, TRUSTED_ACTORS_PATH, ref) or "{}")
            )
        except (PolicyReadError, ValueError):
            listing = {}
        actors = [json_object(a) for a in json_array(listing.get("actors"))]
        ids = tuple(a.get("id") for a in actors)
        valid = listing.get("version") == 1 and all(
            type(i) is int and i > 0 for i in ids
        )
        humans = tuple(a["id"] for a in actors if a.get("kind") == "human")
        kept = tuple(
            a.get("id") for a in actors if _login_key(a.get("login")) not in exclude
        )
        _TRUSTED_IDS[key] = (kept, humans) if valid else ((), ())
    return _TRUSTED_IDS[key]


def adoption_refusal(
    pr: Mapping[str, Any],
    head_committed: Callable[[], Any],
    *,
    idle_hours: int | None,
    owner_ids: Collection[int],
    human_gated: str | None,
    now: datetime,
    queued_at_head: Callable[[], bool] = lambda: False,
) -> str | None:
    """Why the pr-merge lane does not adopt this REST pull request, or None
    when it does (owner decisions Q22 and 2026-10-22): not a draft; opened by
    a User or Bot whose id is in `owner_ids` (`trusted_actor_ids`; never
    matched by login); for a User, its `updated_at` and its head commit's
    committer date, `head_committed()`, read last, both at least
    `idle_hours` old, an unreadable one not idle; and no hold: a
    `MERGE_HOLD_LABELS` label, the resolved `human_gated` role label, or a
    body hold (`BODY_MERGE_HOLD_RE`). A fresh `updated_at` is excused while
    `queued_at_head()` (`lane_queued_at_head`), read only then: the lane's
    own pin comment and enqueue refresh it."""
    user = json_object(pr.get("user"))
    uid = user.get("id")
    kind = user.get("type")
    if kind not in ("User", "Bot") or type(uid) is not int or uid not in owner_ids:
        return AUTHOR_NOT_OWNER
    if pr.get("draft") is not False:
        return "draft"
    if idle_hours is None:
        return "idle-hours-invalid"
    if not human_gated:
        return "human-gated-label-unresolved"
    labels = {
        str(json_object(label).get("name") or "").casefold()
        for label in json_array(pr.get("labels"))
    }
    held = next(
        (h for h in (*MERGE_HOLD_LABELS, human_gated) if h.casefold() in labels), None
    )
    if held:
        return f"hold-label:{held}"
    if BODY_MERGE_HOLD_RE.search(str(pr.get("body") or "")):
        return "hold-body"

    def idle(read: Callable[[], Any]) -> bool:
        try:
            return now - _time(read()) >= timedelta(hours=idle_hours)
        except PolicyReadError:
            return False

    if kind == "Bot":
        return None
    if not idle(lambda: pr.get("updated_at")) and not queued_at_head():
        return "updated-fresh"
    if not idle(head_committed):
        return "head-fresh"
    return None


def _head_committed(owner: str, name: str, pr: Mapping[str, Any]) -> Any:
    """The committer date of the pull request's head commit."""
    sha = str(json_object(pr.get("head")).get("sha") or "")
    status, payload = _get(f"repos/{owner}/{name}/commits/{sha}")
    commit = json_object(payload) if status == 200 else {}
    if not SHA_RE.fullmatch(sha) or commit.get("sha") != sha:
        raise PolicyReadError(f"head commit {sha!r} unreadable (status {status})")
    return json_object(json_object(commit.get("commit")).get("committer")).get("date")


def lane_queued_at_head(
    repo: str, number: int, branch: str, identity: str, head: str
) -> bool:
    """Whether the pull request sits in the merge queue on `branch` as the
    agent identity's own entry, enqueued at `head`, and nobody else has
    spoken since: the identity enqueued it, its newest unedited pin comment,
    posted just before the enqueue, names `head`, and no other author
    commented or reviewed after that pin (`read_pin(alone=True)`), so a
    human asking to wait still refuses. An unreadable queue, pin, comment or
    review is not queued."""
    from babysit_postmerge import (  # noqa: PLC0415
        PostMergeReadError,
        identity_queue,
        read_pin,
    )

    try:
        return bool(
            SHA_RE.fullmatch(head)
            and number in identity_queue(repo, branch, identity)[0]
            and read_pin(repo, number, identity, alone=True) == head
        )
    except PostMergeReadError:
        return False


def lane_eligibility(
    repo: str,
    number: int,
    *,
    pr: Mapping[str, Any],
    denied_paths: Collection[str],
    agent_identity: str | None,
    self_logins: Collection[str] = frozenset(),
    permission: Permission | None = None,
    adoption_idle_hours: int | None = None,
    adoption_owner_ids: Collection[int] = (),
    spec_from_body_ids: Collection[int] = (),
    human_gated: str | None = None,
    now: datetime | None = None,
    queued_at_head: Callable[[], bool] = lambda: False,
) -> Eligibility:
    """Whether the pr-merge lane may consider a pull request: not a fork or a
    dependency manager's, opened by the agent identity or adopted
    (`adoption_refusal`, with `adoption_idle_hours`, `adoption_owner_ids`,
    the resolved `human_gated` label and `queued_at_head`; None or empty
    adopts nothing),
    exactly one closing
    issue in this repository (the verifier verdict binds to it), and a diff
    touching no `merge.diff-check.denied-paths`. Such a pull request is
    class `LANE_CLASS`; no `work-class:` label is read.
    `pr` is the REST record, whose `changed_files` the file listing must
    reach. Holds (a hold label, a `Hold:` line) are the gate's, and
    adoption's too.
    `self_logins` and `permission` are unused: no human read remains."""
    owner, name = _split_repo(repo)
    issue_number = None
    adoption = None
    body_is_intent = False
    try:
        data = _graphql(ELIGIBILITY, f"#{number}", o=owner, r=name, n=number)
        node = json_object(json_object(data.get("repository")).get("pullRequest"))
        if not node:
            return Eligibility(False, "pull-request-unreadable")
        foreign = _foreign_refusal(node, owner)
        if foreign:
            return Eligibility(False, foreign)
        # Anyone could name an issue in `Closes #N`; only a pull request the
        # lane opened, or one it adopted, counts.
        if not _lane_authored(node, agent_identity):
            not_adopted = adoption_refusal(
                pr,
                lambda: _head_committed(owner, name, pr),
                idle_hours=adoption_idle_hours,
                owner_ids=adoption_owner_ids,
                human_gated=human_gated,
                now=now or datetime.now(UTC),
                queued_at_head=queued_at_head,
            )
            if not_adopted == AUTHOR_NOT_OWNER:
                return Eligibility(False, "not-lane-authored")
            if not_adopted:
                return Eligibility(False, f"not-adopted:{not_adopted}")
            adoption = f"idle-owner:{adoption_idle_hours}h"
        issue, refusal = _closing_issue(node, repo)
        if refusal is None:
            issue_number = issue["number"]
        # An adopted pull request closing no issue here is its own intent,
        # the verifier judging its title and body (owner decision 2026-10-22),
        # when a person or a script wrote them (`spec_from_body_ids`: the
        # trusted list's kind human ids and adoption.spec-from-body-apps); a
        # model-written body would be the spec the same run grades itself
        # against, whatever the account's GitHub type.
        body_is_intent = json_object(pr.get("user")).get("id") in spec_from_body_ids
        if refusal is None or adoption and body_is_intent and refusal in NO_ISSUE_HERE:
            refusal = _base_refusal(owner, name, node, shared=True)
        if refusal is None:
            refusal = _denied_path_refusal(
                owner, name, number, pr.get("changed_files"), denied_paths
            )
    except PolicyReadError as exc:
        return Eligibility(False, f"unreadable: {exc}")
    return Eligibility(
        refusal is None,
        refusal,
        LANE_CLASS,
        issue_number,
        adoption=adoption,
        body_is_intent=bool(adoption) and body_is_intent,
    )


# A commit's file list stops at this many entries, so a full one may hide more.
COMMIT_FILES_LIMIT = 300
CI_STATUS_CHECK = "ci-status"


def is_dependabot_pull_request(pr: Mapping[str, Any]) -> bool:
    """A REST pull request opened by Dependabot's App."""
    user = json_object(pr.get("user"))
    return user.get("type") == "Bot" and dependabot.is_dependabot(user.get("login"))


DEPENDABOT_CONFIG = ".github/dependabot.yml"


def _dependabot_pushes(
    owner: str,
    name: str,
    number: int,
    pr: Mapping[str, Any],
    commits: list[dict[str, Any]],
    lane_identity: str | None,
) -> str | None:
    """Who pushed each update of the head branch (`push_refusal`): what binds
    the pull request to Dependabot beyond its commits' author text. Raises
    `PolicyReadError` when the history cannot be read."""
    head = json_object(pr.get("head"))
    ref = quote(f"refs/heads/{head.get('ref')}", safe="")
    activities = _paginated(
        f"repos/{owner}/{name}/activity?ref={ref}&per_page=100", f"#{number} pushes"
    )
    return dependabot.push_refusal(
        activities, str(head.get("sha") or ""), commits, lane_identity
    )


def _dependabot_content(
    owner: str,
    name: str,
    number: int,
    pr: Mapping[str, Any],
    commits: list[dict[str, Any]],
    files: Callable[[str], list[str] | None],
) -> tuple[str | None, str | None, list[str] | None]:
    """(content reason, refusal, changed paths). The content reason,
    `dependabot-content:<x>`, names a diff that is not only covered manifests,
    lock files and `uses:` repins (`content_refusal`, per
    `.github/dependabot.yml` at the base); it sends the pull request to tier
    `review`. The paths a version-bump commit touched count as checked once
    it passes the bump rule (only plugin.json's `version` and CHANGELOG.md;
    else `dependabot-bump-content:<why>`); any other commit that is not
    Dependabot's (a lanes App fix) must pass the fix rule
    (`_fix_commit_refusal`), else `dependabot-fix-content:<why>` is the
    refusal, as is a commit whose file list cannot be read whole. The changed
    paths (either side of a rename) are None when the files listing was not
    read whole. Raises `PolicyReadError` on a read failure."""
    base_sha = str(json_object(pr.get("base")).get("sha") or "")
    config = dependabot.parse_config(
        _file_at(owner, name, DEPENDABOT_CONFIG, base_sha) or ""
    )
    extra: set[str] = set()
    for item in commits:
        if dependabot.is_dependabot_commit(item):
            continue
        sha = str(item.get("sha") or "")
        touched = files(sha)
        if touched is None:
            # Unreadable (or past the listing cap) is not "touches nothing".
            return None, f"unreadable: commit files {sha[:12]}", None
        bump = dependabot.is_actions_commit(item)
        refusal = _fix_commit_refusal(owner, name, sha, config, bump=bump)
        if refusal:
            kind = "bump" if bump else "fix"
            return None, f"dependabot-{kind}-content:{refusal}", None
        extra.update(touched)
    if config is None:
        return "dependabot-config-unreadable", None, None
    listing = _paginated(
        f"repos/{owner}/{name}/pulls/{number}/files?per_page=100", f"#{number} files"
    )
    changed = pr.get("changed_files")
    if not isinstance(changed, int) or changed != len(listing):
        return "dependabot-content:files-incomplete", None, None
    paths = [
        str(p)
        for entry in map(json_object, listing)
        for p in (entry.get("filename"), entry.get("previous_filename"))
        if p
    ]
    return dependabot.content_refusal(listing, config, extra), None, paths


FIX_TREE = """
query FixTree($o: String!, $r: String!, $e: String!) {
  repository(owner: $o, name: $r) {
    object(expression: $e) { ... on Tree { entries { name type mode } } }
  }
}
"""


def _raw_at(owner: str, name: str, path: str, sha: str) -> str | None:
    """The file's text at `sha` through the raw media type, which serves
    files over 1 MB (docs.github.com/en/rest/repos/contents#get-repository-content,
    as of 2026-10-21; recheck when that section changes its size limits);
    None when absent. Raises `PolicyReadError` on any other failure."""
    endpoint = f"repos/{owner}/{name}/contents/{quote(path)}?ref={sha}"
    try:
        proc = gh_capture(
            ["api", endpoint, "-H", "Accept: application/vnd.github.raw+json"]
        )
    except (RuntimeError, ValueError, OSError) as exc:
        raise PolicyReadError(f"{path} at {sha}: {exc}") from exc
    if proc.returncode != 0:
        if gh_http_status(proc.stderr or "") == 404:
            return None
        raise PolicyReadError(f"{path} at {sha} could not be read")
    return proc.stdout


def _fix_commit_refusal(
    owner: str,
    name: str,
    sha: str,
    config: list[tuple[str, str]] | None,
    *,
    bump: bool = False,
) -> str | None:
    """Why a lanes App commit is not a fix the lane may merge with
    (`babysit_dependabot.fix_refusal` against its one parent), or, with
    `bump`, the version-bump commit more than a version bump (`bump_refusal`),
    or None. The commit's files, modes and both sides' text are read here; a
    read that fails is a refusal."""
    status, payload = _get(f"repos/{owner}/{name}/commits/{sha}")
    detail = json_object(payload)
    listing = detail.get("files")
    parents = json_array(detail.get("parents"))
    if (
        status != 200
        or not is_json_array(listing)
        or not listing
        or len(listing) >= COMMIT_FILES_LIMIT
    ):
        return f"commit-files-unreadable:{sha[:12]}"
    parent = str(json_object(parents[0]).get("sha") or "") if parents else ""
    if len(parents) != 1 or not SHA_RE.fullmatch(parent):
        return f"commit-parents:{sha[:12]}"
    trees: dict[str, list[Any]] = {}

    def entry(path: str) -> Any:
        folder = posixpath.dirname(path)
        if folder not in trees:
            data = _graphql(
                FIX_TREE, f"{sha[:12]} tree", o=owner, r=name, e=f"{sha}:{folder}"
            )
            tree = json_object(json_object(data.get("repository")).get("object"))
            trees[folder] = json_array(tree.get("entries"))
        base = posixpath.basename(path)
        return next(
            (e for e in trees[folder] if json_object(e).get("name") == base), None
        )

    def text(side: str, path: str) -> str | None:
        return _raw_at(owner, name, path, parent if side == "before" else sha)

    try:
        if bump:
            return dependabot.bump_refusal(listing, entry, text)
        return dependabot.fix_refusal(listing, config, entry, text)
    except PolicyReadError as exc:
        return f"fix-unreadable:{str(exc)[:120]}"


def _dependabot_policy(owner: str, name: str, base_sha: str) -> Any:
    """The base's standards Dependabot policy as parsed JSON, or None when it
    is absent or not JSON (`review_only` then reports it unreadable). Raises
    `PolicyReadError` on a read failure."""
    text = _file_at(owner, name, dependabot.POLICY_PATH, base_sha)
    try:
        return json.loads(text) if text is not None else None
    except ValueError:
        return None


def _registry_json(url: str, accept: str) -> Any:
    """A package registry's JSON at `url` for the provenance gate; raises on
    any HTTP failure, a timeout or a body that is not JSON."""
    request = urllib.request.Request(
        url, headers={"Accept": accept, "User-Agent": "babysit-prs"}
    )
    with urllib.request.urlopen(  # noqa: S310 - fixed https registry URLs
        request, timeout=dependabot.PROVENANCE_TIMEOUT
    ) as response:
        return json.loads(response.read())


def _commit_files(owner: str, name: str) -> Callable[[str], list[str] | None]:
    cache: dict[str, list[str] | None] = {}

    def files(sha: str) -> list[str] | None:
        if sha not in cache:
            cache[sha] = read(sha)
        return cache[sha]

    def read(sha: str) -> list[str] | None:
        if not SHA_RE.fullmatch(sha):
            return None
        status, payload = _get(f"repos/{owner}/{name}/commits/{sha}")
        listing = json_object(payload).get("files")
        if status != 200 or not is_json_array(listing):
            return None
        if len(listing) >= COMMIT_FILES_LIMIT:
            return None
        return [str(json_object(f).get("filename") or "") for f in listing]

    return files


def _ci_status(owner: str, name: str, head: str) -> str:
    """`success`, `pending`, or the conclusion of a finished `ci-status` run on
    `head` that did not succeed; `unreadable` when the runs cannot be read."""
    status, payload = _get(
        f"repos/{owner}/{name}/commits/{head}/check-runs"
        f"?check_name={CI_STATUS_CHECK}&filter=latest&per_page=100"
    )
    runs = [json_object(r) for r in json_array(json_object(payload).get("check_runs"))]
    if status != 200 or not SHA_RE.fullmatch(head):
        return "unreadable"
    if not runs or any(r.get("status") != "completed" for r in runs):
        return "pending"
    failed = [
        str(r.get("conclusion")) for r in runs if r.get("conclusion") != "success"
    ]
    return failed[0] if failed else "success"


def dependabot_eligibility(
    repo: str,
    number: int,
    *,
    pr: Mapping[str, Any],
    agent_identity: str | None,
    hold_majors: bool = True,
) -> Eligibility:
    """Whether the pr-merge lane may merge a Dependabot pull request: not a
    fork, opened by Dependabot's App; tier `auto` (`babysit_dependabot.classify`),
    or tier `review` with the lanes App's `verdict=merge` round marker at the
    current head (`merge_verdict`) and, under `hold_majors`
    (`merge.dependabot.majors: hold`), no major or unreadable update, where a diff beyond the manifests, lock
    files and `uses:` repins Dependabot manages also makes the tier `review`;
    every commit Dependabot's (plus, after a review, the lanes App's
    `[dependabot skip]` fixes) and every push Dependabot's (or that commit's
    pusher's), never demoted, always refused; a green `ci-status` on
    the head; and no human blocking comment. A running `ci-status` waits. The
    class is C2 (mechanical), so the rung and its cap still bind it. No
    closing issue and no denied-path rule: `ci-status` is the gate. The
    hold labels and a body hold are the gate's, as for every pull
    request."""
    owner, name = _split_repo(repo)
    head = str(json_object(pr.get("head")).get("sha") or "")
    try:
        data = _graphql(ELIGIBILITY, f"#{number}", o=owner, r=name, n=number)
        node = json_object(json_object(data.get("repository")).get("pullRequest"))
        if not node:
            return Eligibility(False, "pull-request-unreadable")
        head_owner = json_object(node.get("headRepositoryOwner")).get("login")
        if (
            node.get("isCrossRepository") is not False
            or str(head_owner).casefold() != owner.casefold()
        ):
            return Eligibility(False, "fork")
        author = json_object(node.get("author"))
        if author.get("__typename") != "Bot" or not dependabot.is_dependabot(
            author.get("login")
        ):
            return Eligibility(False, "not-dependabot-authored")
        commits = pull_request_commits_once(
            f"{owner}/{name}",
            number,
            json_object(pr.get("head")).get("sha"),
            lambda: _paginated(
                f"repos/{owner}/{name}/pulls/{number}/commits?per_page=100",
                f"#{number} commits",
            ),
        )
        total = pr.get("commits")
        if (
            not isinstance(total, int)
            or isinstance(total, bool)
            or total != len(commits)
        ):
            return Eligibility(False, f"commits-listed:{len(commits)}-of:{total}")
        ci = _ci_status(owner, name, head)
        if ci == "unreadable":
            return Eligibility(False, "ci-status:unreadable")
        tier = dependabot.classify(
            str(pr.get("title") or ""),
            str(pr.get("body") or ""),
            str(json_object(pr.get("head")).get("ref") or ""),
            ci,
            commits,
        )
        # A diff that is not only what Dependabot manages goes to review, not
        # to a person: the AI review judges it like any risky bump.
        files = _commit_files(owner, name)
        # Commits no review could admit refuse before any content is read.
        refusal = dependabot.commits_refusal(commits, files, agent_identity)
        if refusal:
            return Eligibility(False, refusal, "C2", dependabot=tier)
        content, refusal, paths = _dependabot_content(
            owner, name, number, pr, commits, files
        )
        if refusal:
            return Eligibility(False, refusal, "C2", dependabot=tier)
        # A dependency the standards policy lists as review-only goes to review
        # whatever its version change; an unreadable policy sends every one.
        listed = dependabot.review_only(
            _dependabot_policy(
                owner, name, str(json_object(pr.get("base")).get("sha") or "")
            ),
            repo,
            str(json_object(pr.get("head")).get("ref") or ""),
            tier.updates,
            paths,
        )
        added = tuple(r for r in (content, *listed) if r)
        # A release whose registry provenance changed goes to review; only a
        # pull request still tier `auto` spends the registry reads.
        if not added and tier.tier == dependabot.AUTO:
            added = dependabot.provenance_reasons(
                tier.updates, tier.ecosystem, _registry_json
            )
        if added:
            tier = replace(
                tier, tier=dependabot.REVIEW, reasons=(*tier.reasons, *added)
            )
        # A tier `review` pull request merges only on the review activity's
        # `verdict=merge` at this head, and may then carry its fix commits.
        lane_commits = None
        # Fail closed: an update whose version cannot be read (a SHA pin), or
        # no readable update at all, is held like a major, marked
        # `(unreadable)`; so is every update when the title and the commit
        # metadata disagree, marked `(disagree)`.
        disagree = "sources-disagree" in tier.reasons
        majors = [
            u.name
            if u.major
            else f"{u.name}(unreadable)"
            if u.major is None
            else f"{u.name}(disagree)"
            for u in tier.updates
            if u.major is not False or disagree
        ] or ([] if tier.updates else ["updates(unreadable)"])
        if hold_majors and majors:
            return Eligibility(
                False,
                f"{MAJOR_HELD}:{','.join(majors)}",
                "C2",
                dependabot=tier,
            )
        if tier.tier != dependabot.AUTO:
            comments = _paginated(
                f"repos/{owner}/{name}/issues/{number}/comments?per_page=100",
                f"#{number} comments",
            )
            run, why = dependabot.merge_verdict(comments, str(agent_identity), head)
            if run is None:
                return Eligibility(
                    False, f"dependabot-review:{tier.reason};{why}", dependabot=tier
                )
            tier = replace(tier, approved=run)
            lane_commits = agent_identity
        # Provenance is never demoted: a push or commit not Dependabot's refuses.
        refusal = dependabot.commits_refusal(
            commits, files, lane_commits
        ) or _dependabot_pushes(owner, name, number, pr, commits, lane_commits)
        if refusal:
            return Eligibility(False, refusal, "C2", dependabot=tier)
        if ci != "success":
            return Eligibility(False, f"ci-status:{ci}", "C2", dependabot=tier)
        blockers = _human_blockers(owner, name, number, str(agent_identity or ""))
        if blockers:
            return Eligibility(
                False,
                f"human-blocking-comment:{','.join(blockers)}",
                "C2",
                dependabot=tier,
            )
    except PolicyReadError as exc:
        return Eligibility(False, f"unreadable: {exc}")
    return Eligibility(True, None, "C2", dependabot=tier)


def recheck_lane_issue(repo: str, number: int, *, issue: int | None) -> str | None:
    """The closing issue read again right before the enqueue: it must still
    be the one, in this repository, that the eligibility read found (`issue`),
    since the verifier verdict binds to it, and the base must still be the
    default branch (`_base_refusal`, read fresh)."""
    owner, name = _split_repo(repo)
    try:
        data = _graphql(ELIGIBILITY, f"#{number}", o=owner, r=name, n=number)
        node = json_object(json_object(data.get("repository")).get("pullRequest"))
        if not node:
            return "pull-request-unreadable"
        found, refusal = _closing_issue(node, repo)
        if issue is None and refusal in NO_ISSUE_HERE:
            return _base_refusal(owner, name, node)
        if refusal:
            return refusal
        if found["number"] != issue:
            return f"closing-issue-changed:{issue}>{found['number']}"
        return _base_refusal(owner, name, node)
    except PolicyReadError as exc:
        return f"unreadable: {exc}"


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
    "pageInfo{hasNextPage endCursor} nodes{number url mergedAt updatedAt headRefOid "
    "mergedBy{__typename login} mergeCommit{oid} "
    "timelineItems(itemTypes:[ADDED_TO_MERGE_QUEUE_EVENT],last:1){nodes{"
    "... on AddedToMergeQueueEvent{actor{__typename login} enqueuer{__typename login}}}}}}}}"
)


def _merged_since(
    owner: str, name: str, branch: str, since: datetime
) -> list[dict[str, Any]] | None:
    """Pull requests merged into `branch` at or after `since`, as the post-merge
    check counts them. Read newest update first until one was last updated
    before `since` (a merge updates the PR, so every PR merged since then comes
    first) or the history ends; a PR merged earlier and updated since is
    skipped. A PR updated mid-read jumps to page 1 and can slip past a walk of
    more than one page, so page 1 is then read again: a merge there the walk
    missed makes the history unreadable. None when the page limit is reached
    first."""
    found: list[dict[str, Any]] = []
    cursor: str | None = None
    for pages in range(1, MERGED_PAGE_LIMIT + 1):
        nodes, info = _merged_page(owner, name, branch, cursor)
        done = False
        for pr in nodes:
            if _time(pr.get("updatedAt")) < since:
                done = True
                break
            if _time(pr.get("mergedAt")) >= since:
                found.append(pr)
        if done or not _has_next_page(info, "merged pull requests"):
            break
        cursor = info.get("endCursor")
        if not isinstance(cursor, str) or not cursor:
            raise PolicyReadError("merged pull requests: a next page with no cursor")
    else:
        return None
    if pages > 1:
        numbers = {pr.get("number") for pr in found}
        for pr in _merged_page(owner, name, branch, None)[0]:
            if _time(pr.get("updatedAt")) < since:
                break
            if _time(pr.get("mergedAt")) >= since and pr.get("number") not in numbers:
                raise PolicyReadError(
                    "merged pull requests: the history changed while it was read"
                )
    return found


def _merged_page(
    owner: str, name: str, branch: str, cursor: str | None
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    data = _graphql(
        RECENT_MERGES_QUERY, "merged pull requests", o=owner, r=name, b=branch, c=cursor
    )
    page = json_object(json_object(data.get("repository")).get("pullRequests"))
    info = page.get("pageInfo")
    if not is_json_array(page.get("nodes")) or not is_json_object(info):
        raise PolicyReadError("merged pull requests: no page")
    return [json_object(pr) for pr in page["nodes"]], info


@dataclass(frozen=True)
class AutoMerge:
    """A merged pull request a human did not land: its merge-queue enqueue was
    not a human's, or it bypassed the queue and its `mergedBy` is not human."""

    number: int
    merge_commit: str | None
    head_ref_oid: str | None
    merged_at: str | None
    url: str | None = None
    # The agent identity landed it, so the wrapper pinned its head; any other
    # actor has no pin and verifies on the dispatch and canary runs alone.
    by_identity: bool = False
    queued: bool = True


def actor_key(actor: Any) -> str:
    """A GraphQL actor in REST spelling, compared exactly: a `Bot` login gains
    the `[bot]` suffix GraphQL omits, and any other type keeps its login, so a
    User who owns the bare slug `app` is never the App `app[bot]`."""
    item = json_object(actor)
    login = str(item.get("login") or "").strip().casefold()
    if login and item.get("__typename") == "Bot" and not login.endswith("[bot]"):
        login += "[bot]"
    return login


def derive_auto_merge(
    pr: Mapping[str, Any],
    human: Callable[[Any], bool],
    identity: str,
    *,
    lane_merges_only: bool = False,
) -> AutoMerge | str | None:
    """The one derivation `in_flight` and the post-merge check share.

    A merge whose latest `AddedToMergeQueueEvent` has a null or non-human
    `actor` or `enqueuer` is an AutoMerge. A merge with no queue event bypassed
    the queue: it is the warning `unqueued-merge:#N` when its `mergedBy` is
    human, and an AutoMerge (`queued` False) when that is null or non-human.
    A human enqueue is None. With `lane_merges_only` (the pr-merge lane), an
    AutoMerge the identity did not land is None too: another App's own
    enqueue, such as a release PR, is not the lane's to judge."""
    number = pr.get("number")
    events = json_array(json_object(pr.get("timelineItems")).get("nodes"))
    if events:
        event = json_object(events[-1])
        actors = (event.get("actor"), event.get("enqueuer"))
        if all(human(a) for a in actors):
            return None
    else:
        actors = (pr.get("mergedBy"),)
        if human(actors[0]):
            return f"unqueued-merge:#{number}"
    if not isinstance(number, int) or isinstance(number, bool):
        raise PolicyReadError(f"merged pull request: no number {number!r}")
    by_identity = identity.strip().casefold() in {actor_key(a) for a in actors}
    if lane_merges_only and not by_identity:
        return None
    return AutoMerge(
        number=number,
        merge_commit=json_object(pr.get("mergeCommit")).get("oid"),
        head_ref_oid=pr.get("headRefOid"),
        merged_at=pr.get("mergedAt"),
        url=pr.get("url"),
        by_identity=by_identity,
        queued=bool(events),
    )


@dataclass(frozen=True)
class InFlight:
    """`queued` holds every merge-queue entry's pull request number, or None
    when the queue was not read whole; `unverified` counts the unverified
    auto-merges read, all of them when clear."""

    clear: bool
    reason: str | None
    queued: frozenset[int] | None = field(default=None, compare=False)
    unverified: int = field(default=0, compare=False)


def in_flight(
    repo: str,
    *,
    agent_identity: str | None,
    self_logins: Collection[str] = frozenset(),
    permission: Permission | None = None,
    verified: Callable[[AutoMerge], bool] | None = None,
    branch: str = "main",
    merged_since: datetime | None = None,
    lane_merges_only: bool = False,
    max_in_flight: int = 1,
) -> InFlight:
    """Clear only while the merges in flight number fewer than
    `max_in_flight`: the agent identity's merge-queue entries plus every
    auto-merge (`derive_auto_merge`: a non-human enqueue, or a queue-bypassing
    merge by a non-human; with `lane_merges_only`, only the identity's)
    merged into `branch` since `merged_since` and not verified. The reason
    names the entry or merge that reached the count. Any queue entry with an
    unknown enqueuer is not clear. With no floor it is not clear and reads
    nothing; a history the read cannot reach the floor or end of is not
    clear. `verified` judges one auto-merge; without it none is."""
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
    queued: frozenset[int] | None = None
    count = unverified = 0
    try:
        data = _graphql(MERGE_QUEUE, "merge queue", o=owner, r=name, b=branch)
        queue = json_object(json_object(data.get("repository")).get("mergeQueue"))
        entries = json_object(queue.get("entries"))
        nodes = [json_object(n) for n in json_array(entries.get("nodes"))]
        if not queue or entries.get("totalCount") != len(nodes):
            return InFlight(False, "merge-queue-unreadable")
        numbers = [json_object(n.get("pullRequest")).get("number") for n in nodes]
        if all(type(n) is int for n in numbers):
            queued = frozenset(numbers)
        for entry, number in zip(nodes, numbers, strict=True):
            enqueuer = json_object(entry.get("enqueuer"))
            if not enqueuer:
                return InFlight(False, f"entry-enqueuer-unknown:#{number}", queued)
            if _login_key(enqueuer.get("login")) == _login_key(agent_identity):
                count += 1
                if count >= max_in_flight:
                    reason = f"identity-entry-queued:#{number}"
                    return InFlight(False, reason, queued)
        merges = _merged_since(owner, name, branch, merged_since)
        if merges is None:
            return InFlight(False, "merged-history-truncated", queued)
        for pr in merges:
            merge = derive_auto_merge(
                pr, human, agent_identity, lane_merges_only=lane_merges_only
            )
            if not isinstance(merge, AutoMerge):
                continue
            if verified is None or not verified(merge):
                count += 1
                unverified += 1
                if count >= max_in_flight:
                    reason = f"unverified-auto-merge:#{merge.number}"
                    return InFlight(False, reason, queued, unverified)
    except PolicyReadError as exc:
        return InFlight(False, f"unreadable: {exc}", queued, unverified)
    return InFlight(True, None, queued, unverified)


# --- Holds on a queued entry -------------------------------------------------------------------

ENTRY_HOLD_QUERY = (
    "query PolicyEntryHold($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){number body labels(first:100){totalCount nodes{name}} "
    "timelineItems(itemTypes:[ADDED_TO_MERGE_QUEUE_EVENT],last:1){nodes{"
    "... on AddedToMergeQueueEvent{createdAt}}}}}}"
)


def _human_blockers(owner: str, name: str, number: int, identity: str) -> list[str]:
    """Logins of humans whose comment, review or inline comment on the pull
    request reads as blocking, by the autopilot tier's predicates. Only an
    owner, member or collaborator counts: on a public repository anyone can
    comment, and a stranger's text must not dequeue the identity's entry."""
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
        if (
            str(item.get("author_association") or "").upper()
            not in BLOCKER_ASSOCIATIONS
        ):
            continue
        body = str(item.get("body") or "")
        if (
            has_blocking_text(body)
            or has_blocking_severity(body)
            or HUMAN_MERGE_VETO_RE.search(body)
        ):
            found.add(login or "unknown")
    return sorted(found)


def _opt_in_hold(
    owner: str,
    name: str,
    pr: dict[str, Any],
    enqueued_at: Any,
    human: Callable[[Any], bool],
) -> str | None:
    """Why the opt-in label no longer stands as it did at enqueue: it was on
    the pull request then and is gone now, or it changed since and its latest
    application is not a human's in person (`_label_provenance`), so a
    non-human cannot restore an opt-in a human revoked."""
    labels = _label_names(pr)
    if labels is None:
        raise PolicyReadError(f"#{pr.get('number')}: labels unreadable")
    number = int(pr.get("number") or 0)
    at = _time(enqueued_at)
    timelines: dict[int, list[dict[str, Any]]] = {}
    events = sorted(
        (
            e
            for e in _timeline(owner, name, number, timelines)
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
    if OPT_IN_LABEL not in labels:
        return "opt-in-label-removed" if present else None
    # The label read and the timeline read are not atomic: a removal the
    # timeline already shows wins over the label snapshot.
    if events and events[-1].get("event") == "unlabeled":
        return "opt-in-label-removed"
    if not any(_time(e.get("created_at")) > at for e in events):
        return None
    untrusted = _label_provenance(
        owner, name, number, OPT_IN_LABEL, None, human, timelines
    )
    return f"opt-in-label:{untrusted}" if untrusted else None


def entry_hold(
    repo: str,
    number: int,
    identity: str,
    *,
    self_logins: Collection[str] = frozenset(),
    permission: Permission | None = None,
) -> str | None:
    """Why a queued entry of the agent identity must leave the queue (D3): the
    `do-not-merge` or human-gated label, a body hold, a human blocking comment, or the opt-in
    label removed since the enqueue or put back by a non-human. An unreadable
    entry is a hold."""
    from babysit_merge import (  # noqa: PLC0415
        BODY_MERGE_HOLD_RE,
        human_gated_label,
        merge_hold_label,
    )
    from babysit_postmerge import PostMergeReadError  # noqa: PLC0415

    owner, name = _split_repo(repo)
    permission = permission or permission_reader(repo)
    human = lambda actor: is_human(  # noqa: E731
        actor,
        repo=repo,
        agent_identity=identity,
        self_logins=self_logins,
        permission=permission,
    )
    try:
        data = _graphql(ENTRY_HOLD_QUERY, f"#{number}", o=owner, r=name, n=number)
        pr = json_object(json_object(data.get("repository")).get("pullRequest"))
        labels = _label_names(pr)
        events = json_array(json_object(pr.get("timelineItems")).get("nodes"))
        if labels is None or not events:
            return "unreadable"
        # Only unattended runs judge queued entries.
        if held_by := merge_hold_label(labels, human_gated=human_gated_label(repo)):
            return held_by
        if BODY_MERGE_HOLD_RE.search(str(pr.get("body") or "")):
            return "body-hold"
        blockers = _human_blockers(owner, name, number, identity)
        if blockers:
            return f"human-blocking-comment:{','.join(blockers)}"
        opt_in = _opt_in_hold(
            owner, name, pr, json_object(events[-1]).get("createdAt"), human
        )
        if opt_in:
            return opt_in
    except (PolicyReadError, PostMergeReadError) as exc:
        return f"unreadable: {exc}"
    return None


# --- Composition ------------------------------------------------------------------------------


DEFAULT_BRANCH_SECTION = "default-branch"
# Repositories whose default branch this process took from the run cache;
# `unattended_enqueue` reads it again before an enqueue.
SHARED_DEFAULT_BRANCHES: set[str] = set()


def _default_branch(repo: str, *, shared: bool = False) -> str:
    """The default branch's name. `shared` takes one another gate process of
    the run read within `run_cache.MAX_AGE`; every read is saved for them, a
    failed one never."""
    cached = (
        run_cache.get(DEFAULT_BRANCH_SECTION, repo, run_cache.MAX_AGE)
        if shared
        else None
    )
    if isinstance(cached, str) and cached:
        SHARED_DEFAULT_BRANCHES.add(repo)
        return cached
    owner, name = _split_repo(repo)
    status, payload = _get(f"repos/{owner}/{name}")
    branch = (
        payload.get("default_branch")
        if status == 200 and is_json_object(payload)
        else None
    )
    if not isinstance(branch, str) or not branch:
        raise PolicyReadError(f"{repo}: the default branch could not be read")
    run_cache.put(DEFAULT_BRANCH_SECTION, repo, branch)
    return branch


def _default_branch_head(repo: str, branch: str | None = None) -> tuple[str, str]:
    """The default branch's name (`branch` when already read) and its head
    SHA."""
    owner, name = _split_repo(repo)
    branch = branch or _default_branch(repo)
    status, payload = _get(f"repos/{owner}/{name}/commits/{quote(branch, safe='')}")
    sha = payload.get("sha") if status == 200 and is_json_object(payload) else None
    if not isinstance(sha, str) or not SHA_RE.fullmatch(sha):
        raise PolicyReadError(f"{repo}: the head of {branch} could not be read")
    return branch, sha


MAX_IN_FLIGHT_SECTION = "max-in-flight"


def _run_max_in_flight(
    repo: str,
    branch: str,
    head: str | None,
    base: PipelineConfig,
    *,
    shared: bool = True,
) -> tuple[int, str]:
    """`merge.max-in-flight` and where it was read. It caps the one merge
    queue, so every candidate reads it at the head of `branch` (the default
    branch; `head` when already read), not at its own base. `shared` reads
    and saves it once per cache window (`run_cache.MAX_AGE`) for the run's
    gate processes, never saving a failed read; a failed read falls back to
    `base`'s value."""
    cached = (
        run_cache.get(MAX_IN_FLIGHT_SECTION, repo, run_cache.MAX_AGE)
        if shared
        else None
    )
    if type(cached) is int and cached >= 1:
        return cached, "default-branch"
    owner, name = _split_repo(repo)
    if head is None:
        status, payload = _get(f"repos/{owner}/{name}/commits/{quote(branch, safe='')}")
        head = payload.get("sha") if status == 200 and is_json_object(payload) else None
    if not isinstance(head, str):
        return base.max_in_flight, "base"
    if head == base.base_sha:
        config = base
    else:
        try:
            config = read_config_at(
                repo,
                head,
                lambda path, sha: (
                    _file_at(owner, name, path, sha) if path == CONFIG_PATH else None
                ),
            )
        except PolicyReadError:
            return base.max_in_flight, "base"
    if config.error:
        return base.max_in_flight, "base"
    if shared:
        run_cache.put(MAX_IN_FLIGHT_SECTION, repo, config.max_in_flight)
    return config.max_in_flight, "default-branch"


def pull_request(repo: str, number: int) -> dict[str, Any]:
    """The pull request's REST record, with a base and head SHA that are full
    commit ids."""
    owner, name = _split_repo(repo)
    status, payload = _get(f"repos/{owner}/{name}/pulls/{number}")
    pr = json_object(payload) if status == 200 else {}
    base, head = json_object(pr.get("base")), json_object(pr.get("head"))
    if not (
        SHA_RE.fullmatch(str(base.get("sha")))
        and SHA_RE.fullmatch(str(head.get("sha")))
        and isinstance(base.get("ref"), str)
        and isinstance(head.get("ref"), str)
    ):
        raise PolicyReadError(f"#{number} could not be read (status {status})")
    record_pull_request_total(repo, number, head.get("sha"), pr.get("commits"))
    return pr


# --- The post-merge floor -----------------------------------------------------------------------

# The pipeline file's commits the contents-API fallback reads for the enabling
# commit: one page. A run of enabled commits longer than that has no readable
# start, which refuses. The local git history has no such limit.
CONFIG_HISTORY_LIMIT = 100


def _history_checkouts() -> list[Path]:
    """Where a local clone may hold the pipeline file's history: this
    script's own checkout (the pr-merge lane runs it from a checkout of main)
    and the working directory's (a local babysit run from a clone)."""
    return [Path(__file__).resolve().parent, Path.cwd()]


# How a history read sees a clone's real commits, beside the
# `--no-replace-objects` each caller passes: a graft file is ignored, and a
# missing object fails the read rather than being lazily fetched. A graft or
# replace ref would cut or rewrite the history a clone reports.
HISTORY_GIT_ENV = {"GIT_GRAFT_FILE": os.devnull, "GIT_NO_LAZY_FETCH": "1"}


def _git(root: Path, *args: str) -> str | None:
    """The stdout of `git` run in `root`, or None when it fails."""
    try:
        proc = run_command(
            ["git", "--no-replace-objects", "-C", str(root), *args],
            allowed_executables=("git",),
            check=False,
            env_overrides=HISTORY_GIT_ENV,
        )
    except (RuntimeError, ValueError, OSError):
        return None
    return proc.stdout if proc.returncode == 0 else None


def _git_file_at(root: Path, path: str, sha: str) -> str | None:
    """The file's text at `sha` in the clone at `root`, or None when absent
    from a readable tree."""
    entry = _git(root, "ls-tree", "-z", sha, "--", path)
    if entry is None:
        raise PolicyReadError(f"the tree at {sha} could not be read")
    if not entry:
        return None
    mode, kind = entry.split(" ", 2)[:2]
    if mode == "120000":
        raise _SymlinkAt(f"{path} at {sha} is a symlink")
    if kind != "blob":
        raise PolicyReadError(f"{path} at {sha} is not a file")
    text = _git(root, "cat-file", "blob", f"{sha}:{path}")
    if text is None:
        raise PolicyReadError(f"{path} at {sha} is unreadable")
    return text


def _full_history_root(checkout: Path) -> Path | None:
    """The top of the clone holding `checkout` when it has its whole history
    (not shallow or partial), else None."""
    # Pathspecs resolve against the working directory, so run at the top.
    top = _git(checkout, "rev-parse", "--show-toplevel")
    if not top or not top.strip():
        return None
    root = Path(top.strip())
    if _git(root, "rev-parse", "--is-shallow-repository") != "false\n":
        return None
    # A partial clone lacks older blobs, which the read never fetches.
    promisor = r"^(extensions\.partialclone|remote\..*\.promisor)$"
    if _git(root, "config", "--get-regexp", promisor) is not None:
        return None
    return root


def _clones_holding(sha: str) -> Iterator[Path]:
    """The top of each clone in `_history_checkouts` that holds `sha` with its
    whole history (`_full_history_root`). A commit id names its whole
    ancestry and tree, so any clone holding it answers for the repository."""
    for checkout in _history_checkouts():
        root = _full_history_root(checkout)
        if root is None or _git(root, "cat-file", "-e", f"{sha}^{{commit}}") is None:
            continue
        yield root


def _local_history(base_sha: str) -> tuple[Path, list[tuple[str, str]]] | None:
    """The pipeline file's commits from `base_sha`, newest first, as (SHA,
    committer date), from the first clone holding `base_sha`
    (`_clones_holding`); None when none does."""
    for root in _clones_holding(base_sha):
        log = _git(
            root,
            "-c",
            "log.follow=false",
            "log",
            "--no-show-signature",
            "--format=%H %cI",
            base_sha,
            "--",
            CONFIG_PATH,
        )
        if log is not None:
            pairs = [line.partition(" ") for line in log.splitlines()]
            return root, [(sha, date) for sha, _, date in pairs]
    return None


def enabled_since(repo: str, base_sha: str, authority: str | None = None) -> datetime:
    """When the unattended path's current enabled run began: the committer
    date of the oldest commit in the unbroken run of pipeline-file commits,
    newest first from `base_sha`, whose config enables `authority`
    (`enabled_authority`; None means the one the config at `base_sha`
    enables). A later edit that keeps it enabled does not move the floor, so
    no merge since enabling escapes the check. Commits reach the default
    branch through the merge queue, whose squash commits GitHub dates.

    The history and each config come from a local clone holding `base_sha`
    (`_local_history`), else from the commits and contents APIs.
    Raises `PolicyReadError` when no start can be read."""
    local = _local_history(base_sha)
    if local is not None:
        root, commits = local
        complete = True

        def read(sha: str) -> PipelineConfig:
            return read_config_at(
                repo, sha, lambda path, ref: _git_file_at(root, path, ref)
            )

    else:
        owner, name = _split_repo(repo)
        status, payload = _get(
            f"repos/{owner}/{name}/commits?sha={base_sha}"
            f"&path={quote(CONFIG_PATH, safe='')}&per_page={CONFIG_HISTORY_LIMIT}"
        )
        if status != 200 or not is_json_array(payload):
            raise PolicyReadError(f"{CONFIG_PATH} history could not be read")
        commits = [
            (
                str(commit.get("sha")),
                str(
                    json_object(json_object(commit.get("commit")).get("committer")).get(
                        "date"
                    )
                ),
            )
            for commit in map(json_object, payload)
        ]
        complete = len(commits) < CONFIG_HISTORY_LIMIT

        def read(sha: str) -> PipelineConfig:
            return read_config_at(repo, sha)

    if not commits:
        raise PolicyReadError(f"{CONFIG_PATH} history could not be read")
    start: str | None = None
    for sha, date in commits:
        config = read(sha)
        enabled = None if config.error else enabled_authority(config)
        authority = authority or enabled
        if enabled is None or enabled != authority:
            break
        start = date
    else:
        if not complete:
            raise PolicyReadError(
                f"more than {CONFIG_HISTORY_LIMIT} enabled {CONFIG_PATH} commits"
            )
    if start is None:
        raise PolicyReadError(f"{CONFIG_PATH} at {base_sha} does not enable the path")
    return _time(start.replace("Z", "+00:00")).astimezone(UTC)


def merged_since_floor(
    repo: str, base_sha: str, demotion: Demotion, authority: str | None = None
) -> datetime:
    """The post-merge floor: the later of the enabling commit of `authority`
    (`enabled_since`) and the newest human close of a demotion record, so a
    human clear restarts the window and a deleted or transferred record moves
    nothing. Raises `PolicyReadError` when the enabling commit cannot be
    read."""
    floor = enabled_since(repo, base_sha, authority)
    if demotion.cleared_at is not None:
        floor = max(floor, demotion.cleared_at)
    return floor


# --- Changed files with git modes -------------------------------------------------------------


def _tree_modes(owner: str, name: str, sha: str) -> dict[str, str] | None:
    """Each path's git mode at `sha`, or None when the listing is truncated:
    from a local clone holding `sha` (`_clones_holding`), else the trees API."""
    for root in _clones_holding(sha):
        listing = _git(root, "ls-tree", "-r", "-t", "-z", "--full-tree", sha)
        if listing is not None:
            # Each entry is `<mode> <type> <id>\t<path>`.
            return {
                path: meta.split(" ", 1)[0]
                for meta, _, path in (
                    entry.partition("\t") for entry in listing.split("\0") if entry
                )
            }
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
    """The pull request's files with git modes from `_tree_modes` (the files
    API carries none): the head side at its head, the previous side at
    `base_sha`. Complete only when every listing reads to its end."""
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
                patch=entry.get("patch"),
                mode=(side or {}).get(path),
                previous_mode=None
                if status in ("added", "removed")
                else (base_modes or {}).get(previous or path),
            )
        )
    return tuple(files), complete


def changed_files(
    repo: str, pr: Mapping[str, Any]
) -> tuple[tuple[ChangedFile, ...], bool]:
    """`_changed_files` for a REST pull request record, the previous side read
    at its base SHA."""
    owner, name = _split_repo(repo)
    shaped = {
        "number": pr.get("number"),
        "headRefOid": json_object(pr.get("head")).get("sha"),
        "changedFiles": pr.get("changed_files"),
    }
    return _changed_files(
        owner, name, shaped, str(json_object(pr.get("base")).get("sha"))
    )


# GitHub's web-flow account, which commits what an App writes through the API.
WEB_FLOW_ID = 19864447


def _own_commit(commit: Mapping[str, Any], user: Mapping[str, Any]) -> bool:
    """Whether a pull request commit is its author's own: GitHub verified
    its signature, its author account is the pull request's author, and,
    for a person, so is its committer. The author account alone comes from
    the git author email, which anyone can set. An App commits through the
    API, which GitHub's web-flow (`WEB_FLOW_ID`) commits, so its committer
    may be web-flow or itself: the weaker case."""
    author = json_object(commit.get("author")).get("id")
    committer = json_object(commit.get("committer")).get("id")
    verified = json_object(
        json_object(json_object(commit.get("commit")).get("verification"))
    ).get("verified")
    allowed = (author, WEB_FLOW_ID) if user.get("type") == "Bot" else (author,)
    return verified is True and author == user.get("id") and committer in allowed


def foreign_paths(
    repo: str, pr: Mapping[str, Any], changed: Collection[str]
) -> frozenset[str] | None:
    """The `changed` paths (the pull request's, both sides of a rename) that
    a commit not its author's own (`_own_commit`) touched: what an adopted
    pull request's floor scores (owner decision 2026-10-22: a trusted
    author's own lines, a person's or an App's, need no person; a lane's fix
    still does, and the lanes App's own pull requests, never adopted, are
    scored whole). A merge commit counts too, intersected with `changed`, so
    main's incoming files outside the pull request's diff score nothing
    while a conflict resolved inside it scores. None, which scores every
    path, when a listing may be cut off or cannot be read."""
    owner, name = _split_repo(repo)
    user = json_object(pr.get("user"))
    try:
        commits = _paginated(
            f"repos/{owner}/{name}/pulls/{pr.get('number')}/commits?per_page=100",
            f"#{pr.get('number')} commits",
        )
        if type(user.get("id")) is not int or len(commits) >= 250:
            return None
        paths: set[str] = set()
        for commit in commits:
            if _own_commit(commit, user):
                continue
            status, payload = _get(f"repos/{owner}/{name}/commits/{commit.get('sha')}")
            files = json_array(json_object(payload).get("files"))
            if status != 200 or len(files) >= 300:
                return None
            for entry in map(json_object, files):
                paths.update(
                    p
                    for p in (entry.get("filename"), entry.get("previous_filename"))
                    if isinstance(p, str) and p
                )
    except PolicyReadError:
        return None
    return frozenset(paths.intersection(changed))


# Paths never a trusted author's own, whoever wrote them (S&C review of
# #9107): who is trusted, what CI runs with tokens (pr-verify runs
# .github/scripts, actions and standards code from main), and who must review.
NEVER_FLOOR_EXEMPT = (
    ".github/standards/**",
    ".github/workflows/**",
    ".github/scripts/**",
    ".github/actions/**",
    # Owner decision 2026-10-20 (Gated PR Merge clause 5): the merge gate,
    # the review lanes and agent permission config, even in his own PRs; the
    # rest of that config is `INSTRUCTION_PATH_RE`.
    "plugins/source-control/skills/babysit-prs/**",
    "plugins/review/**",
    "docs/conventions/**",
    "REVIEW.md",
    "**/settings*.json",
)
# The instruction and runnable-plugin paths (CLAUDE.md, AGENTS.md, .mcp.json,
# .lsp.json, .gitmodules, CODEOWNERS, .claude/ and .claude-plugin/
# directories, plugins/*/hooks, monitors and bin): the twin of
# .github/scripts/pr-unblock/thread-scope.mjs INSTRUCTION_PATH, which a test
# holds equal. Never floor-exempt either.
INSTRUCTION_PATH_RE = re.compile(
    r"(^|\/)((claude|agents)\.md|\.mcp\.json|\.lsp\.json|\.gitmodules|codeowners)$|(^|\/)\.claude(-plugin)?(\/|$)|(^|\/)plugins\/[^/]+\/(hooks|monitors|bin)(\/|$)",
    re.I,
)


def own_paths(
    repo: str, pr: Mapping[str, Any], changed: Collection[str]
) -> frozenset[str]:
    """The `changed` paths only the author's own commits touched
    (`foreign_paths`), less `NEVER_FLOOR_EXEMPT` and `INSTRUCTION_PATH_RE`: what the path floor leaves
    out of an adopted pull request whose author's lines count as its own
    (`Eligibility.body_is_intent`). Empty when the commits cannot be read."""
    others = foreign_paths(repo, pr, changed)
    if others is None:
        return frozenset()
    return frozenset(
        p
        for p in changed
        if p not in others
        and not INSTRUCTION_PATH_RE.search(p)
        and not any(glob_match(g, p) for g in NEVER_FLOOR_EXEMPT)
    )


# Capability file text by (owner, name, path, sha): a SHA pins the text, so a
# run reads each side of each file once.
_TEXT_AT: dict[tuple[str, str, str, str], str | None] = {}


def _text_at(owner: str, name: str, path: str, sha: str) -> str | None:
    key = (owner, name, path, sha)
    if key not in _TEXT_AT:
        # Quoted, so a `?` or `#` in a changed path cannot pick another ref.
        _TEXT_AT[key] = _file_at(owner, name, quote(path, safe="/"), sha)
    return _TEXT_AT[key]


def with_capability_contents(
    repo: str, pr: Mapping[str, Any], files: tuple[ChangedFile, ...]
) -> tuple[ChangedFile, ...]:
    """Each changed capability file, manifest or eval case.yaml (not removed) with its base
    text at the base SHA, from its previous path on a rename or copy, and its head text
    at the head SHA, or the reason either could not be read."""
    owner, name = _split_repo(repo)
    base = json_object(pr.get("base")).get("sha")
    head = json_object(pr.get("head")).get("sha")
    read = []
    for changed in files:
        if changed.status == "removed" or not (
            is_capability_path(changed.path)
            or is_manifest_path(changed.path)
            or is_case_file(changed.path)
        ):
            read.append(changed)
            continue
        try:
            if not (
                isinstance(base, str)
                and SHA_RE.fullmatch(base)
                and isinstance(head, str)
                and SHA_RE.fullmatch(head)
            ):
                raise PolicyReadError(
                    "the pull request record names no base or head SHA"
                )
            before = (
                None
                if changed.status == "added"
                else _text_at(owner, name, changed.previous_path or changed.path, base)
            )
            after = _text_at(owner, name, changed.path, head)
            read.append(replace(changed, contents=(before, after)))
        except Exception as exc:  # noqa: BLE001 - any failure reads as unreadable (HIGH)
            reason = f"{type(exc).__name__}: {exc}"
            # repr escapes a newline in the author-controlled path, so the line
            # cannot start a workflow command.
            print(
                f"capability contents of {changed.path!r}: {reason!r}", file=sys.stderr
            )
            read.append(replace(changed, contents_error=reason))
    return tuple(read)


_TREE_MODE = "040000"


def _base_text(
    owner: str,
    name: str,
    root: Path | None,
    modes: Mapping[str, str],
    path: str,
    base: str,
) -> str | None:
    """A file's text at the base SHA, from the clone at `root` when there is
    one, else the contents API; None when absent, a tree, or unreadable."""
    if modes.get(path) in (None, _TREE_MODE):
        return None
    try:
        if root is not None:
            return _git_file_at(root, path, base)
        return _text_at(owner, name, path, base)
    except (PolicyReadError, ValueError) as exc:
        print(f"base file {path!r}: {type(exc).__name__}", file=sys.stderr)
        return None


def agents_at(
    repo: str, pr: Mapping[str, Any]
) -> tuple[tuple[str, str | None], ...] | None:
    """`babysit_risk.RiskInput.agents`: every `AGENT_FILES` file at the base
    SHA as (path, text), None for a file that could not be read; None when the
    base tree cannot be listed."""
    owner, name = _split_repo(repo)
    base = str(json_object(pr.get("base")).get("sha"))
    try:
        if not SHA_RE.fullmatch(base):
            raise PolicyReadError("the pull request record names no base SHA")
        root = next(_clones_holding(base), None)
        modes = _tree_modes(owner, name, base)
    except (PolicyReadError, ValueError) as exc:
        print(f"agents at the base: {type(exc).__name__}: {exc}", file=sys.stderr)
        return None
    if modes is None:
        return None
    return tuple(
        (path, _base_text(owner, name, root, modes, path, base))
        for path in sorted(modes)
        if modes[path] != _TREE_MODE and glob_match(AGENT_FILES, path)
    )


def eval_cases_at(
    repo: str, pr: Mapping[str, Any], changed: Iterable[str | None]
) -> tuple[tuple[str, str | None], ...] | None:
    """`babysit_risk.RiskInput.eval_cases`: each case file (`is_case_file`) at the base SHA in
    a directory `eval_case_dirs` names for a changed path, as (path, text),
    None for a file that could not be read; None when the base tree cannot be
    listed."""
    owner, name = _split_repo(repo)
    base = str(json_object(pr.get("base")).get("sha"))
    wanted = {d for path in changed if path for d in eval_case_dirs(path)}
    try:
        if not SHA_RE.fullmatch(base):
            raise PolicyReadError("the pull request record names no base SHA")
        root = next(_clones_holding(base), None)
        modes = _tree_modes(owner, name, base)
    except (PolicyReadError, ValueError) as exc:
        print(f"eval cases at the base: {type(exc).__name__}: {exc}", file=sys.stderr)
        return None
    if modes is None:
        return None
    return tuple(
        (path, _base_text(owner, name, root, modes, path, base))
        for path in sorted(modes)
        if modes[path] != _TREE_MODE and is_case_file(path) and case_dir(path) in wanted
    )


def declarations_at(
    repo: str, pr: Mapping[str, Any], changed: Iterable[str | None]
) -> tuple[tuple[str, str | None], ...] | None:
    """`babysit_risk.RiskInput.declarations`: `DECLARATION_FILES` files and
    the config files their plugin.json points at, at the base SHA as (path,
    text), with None for a file that could not be read. From a clone holding
    the base, every plugin's, which costs no API call; else, through the
    contents API, only those of a plugin directory a changed path sits in: a
    declared path outside its own plugin is unsafe, so only another plugin's
    escaping declaration could floor a changed file, and a change outside
    every plugin reads none. None when the base tree cannot be listed; the
    scorer holds the floor either way."""
    plugins = {
        "/".join(parts[:2]).casefold()
        for path in changed
        if isinstance(path, str)
        and len(parts := path.split("/")) >= 3
        and parts[0].casefold() == "plugins"
    }
    owner, name = _split_repo(repo)
    base = str(json_object(pr.get("base")).get("sha"))
    try:
        if not SHA_RE.fullmatch(base):
            raise PolicyReadError("the pull request record names no base SHA")
        root = next(_clones_holding(base), None)
        if root is None and not plugins:
            return ()
        modes = _tree_modes(owner, name, base)
    except (PolicyReadError, ValueError) as exc:
        print(f"declarations at the base: {type(exc).__name__}: {exc}", file=sys.stderr)
        return None
    if modes is None:
        return None

    def read(path: str) -> str | None:
        return _base_text(owner, name, root, modes, path, base)

    found = [
        (path, read(path))
        for path in sorted(modes)
        if (root is not None or "/".join(path.split("/")[:2]).casefold() in plugins)
        and any(glob_match(g, path) for g in DECLARATION_FILES)
    ]
    named = {path for path, _ in found}
    pointers = (
        q for path, text in list(found) for q in declaration_pointers(path, text)
    )
    for pointer in dict.fromkeys(pointers):
        if pointer not in named:
            found.append((pointer, read(pointer)))
    return tuple(found)


# --- Promotion evidence -----------------------------------------------------------------------

# The four babysit-loop options the resolver reads from the operator's managed
# and user settings (operator-options.mjs), each naming a surface or the checker.
PROMOTION_OPTIONS = (
    "promotion_evidence_binding",
    "promotion_evidence_root",
    "promotion_evidence_source",
    "promotion_evidence_checker",
)
# Optional options whose values are not local paths: the credential roots name
# the probe host, so only the settings file they came from is checked.
PROMOTION_SETTINGS_ONLY_OPTIONS = ("promotion_evidence_credential_roots",)
PROMOTION_RESOLVER = (
    Path(__file__).resolve().parents[2]
    / "babysit-loop"
    / "scripts"
    / "resolve-promotion-evidence.mjs"
)
PROMOTABLE_CELLS = ("C2-auto-merge", "C3-auto-merge", "C3-ai-review-blocking")
# The cells a work class needs effective-promoted (promotion-evidence-resolution.md
# "Promotable cells and rung mapping"); C4 and C5 have none and never merge.
CLASS_CELLS = {
    "C1": ("C2-auto-merge",),
    "C2": ("C2-auto-merge",),
    "C3": PROMOTABLE_CELLS,
}


def _lane_writable(path: Path) -> bool:
    """The lane user can write the path, or replace it through any directory
    above it (written, or owned and so re-permissioned), as given or after
    symlinks resolve. Raises `OSError` when the path does not exist."""
    getuid = getattr(os, "getuid", None)
    for candidate in {path.absolute(), path.resolve(strict=True)}:
        for node in (candidate, *candidate.parents):
            if os.access(node, os.W_OK):
                return True
            if getuid is not None and node.stat().st_uid == getuid():
                return True
    return False


def _options_refusal(
    options: dict[str, Any], writable: Callable[[Path], bool]
) -> str | None:
    """Why the option values the resolver reports, or the settings files they
    came from, are not trusted: one is unreported, or the lane user can write
    it or replace it through a directory above it. A lane that can rewrite the
    evidence, the checker or the setting naming them decides `promoted`. A
    reported settings-only option checks its settings file alone."""
    for option in PROMOTION_OPTIONS:
        entry = json_object(options.get(option))
        value, source = entry.get("value"), entry.get("file")
        if not isinstance(value, str) or not isinstance(source, str):
            return f"option-unreported:{option}"
        for label, path in (("evidence", value), ("settings", source)):
            try:
                if writable(Path(path)):
                    return f"{label}-lane-writable:{option}"
            except OSError:
                return f"{label}-unreadable:{option}"
    for option in PROMOTION_SETTINGS_ONLY_OPTIONS:
        if option not in options:
            continue
        source = json_object(options.get(option)).get("file")
        if not isinstance(source, str):
            return f"option-unreported:{option}"
        try:
            if writable(Path(source)):
                return f"settings-lane-writable:{option}"
        except OSError:
            return f"settings-unreadable:{option}"
    return None


def _window_start(at: datetime) -> str:
    """`at` in the checker's strict form, whole seconds in UTC, rounded up so
    the restart never lands before the demotion it stands for."""
    at = at.astimezone(UTC)
    if at.microsecond:
        at = at.replace(microsecond=0) + timedelta(seconds=1)
    return at.strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass(frozen=True)
class Promotion:
    """Each promotable cell's effective state, or the fail-closed reason."""

    cells: Mapping[str, str] | None
    reason: str | None

    def promoted(self, work_class: str | None) -> bool:
        needed = CLASS_CELLS.get(work_class or "")
        return bool(
            self.cells
            and needed
            and all(self.cells.get(cell) == "promoted" for cell in needed)
        )


def worktree_roots(checkout: Path) -> list[str] | None:
    """Every worktree of the checkout's repository, or None when git cannot
    list them."""
    try:
        proc = run_command(
            ["git", "-C", str(checkout), "worktree", "list", "--porcelain"],
            allowed_executables=("git",),
            check=False,
        )
    except (RuntimeError, ValueError, OSError):
        return None
    if proc.returncode != 0:
        return None
    return [
        line.removeprefix("worktree ")
        for line in proc.stdout.splitlines()
        if line.startswith("worktree ")
    ]


def read_promotion(
    *,
    checkout: Path,
    window_start: datetime | None,
    worktrees: Callable[[Path], list[str] | None] = worktree_roots,
    writable: Callable[[Path], bool] = _lane_writable,
) -> Promotion:
    """Run the babysit-loop promotion resolver, which reads the four option
    values from the operator's managed and user settings itself.

    Every worktree of the checkout is a `--worktree-root`, so a surface in a
    sibling worktree refuses. With a demotion record, `--window-start` is its
    creation: the checker reads the source's events plus one `gate-failure`
    per promotable cell then, so a cell stays unpromoted until it is
    re-ratified after the demotion. A value the resolver reports, or the
    settings file it came from, that the lane user can write refuses.
    Anything doubtful is unpromoted."""
    roots = worktrees(checkout)
    if roots is None:
        return Promotion(None, "worktrees-unreadable")
    argv = ["node", str(PROMOTION_RESOLVER), "--checkout", str(checkout)]
    for root in roots:
        argv += ["--worktree-root", root]
    if window_start is not None:
        argv += ["--window-start", _window_start(window_start)]
    try:
        proc = run_command(argv, allowed_executables=("node",), check=False)
        result = json_object(json.loads(proc.stdout))
    except (RuntimeError, ValueError, OSError) as exc:
        return Promotion(None, f"resolver-failed: {exc}")
    if proc.returncode != 0 or result.get("failClosedReason") is not None:
        return Promotion(None, str(result.get("failClosedReason") or "resolver-failed"))
    refusal = _options_refusal(json_object(result.get("options")), writable)
    if refusal:
        return Promotion(None, refusal)
    cells = {
        cell: json_object(state).get("effective")
        for cell, state in json_object(result.get("cells")).items()
    }
    return Promotion({c: str(v) for c, v in cells.items()}, None)


@dataclass(frozen=True)
class PostMergeGate:
    """The post-merge check's answer, as `assess()` consumes it: a refusal
    (a failure or an unreadable verdict) or None, the verdict's report, and
    the `verified` callable `in_flight` judges each auto-merge with."""

    refusal: str | None
    report: Mapping[str, Any]
    verified: Callable[[AutoMerge], bool] | None


# How old a shared post-merge answer may be: the pr-merge job's timeout.
SHARED_MAX_AGE = timedelta(minutes=30)
# How old a shared answer still waiting on a lane merge's verifying run may
# be: that run may have passed since. The verify-evidence listing's bound.
SHARED_UNVERIFIED_MAX_AGE = run_cache.MAX_AGE
# Refusals that bind the answer to another candidate, not to an older state,
# or leave the binding unknown: a recompute under one is not written over
# the run's answer.
SHARED_BINDING_REFUSALS = frozenset(
    {
        "identity-differs",
        "self-logins-differ",
        "lane-differs",
        "floor-differs",
        "config-unreadable",
    }
)
# Runner clocks may run ahead of GitHub's; `since` starts this much earlier.
SINCE_CLOCK_MARGIN = timedelta(minutes=5)


@dataclass(frozen=True)
class SharedPostMerge:
    """The repo-wide part of `assess` (demotion, floor, post-merge answer),
    computed once per pr-merge run at the default branch head by
    `babysit_postmerge.py` and handed to each candidate, bound to what it was
    computed from (`shared_refusal`)."""

    main_sha: str
    config_sha: str
    identity: str
    self_logins: frozenset[str]
    lane_merges_only: bool
    computed_at: datetime
    demotion: Demotion
    floor: datetime
    gate: PostMergeGate


def newest_config_commit(repo: str, sha: str) -> str:
    """The newest commit at or before `sha` that changed the pipeline file,
    where `enabled_since` starts its walk: two SHAs on the (linear, merge
    queue) default branch that share it share the floor. Read from the same
    source: a local clone (`_local_history`), else the commits API. Raises
    `PolicyReadError`."""
    local = _local_history(sha)
    if local is not None:
        newest = local[1][0][0] if local[1] else ""
    else:
        owner, name = _split_repo(repo)
        status, commits = _get(
            f"repos/{owner}/{name}/commits?sha={sha}"
            f"&path={quote(CONFIG_PATH, safe='')}&per_page=1"
        )
        newest = (
            str(json_object(commits[0]).get("sha"))
            if status == 200 and is_json_array(commits) and commits
            else ""
        )
    if not SHA_RE.fullmatch(newest):
        raise PolicyReadError(f"{CONFIG_PATH} history at {sha} could not be read")
    return newest


def _demotion_changed(
    owner: str, name: str, shared: SharedPostMerge, identity: str
) -> bool:
    """Whether anything `read_demotion` reads may differ from the shared
    answer, in one REST call: an issue updated since the answer was computed
    (which precedes its demotion read), less `SINCE_CLOCK_MARGIN`, that a
    record filer opened, or that is a known record. Creating, editing,
    closing or reopening an issue updates it, so no new or changed record
    escapes. A full page or an unreadable
    one counts as changed."""
    since = (
        (shared.computed_at - SINCE_CLOCK_MARGIN)
        .astimezone(UTC)
        .strftime("%Y-%m-%dT%H:%M:%SZ")
    )
    status, issues = _get(
        f"repos/{owner}/{name}/issues?state=all&since={since}&per_page=100"
    )
    if status != 200 or not is_json_array(issues) or len(issues) >= 100:
        return True
    filers = {_login_key(DEMOTION_FILER), _login_key(identity)}
    for issue in map(json_object, issues):
        if "pull_request" in issue:
            continue
        author = _login_key(json_object(issue.get("user")).get("login"))
        if author in filers or issue.get("number") in shared.demotion.records:
            return True
    return False


def shared_refusal(
    repo: str,
    shared: SharedPostMerge,
    *,
    branch: str,
    base_sha: str,
    identity: str,
    self_logins: Collection[str],
    lane: bool,
    authority: str | None = None,
    now: datetime | None = None,
) -> str | None:
    """Why `shared` may not stand in for this pull request's own reads, or
    None: it must name the same identity, self logins and lane, give this
    base the floor its own read would (`merged_since_floor` with the shared
    demotion), be no older than `SHARED_MAX_AGE` (`SHARED_UNVERIFIED_MAX_AGE`
    while it passes with a merge unverified), have no demotion record filed
    or changed since (`_demotion_changed`), and judge every merge the
    post-merge check would judge now. The binding comes before the age, so a
    candidate bound elsewhere reports `SHARED_BINDING_REFUSALS` and does not
    replace the run's answer. The floor is compared under the shared answer's
    demotion, which may be out of date; that changes only the reason and the
    write-back, since any refusal reads afresh.

    The check judges `branch` from the floor, never the base, so the answer
    holds for any base with that floor. A newer default-branch head changes
    the answer only through a merge the check counts (`derive_auto_merge`);
    one that is not in the answer makes this pull request read its own.
    Later runs on already-counted merges are not re-read: an unverified one
    still refuses through `in_flight`, and a verified one counts no run
    created after it verified."""
    age = (now or datetime.now(UTC)) - shared.computed_at
    owner, name = _split_repo(repo)
    binding = (
        (_login_key(shared.identity) != _login_key(identity), "identity-differs"),
        (
            {_login_key(s) for s in shared.self_logins}
            != {_login_key(s) for s in self_logins},
            "self-logins-differ",
        ),
        (shared.lane_merges_only != lane, "lane-differs"),
    )
    refusal = next((text for refused, text in binding if refused), None)
    if refusal:
        return refusal
    try:
        # The same newest config commit is the same floor; any other base
        # walks its own config history to the floor it would read.
        if newest_config_commit(
            repo, base_sha
        ) != shared.config_sha and shared.floor != merged_since_floor(
            repo, base_sha, shared.demotion, authority
        ):
            return "floor-differs"
    except PolicyReadError:
        return "config-unreadable"
    checks = (
        (not timedelta(0) <= age <= SHARED_MAX_AGE, "stale"),
        # A refusing answer refuses whatever was verified since, so only a
        # passing one with a merge still unverified is read again.
        (
            age > SHARED_UNVERIFIED_MAX_AGE
            and shared.gate.refusal is None
            and any(
                json_object(m).get("verified") is not True
                for m in json_array(shared.gate.report.get("autoMerges"))
            ),
            "unverified-stale",
        ),
    )
    refusal = next((text for refused, text in checks if refused), None)
    if refusal:
        return refusal
    if not shared.demotion.active and _demotion_changed(owner, name, shared, identity):
        return "demotion-changed"
    status, payload = _get(f"repos/{owner}/{name}/commits/{quote(branch, safe='')}")
    head = payload.get("sha") if status == 200 and is_json_object(payload) else None
    if head == shared.main_sha:
        return None
    counted = {
        json_object(m).get("number")
        for m in json_array(shared.gate.report.get("autoMerges"))
    }
    try:
        merges = _merged_since(owner, name, branch, shared.floor)
        if merges is None:
            return "merged-history-truncated"
        for pr in merges:
            # Treating no actor as human counts a superset of the check's
            # merges, so no merge it would judge is missed.
            merge = derive_auto_merge(
                pr,
                lambda actor: False,
                identity,
                lane_merges_only=shared.lane_merges_only,
            )
            if isinstance(merge, AutoMerge) and merge.number not in counted:
                return f"new-merge:#{merge.number}"
    except PolicyReadError:
        return "merged-unreadable"
    return None


def assess(
    repo: str,
    number: int,
    *,
    acting_login: str | None = None,
    self_logins: Collection[str] = frozenset(),
    post_merge: Callable[[datetime, str], PostMergeGate] | None = None,
    promotion: Callable[[datetime | None], Promotion] | None = None,
    authority: str = LOCAL_BABYSIT,
    lane_kill_switch: str | None = None,
    lane_rung_cap: str | None = None,
    shared: SharedPostMerge | None = None,
    share: Callable[[SharedPostMerge], object] | None = None,
    human_gated: str | None = None,
) -> UnattendedPolicy:
    """The policy readers for one pull request, in the wiring order.

    `authority` is the caller's: the local babysit lane, or the pr-merge CI
    lane, which reads `lane_eligibility` in place of `eligibility` (and
    `dependabot_eligibility` for a Dependabot pull request, whose report-only
    is `merge.dependabot.mode` short of `enforce`), no
    promotion evidence (D16: report-only, then the owner's live flip), the
    kill switch from `lane_kill_switch` (`kill_switch`), the rung cap from
    `lane_rung_cap` (`rung_cap`), and only its own
    merges in flight. The
    config at the base must enable that authority (`enabled_authority`).

    Config at the pull request's base SHA (the default branch head's alone,
    reported as `baseConfigFallback`, when the base's cannot be parsed), then
    authority, identity, the
    credential chokepoint, the kill switch, a base that is the default
    branch, the config tightened by the default branch head's
    (`with_default_branch`; `merge.max-in-flight` the head's alone,
    `_run_max_in_flight`) and its authority, and the post-merge check: any
    refusal there stops the reads and leaves the path not `enabled`, so no
    later read can lead to a write. Then the rung (demotion and cap), the
    in-flight rule, the promotion evidence and the pull request's
    eligibility and class: each refuses a merge, and all are reported, but
    an in-flight refusal of a pull request not in the merge queue stops the
    reads there.

    `post_merge(floor, identity)` runs the post-merge check from the floor
    (`merged_since_floor`) and must be given: without it the path refuses.
    `shared`, the run's one answer for every candidate, replaces the
    demotion, floor and post-merge reads when `shared_refusal` passes it.
    `share(answer)` receives those reads, when made and readable, bound as a
    `SharedPostMerge` for the next candidate, unless `shared` was refused as
    bound to another candidate (`SHARED_BINDING_REFUSALS`); it must not raise.
    `human_gated`, the tracker's resolved human-gated role label, holds an
    adopted pull request in the lane (`adoption_refusal`); None adopts none.
    `promotion(window_start)` reads the promotion evidence with the newest
    demotion record's creation as the window restart; without it nothing is
    promoted. `self_logins` names only lane or bot self identities (see
    `is_human`). Raises `PolicyReadError` when the pull request or either
    pipeline config cannot be read, because the agent identity is then
    unknown. A default branch head config that cannot be parsed, or names
    another identity, is a stop (`StopReadError`).
    """
    pr = pull_request(repo, number)
    base_ref = str(json_object(pr.get("base")).get("ref"))
    base_sha = str(json_object(pr.get("base")).get("sha"))
    config = read_config_at(repo, base_sha)
    fallback = None
    if config.error == "config-parse-error":
        # A base older than the reader's grammar answers to the default branch
        # head's config alone, never the pull request head's; a head config
        # that cannot be read or parsed raises, as the base's did.
        config = _default_branch_config(repo)
        fallback = (
            f"{CONFIG_PATH} at {base_sha}: config-parse-error; "
            f"read at the default branch head {config.base_sha}"
        )
    if config.error:
        raise PolicyReadError(f"{CONFIG_PATH} at {base_sha}: {config.error}")
    # The commit whose config history sets the post-merge floor: the base, or
    # the default branch head the config fell back to.
    history_sha = config.base_sha
    identity = config.agent_identity
    lane = authority == PR_MERGE
    # A Dependabot pull request in the lane answers to its own switch.
    dependabot_pr = lane and is_dependabot_pull_request(pr)
    report_only = (
        config.dependabot_mode != "enforce" if dependabot_pr else config.report_only
    )
    details: dict[str, Any] = {"baseSha": base_sha, "reportOnly": report_only}
    if fallback:
        details["baseConfigFallback"] = fallback
    inputs: dict[str, Any] = {
        "pr": pr,
        "config": config,
        "branch": base_ref,
        "authority": authority,
    }
    stopped = UnattendedPolicy(
        AUTHORITY_UNCONFIGURED, identity, details, enabled=False, inputs=inputs
    )
    if enabled_authority(config) != authority:
        return stopped
    # The acting login and the credential chokepoint depend on the
    # credentials alone: a gate process of the same run with the same ones
    # reuses a login read and a pass (`run_cache.credentials`).
    held = run_cache.credentials()
    if acting_login is None:
        acting_login = run_cache.get("acting-login", held, None)
        if not isinstance(acting_login, str):
            try:
                acting_login = read_acting_login()
                run_cache.put("acting-login", held, acting_login)
            except PolicyReadError:
                acting_login = None
    resolved = resolve_identity(identity, acting_login, self_logins)
    details["identity"] = resolved.login
    if resolved.reason or resolved.login is None:
        return replace(stopped, reason=resolved.reason)
    passed = f"{held}|{resolved.login.casefold()}"
    credentials = (
        None
        if run_cache.get("identity-only", passed, None) is True
        else credential_refusal(resolved.login)
    )
    if credentials is None:
        run_cache.put("identity-only", passed, True)
    details["credentials"] = credentials or "identity-only"
    if credentials:
        return replace(stopped, reason=f"credentials:{credentials}")
    # From here the session holds only the identity: a refusal below may still
    # dequeue the identity's own entries (`inputs["identity"]`).
    inputs["identity"] = resolved.login
    inputs["lane_kill_switch"] = lane_kill_switch
    kill = kill_switch(repo, authority=authority, lane_value=lane_kill_switch)
    details["killSwitch"] = {"proceed": kill.proceed, "reason": kill.reason}
    if not kill.proceed:
        return replace(stopped, reason=f"kill-switch:{kill.reason}")
    # The post-merge check, its dispatch and the scheduled full run judge the
    # default branch only, so a merge into any other base would go unjudged.
    # An unreadable default branch is a stop (the identity's entries leave).
    try:
        default = _default_branch(repo, shared=True)
    except PolicyReadError:
        return replace(stopped, reason=DEFAULT_BRANCH_UNREADABLE)
    if base_ref != default:
        # Not a stop (other bases keep their entries), but this pull request's
        # own entry, queued on that base, leaves.
        inputs["own_refusal"] = f"base-not-default:{base_ref}"
        return replace(stopped, reason=inputs["own_refusal"])
    # The base's config, tightened by the default branch head's: from here
    # every setting is the stricter of the two.
    # A head config that cannot be parsed, or names another identity, stops.
    try:
        config = inputs["config"] = with_default_branch(repo, config, default)
    except StopReadError as exc:
        details["defaultBranchConfig"] = str(exc)
        return replace(stopped, reason=exc.reason)
    report_only = (
        config.dependabot_mode != "enforce" if dependabot_pr else config.report_only
    )
    details["reportOnly"] = report_only
    if enabled_authority(config) != authority:
        return replace(stopped, reason=AUTHORITY_DIFFERS)

    permission = permission_reader(repo)
    readers = {
        "agent_identity": identity,
        "self_logins": self_logins,
        "permission": permission,
    }
    inputs.update(permission=permission, self_logins=self_logins)
    # The run's shared answer stands in for the demotion, floor and post-merge
    # reads when it is bound to this run; otherwise they are read here.
    reuse = None
    if shared is not None:
        unusable = shared_refusal(
            repo,
            shared,
            branch=default,
            base_sha=history_sha,
            identity=resolved.login,
            self_logins=self_logins,
            lane=lane,
            authority=authority,
        )
        details["postMergeShared"] = f"unused:{unusable}" if unusable else "used"
        reuse = None if unusable else shared
        if unusable in SHARED_BINDING_REFUSALS:
            share = None
    # Bound before the reads it covers: a merge after this head read moves
    # the head, and a record changed after `computed_at` is re-read.
    computed_at = datetime.now(UTC)
    owner, name = _split_repo(repo)
    head = None
    if share is not None and reuse is None:
        status, payload = _get(
            f"repos/{owner}/{name}/commits/{quote(default, safe='')}"
        )
        head = payload.get("sha") if status == 200 and is_json_object(payload) else None
    demotion = reuse.demotion if reuse else read_demotion(repo, **readers)
    details["demotion"] = {
        "active": demotion.active,
        "reason": demotion.reason,
        "records": list(demotion.records),
    }
    if reuse:
        floor = reuse.floor
    else:
        try:
            floor = merged_since_floor(repo, history_sha, demotion, authority)
        except PolicyReadError as exc:
            return replace(stopped, reason=f"post-merge:floor-unreadable: {exc}")
    details["mergedSince"] = floor.isoformat()
    gate = (
        reuse.gate
        if reuse
        else post_merge(floor, resolved.login)
        if post_merge is not None
        else PostMergeGate("unchecked", {}, None)
    )
    details["postMerge"] = dict(gate.report)
    if (
        share is not None
        and isinstance(head, str)
        and SHA_RE.fullmatch(head)
        and gate.report.get("readable") is True
    ):
        try:
            config_sha = newest_config_commit(repo, history_sha)
        except PolicyReadError:
            config_sha = None
        if config_sha:
            share(
                SharedPostMerge(
                    main_sha=head,
                    config_sha=config_sha,
                    identity=resolved.login,
                    self_logins=frozenset(self_logins),
                    lane_merges_only=lane,
                    computed_at=computed_at,
                    demotion=demotion,
                    floor=floor,
                    gate=gate,
                )
            )
    if gate.refusal:
        return replace(stopped, reason=f"post-merge:{gate.refusal}")

    cap = rung_cap(repo, authority=authority, lane_value=lane_rung_cap)
    rung = effective_rung(
        config_rung=config.rung,
        loop_merge=config.loop_merge,
        cap=cap.value,
        demoted=demotion.active,
    )
    # Read at the default branch head alone; the post-enqueue room check
    # reads it again, uncached.
    flight_cap, cap_source = _run_max_in_flight(
        repo, default, head if isinstance(head, str) else None, config
    )
    flight = in_flight(
        repo,
        **readers,
        verified=gate.verified,
        branch=base_ref,
        merged_since=floor,
        lane_merges_only=lane,
        max_in_flight=flight_cap,
    )
    details.update(
        rung=rung.rung,
        rungInputs=dict(rung.inputs),
        rungCap={"value": cap.value, "reason": cap.reason},
        inFlight={
            "clear": flight.clear,
            "reason": flight.reason,
            "cap": flight_cap,
            "capSource": cap_source,
        },
    )
    inputs.update(rung=rung.rung, flight=flight, flight_cap=flight_cap)
    # Past an on rung, the in-flight refusal outranks every read below. With
    # no queue entry of its own, nothing below writes for this pull request
    # either (its risk comment and verifier escalation wait for a run below
    # the merge.max-in-flight cap), so it skips them. A Dependabot pull request is read in
    # full: its class decides the gate's dependency-manager hold.
    if (
        rung.rung != "off"
        and not flight.clear
        and not dependabot_pr
        and flight.queued is not None
        and number not in flight.queued
    ):
        return UnattendedPolicy(
            f"in-flight:{flight.reason}",
            identity,
            details,
            enabled=True,
            promoted=True if lane else None,
            inputs=inputs,
        )
    if dependabot_pr:
        promo = Promotion(None, "not-read-in-pr-merge-lane")
        eligible = (
            dependabot_eligibility(
                repo,
                number,
                pr=pr,
                agent_identity=identity,
                hold_majors=config.dependabot_majors == "hold",
            )
            if config.dependabot_mode != "off"
            else Eligibility(False, "dependabot-merge-off")
        )
        promoted = True
        details["dependabot"] = {
            "mode": config.dependabot_mode,
            "majors": config.dependabot_majors,
            **(eligible.dependabot.report() if eligible.dependabot else {}),
        }
    elif lane:
        promo = Promotion(None, "not-read-in-pr-merge-lane")
        # The trusted list at the default branch head, as its config is read
        # (owner decision Q22): a stacked pull request's base is its author's.
        trusted: tuple[tuple[int, ...], tuple[int, ...]] = ((), ())
        if config.adoption_idle_hours is not None:
            try:
                head = _default_branch_config(repo, default).base_sha
                # Never adopted: the lanes App (its own path) and Dependabot
                # (its tier and review-dependency), by login on the list.
                skip = {_login_key(inputs["identity"]), "dependabot"}
                trusted = trusted_actors(repo, head, exclude=skip)
            except (PolicyReadError, StopReadError):
                pass
        eligible = lane_eligibility(
            repo,
            number,
            pr=pr,
            denied_paths=config.denied_paths,
            adoption_idle_hours=config.adoption_idle_hours,
            adoption_owner_ids=trusted[0],
            spec_from_body_ids=(*trusted[1], *config.spec_from_body_apps),
            human_gated=human_gated,
            queued_at_head=lambda: lane_queued_at_head(
                repo,
                number,
                base_ref,
                inputs["identity"],
                str(json_object(pr.get("head")).get("sha") or ""),
            ),
            **readers,
        )
        promoted = True
    else:
        promo = (
            promotion(demotion.newest_created)
            if promotion is not None
            else Promotion(None, "promotion-unread")
        )
        eligible = eligibility(repo, number, **readers)
        promoted = promo.promoted(eligible.work_class)
    details.update(
        promotion={
            "cells": dict(promo.cells) if promo.cells is not None else None,
            "reason": promo.reason,
        },
        eligibility={
            "eligible": eligible.eligible,
            "reason": eligible.reason,
            "workClass": eligible.work_class,
            "adoption": eligible.adoption,
        },
    )
    inputs["eligibility"] = eligible
    # What refuses this pull request itself, whatever else does: its own
    # queued entry leaves the queue on it.
    own = (
        # No class is read in the lane, so the verifier verdict is its merge
        # criterion: a lane that does not require one would merge on none.
        (
            lane
            and not dependabot_pr
            and config.rung != "off"
            and not config.require_verifier_verdict,
            "verifier-verdict-not-required",
        ),
        (not eligible.eligible, f"ineligible:{eligible.reason}"),
        # The rung is a work-class ceiling: C4 and C5 never merge unattended.
        (
            CLASS_RANK.get(eligible.work_class or "", 99) > RUNG_RANK[rung.rung],
            f"class-above-rung:{eligible.work_class}>{rung.rung}",
        ),
        (not promoted, f"promotion-unqualified:{eligible.work_class}"),
    )
    inputs["own_refusal"] = next((text for refused, text in own if refused), None)
    refusals = (
        (rung.rung == "off", f"rung-off:{rung.limited_by}"),
        (not flight.clear, f"in-flight:{flight.reason}"),
        (
            promo.cells is None and not lane,
            f"promotion-unqualified:{promo.reason}",
        ),
        *own,
    )
    reason = next((text for refused, text in refusals if refused), None)
    return UnattendedPolicy(
        reason, identity, details, enabled=True, promoted=promoted, inputs=inputs
    )
