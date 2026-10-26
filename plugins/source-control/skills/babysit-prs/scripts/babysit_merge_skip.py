#!/usr/bin/env python3
"""Skip a pr-merge candidate whose last refusal stands on the same inputs.

pr-merge.yml gates every candidate on every run, and most are refused again on
inputs that have not changed since the last run. Each such gate process
spends tens of lane-token and job-token calls to repeat its answer. This
script keys every candidate on the inputs its refusal can depend on, read
cheaply, and sets a candidate aside when the last run that gated it refused
it on the same key. It never allows anything: a skipped candidate is reported
refused, with its earlier verdict marked carried, and is never enqueued.

`filter` runs before the gate loop. Per candidate the key covers:

- the listed head SHA, `updatedAt` and, from one aliased GraphQL query for
  every candidate, its labels, base SHA (the gate reads its config and base
  text there), check rollup at the head (each check run's id, status and
  conclusion; each status context's state and time), review decision and
  count, review threads (resolved and outdated), its newest 50 comments by id
  and update time, and each closing issue's update and edit times and comment
  count. Check runs and statuses do not bump `updatedAt`, so it is never the
  key alone;
- the ids of the unexpired `pr-verify-<pr>-<sha>-<verdict>` artifacts naming
  this pull request or its head, from the repository listing the verdict
  reader saves for the gate's first candidate (`Reader.listing`), so the read
  is not added;
- the default branch's blob or tree ids of the gate's config, trusted list,
  tracker config, the pr-merge workflow, the config resolver that picks the
  gate's script and flags, and the gate's scripts, read from the `.base`
  clone, and `CLAUDE_LANES_MERGE_RUNG_CAP`.

The key is read before the gate runs, so a first refusal that posts its
reasons comment changes the comments and `updatedAt`; the next run gates
again (the gate leaves the comment unchanged) and only the one after can
skip. Keep comments in the key: a skip must not miss a new one.

A candidate is skipped only when the stored refusal is one of `SKIPPABLE`,
names the same key and head, was judged less than `max-minutes` ago and has
been skipped fewer than `max-skips` runs in a row; never when it is in the
merge queue, when any read is incomplete or failed, or for `verify:missing`
or `verify:earlier-fail` while a PASS artifact names its head (its run may
finish). When every candidate would be skipped, the first is gated, so a gate
process still sweeps the merge queue. Any doubt gates the candidate.

`record` runs after the gate loop. It stores each gated candidate's refusal
when it is one of `SKIPPABLE` at the listed head and its gate process wrote
nothing that failed and has no review re-run still due, carries a skipped
candidate's record forward with its skip count raised and its judgment time
kept, and keeps an unreached candidate's record. The store is the
`skip-unchanged` section of the file pr-merge.yml carries to the next run as
the pr-merge-run-cache artifact of a scheduled or hand-started run on main
(.github/scripts/pr-merge/carry-run-cache.mjs). Even so, a forged record can
only repeat a refusal, for at most `max-minutes` from the time it names, which
may not be in the future.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from collections.abc import Callable, Iterable, Mapping
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import babysit_verify_evidence as verify_evidence
from babysit_gh import gh_json
from babysit_util import is_json_array, is_json_object, json_array, json_object

SECTION = "skip-unchanged"
VERSION = 1
SKIPPABLE = frozenset(
    {
        "risk:MED",
        "risk:HIGH",
        verify_evidence.FAIL,
        verify_evidence.EARLIER_FAIL,
        verify_evidence.REPEATED_FAIL,
        verify_evidence.MISSING,
        verify_evidence.TOO_OLD,
        verify_evidence.SPEC_CHANGED,
        verify_evidence.UNTRUSTED_SPEC,
    }
)
# `merge.skip-unchanged` in docs/conventions/pr-pipeline.yaml; 0 turns skipping
# off. Scheduled runs are 15 minutes apart, so 3 skips gate an unchanged
# refusal at least every fourth run, and 60 minutes at least hourly whatever
# else starts a run (judgment).
DEFAULT_MAX_MINUTES = 60
DEFAULT_MAX_SKIPS = 3
# Candidates per GraphQL query.
CHUNK = 20
MAIN_PATHS = (
    "docs/conventions/pr-pipeline.yaml",
    ".claude/source-control.md",
    ".github/standards/trusted-actors/trusted-actors.json",
    ".work-item-tracker.json",
    ".github/workflows/pr-merge.yml",
    ".github/actions/resolve-config",
    "plugins/source-control/scripts",
    "plugins/source-control/skills/babysit-prs/scripts",
    "plugins/source-control/skills/babysit-loop/scripts",
)
# A review re-run report the next gate repeats unchanged (or that started a
# run, which changes the check rollup); any other, a re-run still due
# included, gates again.
STABLE_RERUNS = (
    "failure class is not rate-limit",
    "already re-run on this head",
    "not a GitHub Actions job",
    "the job ran on another head",
    "the job named by details_url",
    "job conclusion is",
)
SHA_RE = re.compile(r"[0-9a-f]{40}")
KEY_RE = re.compile(r"[0-9a-f]{64}")
ZONED_RE = re.compile(r"(Z|[+-]\d\d:\d\d)$")
STATE_FIELDS = (
    "number body headRefOid baseRefOid isInMergeQueue updatedAt reviewDecision "
    "labels(first:100){totalCount nodes{name}} reviews{totalCount} "
    "comments(last:50){totalCount nodes{databaseId updatedAt}} "
    "reviewThreads(first:100){totalCount nodes{isResolved isOutdated}} "
    "closingIssuesReferences(first:10){totalCount nodes{number updatedAt "
    "lastEditedAt comments{totalCount}}} "
    "commits(last:1){nodes{commit{oid statusCheckRollup{contexts(first:100){"
    "totalCount nodes{__typename ... on CheckRun{databaseId name status "
    "conclusion} ... on StatusContext{context state createdAt}}}}}}}"
)


def now() -> datetime:
    return datetime.now(UTC)


def _time(text: Any) -> datetime | None:
    """A zoned ISO time, else None."""
    if not isinstance(text, str) or not ZONED_RE.search(text):
        return None
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def limit(text: str | None, default: int) -> int:
    """A `merge.skip-unchanged` limit: empty is `default`, a whole number is
    itself, anything else is 0 (off)."""
    if text is None or text.strip() in ("", "null"):
        return default
    return int(text) if re.fullmatch(r"[0-9]{1,6}", text.strip()) else 0


# --- Reads ---------------------------------------------------------------


def main_inputs(base: Path) -> dict[str, str]:
    """The blob or tree id of each `MAIN_PATHS` entry at the clone's HEAD,
    `absent` for a path it lacks. Raises `RuntimeError` when the clone has
    no HEAD."""

    def rev(spec: str) -> str | None:
        proc = subprocess.run(
            ["git", "-C", str(base), "rev-parse", "--verify", "--quiet", spec],
            capture_output=True,
            text=True,
            check=False,
        )
        return proc.stdout.strip() if proc.returncode == 0 else None

    head = rev("HEAD^{commit}")
    if not head:
        raise RuntimeError(f"{base} has no HEAD commit")
    return {path: rev(f"{head}:{path}") or "absent" for path in MAIN_PATHS}


def state_query(numbers: Iterable[int]) -> str:
    aliases = " ".join(f"p{n}:pullRequest(number:{n}){{...s}}" for n in numbers)
    return (
        "query($o:String!,$r:String!){rateLimit{cost} "
        f"repository(owner:$o,name:$r){{{aliases}}}}} "
        f"fragment s on PullRequest{{{STATE_FIELDS}}}"
    )


def read_states(
    repo: str,
    numbers: list[int],
    graphql: Callable[[list[str]], Any] | None = None,
) -> tuple[dict[int, dict[str, Any]], int]:
    """Each pull request's GraphQL node, by number, and the summed query
    cost. A chunk whose query fails is left out, so its candidates gate."""
    owner, name = repo.split("/", 1)
    states: dict[int, dict[str, Any]] = {}
    cost = 0
    for start in range(0, len(numbers), CHUNK):
        chunk = numbers[start : start + CHUNK]
        try:
            data = json_object(
                (graphql or gh_json)(
                    ["api", "graphql", "-f", f"query={state_query(chunk)}"]
                    + ["-f", f"o={owner}", "-f", f"r={name}"]
                )
            )
        except (RuntimeError, ValueError, OSError) as exc:
            print(f"skip-unchanged: state query failed: {exc}", file=sys.stderr)
            continue
        body = json_object(data.get("data"))
        spent = json_object(body.get("rateLimit")).get("cost")
        cost += spent if isinstance(spent, int) else 0
        repository = json_object(body.get("repository"))
        for n in chunk:
            node = repository.get(f"p{n}")
            if is_json_object(node) and node.get("number") == n:
                states[n] = node
    return states, cost


def _complete(connection: Any, limit_: int) -> list[dict[str, Any]] | None:
    """A connection's nodes when it lists all of them, else None."""
    connection = json_object(connection)
    nodes = connection.get("nodes")
    total = connection.get("totalCount")
    if not is_json_array(nodes) or not isinstance(total, int):
        return None
    if total != len(nodes) or total > limit_ or not all(map(is_json_object, nodes)):
        return None
    return nodes


