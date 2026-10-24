#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Case seeding for the resume-accuracy eval (PLAN.md Phase 1).

A case directory under `plugins/session-flow/evals/re-<name>/` holds one
`resume-eval.json`. This module turns its `seed` into what every arm starts from:

- `build_predecessor_chain` writes the case's shape-2 handoff chain through the real
  `save_point.py new`, hop by hop, with deterministic lane-like content sized like
  the audited chains, plus the case's injected entries at their hops. Every hop
  passes `save_point.py validate --strict-transcript`.
- `seed_history` returns the session the writer resumes from: the pasted resume
  prompt of the newest handoff, the reads a real resume makes of it (tool turns whose
  results are real slices of the file), and the case's work turns.

The generated files embed absolute paths (`transcript:`, Prior-sessions rows, the
`Read @` line), so `out_dir` must be the run's repository itself and the files must
stay where they were written, predecessor transcripts included.

Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import contextvars
import hashlib
import json
import re
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from hop_chain import FILL_RE, between_rails, run_save_point  # noqa: E402

CASE_FILE = "resume-eval.json"
NAMESPACE = uuid.UUID("3c1f9a52-7d4e-5b60-9e1a-2f8c4d6b7a90")

# Entries written per hop into each cumulative slot, with each slot's share of the
# base entry width in characters. With a Prior-sessions row this lands near the
# audit's median growth of 6.4-7.0 KB a hop, split close to its section shares
# (AUDIT.md Q1, Q5: Constraints 24%, Findings and Decisions 19%, Side effects 16%,
# Prior sessions 11%, Approaches 7%).
ENTRIES_PER_HOP = {
    "constraints": (5, 1.0),
    "side-effects": (4, 0.8),
    "decisions": (4, 1.0),
    "abandoned": (2, 0.75),
    "findings": (4, 1.0),
}
BASE_WIDTH = 300
MIN_WIDTH = 120
MAX_WIDTH = 900
SECTION_SLOTS = {
    "constraints": "Constraints that must hold",
    "side-effects": "Side effects already applied",
    "decisions": "Decisions already settled",
    "abandoned": "Approaches tried and abandoned",
    "findings": "Findings that cost effort to discover",
}
# Generic lines appended to the newest hop's own text in these hot sections, so each
# carries about the audited 0.8-2.5 KB without adding a file, PR or rule a probe asks
# about.
HOT_PADDING = {
    "environment": (
        "No services run for this lane; the commands below re-read live state.",
        "Re-read the queue with gh pr list --label lane-queue --json number,title,headRefName.",
        "Re-read main's checks with gh run list --branch main --limit 5 --json workflowName,conclusion.",
        "TaskList: none in this session; nothing to recreate.",
    ),
    "open-questions": (
        "Does nightly-evals.yml still need its 40-minute timeout? Probe: gh run list --workflow nightly-evals.yml --limit 10.",
        "Is the docs-check.yml link checker still flaky on redirects? Probe: its last 10 runs.",
    ),
    "skills": (
        "/source-control:pull-request for any PR this lane opens.",
        "/session-flow:handoff for the next save-point.",
    ),
}

# Read patterns (AUDIT.md Q2): files up to WHOLE_MAX are read in one Read, up to
# PAGED_MAX in pages, larger ones partially.
WHOLE_MAX = 60_000
PAGED_MAX = 100_000
PAGE_LINES = 150
TOP_LINES = 100
TAIL_LINES = 80

# --- deterministic choice ----------------------------------------------------------


def _n(key: str) -> int:
    return int.from_bytes(hashlib.sha256(key.encode("utf-8")).digest()[:8], "big")


def _pick(key: str, seq):
    return seq[_n(key) % len(seq)]


def _num(key: str, lo: int, hi: int) -> int:
    """A number in [lo, hi], re-drawn while it is one the case itself names, so no
    generated line mentions a trap PR, issue or run."""
    salt = 0
    while (value := lo + _n(f"{key}#{salt}" if salt else key) % (hi - lo + 1)) in (
        _RESERVED.get()
    ):
        salt += 1
    return value


