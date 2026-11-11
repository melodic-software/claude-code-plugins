"""Whether a github-actions[bot] comment footed `claude-lane: <lane>` is that
review lane's own: the Python side of lib/lane-binding.mjs, whose header is
the contract.

Any workflow's job token posts as github-actions[bot], so the footer alone
proves nothing. The lane writes a binding line above the footer,
`<!-- claude-lane-run id=<run> sha=<head> -->`, and its status job uploads
an artifact, `claude-lane-comments-<lane>-<attempt>`, whose comments.jsonl
lists each comment it posted: lane, pull request, head, kind
(review_comment, issue_comment or review), id and the sha256 of the body as
GitHub stored it. A comment counts only when the run its binding names is
the lane's caller workflow, ran on the head the binding names, and one of
that run's records lists the
comment's kind, id and body digest for the same lane, pull request and head.
Every attempt's record counts, so a re-run's comments stay bound. A record
covers its attempt only when it holds the `{"complete":true}` line the lane
writes once its publish and hold steps did not fail.

A comment without a binding counts while LEGACY_CUTOFF is None, then only
when posted at or before it and never edited. A comment no live record
lists, of a finished run one of whose attempts left no live record of the
lane (expired, or a job lost before its upload step), is proved by time
instead: posted between the run's creation and its last update, and never
edited. A comment no record lists yet, of a run still going, raises, so the
caller reads again later. Reads that fail raise, so a caller fails closed
rather than dropping a comment it could not check.
"""

from __future__ import annotations

import hashlib
import io
import json
import re
import zipfile
from collections.abc import Callable, Mapping
from datetime import datetime
from typing import Any

RECORD_PREFIX = "claude-lane-comments-"
RECORD_FILE = "comments.jsonl"
# The largest record read: far above one run's comments, small enough that a
# crafted archive cannot exhaust memory.
MAX_RECORD_BYTES = 4 << 20
# The last time a comment with no binding can be the lane's (ISO 8601): 48
# hours after the lanes began writing bindings, so a run that started before
# then, and a re-run of one within the lost-run reconciler's 24-hour lookback,
# still posts comments that count.
LEGACY_CUTOFF: str | None = "2026-11-13T22:24:32Z"
# A REST comment carries no edit time, only updated_at, which a review's
# batch sets up to a second after created_at; a gap past this counts as an
# edit (GraphQL's lastEditedAt is exact and wins when present).
EDIT_SLACK_SECONDS = 60

FOOTER = re.compile(r"`?claude-lane: (claude-review|claude-security-review)`?")
BINDING = re.compile(r"<!-- claude-lane-run id=([1-9][0-9]{0,19}) sha=([0-9a-f]{40}) -->")
# The field a caller sets on a footed comment it checked: True when the
# checker accepted it, False when not.
VERDICT = "lane_bound"


def _lines(body: Any) -> list[str]:
    return ("" if body is None else str(body)).replace("\r\n", "\n").split("\n")


def _non_blank(lines: list[str]) -> list[int]:
    return [i for i, line in enumerate(lines) if line.strip()]


def lane_footer(body: Any) -> str | None:
    """The lane a body's last non-blank line names as its footer, or None."""
    lines = _lines(body)
    at = _non_blank(lines)
    if not at:
        return None
    match = FOOTER.fullmatch(lines[at[-1]].strip())
    return match[1] if match else None


def binding_of(body: Any) -> tuple[str, str] | None:
    """(run id, head sha) from the binding on the last non-blank line above a
    footed body's footer, or None."""
    lines = _lines(body)
    at = _non_blank(lines)
    if len(at) < 2 or lane_footer(body) is None:
        return None
    match = BINDING.fullmatch(lines[at[-2]].strip())
    return (match[1], match[2]) if match else None


def without_binding(body: Any) -> str:
    """The body without its binding line, the shape every reader parsed
    before the lanes wrote one."""
    text = "" if body is None else str(body)
    if binding_of(text) is None:
        return text
    lines = text.split("\n")
    at = _non_blank([line.removesuffix("\r") for line in lines])
    del lines[at[-2]]
    return "\n".join(lines)