def pr_state(node: Mapping[str, Any]) -> dict[str, Any] | None:
    """The key's view of one GraphQL node, or None when any part of it is
    missing or cut short, or when its issue is a `Refs:` one
    (`merge_policy.refs_issue`), whose update times this read does not carry:
    such a pull request is gated every run."""
    commits = json_array(json_object(node.get("commits")).get("nodes"))
    commit = json_object(json_object(commits[0]).get("commit")) if commits else {}
    head = node.get("headRefOid")
    labels = _complete(node.get("labels"), 100)
    threads = _complete(node.get("reviewThreads"), 100)
    issues = _complete(node.get("closingIssuesReferences"), 10)
    rollup = json_object(commit.get("statusCheckRollup"))
    contexts = _complete(rollup.get("contexts"), 100) if rollup else []
    comments = json_object(node.get("comments"))
    reviews = json_object(node.get("reviews")).get("totalCount")
    if (
        not isinstance(head, str)
        or not SHA_RE.fullmatch(head)
        or commit.get("oid") != head
        or not isinstance(node.get("baseRefOid"), str)
        or not isinstance(node.get("isInMergeQueue"), bool)
        or None in (labels, threads, issues, contexts)
        or not issues
        and verify_evidence.merge_policy.refs_issue(node.get("body"))[0] is not None
        or not isinstance(comments.get("totalCount"), int)
        or not is_json_array(comments.get("nodes"))
        or not isinstance(reviews, int)
    ):
        return None
    return {
        "head": head,
        "base": node["baseRefOid"],
        "inQueue": node["isInMergeQueue"],
        "updatedAt": node.get("updatedAt"),
        "labels": sorted(str(label.get("name")) for label in labels or []),
        "reviewDecision": node.get("reviewDecision"),
        "reviews": reviews,
        "comments": [
            comments["totalCount"],
            *(
                [c.get("databaseId"), c.get("updatedAt")]
                for c in map(json_object, comments["nodes"])
            ),
        ],
        "threads": sorted(
            [bool(t.get("isResolved")), bool(t.get("isOutdated"))]
            for t in threads or []
        ),
        "issues": sorted(
            (
                [
                    i.get("number"),
                    i.get("updatedAt"),
                    i.get("lastEditedAt"),
                    json_object(i.get("comments")).get("totalCount"),
                ]
                for i in issues or []
            ),
            key=json.dumps,
        ),
        "rollup": sorted(
            (
                [
                    c.get("__typename"),
                    c.get("databaseId", c.get("context")),
                    c.get("name"),
                    c.get("status", c.get("state")),
                    c.get("conclusion", c.get("createdAt")),
                ]
                for c in contexts or []
            ),
            key=json.dumps,
        ),
    }