# Numbers the case spec names (its PRs, issues, runs), set per build.
_RESERVED: contextvars.ContextVar[frozenset[int]] = contextvars.ContextVar(
    "reserved", default=frozenset()
)
SPEC_NUMBER_RE = re.compile(r"(?<![0-9a-f])(?:4[1-4]\d\d|8\d{7})(?![0-9a-f])")


def reserved_numbers(case_spec: dict) -> frozenset[int]:
    """Every PR, issue or run number in the case's own text."""
    return frozenset(int(m) for m in SPEC_NUMBER_RE.findall(json.dumps(case_spec)))


def _sha(key: str) -> str:
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:7]


# --- lane-like content -------------------------------------------------------------

WORKFLOWS = (
    "ci-status.yml",
    "queue-drain.yml",
    "babysit-cycle.yml",
    "intake-triage.yml",
    "nightly-evals.yml",
    "docs-check.yml",
)
FILES = (
    "lane/cycle.py",
    "lane/frontier.py",
    "lane/telemetry.py",
    "scripts/gate_check.py",
    "scripts/label_sync.py",
    "tests/test_cycle.py",
    "docs/lane-runbook.md",
)
PHRASES = (
    "re-key the cache on the lockfile hash",
    "skip fork PRs in the review cycle",
    "record the stop reason in telemetry",
    "cap the drain batch size",
    "retry transient API errors with jitter",
    "split the matrix by changed plugin",
    "re-read threads after a force-push",
)

