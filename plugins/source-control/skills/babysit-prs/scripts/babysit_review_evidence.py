"""Per-lane AI review evidence, bound to the lane's workflow runs and the
pinned head SHA.

A green review check alone proves nothing: a lane has concluded success
with no review done. `bind()` counts a lane as reviewed only when its newest
workflow run on the pinned head succeeded on an allowed attempt, the lane
job left exactly one completion record for that head, an incremental or
no-change record leads back to a whole review, and the lane's
reviewed-head marker names the head. Anything doubtful is unbound; the
function never raises.

Inputs are raw GitHub API shapes the caller collects for one pull request:

- `runs`: the caller workflow runs of both lanes on this pull request (the
  `actions/workflows/{file}/runs` listing), each with an `attempts` list
  (`actions/runs/{id}/attempts/{n}`), each attempt with its `jobs`
  (`.../attempts/{n}/jobs`), each job with its check run's `annotations`
  (`check-runs/{job id}/annotations`). Each run's `head_commit.tree_id`
  names its head's tree, which finding closure keys on (`_open_findings`).
- `comments`: the pull request's issue comments (REST), each by
  github-actions[bot] or the Claude App carrying an `edit` record: GraphQL's
  `lastEditedAt` and `editor{__typename login}` for it (`_edited_by_another`).
- `threads`: `babysit_gh.fetch_review_threads(..., include_resolved=True)`,
  whose comments carry `lastEditedAt` and `editor`, or None when they could
  not be read.
- `is_human`: the merge policy's test of one GraphQL actor (or None).
- `head_file`: reads a file at the pinned head, given its path and the
  commit a thread was raised on: its text, None when that file was deleted
  since, raising when neither is proven.

The record format is the lane producer's (ci-workflows
`.github/workflows/pr-review-cli.yml`, and `pr-review.yml` for older runs).
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from babysit_risk import FLOOR, LaneEvidence, glob_match

# Lane id -> (caller workflow path, lane job name suffix). Fixed in code: a
# weaker table could only come from a file a pull request can edit.
LANES: dict[str, tuple[str, str]] = {
    "claude-review": (".github/workflows/pr-review-hosted.yml", "claude-review-status"),
    "claude-security-review": (
        ".github/workflows/pr-review-security-hosted.yml",
        "security-review",
    ),
}

# What a pull request's own checkout can feed or forge for its own review:
# its workflows (a pull_request event runs the head's copy of the callers, and
# a workflow it adds or edits whose token can write posts as
# github-actions[bot], the reviewed-head marker's author, so it could forge a
# marker or a `critical-findings:` count; `readonly_workflow` clears the
# workflows that cannot),
# Claude Code project config and instruction files at any depth, the criteria the lane skills read from the checkout (REVIEW.md,
# the standards index, the instruction exception register, the
# untrusted-content contract), the lane's input directory .claude-lane/ (the
# code lane falls back to a context file there), and .gitattributes, which can
# hide a hunk from the lane's `git diff`. The callers run every local action
# from a checkout of main and the reusable runs its composites from its own
# repository, so the rest of .github/ feeds no review. A pull request that
# changes any listed path may have changed its own review, so its records
# prove no review by the default branch's lane. plugins/review/ is not listed:
# the reusable pr-review-cli.yml stages the review plugin from
# claude-code-plugins' default-branch tip, never the head, and
# scripts/ci-review-plugin-source.test.sh fails if a caller stops calling it
# pinned to a SHA or passes it a plugin path.
LANE_SOURCE_PREFIXES = (
    ".github/workflows/",
    "docs/standards/",
    "docs/contracts/instruction-exception-register/",
    "docs/contracts/untrusted-content/",
    ".claude-lane/",
)
LANE_SOURCE_SEGMENT = ".claude"
LANE_SOURCE_NAMES = (
    ".mcp.json",
    "CLAUDE.md",
    "CLAUDE.local.md",
    "AGENTS.md",
    "REVIEW.md",
    ".gitattributes",
)

# A changed workflow file `readonly_workflow` may clear: a top-level `.yml`.
# A `.yaml` stays a lane source, since its stem could repeat a `.yml`'s name
# (the name rule below).
WORKFLOW_PATH_RE = re.compile(r"^\.github/workflows/([a-z0-9][a-z0-9_-]*)\.yml$")
# The review callers stay lane sources whatever their content: the head's copy
# runs the review itself.
REVIEW_CALLERS = frozenset(path for path, _ in LANES.values())
WORKFLOW_KEYS = frozenset(
    {"name", "run-name", "on", "permissions", "env", "defaults", "concurrency", "jobs"}
)
JOB_KEYS = frozenset(
    {
        "name",
        "permissions",
        "needs",
        "if",
        "runs-on",
        "snapshot",
        "environment",
        "concurrency",
        "outputs",
        "env",
        "defaults",
        "steps",
        "timeout-minutes",
        "strategy",
        "continue-on-error",
        "container",
        "services",
        "uses",
        "with",
    }
)
# Triggers that run a privileged default-branch copy on another run's behalf,
# and `workflow_call`: a privileged caller run on the branch would act on the
# head copy's outputs with its own write token.
DENIED_TRIGGERS = frozenset({"pull_request_target", "workflow_run", "workflow_call"})
# Any secret can carry a credential (a GitHub App private key, a PAT) whose
# token ignores `permissions:`; GITHUB_TOKEN is the job's own token.
SECRETS_RE = re.compile(r"\bsecrets\b", re.IGNORECASE)
GITHUB_TOKEN_SECRET_RE = re.compile(r"\bsecrets\.github_token\b", re.IGNORECASE)
# Raw-text backstops, so a parser difference between PyYAML and GitHub's
# cannot hide a write grant or a denied trigger.
WORKFLOW_DENIED_TEXT_RE = re.compile(
    r"id-token|pull_request_target|workflow_run|workflow_call"
    r"|:\s*['\"]?write(?:-all)?['\"]?\s*(?:[,}\]#]|$)",
    re.IGNORECASE | re.MULTILINE,
)

RECORD_TITLE = "claude-lane-review-complete"
_SHA = r"[0-9a-f]{40}"
_COUNT = r"\d{1,6}"
RECORD_RE = re.compile(
    rf"^{RECORD_TITLE} lane=(?P<lane>[\w-]+) sha=(?P<sha>{_SHA}) "
    rf"(?:findings=(?P<n>{_COUNT}) inline=(?P<k>{_COUNT}) "
    rf"scope=(?:(?P<whole>whole)|incremental since=(?P<since>{_SHA}))"
    rf"|skip=no-change through=(?P<through>{_SHA})"
    rf"|skip=(?P<skip>[\w-]+))"
    # The subscription leg's review (ci-workflows pr-review-cli.yml).
    rf"(?: account=fallback)?$"
)
SHA_RE = re.compile(rf"^{_SHA}$")
HUNK_HEADER_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
# The reconciler re-runs any failed lane run once; attempt 2 binds only when
# attempt 1 failed on a usage limit.
RATE_LIMIT_CLASS_RE = re.compile(r"\bclass=rate-limit\b")
# Or on a rejected Claude credential: this lane's publish-review failure line
# (ci-workflows publish.cjs `fail`) with class `auth`. Like a usage limit,
# attempt 1 then left no verdict, so a re-run cannot trade one review for
# another. It binds a re-run but does not start one (GATE_RERUN_CLASSES), since a
# re-run before the secret is fixed would spend the one allowed attempt. A
# spent key needs no entry: publish.cjs reports it as `rate-limit`.
AUTH_FAILURE_RE = re.compile(r"(?P<lane>[\w-]+): failure-class=auth: ")
# Or when the review's own post hit GitHub's API rate limit: the message opens
# with this lane's publish-review failure line (ci-workflows publish.cjs `fail`)
# whose detail, the request error's message, opens with GitHub's primary or
# secondary rate-limit text
# (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
# Any other publish failure stays refused, so a re-run cannot hide one.
PUBLISH_RATE_LIMIT_RE = re.compile(
    r"(?P<lane>[\w-]+): failure-class=publish-failed: [^(\n]*"
    r"\((?:API rate limit exceeded|You have exceeded a secondary rate limit)\b"
)
# Or when the runner isolation or the Claude Code CLI install failed before the
# review ran: this lane's publish-review failure line (ci-workflows publish.cjs
# `fail`) with class `install-failed`, which a failed `Isolate the runner` step
# reports from ci-workflows v0.65.14 (ci-workflows#893). Attempt 1 then left no
# verdict, often on a slow package mirror, so a re-run trades no review away.
INSTALL_FAILED = "install-failed"
INSTALL_FAILURE_RE = re.compile(
    rf"(?P<lane>[\w-]+): failure-class={re.escape(INSTALL_FAILED)}: "
)
# Or when a kill switch stopped attempt 1 before the review started: the
# caller's `kill-switch` job succeeded and its `Report the kill switch` step
# wrote this lane's notice, whose `if` is the negation of the `proceed` output
# the lane job needs, and attempt 1 has no lane job. Attempt 1 then left no
# verdict. The step's text comes from the switch values only, and a head that
# edits a caller to forge it unbinds through `lane_source`. Like `auth`, it
# binds a re-run but does not start one: the gate cannot read the switch.
# Or when an outage ended attempt 1 without a result: a run GitHub concluded
# cancelled, timed out or never started (the lost-run reconciler's `LOST` in
# .github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs). Attempt 1
# then left no verdict unless its lane already posted on the head
# (`_lost_unposted`), which leaves the run to a person.
LOST = "lost"
LOST_CONCLUSIONS = frozenset({"cancelled", "timed_out", "startup_failure"})
KILL_SWITCH_JOB = "kill-switch"
KILL_SWITCH_NOTICE_RE = {
    "claude-review": re.compile(r"a kill switch stops this review \("),
    "claude-security-review": re.compile(
        r"a kill switch stops this security review \("
    ),
}
MARKER_AUTHOR = "github-actions[bot]"
MARKER_RE = re.compile(
    rf"^<!-- claude-lane-reviewed-head lane=([\w-]+) sha=({_SHA}) -->$"
)
CLAUDE_APP_LOGINS = frozenset({"claude", "claude[bot]"})
LANE_TAG_RE = re.compile(r"^\s*`?claude-lane: ([\w-]+)`?\s*$", re.MULTILINE)
# ci-workflows pr-review-cli.yml posts as github-actions[bot] (REST login;
# GraphQL drops the suffix). Such a comment is the lane's only when its last
# non-blank line is that lane's footer.
ACTIONS_LOGINS = frozenset({"github-actions", "github-actions[bot]"})
# Every author a lane comment can have; the caller attaches each one's edit
# record (babysit_merge._attach_edits).
LANE_AUTHORS = ACTIONS_LOGINS | CLAUDE_APP_LOGINS


def _footer_lane(body: str) -> str | None:
    """The lane a body's last non-blank line names as its `claude-lane:`
    footer, None when that line is no footer."""
    lines = [line for line in body.splitlines() if line.strip()]
    tag = LANE_TAG_RE.fullmatch(lines[-1]) if lines else None
    return tag[1] if tag else None


def _lane_comment(lane: str, login: object, body: str) -> bool:
    """A Claude App comment untagged or tagged for `lane`, or a
    github-actions[bot] comment whose footer names `lane`."""
    if login in CLAUDE_APP_LOGINS:
        tag = LANE_TAG_RE.search(body)
        return tag is None or tag[1] == lane
    return login in ACTIONS_LOGINS and _footer_lane(body) == lane


# The lane whose findings hold the merge only at its top tier, CRITICAL
# (/review:security-review, "Reporting"): each inline
# comment carries one `severity:` line, and the summary one
# `critical-findings:` line counting its CRITICAL findings with no inline
# comment. A comment or summary without exactly one readable line counts every
# finding it holds as CRITICAL.
SEVERITY_LANE = "claude-security-review"
SEVERITY_RE = re.compile(
    r"^\s*`?severity: (CRITICAL|IMPORTANT|SUGGESTION)`?\s*$", re.MULTILINE
)
SUMMARY_CRITICAL_RE = re.compile(
    r"^\s*`?critical-findings: (\d{1,6})`?\s*$", re.MULTILINE
)
MAX_CHAIN = 100


@dataclass(frozen=True)
class _Record:
    sha: str
    findings: int | None = None
    inline: int | None = None
    whole: bool = False
    since: str | None = None  # incremental review base
    through: str | None = None  # no-change skip target
    skip: str | None = None  # any other skip
    completed: datetime | None = None  # when the lane job that left it completed


class Unbound(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def bind(
    head_sha: str,
    runs: Sequence[Mapping[str, Any]],
    comments: Sequence[Mapping[str, Any]],
    threads: Sequence[Mapping[str, Any]] | None,
    *,
    is_human: Callable[[Any], bool],
    changed_paths: Sequence[str] | None,
    base_changed: bool = False,
    head_file: Callable[[str, str], str | None] | None = None,
    base_sha: str | None = None,
) -> tuple[LaneEvidence, ...]:
    """Evidence for every lane in `LANES`, in that order.

    Caller contract (`babysit_gh.collect_lane_runs` meets it): list each lane
    workflow's runs by branch, with no `head_sha` filter, and keep those whose
    `pull_requests` name this pull request, so the earlier whole reviews an
    incremental chain leads back to are included. Read each run's attempt
    numbers from a fresh `GET actions/runs/{id}` taken after the listing, not
    from the listing's `run_attempt`, so a re-run that starts in between is
    seen. `is_human` takes one actor and must return False for the agent
    identity, the pull request's author and its head pushers. `base_changed`
    is True when the pull request was ever retargeted: the reviews read a
    diff against another base, so no lane binds. `changed_paths` holds every
    path the pull request changes (both sides of a rename), or None when the
    list is unread or incomplete: no lane binds then, nor when one is a lane
    source (`lane_source`) that `readonly_workflow` does not clear through
    `head_file`, with `base_sha` (the pull request's base commit) proving a
    deletion.

    A lane binds only when every head its reviewed-head markers name still
    has a listed run: a deleted or expired run would drop its findings from
    the count, so it unbinds the lane rather than lowering the count.
    """
    try:
        if not isinstance(head_sha, str) or not SHA_RE.match(head_sha):
            raise Unbound("bad-head")
        if base_changed is not False:
            raise Unbound("base-retargeted")
        if not isinstance(changed_paths, list | tuple):
            raise Unbound("changed-files-unread")
        sources = [path for path in changed_paths if lane_source(path)]
        # Paths first, so no file is read when one source can never clear.
        if not all(_readonly_candidate(path) for path in sources) or not all(
            readonly_workflow(path, head_file, base_sha) for path in sources
        ):
            raise Unbound("lane-source-changed")
        # Thread ids already standing for a recorded finding in some lane.
        # LANES order matters: claude-review claims first, so a doubtful
        # untagged thread leaves the count on the security lane.
        claimed: set[str] = set()
        return tuple(
            _bind_lane(
                lane, head_sha, runs, comments, threads, is_human, claimed, head_file
            )
            for lane in LANES
        )
    except Exception as exc:  # noqa: BLE001 - any doubt is unbound
        reason = exc.reason if isinstance(exc, Unbound) else "evidence-error"
        return tuple(
            _unbound(
                lane, reason, head_sha, runs, comments, threads, is_human, head_file
            )
            for lane in LANES
        )


def lane_source(path: Any) -> bool:
    """Whether a changed path is one the pull request's checkout feeds its
    own review; a path that is not a string counts as one."""
    if not isinstance(path, str):
        return True
    # A bare directory path (a symlink in its place) counts as the directory.
    parts = path.split("/")
    return (
        f"{path}/".startswith(LANE_SOURCE_PREFIXES)
        or LANE_SOURCE_SEGMENT in parts
        or parts[-1] in LANE_SOURCE_NAMES
    )


def _readonly_candidate(path: Any) -> bool:
    """A lane source `readonly_workflow` may clear by its content: a workflow
    that is neither a review caller nor on the merge floor
    (`babysit_risk.FLOOR`), whose text no rewrite may clear."""
    return (
        isinstance(path, str)
        and bool(WORKFLOW_PATH_RE.match(path))
        and path not in REVIEW_CALLERS
        and not any(glob_match(glob, path) for glob in FLOOR)
    )


def readonly_workflow(
    path: str,
    head_file: Callable[[str, str], str | None] | None,
    base_sha: str | None,
) -> bool:
    """Whether a changed workflow file cannot post as github-actions[bot] with
    write access, nor reach a credential that could: a head copy that passes
    `_readonly_workflow_text`. A deleted workflow is not cleared, since what it
    enforced goes with it; nor is a review caller, a floor workflow, any other
    lane source, or any doubt (no reader, no base, a read that fails)."""
    if not _readonly_candidate(path) or head_file is None:
        return False
    if not isinstance(base_sha, str) or not SHA_RE.match(base_sha):
        return False
    try:
        text = head_file(path, base_sha)
    except Exception:  # noqa: BLE001 - unread is not cleared
        return False
    if text is None:
        return False
    stem = WORKFLOW_PATH_RE.match(path)[1]  # type: ignore[index]
    return isinstance(text, str) and _readonly_workflow_text(text, stem)


def _readonly_workflow_text(text: str, stem: str) -> bool:
    """Whether workflow text, read as GitHub would, grants its token no write
    scope and reaches no secret:

    - one plain YAML document: no anchor, alias, explicit tag, directive,
      `<<` merge key or repeated key (PyYAML and GitHub's parser could read
      those differently), and only known top-level and job keys;
    - `name:` equal to the file stem, so no `workflow_run` listener that
      names another workflow fires on it (its `workflows` filter matches
      names, and an omitted name is the file path);
    - no `pull_request_target`, `workflow_run` or `workflow_call` trigger;
    - every job's token set by a `permissions:` of its own or the top level,
      each scope `read` or `none` (`read-all` or `{}` too): a scope set
      leaves every other `none`, while a job with neither inherits the
      repository default, which the pull request cannot show;
    - no `secrets` reference but `secrets.GITHUB_TOKEN`, the job's own
      token, which also rules out `secrets: inherit` on a reusable call (a
      called workflow's permissions can only be kept or reduced);
    - none of `WORKFLOW_DENIED_TEXT_RE` anywhere in the raw text.

    Without PyYAML nothing clears."""
    try:
        import yaml
    except ImportError:
        return False
    if WORKFLOW_DENIED_TEXT_RE.search(text) or _mentions_secrets(text):
        return False
    try:
        for event in yaml.parse(text, Loader=yaml.SafeLoader):
            if isinstance(event, yaml.AliasEvent) or getattr(event, "anchor", None):
                return False
            if getattr(event, "tag", None) is not None:
                return False
            if isinstance(event, yaml.DocumentStartEvent) and (
                event.version or event.tags
            ):
                return False
        root = yaml.compose(text, Loader=yaml.SafeLoader)
        top = _yaml_mapping(root, yaml)
    except Exception:  # noqa: BLE001 - unreadable is not cleared
        return False
    if top is None or not set(top) <= WORKFLOW_KEYS:
        return False
    name, on, jobs = top.get("name"), top.get("on"), top.get("jobs")
    if not isinstance(name, yaml.ScalarNode) or name.value != stem:
        return False
    triggers = _yaml_names(on, yaml)
    if not triggers or {t.casefold() for t in triggers} & DENIED_TRIGGERS:
        return False
    default = top.get("permissions")
    if default is not None and not _readonly_permissions(default, yaml):
        return False
    job_map = _yaml_mapping(jobs, yaml)
    if not job_map:
        return False
    for job in job_map.values():
        keys = _yaml_mapping(job, yaml)
        if keys is None or not set(keys) <= JOB_KEYS:
            return False
        own = keys.get("permissions")
        if own is None and default is None:
            return False
        if own is not None and not _readonly_permissions(own, yaml):
            return False
    return True


def _mentions_secrets(text: str) -> bool:
    return bool(SECRETS_RE.search(GITHUB_TOKEN_SECRET_RE.sub("", text)))


def _yaml_mapping(node: Any, yaml: Any) -> dict[str, Any] | None:
    """A mapping node's values by key, after checking every node under it:
    each mapping key a plain string scalar, not `<<`, and unique even
    ignoring case; each decoded scalar free of `secrets`. None when `node`
    is not a mapping; raises on a check that fails."""
    if not isinstance(node, yaml.MappingNode):
        return None
    _check_yaml_tree(node, yaml)
    return {key.value: value for key, value in node.value}


def _check_yaml_tree(node: Any, yaml: Any) -> None:
    if isinstance(node, yaml.ScalarNode):
        # A double-quoted escape can spell `secrets` the raw text hides.
        if _mentions_secrets(str(node.value)):
            raise ValueError("secrets")
        return
    if isinstance(node, yaml.SequenceNode):
        for item in node.value:
            _check_yaml_tree(item, yaml)
        return
    if not isinstance(node, yaml.MappingNode):
        raise ValueError("node")
    seen: set[str] = set()
    for key, value in node.value:
        # GitHub reads every key as a string: PyYAML's YAML 1.1 bool tag on
        # a plain `on` does not matter, and the parse refused explicit tags.
        if not isinstance(key, yaml.ScalarNode):
            raise ValueError("key")
        folded = str(key.value).casefold()
        if key.value == "<<" or folded in seen:
            raise ValueError("key")
        seen.add(folded)
        _check_yaml_tree(key, yaml)
        _check_yaml_tree(value, yaml)


def _yaml_names(node: Any, yaml: Any) -> list[str]:
    """The event names an `on:` node lists, or [] when its shape is not one
    GitHub reads (a name, a list of names, or a mapping keyed by name)."""
    if isinstance(node, yaml.ScalarNode):
        return [str(node.value)] if node.value else []
    if isinstance(node, yaml.SequenceNode):
        items = node.value
        if all(isinstance(item, yaml.ScalarNode) for item in items):
            return [str(item.value) for item in items]
        return []
    if isinstance(node, yaml.MappingNode):
        return [str(key.value) for key, _ in node.value]
    return []


def _readonly_permissions(node: Any, yaml: Any) -> bool:
    """`read-all`, or a mapping whose every scope is `read` or `none` and
    whose `id-token`, which has no read level, is `none`."""
    if isinstance(node, yaml.ScalarNode):
        return node.value == "read-all"
    if not isinstance(node, yaml.MappingNode):
        return False
    for key, value in node.value:
        if not isinstance(value, yaml.ScalarNode) or value.value not in (
            "read",
            "none",
        ):
            return False
        if str(key.value).casefold() == "id-token" and value.value != "none":
            return False
    return True


def _bind_lane(
    lane: str,
    head: str,
    runs: Sequence[Mapping[str, Any]],
    comments: Sequence[Mapping[str, Any]],
    threads: Sequence[Mapping[str, Any]] | None,
    is_human: Callable[[Any], bool],
    claimed: set[str],
    head_file: Callable[[str, str], str | None] | None,
) -> LaneEvidence:
    try:
        lane_runs = _lane_runs(lane, runs)
        reviewed, chain = _resolve(lane, head, lane_runs, _poster(comments, threads))
        marker = _require_marker(lane, head, comments)
        _require_marked_runs(lane, lane_runs, comments)
        count, clears, critical = _open_findings(
            lane,
            lane_runs,
            threads,
            is_human,
            claimed,
            reviewed,
            chain,
            head_file,
            [(None, marker), *_summary_comments(lane, comments)],
        )
    except Unbound as exc:
        return _unbound(
            lane, exc.reason, head, runs, comments, threads, is_human, head_file
        )
    blocking = critical if lane == SEVERITY_LANE else None
    return LaneEvidence(lane, True, None, count, clears, blocking)


def _unbound(
    lane: str,
    reason: str,
    head: Any,
    runs: Any,
    comments: Any,
    threads: Any,
    is_human: Callable[[Any], bool],
    head_file: Callable[[str, str], str | None] | None,
) -> LaneEvidence:
    """The unbound evidence for `lane`, carrying for the security lane the
    blocking findings its last bound review on this pull request still
    leaves open (`_carried_blocking`), so an unbind never hides one."""
    carried = (
        _carried_blocking(head, runs, comments, threads, is_human, head_file)
        if lane == SEVERITY_LANE
        else None
    )
    return LaneEvidence(lane, False, reason, None, False, carried or None)


def _carried_blocking(
    head: Any,
    runs: Any,
    comments: Any,
    threads: Any,
    is_human: Callable[[Any], bool],
    head_file: Callable[[str, str], str | None] | None,
) -> int | None:
    """The security lane's blocking findings at the newest head of this pull
    request its evidence binds at, the pinned head first, judged as at that
    head against the threads and comments read now; None when none binds.
    It reads only what the caller already read."""
    try:
        lane_runs = _lane_runs(SEVERITY_LANE, runs)
        ordered = sorted(
            lane_runs,
            key=lambda item: (str(item.get("created_at") or ""), item["id"]),
            reverse=True,
        )
        heads = [head, *dict.fromkeys(item["head_sha"] for item in ordered)]
    except Exception:  # noqa: BLE001 - nothing read, nothing carried
        return None
    posted = _poster(comments, threads)
    for sha in dict.fromkeys(h for h in heads if isinstance(h, str)):
        try:
            reviewed, chain = _resolve(SEVERITY_LANE, sha, lane_runs, posted)
            marker = _require_marker(SEVERITY_LANE, sha, comments, newest_only=False)
            _require_marked_runs(SEVERITY_LANE, lane_runs, comments)
            _, _, critical = _open_findings(
                SEVERITY_LANE,
                lane_runs,
                threads,
                is_human,
                set(),
                reviewed,
                chain,
                head_file,
                [(None, marker), *_summary_comments(SEVERITY_LANE, comments)],
            )
        except Exception:  # noqa: BLE001 - this head does not bind; try older
            continue
        return critical
    return None


def _lane_runs(lane: str, runs: Sequence[Mapping[str, Any]]) -> list[Mapping[str, Any]]:
    path = LANES[lane][0]
    if not isinstance(runs, list | tuple):
        raise Unbound("evidence-error")
    selected = []
    for item in runs:
        if not isinstance(item, Mapping):
            raise Unbound("evidence-error")
        if item.get("path") != path or item.get("event") != "pull_request":
            continue
        if not isinstance(item.get("id"), int) or not isinstance(
            item.get("head_sha"), str
        ):
            raise Unbound("evidence-error")
        selected.append(item)
    return selected


# Whether a lane posted on a head between two times (`lane_posted`, bound to
# the pull request's comments and threads by `_poster`).
Poster = Callable[[str, str, Any, Any], bool]


def _resolve(
    lane: str, head: str, lane_runs: list[Mapping[str, Any]], posted: Poster
) -> tuple[str, list[_Record]]:
    """Require a bound run at `head` whose record leads back to a whole review,
    and return the head of the review that covers `head` with the chain of
    review records that covers it, newest first, back to the whole review.

    A no-change skip binds to the review it names, one hop; an incremental
    review needs every earlier link bound, back to a whole review. Each link
    is the newest run's latest attempt at its head (`_bound_record`).
    """
    rec = _bound_record(lane, head, lane_runs, posted)
    seen = {head}
    if rec.skip is not None:
        raise Unbound("skip-not-no-change")
    if rec.through is not None:
        rec = _skip_target(lane, rec.through, lane_runs, seen, posted)
    reviewed = rec.sha
    chain = [rec]
    for _ in range(MAX_CHAIN):
        if rec.whole:
            return reviewed, chain
        rec = _link(lane, rec.since, lane_runs, seen, posted)  # type: ignore[arg-type]
        if rec.skip is not None:
            raise Unbound("incremental-gap")
        if rec.through is not None:
            rec = _skip_target(lane, rec.through, lane_runs, seen, posted)
        chain.append(rec)
    raise Unbound("incremental-gap")


def _skip_target(
    lane: str,
    sha: str,
    lane_runs: list[Mapping[str, Any]],
    seen: set[str],
    posted: Poster,
) -> _Record:
    rec = _link(lane, sha, lane_runs, seen, posted)
    if rec.through is not None or rec.skip is not None:
        raise Unbound("skip-chain")
    return rec


def _link(
    lane: str,
    sha: str,
    lane_runs: list[Mapping[str, Any]],
    seen: set[str],
    posted: Poster,
) -> _Record:
    """An earlier head in the chain; any failure to bind it is a gap."""
    if sha in seen:
        raise Unbound("incremental-gap")
    seen.add(sha)
    try:
        return _bound_record(lane, sha, lane_runs, posted)
    except Unbound as exc:
        if exc.reason in {"count-inconsistent", "evidence-error", "evidence-missing"}:
            raise
        raise Unbound("incremental-gap") from exc


def _bound_record(
    lane: str, sha: str, lane_runs: list[Mapping[str, Any]], posted: Poster
) -> _Record:
    at_sha = [item for item in lane_runs if item["head_sha"] == sha]
    if not at_sha:
        raise Unbound("no-run")
    newest = max(
        at_sha, key=lambda item: (str(item.get("created_at") or ""), item["id"])
    )
    if newest.get("status") != "completed" or newest.get("conclusion") != "success":
        raise Unbound("run-not-success")
    latest_n = newest.get("run_attempt")
    if not isinstance(latest_n, int) or isinstance(latest_n, bool) or latest_n < 1:
        raise Unbound("evidence-error")
    attempts = _attempts(newest)
    latest = attempts.get(latest_n)
    if latest is None:
        raise Unbound("evidence-missing")
    if max(attempts) != latest_n:
        # The listing predates a re-run the attempts already show.
        raise Unbound("evidence-error")
    if (
        latest.get("status") != "completed"
        or latest.get("conclusion") != "success"
        or latest.get("head_sha") != sha
    ):
        raise Unbound("run-not-success")
    if latest_n > 1:
        first = attempts.get(1)
        if latest_n > 2:
            raise Unbound("rerun-not-allowed")
        if first is None:
            raise Unbound("evidence-missing")
        if not rerun_binds(lane, newest["id"], first, sha, latest, posted):
            raise Unbound("rerun-not-allowed")
    job = _lane_job(lane, newest["id"], latest)
    if job.get("conclusion") != "success" or job.get("head_sha") != sha:
        raise Unbound("run-not-success")
    rec = _record(lane, sha, job)
    if rec is None:
        raise Unbound("no-record")
    if rec.findings is not None and rec.findings < rec.inline:  # type: ignore[operator]
        raise Unbound("count-inconsistent")
    return rec


def _attempts(item: Mapping[str, Any]) -> dict[int, Mapping[str, Any]]:
    attempts = item.get("attempts")
    if not isinstance(attempts, list | tuple):
        raise Unbound("evidence-missing")
    by_n: dict[int, Mapping[str, Any]] = {}
    for attempt in attempts:
        if not isinstance(attempt, Mapping):
            raise Unbound("evidence-error")
        n = attempt.get("run_attempt")
        if not isinstance(n, int) or n in by_n or attempt.get("id") != item["id"]:
            raise Unbound("evidence-error")
        by_n[n] = attempt
    return by_n


def _lane_job(lane: str, run_id: int, attempt: Mapping[str, Any]) -> Mapping[str, Any]:
    suffix = LANES[lane][1]
    jobs = attempt.get("jobs")
    if not isinstance(jobs, list | tuple):
        raise Unbound("evidence-missing")
    matches = [
        job
        for job in jobs
        if isinstance(job, Mapping)
        and isinstance(job.get("name"), str)
        and job["name"].rsplit(" / ", 1)[-1] == suffix
    ]
    if not matches:
        raise Unbound("no-lane-job" if jobs else "evidence-missing")
    if len(matches) > 1:
        raise Unbound("record-malformed")
    job = matches[0]
    if job.get("run_id") != run_id or job.get("run_attempt") != attempt.get(
        "run_attempt"
    ):
        raise Unbound("evidence-error")
    if not isinstance(job.get("annotations"), list | tuple):
        raise Unbound("evidence-missing")
    return job


def _failures(job: Mapping[str, Any]) -> list[str]:
    """The messages of the job's failure-level annotations."""
    return [
        str(a.get("message") or "")
        for a in job["annotations"]
        if isinstance(a, Mapping) and a.get("annotation_level") == "failure"
    ]


def _lane_line(pattern: re.Pattern[str], lane: str, message: str) -> bool:
    """Whether `message` opens with `pattern` for this lane."""
    found = pattern.match(message)
    return found is not None and found["lane"] == lane


# The failure classes of a failed attempt 1 after which attempt 2 binds
# (`rerun_binds`), each with its test of one failure annotation's message.
RERUN_CLASSES: dict[str, Callable[[str, str], bool]] = {
    "rate-limit": lambda lane, m: RATE_LIMIT_CLASS_RE.search(m) is not None,
    "publish-rate-limit": lambda lane, m: _lane_line(PUBLISH_RATE_LIMIT_RE, lane, m),
    "auth": lambda lane, m: _lane_line(AUTH_FAILURE_RE, lane, m),
    INSTALL_FAILED: lambda lane, m: _lane_line(INSTALL_FAILURE_RE, lane, m),
}
# The ones the merge gate re-runs itself (babysit_merge
# `rerun_rate_limited_review`): those failure classes, and `LOST`, which a
# run's conclusion names rather than an annotation. A rejected credential is
# left to a person: a re-run before the secret is fixed would spend the one
# allowed attempt.
GATE_RERUN_CLASSES = frozenset(
    {"rate-limit", "publish-rate-limit", INSTALL_FAILED, LOST}
)


def rerun_classes(lane: str, job: Mapping[str, Any]) -> frozenset[str]:
    """The `RERUN_CLASSES` a failure annotation of the lane's job names."""
    failures = _failures(job)
    return frozenset(
        name
        for name, test in RERUN_CLASSES.items()
        if any(test(lane, m) for m in failures)
    )


def rerun_binds(
    lane: str,
    run_id: int,
    first: Mapping[str, Any],
    sha: str | None = None,
    second: Mapping[str, Any] | None = None,
    posted: Poster | None = None,
) -> bool:
    """Whether attempt 1 (`first`) left no verdict, so attempt 2 (`second`, at
    `sha`) binds: it failed on one of `RERUN_CLASSES`, a kill switch stopped it
    (`_kill_switch_stopped`), or an outage lost it before its lane posted
    (`_lost_unposted`)."""
    if first.get("conclusion") == "success":
        return _kill_switch_stopped(lane, run_id, first)
    if first.get("conclusion") in LOST_CONCLUSIONS:
        return _lost_unposted(lane, run_id, first, sha, second, posted)
    if first.get("conclusion") != "failure":
        return False
    return bool(rerun_classes(lane, _lane_job(lane, run_id, first)))


def recorded(job: Mapping[str, Any]) -> bool:
    """Whether a job's annotations hold a completion record, well formed or not."""
    return any(
        isinstance(a, Mapping) and a.get("title") == RECORD_TITLE
        for a in job.get("annotations") or ()
    )


def _lost_unposted(
    lane: str,
    run_id: int,
    first: Mapping[str, Any],
    sha: str | None,
    second: Mapping[str, Any] | None,
    posted: Poster | None,
) -> bool:
    """Whether lost attempt 1 reached no side effect: its lane job, when it
    has one, was lost too and left no completion record, and the lane posted
    nothing on `sha` from attempt 1's start to attempt 2's (`lane_posted`). A
    lane job that ended on its own (a failure outside `RERUN_CLASSES`) judged
    the head, so a re-run could trade its verdict away."""
    if sha is None or second is None or posted is None:
        return False
    jobs = first.get("jobs")
    if not isinstance(jobs, list | tuple):
        raise Unbound("evidence-missing")
    if _has_lane_job(lane, jobs):
        job = _lane_job(lane, run_id, first)
        if job.get("conclusion") not in LOST_CONCLUSIONS or recorded(job):
            return False
    return not posted(
        lane, sha, first.get("run_started_at"), second.get("run_started_at")
    )


def lane_posted(
    lane: str,
    head: str,
    since: Any,
    until: Any,
    comments: Any,
    threads: Any,
) -> bool:
    """Whether the lane posted on `head` from `since` to before `until` (both
    timestamps; `until` None is now): its reviewed-head marker naming `head`,
    another lane comment, or a lane thread opened then. An unreadable `since`,
    time or input counts as posted; an unreadable `until` reads as now."""
    start = _time(since)
    if start is None or not isinstance(comments, list | tuple):
        return True
    end = _time(until)

    def within(value: Any) -> bool:
        at = _time(value)
        return at is None or (start <= at and (end is None or at < end))

    for comment in comments:
        if not isinstance(comment, Mapping):
            return True
        user = comment.get("user")
        login = user.get("login") if isinstance(user, Mapping) else None
        body = str(comment.get("body") or "")
        mark = MARKER_RE.match(body.split("\n", 1)[0].rstrip("\r"))
        if mark is not None:
            if login == MARKER_AUTHOR and mark[1] == lane and mark[2] == head:
                if within(comment.get("created_at")):
                    return True
            continue
        if _lane_comment(lane, login, body) and within(comment.get("created_at")):
            return True
    if not isinstance(threads, list | tuple):
        return True
    for thread in threads:
        if not isinstance(thread, Mapping):
            return True
        if _lane_thread(lane, thread) and within(
            thread["comments"][0].get("createdAt")
        ):
            return True
    return False


def _has_lane_job(lane: str, jobs: Sequence[Any]) -> bool:
    suffix = LANES[lane][1]
    return any(
        isinstance(job, Mapping)
        and str(job.get("name") or "").rsplit(" / ", 1)[-1] == suffix
        for job in jobs
    )


def _lost_before_lane_job(lane: str, attempt: Mapping[str, Any]) -> bool:
    """Whether an outage lost this attempt before its lane job existed."""
    jobs = attempt.get("jobs")
    return (
        attempt.get("conclusion") in LOST_CONCLUSIONS
        and isinstance(jobs, list | tuple)
        and not _has_lane_job(lane, jobs)
    )


def _poster(comments: Any, threads: Any) -> Poster:
    """`lane_posted` over this pull request's comments and threads."""
    return lambda lane, head, since, until: lane_posted(
        lane, head, since, until, comments, threads
    )


def _kill_switch_stopped(lane: str, run_id: int, attempt: Mapping[str, Any]) -> bool:
    """Whether a kill switch stopped this attempt before its lane job existed."""
    jobs = attempt.get("jobs")
    if not isinstance(jobs, list | tuple) or not all(
        isinstance(job, Mapping) for job in jobs
    ):
        raise Unbound("evidence-missing")
    suffix = LANES[lane][1]
    if any(str(job.get("name") or "").rsplit(" / ", 1)[-1] == suffix for job in jobs):
        return False
    kills = [job for job in jobs if job.get("name") == KILL_SWITCH_JOB]
    if len(kills) != 1 or kills[0].get("conclusion") != "success":
        return False
    kill = kills[0]
    if kill.get("run_id") != run_id or kill.get("run_attempt") != attempt.get(
        "run_attempt"
    ):
        raise Unbound("evidence-error")
    if not isinstance(kill.get("annotations"), list | tuple):
        raise Unbound("evidence-missing")
    return any(
        isinstance(a, Mapping)
        and a.get("annotation_level") == "notice"
        and KILL_SWITCH_NOTICE_RE[lane].match(str(a.get("message") or ""))
        for a in kill["annotations"]
    )


def _record(lane: str, sha: str, job: Mapping[str, Any]) -> _Record | None:
    """The job's one completion record for `sha`, None when it left none."""
    found = [
        a
        for a in job["annotations"]
        if isinstance(a, Mapping) and a.get("title") == RECORD_TITLE
    ]
    if not found:
        return None
    if len(found) > 1 or found[0].get("annotation_level") != "notice":
        raise Unbound("record-malformed")
    match = RECORD_RE.match(str(found[0].get("message") or ""))
    if not match or match["lane"] != lane or match["sha"] != sha:
        raise Unbound("record-malformed")
    if match["skip"] is not None:
        return _Record(sha, skip=match["skip"])
    if match["through"] is not None:
        return _Record(sha, through=match["through"])
    return _Record(
        sha,
        findings=int(match["n"]),
        inline=int(match["k"]),
        whole=match["whole"] is not None,
        since=match["since"],
        completed=_time(job.get("completed_at")),
    )


def _require_marker(
    lane: str,
    head: str,
    comments: Sequence[Mapping[str, Any]],
    newest_only: bool = True,
) -> str:
    """The newest reviewed-head marker the lane job wrote must name `head`;
    its body, which carries the covering review's summary. With
    `newest_only` False, the newest marker naming `head` will do, for a
    review a newer marker has passed."""
    if not isinstance(comments, list | tuple):
        raise Unbound("evidence-error")
    newest: tuple[str, int, str, str] | None = None
    for comment in comments:
        if not isinstance(comment, Mapping):
            raise Unbound("evidence-error")
        user = comment.get("user")
        if not isinstance(user, Mapping) or user.get("login") != MARKER_AUTHOR:
            continue
        # Before the body is read: an edit could change the line that makes
        # it a marker.
        if _edited_by_another(user, comment.get("edit")):
            raise Unbound("comment-edited")
        first_line = str(comment.get("body") or "").split("\n", 1)[0].rstrip("\r")
        match = MARKER_RE.match(first_line)
        if not match or match[1] != lane or not (newest_only or match[2] == head):
            continue
        key = (
            str(comment.get("created_at") or ""),
            int(comment.get("id") or 0),
            match[2],
            str(comment.get("body") or ""),
        )
        if newest is None or key[:2] > newest[:2]:
            newest = key
    if newest is None or newest[2] != head:
        raise Unbound("no-marker")
    return newest[3]


def _summary_comments(
    lane: str, comments: Sequence[Mapping[str, Any]]
) -> list[tuple[datetime | None, str]]:
    """Each lane comment of `lane` (`_lane_comment`) but a reviewed-head
    marker, which the caller reads already, with its creation time: the
    summary comments a lane producer posted."""
    found = []
    for comment in comments:
        user = comment.get("user")
        if not isinstance(user, Mapping):
            continue
        body = str(comment.get("body") or "")
        created = _time(comment.get("created_at"))
        if MARKER_RE.match(body.split("\n", 1)[0]):
            continue
        # A REST comment always carries the bot's suffixed login and type.
        if user.get("login") in ACTIONS_LOGINS and (
            user.get("login") != MARKER_AUTHOR or user.get("type") != "Bot"
        ):
            continue
        # Before the body is read: an edit could drop the footer that makes
        # it the lane's.
        if user.get("login") in LANE_AUTHORS and _edited_by_another(
            user, comment.get("edit")
        ):
            raise Unbound("comment-edited")
        if not _lane_comment(lane, user.get("login"), body):
            continue
        if created is not None:
            found.append((created, body))
    return found


def _require_marked_runs(
    lane: str,
    lane_runs: list[Mapping[str, Any]],
    comments: Sequence[Mapping[str, Any]],
) -> None:
    """Every head a reviewed-head marker of the lane names has a listed run, so
    no reviewed run's findings are missing from the count."""
    listed = {item["head_sha"] for item in lane_runs}
    for comment in comments:
        user = comment.get("user")
        if not isinstance(user, Mapping) or user.get("login") != MARKER_AUTHOR:
            continue
        first_line = str(comment.get("body") or "").split("\n", 1)[0].rstrip("\r")
        match = MARKER_RE.match(first_line)
        if match and match[1] == lane and match[2] not in listed:
            raise Unbound("run-missing")


def _open_findings(
    lane: str,
    lane_runs: list[Mapping[str, Any]],
    threads: Sequence[Mapping[str, Any]] | None,
    is_human: Callable[[Any], bool],
    claimed: set[str],
    reviewed: str,
    chain: Sequence[_Record],
    head_file: Callable[[str, str], str | None] | None = None,
    summaries: Sequence[tuple[datetime | None, str]] = (),
) -> tuple[int, bool, int]:
    """Summary findings of the review chain covering the pinned head
    (`chain`, from `_resolve`), plus inline threads still open, plus inline
    findings of the chain whose thread is gone. A summary or thread-less
    inline finding from a review of an earlier head outside that chain is
    closed: the covering review no longer reports it. Reviews of one head
    never supersede each other, whatever their kind: each link counts the
    most summary findings, and the most inline findings left without a
    thread, that any completed review of its head (whole or incremental)
    reported. A head here is its tree (the run's `head_commit.tree_id`), so
    commits with one tree are one head. So a finding any review of a head
    reported clears only by a new head (a fix that changes the tree) or a
    human resolution; re-running the review of the same head, or of an
    empty commit on it, until it comes back clean never clears it. A
    reviewed run with no readable tree unbinds the lane.

    A resolved thread is closed when:
    - a human resolved it;
    - no completed review of a chain link's head (whole or incremental)
      reported a finding, and the thread was opened before the covering
      review's job completed, so that review read past it. A whole review of
      the head is a chain of one, so a clean whole review closes a thread
      whoever resolved it, unless another review of that head reported a
      finding. An incremental review reads only what changed and never closes
      an unchanged thread this way. Closure is per lane: a security-lane
      (HIGH) thread needs the security lane's own clean whole review;
    - or GitHub marks it outdated, it was opened before the first review at
      `reviewed` (the head whose review covers the pinned head) started, and
      no line of its flagged range is left at the pinned head
      (`_line_changed`): a later review read the changed lines.
    Otherwise it stays open until a human resolves it: resolving a thread
    alone never closes it, so the reviewer clears a finding, not the agent
    that resolved it. A thread stands for a recorded inline finding only when
    it was opened inside that lane job's run, and it stands for one finding
    across both lanes (`claimed`), so neither an unrecorded review's thread
    nor the other lane's untagged thread hides a missing one.

    Also returns whether a clean whole review of `reviewed` would close every
    open finding: none is an unresolved thread, no completed review of
    `reviewed`'s tree reported a finding, and none of them was a whole
    review; and how many open findings are CRITICAL (`SEVERITY_RE`): open
    threads whose comment is not marked IMPORTANT or SUGGESTION, every inline
    finding whose thread is gone, and the summary findings, of which only the
    covering review's own may count fewer, when no other review of its tree
    reported a summary finding: its one `critical-findings:` line, read from
    `summaries` (the reviewed-head marker, which carries the summary, and
    each Claude App summary comment posted inside that review's job). An
    earlier review's summary is not read, so all its findings count."""
    if threads is None:
        raise Unbound("threads-unread")
    # The covering review's job window, to place its summary comments.
    span: tuple[datetime | None, datetime | None] | None = None
    # (job started, job completed, inline findings) per recorded attempt.
    windows: list[tuple[datetime | None, datetime | None, int]] = []
    # The tree per window, to count missing ones on the chain.
    window_trees: list[str] = []
    # When the first review at `reviewed` started; unknown keeps every
    # thread's human test.
    first: datetime | None = None
    # Per reviewed head sha, its tree: findings are keyed on the tree, so a
    # new commit with the same tree (an empty one) re-rolls no review.
    trees: dict[str, str] = {}
    # Per tree, the most findings and the most summary findings any completed
    # review of it, whole or incremental, reported.
    head_max: dict[str, int] = {}
    summary_max: dict[str, int] = {}
    # Per tree, how many reviews of it reported a summary finding.
    summary_reviews: dict[str, int] = {}
    # The trees any review of which was whole or reported a finding.
    spent: set[str] = set()
    for item in lane_runs:
        for attempt in _attempts(item).values():
            # A draft-skipped or kill-switched run reviewed nothing, nor did a
            # lost one that never reached its lane job.
            if (
                attempt.get("status") != "completed"
                or attempt.get("conclusion") == "skipped"
                or _kill_switch_stopped(lane, item["id"], attempt)
                or _lost_before_lane_job(lane, attempt)
            ):
                continue
            job = _lane_job(lane, item["id"], attempt)
            rec = _record(lane, item["head_sha"], job)
            if rec is None or rec.findings is None:
                continue
            if rec.findings < rec.inline:  # type: ignore[operator]
                raise Unbound("count-inconsistent")
            tree = _tree(item)
            if trees.setdefault(rec.sha, tree) != tree:
                raise Unbound("evidence-error")
            head_max[tree] = max(head_max.get(tree, 0), rec.findings)
            summary_max[tree] = max(
                summary_max.get(tree, 0),
                rec.findings - rec.inline,  # type: ignore[operator]
            )
            if rec.findings > rec.inline:  # type: ignore[operator]
                summary_reviews[tree] = summary_reviews.get(tree, 0) + 1
            started = _time(job.get("started_at"))
            if rec == chain[0]:
                span = (started, rec.completed)
            windows.append(
                (
                    started,
                    _time(job.get("completed_at")),
                    rec.inline,  # type: ignore[arg-type]
                )
            )
            window_trees.append(tree)
            if rec.whole or rec.findings > 0:
                spent.add(tree)
            if (
                item["head_sha"] == reviewed
                and started
                and (first is None or started < first)
            ):
                first = started
    if any(rec.sha not in trees for rec in chain):
        raise Unbound("tree-unread")
    # The chain's trees, the covering review's first; links that share one
    # count once.
    chain_trees = list(dict.fromkeys(trees[rec.sha] for rec in chain))
    head_spent = chain_trees[0] in spent
    summary = sum(summary_max.get(tree, 0) for tree in chain_trees)
    cleared = not any(head_max.get(tree) for tree in chain_trees)
    # The covering review read only threads opened before its job completed.
    read_through = chain[0].completed
    if not isinstance(threads, list | tuple):
        raise Unbound("evidence-error")
    covered = [0] * len(windows)
    # Open threads: unresolved ones, and resolved ones nothing closed.
    unresolved = held = critical = 0
    for thread in threads:
        if not isinstance(thread, Mapping):
            raise Unbound("evidence-error")
        if not _lane_thread(lane, thread):
            continue
        created = _time(thread["comments"][0].get("createdAt"))
        thread_id = thread.get("id")
        if created and isinstance(thread_id, str) and thread_id not in claimed:
            for i, (start, end, k) in enumerate(windows):
                if start and end and start <= created <= end and covered[i] < k:
                    covered[i] += 1
                    claimed.add(thread_id)
                    break
        if thread.get("isResolved") is not True:
            unresolved += 1
        elif cleared and read_through and created and created < read_through:
            continue
        elif not (
            thread.get("isOutdated") is True
            and first
            and created
            and created < first
            and _line_changed(thread, head_file)
        ) and not is_human(thread.get("resolvedBy")):
            held += 1
        else:
            continue
        severities = SEVERITY_RE.findall(str(thread["comments"][0].get("body") or ""))
        if len(severities) != 1 or severities[0] == "CRITICAL":
            critical += 1
    # Inline findings with no thread left, counted like summary findings:
    # per chain tree, the most any review of it left.
    gone = [max(k - n, 0) for (_, _, k), n in zip(windows, covered)]
    missing = sum(
        max((g for g, at in zip(gone, window_trees) if at == tree), default=0)
        for tree in chain_trees
    )
    count = summary + unresolved + held + missing
    # The covering review's summary findings, when it was the head's only
    # summary count and its line reads no more than it reported.
    own = chain[0].findings - chain[0].inline  # type: ignore[operator]
    start, end = span or (None, None)
    lines = [
        line
        for at, body in summaries
        if at is None or (start and end and start <= at <= end)
        for line in SUMMARY_CRITICAL_RE.findall(body)
    ]
    rest = summary - summary_max.get(chain_trees[0], 0)
    if (
        own == summary_max.get(chain_trees[0], 0)
        and summary_reviews.get(chain_trees[0], 0) <= 1
        and len(lines) == 1
    ):
        summary = rest + min(int(lines[0]), own)
    return (
        count,
        count > 0 and not unresolved and not head_spent,
        summary + critical + missing,
    )


def _tree(item: Mapping[str, Any]) -> str:
    """The tree of a run's head commit (`head_commit.tree_id`, which GitHub
    may leave null); unreadable unbinds."""
    commit = item.get("head_commit")
    tree = commit.get("tree_id") if isinstance(commit, Mapping) else None
    if not isinstance(tree, str) or not SHA_RE.match(tree):
        raise Unbound("tree-unread")
    return tree


def _line_changed(
    thread: Mapping[str, Any], head_file: Callable[[str, str], str | None] | None
) -> bool:
    """Whether every non-blank line of the range a thread flagged
    (`originalStartLine`..`originalLine` on the new side, read from the end of
    its diff hunk) is absent from its file at the pinned head, or the file was
    deleted. No reader, a range the hunk does not end on, an all-blank range
    or anything unreadable is no evidence."""
    if head_file is None:
        return False
    try:
        first = thread["comments"][0]
        path, hunk = first.get("path"), first.get("diffHunk")
        oid = (first.get("originalCommit") or {}).get("oid")
        end = thread.get("originalLine")
        start = thread.get("originalStartLine")
        start = end if start is None else start
        if not (
            isinstance(path, str)
            and path
            and isinstance(hunk, str)
            and isinstance(oid, str)
            and SHA_RE.match(oid)
            and type(start) is int
            and type(end) is int
            and 1 <= start <= end
        ):
            return False
        rows = [row.rstrip("\r") for row in hunk.rstrip("\n").split("\n")]
        header = HUNK_HEADER_RE.match(rows[0])
        if not header or rows[-1][:1] not in ("+", " "):
            return False
        number, flagged = int(header[1]), []
        for row in rows[1:]:
            if row[:1] in ("+", " "):
                if start <= number:
                    flagged.append(row[1:])
                number += 1
        # The hunk must end on the range's last line and hold all of it.
        if number - 1 != end or len(flagged) != end - start + 1:
            return False
        flagged = [line for line in flagged if line.strip()]
        if not flagged:
            return False
        text = head_file(path, oid)
        if text is None:
            return True
        if not isinstance(text, str):
            return False
        present = {line.rstrip("\r") for line in text.split("\n")}
        return not any(line in present for line in flagged)
    except Exception:  # noqa: BLE001 - unreadable is no evidence
        return False


def _edited_by_another(author: Mapping[str, Any], record: Any) -> bool:
    """Whether a lane comment's text may not be its author's: anyone with
    write access can edit a comment, and the last editor wrote the whole body
    (GraphQL `editor`, "The actor who edited the comment", and
    `lastEditedAt`, "The moment the editor made the last edit"). `record`
    holds those two fields: a thread comment itself, or the `edit` record the
    caller attaches to an issue comment. The lane producer edits its own
    reviewed-head marker on each review (ci-workflows publish.cjs
    `writeMarker`), so an edit by the author, a Bot, is its own text. A
    record that is missing or unreadable is not proven unedited."""
    if not isinstance(record, Mapping) or "lastEditedAt" not in record:
        return True
    if record["lastEditedAt"] is None:
        return False
    editor = record.get("editor")
    return not (
        isinstance(editor, Mapping)
        and editor.get("__typename") == "Bot"
        and _bare_login(editor.get("login")) == _bare_login(author.get("login"))
    )


def _bare_login(login: Any) -> str | None:
    """A login without REST's `[bot]` suffix, which GraphQL drops."""
    if not isinstance(login, str) or not login:
        return None
    return login.removesuffix("[bot]")


def _time(value: Any) -> datetime | None:
    """An aware timestamp, or None when absent or unreadable."""
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else None


def _lane_thread(lane: str, thread: Mapping[str, Any]) -> bool:
    """A thread the Claude App opened, untagged or tagged for `lane`, or
    github-actions[bot] opened with `lane`'s footer last."""
    comments = thread.get("comments")
    if not isinstance(comments, list | tuple):
        raise Unbound("evidence-error")
    if not comments:
        return False
    first = comments[0]
    if not isinstance(first, Mapping):
        raise Unbound("evidence-error")
    author = first.get("author")
    if not isinstance(author, Mapping):
        return False
    if author.get("__typename") != "Bot":
        return False
    # Before the body is read: an edit could drop the footer that makes it
    # the lane's.
    if author.get("login") in LANE_AUTHORS and _edited_by_another(author, first):
        raise Unbound("comment-edited")
    return _lane_comment(lane, author.get("login"), str(first.get("body") or ""))