def body_digest(body: Any) -> str:
    return hashlib.sha256(("" if body is None else str(body)).encode("utf-8")).hexdigest()


def _time(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else None


def was_edited(comment: Mapping[str, Any]) -> bool:
    """Whether a comment was edited after it was posted: GraphQL's
    lastEditedAt when the view has the key, else REST updated_at past
    created_at by more than EDIT_SLACK_SECONDS."""
    if "lastEditedAt" in comment:
        return comment["lastEditedAt"] is not None
    created, updated = _time(comment.get("createdAt")), _time(comment.get("updatedAt"))
    if created is None or updated is None:
        return False
    return (updated - created).total_seconds() > EDIT_SLACK_SECONDS


def legacy_counts(comment: Mapping[str, Any], cutoff: str | None = LEGACY_CUTOFF) -> bool:
    """Whether a comment with no binding still counts."""
    if cutoff is None:
        return True
    created, limit = _time(comment.get("createdAt")), _time(cutoff)
    return created is not None and limit is not None and created <= limit and not was_edited(comment)


def zip_entry(data: bytes, name: str) -> bytes | None:
    """One file's bytes from a zip archive, or None when the archive does not
    hold it. A malformed archive raises ValueError."""
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            try:
                info = archive.getinfo(name)
            except KeyError:
                return None
            if info.file_size > MAX_RECORD_BYTES:
                raise ValueError(f"{name} is over {MAX_RECORD_BYTES} bytes")
            with archive.open(info) as handle:
                data = handle.read(MAX_RECORD_BYTES + 1)
            if len(data) > MAX_RECORD_BYTES:
                raise ValueError(f"{name} is over {MAX_RECORD_BYTES} bytes")
            return data
    except (zipfile.BadZipFile, NotImplementedError, OSError, EOFError) as exc:
        raise ValueError(f"zip archive unread: {exc}") from exc


def record_entries(text: Any) -> list[dict[str, Any]]:
    """The entries of one record's comments.jsonl; a line that is not an
    object is skipped."""
    entries = []
    for line in ("" if text is None else str(text)).split("\n"):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            entries.append(entry)
    return entries


def _same_int(value: Any, expected: int | None) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value == expected


def _int(value: Any) -> int | None:
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, str) and re.fullmatch(r"[0-9]+", value):
        return int(value)
    return None


def issue_comment_view(comment: Mapping[str, Any]) -> dict[str, Any]:
    """A REST issue comment as the checker reads it; lastEditedAt comes from
    the `edit` record the caller attaches, when it has one."""
    view = {
        "kind": "issue_comment",
        "id": comment.get("id"),
        "body": comment.get("body"),
        "createdAt": comment.get("created_at"),
        "updatedAt": comment.get("updated_at"),
    }
    edit = comment.get("edit")
    if isinstance(edit, Mapping) and "lastEditedAt" in edit:
        view["lastEditedAt"] = edit["lastEditedAt"]
    return view


def review_comment_view(comment: Mapping[str, Any]) -> dict[str, Any]:
    """A GraphQL review-thread comment as the checker reads it."""
    view = {
        "kind": "review_comment",
        "id": comment.get("databaseId"),
        "body": comment.get("body"),
        "createdAt": comment.get("createdAt"),
        "updatedAt": comment.get("updatedAt"),
    }
    if "lastEditedAt" in comment:
        view["lastEditedAt"] = comment["lastEditedAt"]
    return view


Check = Callable[[Mapping[str, Any]], bool]


