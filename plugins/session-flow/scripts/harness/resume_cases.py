#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Case seeding for the resume-accuracy eval (PLAN.md Phase 1).

A case directory under `plugins/session-flow/evals/re-<name>/` holds one
`resume-eval.json`. This module turns its `seed` into what every arm starts from:

- `build_predecessor_chain` writes the case's handoff chain through the real
  `save_point.py new`, hop by hop, with deterministic lane-like content, plus the
  case's injected entries at their hops. Shape 2, sized like the audited chains, is
  the default; `"shape": 3` or `4` builds hot files and hop files filled through
  `save_point.py fill`, whose `retire` moves each injection with a `retire` hop
  into that hop's file. Every hop passes `save_point.py validate --strict-transcript`.
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
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from hop_chain import (  # noqa: E402
    FILL_RE,
    SAVE_POINT,
    frontmatter_value,
)
from resume_history import _section_span, read_turns, seed_history  # noqa: E402,F401

CASE_FILE = "resume-eval.json"
SEED_SHAPES = (2, 3, 4)
TASK_RELATIONS = ("same", "boundary")
HANDOFF_SHAPE_RE = re.compile(r"^HANDOFF_SHAPE = (\d+)$", re.MULTILINE)
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
# Sections rewritten whole at every hop, filled by `_hot`.
HOT_SLOTS = (
    "brief",
    "criteria",
    "environment",
    "file-roles",
    "remaining",
    "open-questions",
    "blockers",
    "skills",
    "next",
)


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


def _render(key: str, templates, lane: str) -> str:
    return _pick(key, templates).format(**_fields(key, lane))


def _entry(slot: str, key: str, lane: str, width: int) -> str:
    text = _render(key, TEMPLATES[slot], lane)
    extra = 0
    while len(text) < width:
        text += " " + _render(f"{key}/d{extra}", DETAILS, lane)
        extra += 1
    return text