def verdicts(listing: Iterable[Any], number: int, head: str) -> list[list[Any]]:
    """The unexpired verdict artifacts naming this pull request or its head:
    [id, name], by id."""
    found = []
    for item in map(json_object, listing):
        match = verify_evidence.verdict_name(str(item.get("name") or ""))
        if not match or item.get("expired") is not False:
            continue
        if int(match[1]) == number or match[2] == head:
            found.append([item.get("id"), item.get("name")])
    return sorted(found, key=json.dumps)


def state_key(
    candidate: Mapping[str, Any],
    state: Mapping[str, Any],
    artifacts: list[list[Any]],
    main: Mapping[str, str],
    rung_cap: str,
) -> str:
    """The SHA-256 of every input the key covers, as canonical JSON."""
    body = {
        "v": VERSION,
        "pr": candidate.get("number"),
        "listed": [candidate.get("head"), candidate.get("updatedAt")],
        "state": {k: v for k, v in state.items() if k != "inQueue"},
        "artifacts": artifacts,
        "main": dict(sorted(main.items())),
        "rungCap": rung_cap,
    }
    text = json.dumps(body, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode()).hexdigest()


# --- Filter ----------------------------------------------------------------


def _row(value: Any, number: int) -> dict[str, Any] | None:
    """A refused summary row rebuilt from a stored one, or None: a stored
    row is untrusted, so only its reason, report-only flag and blockers are
    kept, and it never reads as ready, enqueued, merged or dispatched."""
    row = json_object(value)
    if row.get("pr") != number or row.get("exit") != 10:
        return None
    blockers = row.get("blockers")
    report_only = row.get("reportOnly")
    return {
        "pr": number,
        "head": row.get("head"),
        "updatedAt": row.get("updatedAt"),
        "exit": 10,
        "ready": False,
        "enqueued": False,
        "merged": False,
        "reportOnly": report_only if isinstance(report_only, bool) else None,
        "reason": row.get("reason"),
        "dispatched": None,
        "blockers": [
            str(b)[:300] for b in (blockers if is_json_array(blockers) else [])[:20]
        ],
    }