TEMPLATES = {
    "constraints": (
        "A {lane} PR counts as green only when ci-status passed on its current head; a pass on an older head does not count, so re-read the checks after every push (#{pr} showed it).",
        "Label a superseded PR do-not-merge before writing any explanation in its body; the gate reads only the label (applied to #{pr}).",
        "Lint Python through scripts/run-ruff.sh, never a bare ruff on PATH; the pinned version differs from the one {wf} would otherwise resolve.",
        "Every change lands through a PR from a feature branch named for its issue (#{issue}); nothing is pushed to main directly.",
        "Keep the {wf} concurrency group keyed by ref so a second run on one ref cancels the older one; dropping it doubled runner minutes on #{pr}.",
        "Every PR title is in Conventional Commits form; ci-status fails any other title, which cost a cycle on #{pr}.",
        "A changelog fragment under .changes/ ships with every plugin change, and {file} counts as plugin code.",
        "Do not widen a lane token's scope to fix a failing call; route the call through the existing App token instead (#{issue}).",
        "Scratch harnesses and run logs stay in .work/; commit only the conclusion to the doc or skill that uses it.",
        "{wf} runs on hosted runners only; the self-hosted pool is reserved for the nightly eval batch.",
        "Run the tests for {file} with pytest -q -p no:cacheprovider so no cache directory lands in the repo.",
        "Cap each drain cycle at {n} items; a larger batch starved the review lane on run {run}.",
        "A lane that meets a rate-limit marker stops and records the stop in its telemetry row instead of retrying in a loop.",
        "Keep {file} stdlib-only; the lane image has no pip step.",
    ),
    "findings": (
        "Run {run} of {wf} failed at cache restore because the key omitted the lockfile hash; re-keyed in #{pr}, and the next {n} runs restored in under ten seconds.",
        "The {lane} frontier double-counted items whose PR was reopened: the dedup key used the PR number alone; {file} now keys on number plus head {sha}.",
        "gh pr checks reports a skipped required check as passing; {wf} now fails the cycle when a required check is skipped (#{pr}).",
        "Telemetry rows written during a runner restart lost their exit field; {file} now flushes before acknowledging the restart signal.",
        "Bot-resolved review threads reopen after a force-push; the babysit cycle re-reads threads after every push (#{pr}).",
        "{wf} took {n} minutes on run {run} because the matrix fanned out per plugin; limiting it to changed plugins brought it to {m} minutes.",
        "The intake triage step skipped issues filed from a template with no labels; {file} now treats an empty label list as untriaged (#{issue}).",
    ),
    "decisions": (
        "Chose squash merges for {lane} PRs so each changelog fragment stays one commit on main (#{pr}).",
        "Kept {file} free of third-party imports so the lane runs on a bare runner image.",
        "Keyed the drain frontier by issue number rather than PR number, since one issue can carry two PRs (#{issue}).",
        "Stored lane telemetry as JSON lines in {file} instead of SQLite, because appends from two runners are safe with O_APPEND.",
        "{wf} reports and never mutates when it runs on a fork PR.",
        "Settled on {n} retries with jittered backoff for transient API errors; more retries hid a real outage on run {run}.",
        "Moved the {phrase} change into its own PR (#{pr}) so a revert stays one commit.",
    ),
    "side-effects": (
        "Opened #{pr} ({lane}: {phrase}) from feat/{slug}; head {sha}.",
        "Pushed {sha} to feat/{slug} for #{pr}; ci-status went green on run {run}.",
        "Filed #{issue} for the {wf} timeout seen on run {run}.",
        "#{pr} merged (squash) after ci-status went green on head {sha}.",
        "Applied do-not-merge to #{pr}, superseded by #{pr2}.",
        "Re-ran the failed {wf} job on run {run}; it passed on the second attempt.",
    ),
    "abandoned": (
        "Tried raising the {wf} timeout to cure the hang on run {run}; abandoned because the hang was a held lock, not slowness.",
        "Tried polling PR state every 30 seconds from the {lane} cycle; abandoned for one read per cycle because it spent the API budget.",
        "Tried one shared branch for all {lane} fixes; abandoned because one red PR blocked every other fix.",
        "Tried parsing gh table output in {file}; abandoned for --json fields after a gh release changed the column layout.",
        "Tried caching the frontier between cycles; abandoned because a stale frontier re-queued merged items (#{pr}).",
    ),
}
DETAILS = (
    "Verified again on run {run}.",
    "The diff is in #{pr}.",
    "Recorded in the lane telemetry for cycle {n}.",
    "Re-checked at head {sha}.",
    "The follow-up is tracked in #{issue}.",
    "No other lane was affected.",
    "The measurement came from {m} consecutive cycles.",
    "{file} carries the change.",
    "{wf} logs show it on run {run}.",
)
DID_TEMPLATES = (
    "merged #{pr} and #{pr2}, re-keyed the {wf} cache, and filed #{issue} for the timeout on run {run}",
    "landed the {phrase} change in #{pr}, re-ran {wf} on run {run}, and closed #{issue}",
    "rebased #{pr} on main, fixed the {file} test, and moved #{pr2} to green on head {sha}",
)
LEFT_TEMPLATES = (
    "#{pr2} still red on {wf}, #{issue} unanswered, and the {phrase} follow-up not started",
    "the {file} cleanup and the review on #{pr2} still open",
    "#{issue} waiting on a fresh run of {wf} and #{pr2} not rebased",
)


def _fields(key: str, lane: str) -> dict:
    return {
        "lane": lane,
        "pr": _num(key + "/pr", 4100, 4399),
        "pr2": _num(key + "/pr2", 4100, 4399),
        "issue": _num(key + "/issue", 4400, 4499),
        "run": _num(key + "/run", 81_000_000, 81_999_999),
        "wf": _pick(key + "/wf", WORKFLOWS),
        "file": _pick(key + "/file", FILES),
        "phrase": _pick(key + "/phrase", PHRASES),
        "slug": _pick(
            key + "/slug",
            ("cache-key", "fork-skip", "stop-reason", "batch-cap", "retry-jitter"),
        ),
        "sha": _sha(key + "/sha"),
        "n": _num(key + "/n", 3, 12),
        "m": _num(key + "/m", 13, 40),
    }