def _when(pred: dict, hop: int) -> str:
    start = datetime.strptime(pred["start"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    stamp = start + timedelta(minutes=int(pred.get("hop_minutes", 240)) * (hop - 1))
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


def _session_id(case: str, hop: int) -> str:
    return str(uuid.uuid5(NAMESPACE, f"{case}/hop-{hop}"))


def _final(pred: dict, hop: int) -> dict:
    """The case's final-hop text at the newest hop, else nothing."""
    return (pred.get("final") or {}) if hop == int(pred["hops"]) else {}


def _hot(pred: dict, hop: int, name: str, lane: str) -> list[str]:
    """A rewritten (hot) section's lines: the case's final-hop text at the newest hop,
    generic lane text before it."""
    final = _final(pred, hop)
    if final.get(name):
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
    final = _final(pred, hop)
    if final.get("did"):
        return final["did"], final["left"]
    did = "; then ".join(
        _render(f"{lane}/{hop}/did{i}", DID_TEMPLATES, lane) for i in range(2)
    )
    left = "; and ".join(
        _render(f"{lane}/{hop}/left{i}", LEFT_TEMPLATES, lane) for i in range(2)
    )
    return did, left


def _injection_items(pred: dict, hop: int, slot: str) -> tuple[list[dict], list[dict]]:
    """The case's injections into `slot` at `hop`: the `first` ones, then the rest."""
    items = [
        item
        for item in pred.get("injections", [])
        if int(item["hop"]) == hop and item["section"] == slot
    ]
    return (
        [i for i in items if i.get("position") == "first"],
        [i for i in items if i.get("position") != "first"],
    )


def _injections(pred: dict, hop: int, slot: str) -> tuple[list[str], list[str]]:
    first, rest = _injection_items(pred, hop, slot)
    return [i["text"] for i in first], [i["text"] for i in rest]


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
        elif slot in HOT_SLOTS:
            out.extend(_hot(pred, hop, slot, lane))
        else:
            base = slot.removesuffix("-new")
            first, last = _injections(pred, hop, base)
            count, share = ENTRIES_PER_HOP[base]
            key = f"{pred['topic']}/{hop}/{base}"
            texts = [
                _entry(base, f"{key}/{i}", lane, int(width * share))
                for i in range(count)
            ]
            generated += sum(map(len, texts))
            out.extend(f"- [h{hop}] {text}" for text in [*first, *texts, *last])
    path.write_text("\n".join(out), encoding="utf-8", newline="\n")
    return generated


# --- shape 3 ---------------------------------------------------------------------
#
# A shape-3 predecessor is filled through `save_point.py fill`, so its retirements are
# the script's own: an injection's `retire` names the hop that retires it, and `fill`
# moves the entry into that hop's file under its retire heading and points Review
# before you continue at it.

SHAPE3_SECTIONS = ("amendment", "trail", "rules", "open-questions", "decisions")
ID_PREFIX = {"rules": "R", "open-questions": "Q", "decisions": "D"}
SHAPE3_RULES = 3
SHAPE3_RULE_WIDTH = 200
SHAPE3_STEERED_RULES = 2
SLOT_RE = re.compile(r"<!-- FILL: (\S+) — (optional:)?")


def _check_shape3_spec(pred: dict, hops: int) -> None:
    by_id = {item["id"]: item for item in pred.get("injections", [])}
    for item in pred.get("injections", []):
        held = by_id.get(item.get("reuse", ""), {})
        if "reuse" in item and not (
            held.get("section") == item["section"] in ID_PREFIX
            and int((held.get("retire") or {}).get("hop", hops + 1)) < int(item["hop"])
        ):
            raise ValueError(
                f"injection {item['id']!r}: reuse names an injection in the same id section retired before hop {item['hop']}"
            )
        if item["section"] not in SHAPE3_SECTIONS:
            raise ValueError(
                f"injection {item['id']!r}: section {item['section']!r} is not a shape-3 target {SHAPE3_SECTIONS}"
            )
        if item["section"] == "amendment" and any(
            not line.strip() or line.startswith("**")
            for line in item["text"].split("\n")[1:]
        ):
            raise ValueError(
                f"injection {item['id']!r}: an amendment's continuation lines are non-blank and never start with '**', or the unit splits"
            )
        retire = item.get("retire")
        if retire is None:
            continue
        reason = str(retire.get("reason", ""))
        if not int(item["hop"]) < int(retire["hop"]) <= hops:
            raise ValueError(
                f"injection {item['id']!r}: retire hop {retire['hop']} must follow hop {item['hop']} and be at most {hops}"
            )
        if not reason.strip() or "\n" in reason:
            raise ValueError(
                f"injection {item['id']!r}: a retire reason is one non-empty line"
            )


def _slots(path: Path) -> dict[str, bool]:
    """Slot name to whether it is optional, from the skeleton `new` wrote."""
    return {
        m.group(1): bool(m.group(2))
        for m in SLOT_RE.finditer(path.read_text(encoding="utf-8"))
    }


def _section_body(text: str, title: str) -> list[str]:
    lines = text.split("\n")
    start, count = _section_span(lines, title)
    return lines[start : start + count - 1]


def _ordinal(lines: list[str], body, text: str, what: str) -> int:
    """1-based ordinal, among the lines `body` maps to a string, of the one line whose
    body is exactly `text`'s first line."""
    first = text.split("\n")[0]
    bodies = [b for b in map(body, lines) if b is not None]
    hits = [i for i, b in enumerate(bodies, 1) if b == first]
    if len(hits) != 1:
        raise ValueError(
            f"{what}: {len(hits)} entries read {first[:60]!r} in the file it retires from; want 1"
        )
    return hits[0]


def _fill_3(
    path: Path,
    pred: dict,
    hop: int,
    lane: str,
    live: dict,
    script: Path,
    steer_count: int = 0,
    stated: bool = False,
) -> int:
    """Fill a shape-3 skeleton through `save_point.py fill`; return the characters of
    generated rule text. `live` carries, hop to hop, the id-carrying lines of Open
    questions and Decisions in force and the ref each injection was given. A hop after
    the first adds `steer_count` generated rules; rules stay in the hot file, so their
    count steers its size."""
    from save_point import AMENDMENT_RE  # hop_chain put the scripts dir on sys.path

    final = _final(pred, hop)
    date = _when(pred, hop)[:10]
    slots = _slots(path)
    floors = {
        prefix: int(frontmatter_value(path, key))
        for prefix, key in (
            ("R", "next_rule_id"),
            ("Q", "next_question_id"),
            ("D", "next_decision_id"),
        )
    }

    def new_id(prefix: str) -> str:
        n = floors[prefix]
        floors[prefix] += 1
        return f"[{prefix}{n}]"

    def id_lines(section: str, generated: list[str]) -> list[str]:
        """This hop's new entries for an id section: injections around generated text."""
        prefix = ID_PREFIX[section]
        firsts, rest = _injection_items(pred, hop, section)

        def injected(item: dict) -> str:
            ref = live["refs"][item["reuse"]] if "reuse" in item else new_id(prefix)
            live["refs"][item["id"]] = ref
            return f"- {ref} {item['text']}"

        head = [injected(item) for item in firsts]
        middle = [f"- {new_id(prefix)} {text}" for text in generated]
        return head + middle + [injected(item) for item in rest]

    f = _fields(f"{lane}/{hop}/shape3", lane)
    values: dict[str, str] = {}

    firsts, rest = _injection_items(pred, hop, "amendment")
    amendments = [
        i["text"]
        if hop == 1 and n == 0
        else f"**Amended (owner, {date}):** {i['text']}"
        for n, i in enumerate([*firsts, *rest])
    ]
    if hop == 1:
        values["goal"] = f"> {pred['goal']} (owner, {pred['start'][:10]})"
        values["intent"] = pred.get("intent") or "None stated."
        values["vision"] = pred.get("vision") or "None stated."
        values["amended"] = "\n".join(amendments) or "None."
        values["opening-ask"] = pred["opening_ask"]
    elif amendments:
        values["goal-new"] = "\n".join(amendments)

    trail = (
        [f"start: the {lane} work on the goal above (owner-directed: the opening ask)"]
        if hop == 1
        else [
            f"moved to the {f['phrase']} change (agent-initiated: {f['wf']} run {f['run']} showed it)"
        ]
    )
    first, last = _injections(pred, hop, "trail")
    values["trail" if hop == 1 else "trail-new"] = "\n".join(
        f"- [h{hop}] {text}" for text in [*first, *trail, *last]
    )

    if hop == 1:
        rules = [
            _entry(
                "constraints", f"{pred['topic']}/1/rules/{i}", lane, SHAPE3_RULE_WIDTH
            )
            for i in range(SHAPE3_RULES)
        ]
    else:
        rules = [
            _entry("constraints", f"{pred['topic']}/{hop}/rules/{i}", lane, BASE_WIDTH)
            for i in range(steer_count)
        ]
    rule_lines = id_lines("rules", rules)
    if hop == 1:
        values["rules"] = "\n".join(rule_lines)
        values["preferences"] = "None. No standing preference is pending promotion."
    elif rule_lines:
        values["rules-new"] = "\n".join(rule_lines)

    questions = (
        [
            f"Does {f['wf']} still need its {f['n']}-minute timeout? Options: keep it, or cut it to {f['n'] - 1}; recommendation: keep it until {f['m']} runs pass; unblocks the drain cap."
        ]
        if hop == 1
        else []
    )

    def put(section: str, added: list[str]) -> None:
        """A section `new` carried off disk takes only this hop's new lines."""
        live[section] += added
        if f"{section}-new" not in slots:
            values[section] = "\n".join(live[section])
        elif added:
            values[f"{section}-new"] = "\n".join(added)

    put(
        "open-questions",
        id_lines("open-questions", questions)
        + [f"- {new_id('Q')} {text}" for text in final.get("open-questions", [])],
    )

    # Each hop settles a new batch cap and retires the last one, so every hop file
    # carries a retire listing and Review before you continue a pointer to it.
    retire: list[dict] = []
    decisions = (
        [
            _render(f"{lane}/1/decision/{i}", TEMPLATES["decisions"], lane)
            for i in range(2)
        ]
        if hop == 1
        else []
    )
    rolling = f"Cap each drain batch at {f['n']} items from hop {hop} on (measured on run {f['run']})."
    added = id_lines("decisions", [*decisions, rolling])
    rolling_line = next(line for line in added if line.endswith(rolling))
    old = live["rolling"]
    if old:
        retire.append(
            {
                "ref": old.split(" ", 2)[1],
                "reason": f"superseded by {rolling_line.split(' ', 2)[1]} at hop {hop}",
            }
        )
    live["rolling"] = rolling_line
    put(
        "decisions",
        added + [f"- {new_id('D')} {text}" for text in final.get("decisions", [])],
    )
    if old:
        live["decisions"].remove(old)

    for name in ("brief", "criteria", "remaining", "environment", "skills", "next"):
        values[name] = "\n".join(_hot(pred, hop, name, lane))
    values["brief"] = values["brief"].replace(
        "Read Constraints that must hold first.", "Read Current rules first."
    )
    values["review"] = "\n".join(
        final.get("review")
        or [
            "- Read Current rules first.",
            "- Re-read the queue: gh pr list --label lane-queue --json number,title,headRefName.",
        ]
    )
    values["observations"] = "\n".join(
        final.get("observations")
        or [
            f"- The {lane} queue held {f['n']} open items at hop {hop}; detail stays in this hop's file."
        ]
    )
    values["commands"] = "None. No command waits on the user."
    values["did"], values["left"] = _did_left(pred, hop, lane)
    values["rescan"] = (
        "the re-scan read the lossless on-disk transcript; no compaction occurred."
    )

    # Ordinals count in the file as `fill` writes it, before any retirement.
    text = path.read_text(encoding="utf-8")
    goal = [
        new
        for line in _section_body(text, "Original goal")
        for new in (
            values.get("goal-new", "").split("\n")
            if "<!-- FILL: goal-new " in line
            else [line]
        )
    ]
    trail_lines = _section_body(text, "Direction changes")
    for item in pred.get("injections", []):
        if int((item.get("retire") or {}).get("hop", 0)) != hop:
            continue
        section = item["section"]
        if section == "amendment":
            ref = "amendment#%d" % _ordinal(
                goal,
                lambda line: (
                    line[m.end() :].strip() if (m := AMENDMENT_RE.match(line)) else None
                ),
                item["text"],
                item["id"],
            )
        elif section == "trail":
            tag = f"- [h{item['hop']}] "
            ref = f"[h{item['hop']}]#%d" % _ordinal(
                trail_lines,
                lambda line: line[len(tag) :] if line.startswith(tag) else None,
                item["text"],
                item["id"],
            )
        else:
            ref = live["refs"][item["id"]]
            if section in live:
                live[section] = [
                    line for line in live[section] if line.split(" ", 2)[1] != ref
                ]
        retire.append({"ref": ref, "reason": item["retire"]["reason"]})
    if retire:
        values["retire"] = retire  # type: ignore[assignment]
    for name in [n for n in values if n != "retire" and n not in slots]:
        raise ValueError(f"hop {hop}: generated slot {name!r} is not in the skeleton")

    with tempfile.TemporaryDirectory(prefix="resume-fill-") as tmp:
        slots_file = Path(tmp) / "slots.json"
        slots_file.write_text(json.dumps(values), encoding="utf-8")
        fill = ["fill", str(path), "--slots", str(slots_file)]
        filled = _run(script, fill)
        if (
            filled.returncode != 0
            and stated
            and "over its" in filled.stdout + filled.stderr
            and "budget" in filled.stdout + filled.stderr
        ):
            filled = _run(script, fill)
    if filled.returncode != 0:
        raise SystemExit(f"`fill` failed at hop {hop}: {filled.stdout}{filled.stderr}")
    return sum(map(len, rules)) if hop > 1 else 0


def copy_shape(save_point: Path) -> int:
    """The `HANDOFF_SHAPE` a plugin copy's `save_point.py` writes, read from its source
    so a second copy never shadows the imported one."""
    match = HANDOFF_SHAPE_RE.search(Path(save_point).read_text(encoding="utf-8"))
    if match is None:
        raise ValueError(f"{save_point}: no `HANDOFF_SHAPE = <n>` line")
    return int(match.group(1))


def seed_shape(case_spec: dict, save_point: Path | None) -> int:
    """The case's explicit `shape`, else the shape `save_point` writes (this
    checkout's when None, the script the build then runs)."""
    explicit = case_spec["seed"]["predecessor"].get("shape")
    if explicit is not None:
        return int(explicit)
    return copy_shape(save_point or SAVE_POINT)


def seed_hash(out_dir: Path, memory_dir: Path | None = None) -> str:
    """sha256 over every file the chain build wrote under `<memory>/handoffs`, with
    `out_dir` written as `{repo}`, so two runs of one case and arm compare equal."""
    root = Path(out_dir)
    handoffs = (Path(memory_dir) if memory_dir else root / ".work") / "handoffs"
    digest = hashlib.sha256()
    for path in sorted(p for p in handoffs.rglob("*") if p.is_file()):
        text = path.read_text(encoding="utf-8").replace(str(root), "{repo}")
        digest.update(path.relative_to(handoffs).as_posix().encode("utf-8") + b"\0")
        digest.update(text.encode("utf-8") + b"\0")
    return digest.hexdigest()


def _expected_fail(
    pred: dict, case: str, hops: int, arm: str | None
) -> dict[int, re.Pattern[str]]:
    """`expected_fail` as {hop: pattern}: that hop must FAIL `validate`, and every one
    of its FAIL lines must match the pattern. An entry naming `arms` holds only there."""
    stated: dict[int, re.Pattern[str]] = {}
    for item in pred.get("expected_fail", []):
        if "arms" in item and arm not in item["arms"]:
            continue
        hop, pattern = int(item["hop"]), str(item.get("fail") or "")
        if not 1 <= hop <= hops or not pattern.strip() or hop in stated:
            raise ValueError(
                f"{case}: expected_fail {item!r} needs one entry per hop in 1..{hops} with a non-empty `fail` pattern"
            )
        stated[hop] = re.compile(pattern)
    return stated


def _run(script: Path, args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-X", "utf8", str(script), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )


def build_predecessor_chain(
    case_spec: dict,
    out_dir: Path,
    memory_dir: Path | None = None,
    *,
    save_point: Path | None = None,
    arm: str | None = None,
) -> list[Path]:
    """Write the case's predecessor chain into `out_dir` (the run's repository) with
    `save_point` (an arm copy's script; this checkout's when None) for `arm` and return
    the hop files, oldest first. Raises SystemExit when `new` or `validate` refuses a hop."""
    token = _RESERVED.set(reserved_numbers(case_spec))
    try:
        return _build(case_spec, Path(out_dir), memory_dir, save_point, arm)
    finally:
        _RESERVED.reset(token)


def _build(
    case_spec: dict,
    out_dir: Path,
    memory_dir: Path | None,
    save_point: Path | None,
    arm: str | None,
) -> list[Path]:
    pred = case_spec["seed"]["predecessor"]
    case = case_spec["name"]
    hops = int(pred["hops"])
    target = pred.get("target_bytes")
    lane = pred.get("lane", pred["topic"])
    shape = seed_shape(case_spec, save_point)
    script = Path(save_point) if save_point else SAVE_POINT

    def run_save_point(args: list[str]) -> subprocess.CompletedProcess[str]:
        return _run(script, args)

    if shape not in SEED_SHAPES:
        raise ValueError(
            f"{case}: unsupported seed shape {shape}; the seeder builds {SEED_SHAPES}"
        )
    if shape >= 3:
        _check_shape3_spec(pred, hops)
    expected_fail = _expected_fail(pred, case, hops, arm)
    live: dict = {"refs": {}, "open-questions": [], "decisions": [], "rolling": None}
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
    rule_count = SHAPE3_STEERED_RULES if target else 0
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
            "--shape",
            str(shape),
        ]
        args += ["--previous", str(previous)] if previous else ["--no-previous"]
        made = run_save_point(args)
        if made.returncode != 0:
            raise SystemExit(
                f"{case}: `new` failed at hop {hop}: {made.stdout}{made.stderr}"
            )
        path = Path(made.stdout.strip())
        if shape >= 3:
            generated = _fill_3(
                path, pred, hop, lane, live, script, rule_count, hop in expected_fail
            )
        else:
            generated = _fill(path, pred, hop, width, lane)
        if hop == hops and pred.get("amend"):
            amend_file = path.with_suffix(".amend.json")
            amend_file.write_text(json.dumps(pred["amend"]), encoding="utf-8")
            amended = run_save_point(
                [
                    "amend",
                    str(path),
                    "--json",
                    str(amend_file),
                    "--now",
                    _when(pred, hop),
                ]
            )
            amend_file.unlink()
            if amended.returncode != 0:
                raise SystemExit(
                    f"{case}: `amend` failed: {amended.stdout}{amended.stderr}"
                )
        checked = run_save_point(
            [
                "validate",
                str(path),
                "--projects-root",
                str(projects),
                "--strict-transcript",
            ]
        )
        stated = expected_fail.get(hop)
        if stated is None and checked.returncode != 0:
            raise SystemExit(f"{case}: hop {hop} does not validate:\n{checked.stdout}")
        fails = [
            line.removeprefix("FAIL: ")
            for line in checked.stdout.splitlines()
            if line.startswith("FAIL: ")
        ]
        if stated is not None and (
            checked.returncode == 0
            or not fails
            or not all(stated.search(text) for text in fails)
        ):
            raise SystemExit(
                f"{case}: hop {hop} was stated to FAIL matching {stated.pattern!r}, but validate printed:\n{checked.stdout}"
            )
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
            if shape >= 3:
                per_rule = generated / rule_count if rule_count else BASE_WIDTH
                rule_count = max(0, round((need - overhead) / per_rule))
            else:
                scale = (need - overhead) / max(base_chars, 1)
                width = max(MIN_WIDTH, min(MAX_WIDTH, int(BASE_WIDTH * scale)))
    return files


def load_case(case_dir: Path) -> dict:
    """The case's `resume-eval.json`, with its directory recorded as `case_dir`."""
    case_dir = Path(case_dir)
    spec = json.loads((case_dir / CASE_FILE).read_text(encoding="utf-8"))
    relation = spec.get("task_relation")
    if relation is not None and relation not in TASK_RELATIONS:
        raise ValueError(
            f"{case_dir.name}: task_relation {relation!r} is not one of {TASK_RELATIONS}"
        )
    spec["case_dir"] = str(case_dir)
    return spec
