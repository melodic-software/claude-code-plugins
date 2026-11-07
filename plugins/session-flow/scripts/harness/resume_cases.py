#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Case seeding for the resume-accuracy eval (PLAN.md Phase 1).

A case directory under `plugins/session-flow/evals/re-<name>/` holds one
`resume-eval.json`. This module turns its `seed` into what every arm starts from:

- `build_predecessor_chain` writes the case's handoff chain through the real
  `save_point.py new`, hop by hop, with deterministic lane-like content, plus the
  case's injected entries at their hops. Shape 2, sized like the audited chains, is
  the default; `"shape": 3` builds hot files and hop files filled through
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
    between_rails,
    frontmatter_value,
    run_save_point,
)

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


def _injection_items(pred: dict, hop: int, slot: str) -> list[dict]:
    """The case's injections into `slot` at `hop`, the `first` ones ahead of the rest."""
    items = [
        item
        for item in pred.get("injections", [])
        if int(item["hop"]) == hop and item["section"] == slot
    ]
    return [i for i in items if i.get("position") == "first"] + [
        i for i in items if i.get("position") != "first"
    ]


def _injections(pred: dict, hop: int, slot: str) -> tuple[list[str], list[str]]:
    items = _injection_items(pred, hop, slot)
    return (
        [i["text"] for i in items if i.get("position") == "first"],
        [i["text"] for i in items if i.get("position") != "first"],
    )


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
SLOT_RE = re.compile(r"<!-- FILL: (\S+) — (optional:)?")


def _check_shape3_spec(pred: dict, hops: int) -> None:
    for item in pred.get("injections", []):
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
    start = lines.index(f"## {title}") + 1
    end = next(
        (i for i in range(start, len(lines)) if lines[i].startswith("## ")), len(lines)
    )
    return lines[start:end]


def _ordinal(lines: list[str], match, text: str, what: str) -> int:
    """1-based ordinal of the line holding `text` among the lines `match` accepts."""
    first = text.split("\n")[0]
    hits = [line for line in lines if match(line)]
    for i, line in enumerate(hits, 1):
        if first in line:
            return i
    raise ValueError(f"{what}: {first[:60]!r} is not in the file it retires from")


def _fill_3(path: Path, pred: dict, hop: int, lane: str, live: dict) -> None:
    """Fill a shape-3 skeleton through `save_point.py fill`. `live` carries, hop to hop,
    the id-carrying lines Open questions and Decisions in force rewrite each hop and the
    ref each injection was given."""
    from save_point import AMENDMENT_RE  # hop_chain put the scripts dir on sys.path

    hops = int(pred["hops"])
    final = (pred.get("final") or {}) if hop == hops else {}
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
        items = _injection_items(pred, hop, section)
        firsts = [i for i in items if i.get("position") == "first"]
        rest = [i for i in items if i.get("position") != "first"]
        out = []
        for item in firsts:
            live["refs"][item["id"]] = ref = new_id(ID_PREFIX[section])
            out.append(f"- {ref} {item['text']}")
        out += [f"- {new_id(ID_PREFIX[section])} {text}" for text in generated]
        for item in rest:
            live["refs"][item["id"]] = ref = new_id(ID_PREFIX[section])
            out.append(f"- {ref} {item['text']}")
        return out

    f = _fields(f"{lane}/{hop}/shape3", lane)
    values: dict[str, str] = {}

    amendments = [
        i["text"]
        if hop == 1 and n == 0
        else f"**Amended (owner, {date}):** {i['text']}"
        for n, i in enumerate(_injection_items(pred, hop, "amendment"))
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

    rules = (
        [
            _entry(
                "constraints",
                f"{pred['topic']}/1/rules/{i}",
                lane,
                SHAPE3_RULE_WIDTH,
            )
            for i in range(SHAPE3_RULES)
        ]
        if hop == 1
        else []
    )
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
    live["open-questions"] += id_lines("open-questions", questions)
    live["open-questions"] += [
        f"- {new_id('Q')} {text}" for text in final.get("open-questions", [])
    ]
    values["open-questions"] = "\n".join(live["open-questions"])

    # Each hop settles a new batch cap and retires the last one, so every hop file
    # carries a retire listing and Review before you continue a pointer to it.
    retire: list[dict] = []
    decisions = (
        [
            _pick(f"{lane}/1/decision/{i}", TEMPLATES["decisions"]).format(
                **_fields(f"{lane}/1/decision/{i}", lane)
            )
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
    live["decisions"] += added
    live["decisions"] += [
        f"- {new_id('D')} {text}" for text in final.get("decisions", [])
    ]
    values["decisions"] = "\n".join(live["decisions"])
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
                goal, AMENDMENT_RE.match, item["text"], item["id"]
            )
        elif section == "trail":
            tag = f"[h{item['hop']}]"
            ref = f"{tag}#%d" % _ordinal(
                trail_lines,
                lambda line: line.startswith(f"- {tag} "),
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
        filled = run_save_point(["fill", str(path), "--slots", str(slots_file)])
    if filled.returncode != 0:
        raise SystemExit(f"`fill` failed at hop {hop}: {filled.stdout}{filled.stderr}")


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
    # The audited chains are shape 2, so the cases rebuild that shape unless one opts
    # into shape 3.
    shape = int(pred.get("shape", 2))
    if shape not in (2, 3):
        raise ValueError(f"{case}: predecessor shape {shape} is not 2 or 3")
    if shape == 3:
        if target:
            raise ValueError(f"{case}: target_bytes steers shape-2 chains only")
        _check_shape3_spec(pred, hops)
    live: dict = {"refs": {}, "open-questions": [], "decisions": [], "rolling": None}
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
        if shape == 3:
            _fill_3(path, pred, hop, lane, live)
            generated = 0
        else:
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
        # Read results number each line, so a multi-line entry is seen line by line.
        lines = item["text"].split("\n")
        shown = all(line in seen for line in lines)
        if shown != bool(visible):
            raise ValueError(
                f"{case_spec['name']}: injection {item['id']!r} visible_in_reads={visible} "
                f"but the read slices {'show' if shown else 'miss'} it"
            )
        if not visible and any(line in said for line in lines):
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