def _entry(slot: str, key: str, lane: str, width: int) -> str:
    text = _pick(key, TEMPLATES[slot]).format(**_fields(key, lane))
    extra = 0
    while len(text) < width:
        detail_key = f"{key}/d{extra}"
        text += " " + _pick(detail_key, DETAILS).format(**_fields(detail_key, lane))
        extra += 1
    return text


# --- the chain ------------------------------------------------------------------


def _when(pred: dict, hop: int) -> str:
    start = datetime.strptime(pred["start"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    stamp = start + timedelta(minutes=int(pred.get("hop_minutes", 240)) * (hop - 1))
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


def _session_id(case: str, hop: int) -> str:
    return str(uuid.uuid5(NAMESPACE, f"{case}/hop-{hop}"))


def _hot(pred: dict, hop: int, name: str, lane: str) -> list[str]:
    """A rewritten (hot) section's lines: the case's final-hop text at the newest hop,
    generic lane text before it."""
    final = pred.get("final") or {}
    if hop == int(pred["hops"]) and final.get(name):
        return [*final[name], *HOT_PADDING.get(name, ())]
    f = _fields(f"{lane}/{hop}/{name}", lane)
    generic = {
        "brief": [
            f"Written at hop {hop} against main at {f['sha']}; the {lane} queue has {f['n']} open items.",
            f"Next: get #{f['pr']} green on {f['wf']}, governed by Remaining actions.",
            "Read Constraints that must hold first.",
        ],
        "criteria": [
            f"Why: the {lane} lane exists so green PRs land without waiting on a person.",
            f"- [ ] #{f['pr']} merged with ci-status green on its head (gh pr view {f['pr']} --json state).",
            f"- [ ] {f['wf']} green on main for {f['n']} consecutive runs (gh run list --workflow {f['wf']}).",
        ],
        "environment": [
            f"Branch feat/{f['slug']} in the lane worktree; no services; no background tasks.",
            "TaskList: none in this session; nothing to recreate.",
        ],
        "file-roles": [
            f"{f['file']}: modified; carries the {f['phrase']} change.",
            "tests/test_cycle.py: test that must pass.",
        ],
        "remaining": [
            f"1. Get #{f['pr']} green on {f['wf']} and merge it.",
            f"2. Answer the review on #{f['pr2']}.",
            f"3. Close #{f['issue']} once run {f['run']} is re-run green.",
        ],
        "open-questions": [
            f"Does {f['wf']} still need the {f['n']}-minute timeout? Probe: gh run list --workflow {f['wf']}."
        ],
        "blockers": ["None. Nothing waits on an outside decision."],
        "skills": [f"/source-control:pull-request for #{f['pr']}."],
        "next": [
            f"Get #{f['pr']} green on {f['wf']}.",
            f"Answer the review on #{f['pr2']}.",
        ],
    }
    return generic[name]


def _did_left(pred: dict, hop: int, lane: str) -> tuple[str, str]:
    final = pred.get("final") or {}
    if hop == int(pred["hops"]) and final.get("did"):
        return final["did"], final["left"]
    did = "; then ".join(
        _pick(f"{lane}/{hop}/did{i}", DID_TEMPLATES).format(
            **_fields(f"{lane}/{hop}/did{i}", lane)
        )
        for i in range(2)
    )
    left = "; and ".join(
        _pick(f"{lane}/{hop}/left{i}", LEFT_TEMPLATES).format(
            **_fields(f"{lane}/{hop}/left{i}", lane)
        )
        for i in range(2)
    )
    return did, left


def _injections(pred: dict, hop: int, slot: str) -> tuple[list[str], list[str]]:
    first, last = [], []
    for item in pred.get("injections", []):
        if int(item["hop"]) == hop and item["section"] == slot:
            (first if item.get("position") == "first" else last).append(item["text"])
    return first, last


def _fill(path: Path, pred: dict, hop: int, width: int, lane: str) -> int:
    """Replace every FILL slot; return the characters of generated entry text."""
    generated = 0
    out: list[str] = []
    for line in path.read_text(encoding="utf-8").split("\n"):
        match = FILL_RE.search(line)
        if match is None:
            out.append(line)
            continue
        slot = match.group(1)
        prefix = line[: match.start()]
        if slot in ("goal-first", "goal-after", "below-rail"):
            continue
        if slot == "goal":
            date = pred["start"][:10]
            out.append(f"> {pred['goal']} (owner, {date})")
            if pred.get("vision"):
                out.append(f"> Vision: {pred['vision']} (owner, {date})")
        elif slot == "amended":
            out.append(prefix + "None.")
        elif slot == "opening-ask":
            out.extend(pred["opening_ask"].split("\n"))
        elif slot == "drift-check":
            out.append(
                prefix
                + "the first remaining action moves the lane toward the goal above."
            )
        elif slot == "did":
            did, left = _did_left(pred, hop, lane)
            rest = line[match.end() :]
            second = FILL_RE.search(rest)
            out.append(
                prefix + did + rest[: second.start()] + left + rest[second.end() :]
            )
        elif slot == "rescan":
            out.append(
                prefix
                + "the re-scan read the lossless on-disk transcript; no compaction occurred."
            )
        elif slot in (
            "brief",
            "criteria",
            "environment",
            "file-roles",
            "remaining",
            "open-questions",
            "blockers",
            "skills",
            "next",
        ):
            out.extend(_hot(pred, hop, slot, lane))
        else:
            base = slot[: -len("-new")] if slot.endswith("-new") else slot
            first, last = _injections(pred, hop, base)
            texts = []
            count, share = ENTRIES_PER_HOP[base]
            for i in range(count):
                key = f"{pred['topic']}/{hop}/{base}/{i}"
                text = _entry(base, key, lane, int(width * share))
                generated += len(text)
                texts.append(text)
            out.extend(f"- [h{hop}] {text}" for text in [*first, *texts, *last])
    path.write_text("\n".join(out), encoding="utf-8", newline="\n")
    return generated


def build_predecessor_chain(
    case_spec: dict, out_dir: Path, memory_dir: Path | None = None
) -> list[Path]:
    """Write the case's predecessor chain into `out_dir` (the run's repository) and
    return the hop files, oldest first. Raises SystemExit when `new` or `validate`
    refuses a hop."""
    token = _RESERVED.set(reserved_numbers(case_spec))
    try:
        return _build(case_spec, Path(out_dir), memory_dir)
    finally:
        _RESERVED.reset(token)


def _build(case_spec: dict, out_dir: Path, memory_dir: Path | None) -> list[Path]:
    pred = case_spec["seed"]["predecessor"]
    case = case_spec["name"]
    hops = int(pred["hops"])
    target = pred.get("target_bytes")
    lane = pred.get("lane", pred["topic"])
    out_dir = Path(out_dir)
    memory = Path(memory_dir) if memory_dir else out_dir / ".work"
    (memory / "handoffs").mkdir(parents=True, exist_ok=True)
    ignore = memory / ".gitignore"
    if not ignore.exists():
        ignore.write_text("*\n", encoding="utf-8", newline="\n")
    projects = memory / "predecessor-transcripts"
    (projects / "seed").mkdir(parents=True, exist_ok=True)

    files: list[Path] = []
    sizes: list[int] = []
    overheads: list[int] = []
    width = BASE_WIDTH
    base_chars = 0
    previous: Path | None = None
    for hop in range(1, hops + 1):
        session_id = _session_id(case, hop)
        (projects / "seed" / f"{session_id}.jsonl").write_text(
            "", encoding="utf-8", newline="\n"
        )
        args = [
            "new",
            "--topic",
            pred["topic"],
            "--memory-dir",
            str(memory),
            "--repo-root",
            str(out_dir),
            "--projects-root",
            str(projects),
            "--session-id",
            session_id,
            "--now",
            _when(pred, hop),
            # The audited chains are shape 2; the cases rebuild that shape.
            "--shape",
            "2",
        ]
        args += ["--previous", str(previous)] if previous else ["--no-previous"]
        made = run_save_point(args)
        if made.returncode != 0:
            raise SystemExit(
                f"{case}: `new` failed at hop {hop}: {made.stdout}{made.stderr}"
            )
        path = Path(made.stdout.strip())
        generated = _fill(path, pred, hop, width, lane)
        checked = run_save_point(
            [
                "validate",
                str(path),
                "--projects-root",
                str(projects),
                "--strict-transcript",
            ]
        )
        if checked.returncode != 0:
            raise SystemExit(f"{case}: hop {hop} does not validate:\n{checked.stdout}")
        files.append(path)
        sizes.append(path.stat().st_size)
        previous = path
        if hop == 1:
            base_chars = generated
        elif target and hop < hops:
            # Steer the entry width so the newest hop lands on target_bytes: the
            # growth not made of generated entries is measured, not assumed.
            overheads.append(sizes[-1] - sizes[-2] - generated)
            overhead = sorted(overheads)[len(overheads) // 2]
            need = (int(target) - sizes[-1]) / (hops - hop)
            scale = (need - overhead) / max(base_chars, 1)
            width = max(MIN_WIDTH, min(MAX_WIDTH, int(BASE_WIDTH * scale)))
    return files


# --- the seeded session -----------------------------------------------------------


def _numbered(lines: list[str], start: int) -> str:
    """Lines in the Read tool's `cat -n` form, numbered from `start` (1-based)."""
    return "\n".join(f"{start + i:>6}\t{line}" for i, line in enumerate(lines))


def _read(
    path: Path, lines: list[str], offset: int | None = None, limit: int | None = None
) -> dict:
    start = offset or 1
    end = len(lines) if limit is None else min(len(lines), start - 1 + limit)
    tool_input: dict = {"file_path": str(path)}
    if offset is not None:
        tool_input["offset"] = offset
    if limit is not None:
        tool_input["limit"] = limit
    return {
        "role": "tool",
        "name": "Read",
        "input": tool_input,
        "result": _numbered(lines[start - 1 : end], start),
    }


def _grep(
    path: Path,
    lines: list[str],
    fixed: list[str] | None,
    heading: bool,
    description: str,
) -> dict:
    if heading:
        command = f"grep -n '^## ' {path}"
        hits = [(i, line) for i, line in enumerate(lines, 1) if line.startswith("## ")]
    else:
        command = (
            "grep -nF " + " ".join(f"-e '{tag}'" for tag in fixed or []) + f" {path}"
        )
        hits = [
            (i, line)
            for i, line in enumerate(lines, 1)
            if any(t in line for t in fixed or [])
        ]
    return {
        "role": "tool",
        "name": "Bash",
        "input": {"command": command, "description": description},
        "result": "\n".join(f"{i}:{line}" for i, line in hits),
    }


def _section_span(
    lines: list[str], title: str, until: str | None = None
) -> tuple[int, int]:
    """1-based start line of `## title` and the line count up to the next heading
    (or up to `## until`)."""
    start = lines.index(f"## {title}") + 1
    stop_title = f"## {until}" if until else None
    for i in range(start, len(lines)):
        line = lines[i]
        if (stop_title and line == stop_title) or (
            not stop_title and line.startswith("## ")
        ):
            return start, i - start + 1
    return start, len(lines) - start + 1


def read_turns(path: Path, pattern: str | None = None) -> list[dict]:
    """The reads a real resume makes of one handoff (AUDIT.md Q2): a small file in one
    Read, a mid-size one in pages, a large one partially (a heading grep, the top 100
    lines, the hot block from Remaining actions to Prior sessions, the tail, and a
    grep for the two newest hop tags); `partial+constraints` adds a full read of
    Constraints, as the audited superseded-rule resume made."""
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    size = len(text.encode("utf-8"))
    pattern = pattern or (
        "whole" if size <= WHOLE_MAX else "paged" if size <= PAGED_MAX else "partial"
    )
    if pattern == "whole":
        return [_read(path, lines)]
    if pattern == "paged":
        return [
            _read(path, lines, offset=start, limit=PAGE_LINES)
            for start in range(1, len(lines) + 1, PAGE_LINES)
        ]
    if pattern not in ("partial", "partial+constraints"):
        raise ValueError(f"unknown read pattern {pattern!r}")
    hops = [int(h) for h in re.findall(r"\[h(\d+)\]", text)]
    newest = max(hops) if hops else 1
    tags = [f"[h{newest - 1}]", f"[h{newest}]"] if newest > 1 else [f"[h{newest}]"]
    turns = [
        _grep(path, lines, None, True, "List the handoff's section headings"),
        _read(path, lines, limit=TOP_LINES),
    ]
    if pattern == "partial+constraints":
        start, count = _section_span(lines, "Constraints that must hold")
        turns.append(_read(path, lines, offset=start, limit=count))
    start, count = _section_span(
        lines, "Remaining actions, in order", until="Prior sessions"
    )
    turns.append(_read(path, lines, offset=start, limit=count))
    turns.append(_read(path, lines, offset=max(1, len(lines) - TAIL_LINES + 1)))
    turns.append(_grep(path, lines, tags, False, "Find the newest hop entries"))
    return turns


def _expand(value, subs: dict):
    if isinstance(value, str):
        for key, sub in subs.items():
            value = value.replace("{" + key + "}", sub)
        return value
    if isinstance(value, list):
        return [_expand(v, subs) for v in value]
    if isinstance(value, dict):
        return {k: _expand(v, subs) for k, v in value.items()}
    return value


def seed_history(
    case_spec: dict, chain: list[Path], repo_root: Path | None = None
) -> list[dict]:
    """The session every arm's writer resumes from, as `resume_eval.render_history`
    turns. It opens with the newest handoff's pasted resume prompt, then the reads,
    then the case's work turns, and ends on an assistant turn; the harness sends
    `writer.interrupt` next. `{repo}` and `{handoff}` in work turns expand to the
    repository and the newest handoff's paths.

    Raises ValueError when an injection's `visible_in_reads` disagrees with the read
    slices, or when a turn the reads did not produce restates a hidden injection."""
    newest = Path(chain[-1])
    repo = Path(repo_root) if repo_root else newest.parents[2]
    seed = case_spec["seed"]
    paste = between_rails(newest.read_text(encoding="utf-8"))
    if paste is None:
        raise ValueError(f"{newest.name}: no resume region between rails")
    reads = read_turns(newest, (seed.get("reads") or {}).get("pattern"))
    subs = {"repo": str(repo), "handoff": str(newest)}
    history = seed.get("history") or {}
    work = _expand(list(history.get("work", [])), subs)
    turns = [{"role": "user", "text": paste}, *reads]
    turns.append({"role": "assistant", "text": _expand(history["after_reads"], subs)})
    turns += work
    if turns[-1]["role"] != "assistant":
        raise ValueError(f"{case_spec['name']}: history must end on an assistant turn")

    seen = "\n".join(turn["result"] for turn in reads)
    said = "\n".join(
        turn.get("text") or json.dumps(turn.get("input")) + str(turn.get("result"))
        for turn in turns
        if turn not in reads
    )
    for item in seed["predecessor"].get("injections", []):
        visible = item.get("visible_in_reads")
        if visible is None:
            continue
        if (item["text"] in seen) != bool(visible):
            raise ValueError(
                f"{case_spec['name']}: injection {item['id']!r} visible_in_reads={visible} "
                f"but the read slices {'show' if item['text'] in seen else 'miss'} it"
            )
        if not visible and item["text"] in said:
            raise ValueError(
                f"{case_spec['name']}: a work turn restates hidden injection {item['id']!r}"
            )
    return turns


def load_case(case_dir: Path) -> dict:
    """The case's `resume-eval.json`, with its directory recorded as `case_dir`."""
    case_dir = Path(case_dir)
    spec = json.loads((case_dir / CASE_FILE).read_text(encoding="utf-8"))
    spec["case_dir"] = str(case_dir)
    return spec