def prior(
    entry: Any,
    *,
    number: int,
    head: str,
    key: str,
    at: datetime,
    max_minutes: int,
    max_skips: int,
) -> dict[str, Any] | None:
    """A stored record that still holds for this key at `at`, else None."""
    entry = json_object(entry)
    value = json_object(entry.get("value"))
    judged = _time(entry.get("at"))
    skips = value.get("skips")
    row = _row(value.get("row"), number)
    if (
        judged is None
        or not timedelta(0) <= at - judged < timedelta(minutes=max_minutes)
        or not isinstance(skips, int)
        or isinstance(skips, bool)
        or not 0 <= skips < max_skips
        or value.get("key") != key
        or value.get("head") != head
        or value.get("reason") not in SKIPPABLE
        or row is None
        or row.get("reason") != value.get("reason")
    ):
        return None
    return {"at": entry["at"], "value": {**value, "row": row}}


def select(
    candidates: list[dict[str, Any]],
    keys: Mapping[int, dict[str, Any]],
    store: Mapping[str, Any],
    *,
    at: datetime,
    max_minutes: int,
    max_skips: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    """The candidates to gate, the summary rows of those skipped, and the
    skipped ones' records as the next run should find them."""
    kept: list[dict[str, Any]] = []
    skipped: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for candidate in candidates:
        number = candidate.get("number")
        known = keys.get(number) if isinstance(number, int) else None
        record = (
            prior(
                store.get(str(number)),
                number=number,
                head=str(candidate.get("head")),
                key=known["key"],
                at=at,
                max_minutes=max_minutes,
                max_skips=max_skips,
            )
            if known is not None and known.get("skippable") and max_minutes > 0
            else None
        )
        if record is None or (
            record["value"]["reason"]
            in (verify_evidence.MISSING, verify_evidence.EARLIER_FAIL)
            and known.get("passAtHead")
        ):
            kept.append(candidate)
        else:
            skipped.append((candidate, record))
    if not kept and skipped:
        kept.append(skipped.pop(0)[0])
    rows, carried = [], {}
    for candidate, record in skipped:
        value = {**record["value"], "skips": record["value"]["skips"] + 1}
        carried[str(candidate["number"])] = {"at": record["at"], "value": value}
        rows.append(
            {
                **value["row"],
                "head": candidate.get("head"),
                "updatedAt": candidate.get("updatedAt"),
                "carried": {
                    "judgedAt": record["at"],
                    "skips": value["skips"],
                    "runId": value.get("runId"),
                },
            }
        )
    return kept, rows, carried


def keys_for(
    repo: str,
    candidates: list[dict[str, Any]],
    *,
    base: Path,
    rung_cap: str,
    listing: Callable[[], list[Any]],
    graphql: Callable[[list[str]], Any] | None = None,
) -> tuple[dict[int, dict[str, Any]], int]:
    """Each candidate's key, head and whether it may be skipped at all, and
    the GraphQL cost spent. Raises `RuntimeError` when the clone or the
    artifact listing cannot be read, so nothing is skipped."""
    main = main_inputs(base)
    artifacts = listing()
    numbers = [c["number"] for c in candidates if isinstance(c.get("number"), int)]
    states, cost = read_states(repo, numbers, graphql)
    keys: dict[int, dict[str, Any]] = {}
    for candidate in candidates:
        number, head = candidate.get("number"), candidate.get("head")
        node = states.get(number) if isinstance(number, int) else None
        state = pr_state(node) if node is not None else None
        if state is None or state["head"] != head:
            continue
        found = verdicts(artifacts, number, head)
        keys[number] = {
            "key": state_key(candidate, state, found, main, rung_cap),
            "head": head,
            "skippable": not state["inQueue"],
            "passAtHead": any(
                (m := verify_evidence.verdict_name(str(name))) is not None
                and m[2] == head
                and m[3] in verify_evidence.PASSES
                for _, name in found
            ),
        }
    return keys, cost


def _write(path: Path, data: Any) -> None:
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    os.replace(tmp, path)


def _load(path: Path | None) -> Any:
    if path is None:
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def run_filter(args: argparse.Namespace) -> int:
    at = now()
    max_minutes = limit(args.max_minutes, DEFAULT_MAX_MINUTES)
    max_skips = limit(args.max_skips, DEFAULT_MAX_SKIPS)
    candidates = [json_object(c) for c in json_array(_load(args.candidates))]
    if not candidates:
        print("skip-unchanged: no candidates")
        return 0
    for name, text in (
        ("max-minutes", args.max_minutes),
        ("max-skips", args.max_skips),
    ):
        if text.strip() not in ("", "null") and not re.fullmatch(
            r"[0-9]{1,6}", text.strip()
        ):
            print(
                f"::warning::merge.skip-unchanged.{name} is not a whole number; no candidate is skipped"
            )
    if max_minutes <= 0 or max_skips <= 0:
        # Off: read nothing and leave every candidate for the gate. With no
        # keys file, `record` stores nothing.
        print("skip-unchanged: off, every candidate is gated")
        return 0
    reader = verify_evidence.Reader(args.repo, args.branch)
    try:
        keys, cost = keys_for(
            args.repo,
            candidates,
            base=args.base,
            rung_cap=args.rung_cap,
            listing=reader.listing,
        )
    except RuntimeError as exc:
        print(f"::warning::no candidate is skipped: {exc}")
        return 1
    store = json_object(json_object(_load(args.store)).get(SECTION))
    kept, rows, carried = select(
        candidates,
        keys,
        store,
        at=at,
        max_minutes=max_minutes,
        max_skips=max_skips,
    )
    # A record still good for its own key, kept for a candidate the loop may
    # not reach; a stale or malformed one is dropped.
    earlier = {}
    for candidate in candidates:
        number = candidate.get("number")
        entry = store.get(str(number))
        value = json_object(json_object(entry).get("value"))
        if (
            isinstance(number, int)
            and str(number) not in carried
            and prior(
                entry,
                number=number,
                head=str(candidate.get("head")),
                key=str(value.get("key")),
                at=at,
                max_minutes=max_minutes,
                max_skips=max_skips,
            )
        ):
            earlier[str(number)] = entry
    _write(
        args.out_keys,
        {
            "v": VERSION,
            "at": at.isoformat(),
            "keys": {
                str(n): {"key": k["key"], "head": k["head"]} for n, k in keys.items()
            },
            "carried": carried,
            "prior": earlier,
        },
    )
    _write(args.out_skipped, rows)
    _write(args.candidates, kept)
    print(
        f"skip-unchanged: skipped={len(rows)} gated={len(kept)} keyed={len(keys)} "
        f"of {len(candidates)} graphql-cost={cost}"
    )
    return 0


# --- Record ----------------------------------------------------------------


def stable(output: Mapping[str, Any]) -> bool:
    """Whether a gate process's output leaves nothing for the next one to
    do: no error, no failed write, no pending merge request, no queue
    state, and only review re-run reports the next gate repeats."""
    unattended = json_object(output.get("unattended"))
    writes = unattended.get("writes")
    reruns = output.get("aiReviewReruns", [])
    return (
        "error" not in output
        and "pendingMergeRequest" not in output
        and not output.get("enqueued")
        and not output.get("dequeued")
        and (writes is None or json_object(writes).get("errors") == [])
        and is_json_array(reruns)
        and all(
            json_object(r).get("rerun") is True
            or str(json_object(r).get("reason") or "").startswith(STABLE_RERUNS)
            for r in reruns
        )
    )


def record(
    keys: Mapping[str, Any],
    rows: Iterable[Any],
    outputs: Callable[[int], Mapping[str, Any] | None],
    run_id: str,
) -> dict[str, Any]:
    """The `SECTION` the next run starts from."""
    keyed = json_object(keys.get("keys"))
    carried = json_object(keys.get("carried"))
    earlier = json_object(keys.get("prior"))
    at = keys.get("at")
    gated: dict[str, dict[str, Any]] = {}
    for row in map(json_object, rows):
        if isinstance(row.get("pr"), int) and "carried" not in row:
            gated[str(row["pr"])] = row
    section: dict[str, Any] = {}
    for number in {*keyed, *carried, *earlier}:
        row = gated.get(number)
        if row is None:
            # Skipped, or not reached before the gate budget ran out.
            if number in carried:
                section[number] = carried[number]
            elif number in earlier:
                section[number] = earlier[number]
            continue
        key = json_object(keyed.get(number))
        output = outputs(int(number))
        kept = _row(row, int(number))
        if (
            kept is None
            or _time(at) is None
            or not KEY_RE.fullmatch(str(key.get("key")))
            or row.get("reason") not in SKIPPABLE
            or row.get("head") != key.get("head")
            or row.get("ready") is not False
            or row.get("enqueued")
            or row.get("merged")
            or output is None
            or output.get("headMatches") is not True
            or output.get("headRefOid") != key.get("head")
            or not stable(output)
        ):
            continue
        section[number] = {
            "at": at,
            "value": {
                "key": key["key"],
                "head": key["head"],
                "reason": row["reason"],
                "row": kept,
                "skips": 0,
                "runId": run_id,
            },
        }
    return dict(sorted(section.items(), key=lambda kv: int(kv[0])))


def run_record(args: argparse.Namespace) -> int:
    keys = json_object(_load(args.keys))
    rows = json_array(_load(args.summary))
    store = _load(args.store)
    if not is_json_object(store) or keys.get("v") != VERSION:
        print("skip-unchanged: nothing recorded (no keys or no store)")
        return 0

    def outputs(number: int) -> Mapping[str, Any] | None:
        value = _load(args.outputs_dir / f"gate-{number}.json")
        return value if is_json_object(value) else None

    store[SECTION] = record(keys, rows, outputs, args.run_id)
    _write(args.store, store)
    print(f"skip-unchanged: recorded={len(store[SECTION])}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    sub = parser.add_subparsers(dest="command", required=True)
    f = sub.add_parser("filter", allow_abbrev=False)
    f.add_argument("--repo", required=True)
    f.add_argument("--branch", default="main")
    f.add_argument("--base", type=Path, required=True)
    f.add_argument("--store", type=Path)
    f.add_argument("--candidates", type=Path, required=True)
    f.add_argument("--out-keys", type=Path, required=True)
    f.add_argument("--out-skipped", type=Path, required=True)
    f.add_argument("--rung-cap", default="")
    f.add_argument("--max-minutes", default="")
    f.add_argument("--max-skips", default="")
    r = sub.add_parser("record", allow_abbrev=False)
    r.add_argument("--keys", type=Path, required=True)
    r.add_argument("--summary", type=Path, required=True)
    r.add_argument("--outputs-dir", type=Path, required=True)
    r.add_argument("--store", type=Path, required=True)
    r.add_argument("--run-id", default="")
    args = parser.parse_args(argv)
    return run_filter(args) if args.command == "filter" else run_record(args)


if __name__ == "__main__":
    raise SystemExit(main())