def lane_checker(
    *,
    pr: int,
    get_pull: Callable[[int | None], Mapping[str, Any]],
    get_run: Callable[[str], Mapping[str, Any]],
    list_artifacts: Callable[[str], list[Mapping[str, Any]]],
    download: Callable[[Any], bytes],
    workflows: Mapping[str, str],
    cutoff: str | None = LEGACY_CUTOFF,
) -> Check:
    """A checker for one pull request's lane comments. `get_pull(pr)` reads
    /pulls/<pr>, `get_run(id)` reads /actions/runs/<id>, `list_artifacts(id)` that run's artifacts (every
    page), `download(artifact id)` an artifact's zip bytes; `workflows` maps
    each lane to its caller workflow path. Each run is read once, a failed
    read included. `check(view)`, a view from `issue_comment_view` or
    `review_comment_view`, is True when the comment is its footer lane's
    own; a comment with no lane footer is not a lane comment. A run counts
    only when it ran on the pull request's own head branch: a pull_request
    run takes its workflow from the head, so a run of another branch could
    have written any record. The pull request is read once, and only for a
    comment that carries a binding."""
    runs: dict[str, tuple[Any, BaseException | None]] = {}
    pulls: list[Mapping[str, Any]] = []

    def head() -> Mapping[str, Any]:
        if not pulls:
            pulls.append(get_pull(number))
        found = pulls[0].get("head") if isinstance(pulls[0], Mapping) else None
        return found if isinstance(found, Mapping) else {}
    number = _int(pr)

    def read_run(run_id: str) -> Any:
        if run_id not in runs:
            try:
                run = get_run(run_id)
                records = [
                    a
                    for a in list_artifacts(run_id)
                    if str((a or {}).get("name") or "").startswith(RECORD_PREFIX)
                ]
                live = [a for a in records if a.get("expired") is not True]
                entries: list[dict[str, Any]] = []
                recorded: set[str] = set()
                for artifact in live:
                    data = zip_entry(download(artifact.get("id")), RECORD_FILE)
                    lines = record_entries(None if data is None else data.decode("utf-8"))
                    entries.extend(lines)
                    if any(e.get("complete") is True for e in lines):
                        recorded.add(str(artifact.get("name")))
                runs[run_id] = ((run, entries, recorded), None)
            except Exception as exc:  # noqa: BLE001 - kept and raised on each check
                runs[run_id] = (None, exc)
        found, failure = runs[run_id]
        if failure is not None:
            raise failure
        return found

    def check(comment: Mapping[str, Any]) -> bool:
        body = comment.get("body")
        lane = lane_footer(body)
        if lane is None:
            return False
        binding = binding_of(body)
        if binding is None:
            return legacy_counts(comment, cutoff)
        run_id, sha = binding
        run, entries, recorded = read_run(run_id)
        if (
            not isinstance(run, Mapping)
            or str(run.get("id")) != run_id
            or run.get("path") != workflows.get(lane)
            or run.get("head_sha") != sha
        ):
            return False
        pull_head = head()
        repo = pull_head.get("repo") if isinstance(pull_head.get("repo"), Mapping) else {}
        run_repo = run.get("head_repository") if isinstance(run.get("head_repository"), Mapping) else {}
        if (
            not isinstance(run.get("head_branch"), str)
            or run.get("head_branch") != pull_head.get("ref")
            or run_repo.get("full_name") != repo.get("full_name")
        ):
            return False
        digest = body_digest(body)
        comment_id = _int(comment.get("id"))
        listed = any(
            e.get("lane") == lane
            and _same_int(e.get("pr"), number)
            and e.get("head") == sha
            and e.get("kind") == comment.get("kind")
            and _same_int(e.get("id"), comment_id)
            and e.get("sha256") == digest
            for e in entries
        )
        if listed:
            return True
        if run.get("status") != "completed":
            raise RuntimeError(f"lane run {run_id} is still running, so its comment record may not be uploaded yet")
        attempt = run.get("run_attempt")
        attempts = attempt if isinstance(attempt, int) and not isinstance(attempt, bool) and attempt > 0 else 1
        if all(f"{RECORD_PREFIX}{lane}-{n}" in recorded for n in range(1, attempts + 1)):
            return False
        at = _time(comment.get("createdAt"))
        start, end = _time(run.get("created_at")), _time(run.get("updated_at"))
        in_window = None not in (at, start, end) and start <= at <= end  # type: ignore[operator]
        return in_window and not was_edited(comment)

    return check
