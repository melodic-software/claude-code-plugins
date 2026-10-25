"""Tests for resume_cases.py. No test reaches the API or a model CLI; chains are built
through the real save_point.py, and read slices are checked against `cat -n` and
`grep` run on the generated file."""

import copy
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

import resume_cases
import resume_eval
from hop_chain import between_rails

EVALS = Path(__file__).resolve().parents[2] / "evals"
SAVE_POINT = Path(__file__).resolve().parents[1] / "save_point.py"
CASE_DIRS = sorted(p.parent for p in EVALS.glob("re-*/resume-eval.json"))
CASE_NAMES = [p.name for p in CASE_DIRS]

# AUDIT.md Q1 (chain growth, sizes) and Q2 (Read refuses a file over 256 KB).
READ_LIMIT = 256 * 1024
MEDIAN_GROWTH = (6_400, 7_000)
NEWEST_CHAIN_FILE = 370_324
CUMULATIVE_TITLES = (
    "Constraints that must hold",
    "Side effects already applied",
    "Decisions already settled",
    "Approaches tried and abandoned",
    "Findings that cost effort to discover",
    "Prior sessions",
)
CHECK_KINDS = {
    "gh_call_regex",
    "tool_command_regex",
    "text_regex",
    "file_regex",
    "file_rewritten",
    "edited_path_regex",
    "handoff_contains",
    "handoff_regex",
    "tool_target_count",
    "any_of",
}


@pytest.fixture(scope="session")
def built(tmp_path_factory):
    """Every case built once: {name: (spec, chain, history)}."""
    root = tmp_path_factory.mktemp("cases")
    out = {}
    for case_dir in CASE_DIRS:
        spec = resume_cases.load_case(case_dir)
        repo = root / spec["name"]
        repo.mkdir()
        chain = resume_cases.build_predecessor_chain(spec, repo)
        out[spec["name"]] = (spec, chain, resume_cases.seed_history(spec, chain))
    return out


def sections(path: Path) -> dict[str, str]:
    found: dict[str, list[str]] = {}
    title = None
    for line in path.read_text(encoding="utf-8").split("\n"):
        if line.startswith("## "):
            title = line[3:]
            found[title] = []
        elif title:
            found[title].append(line)
    return {k: "\n".join(v) for k, v in found.items()}


def test_seven_cases_are_committed():
    assert CASE_NAMES == sorted(
        [
            "re-skipped-rule",
            "re-superseded-rule",
            "re-stale-github-fact",
            "re-restated-preference",
            "re-archive-only-answer",
            "re-first-split-hop",
            "re-multi-hop",
        ]
    )


def test_same_spec_same_bytes(tmp_path):
    spec = resume_cases.load_case(EVALS / "re-stale-github-fact")
    repo = tmp_path / "repo"
    first = {
        p.name: p.read_bytes() for p in resume_cases.build_predecessor_chain(spec, repo)
    }
    shutil.rmtree(repo)
    second = {
        p.name: p.read_bytes() for p in resume_cases.build_predecessor_chain(spec, repo)
    }
    assert first == second and len(first) == 5


@pytest.mark.parametrize("name", CASE_NAMES)
def test_every_hop_validates_and_the_next_hop_builds_clean(built, name, tmp_path):
    _, chain, _ = built[name]
    projects = chain[0].parents[1] / "predecessor-transcripts"
    for path in chain:
        done = subprocess.run(
            [
                sys.executable,
                str(SAVE_POINT),
                "validate",
                str(path),
                "--projects-root",
                str(projects),
                "--strict-transcript",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        assert done.returncode == 0, done.stdout
        assert "secret-shaped" not in done.stdout
    # A successor built on the newest file must not see a failed predecessor, which
    # would stamp every carried entry UNVERIFIED and change the before arm.
    (projects / "seed" / "11111111-2222-4333-8444-555555555555.jsonl").write_text(
        "", encoding="utf-8"
    )
    shutil.copytree(chain[0].parent, tmp_path / "mem" / "handoffs")
    (tmp_path / "mem" / ".gitignore").write_text("*\n", encoding="utf-8")
    made = subprocess.run(
        [
            sys.executable,
            str(SAVE_POINT),
            "new",
            "--topic",
            "probe",
            "--memory-dir",
            str(tmp_path / "mem"),
            "--repo-root",
            str(tmp_path),
            "--projects-root",
            str(projects),
            "--session-id",
            "11111111-2222-4333-8444-555555555555",
            "--previous",
            str(tmp_path / "mem" / "handoffs" / chain[-1].name),
            "--now",
            "2027-01-01T00:00:00Z",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    assert made.returncode == 0, made.stderr
    assert "UNVERIFIED" not in Path(made.stdout.strip()).read_text(encoding="utf-8")


@pytest.mark.parametrize("name", CASE_NAMES)
def test_sizes_follow_the_audit(built, name):
    spec, chain, _ = built[name]
    pred = spec["seed"]["predecessor"]
    sizes = [p.stat().st_size for p in chain]
    assert len(chain) == pred["hops"]
    if pred.get("target_bytes"):
        assert abs(sizes[-1] - pred["target_bytes"]) <= 0.10 * pred["target_bytes"]
    growth = sorted(b - a for a, b in zip(sizes, sizes[1:]))
    if len(growth) >= 4:
        median = growth[len(growth) // 2]
        assert 0.9 * MEDIAN_GROWTH[0] <= median <= 1.1 * MEDIAN_GROWTH[1]
        assert all(step > 0 for step in growth)
    if len(chain) >= 18:
        found = sections(chain[-1])
        share = sum(len(found[t]) for t in CUMULATIVE_TITLES) / sizes[-1]
        assert share >= 0.80


def test_audited_size_buckets(built):
    size = {name: chain[-1].stat().st_size for name, (_, chain, _) in built.items()}
    assert size["re-skipped-rule"] > READ_LIMIT
    assert 100 * 1024 <= size["re-superseded-rule"] <= READ_LIMIT
    assert (
        abs(size["re-first-split-hop"] - NEWEST_CHAIN_FILE) <= 0.10 * NEWEST_CHAIN_FILE
    )


@pytest.mark.parametrize("name", CASE_NAMES)
def test_history_reads_are_real_slices(built, name):
    _, chain, history = built[name]
    newest = chain[-1]
    assert history[0] == {
        "role": "user",
        "text": between_rails(newest.read_text(encoding="utf-8")),
    }
    assert history[-1]["role"] == "assistant"
    reads = [
        t
        for t in history
        if t["role"] == "tool" and str(newest) in json.dumps(t["input"])
    ]
    assert reads
    for turn in reads:
        if turn["name"] == "Read":
            start = turn["input"].get("offset", 1)
            limit = turn["input"].get("limit")
            end = "$" if limit is None else str(start + limit - 1)
            numbered = subprocess.run(
                ["cat", "-n", str(newest)],
                capture_output=True,
                text=True,
                encoding="utf-8",
            ).stdout
            want = subprocess.run(
                ["sed", "-n", f"{start},{end}p"],
                input=numbered,
                capture_output=True,
                text=True,
                encoding="utf-8",
            ).stdout
        else:
            want = subprocess.run(
                ["bash", "-c", turn["input"]["command"]],
                capture_output=True,
                text=True,
                encoding="utf-8",
            ).stdout
        assert turn["result"] + "\n" == want


@pytest.mark.parametrize("name", CASE_NAMES)
def test_injections_land_where_the_spec_says(built, name):
    spec, chain, history = built[name]
    newest = sections(chain[-1])
    seen = "\n".join(t["result"] for t in history if t["role"] == "tool")
    for item in spec["seed"]["predecessor"].get("injections", []):
        hop = item["hop"]
        title = resume_cases.SECTION_SLOTS[item["section"]]
        assert f"- [h{hop}] {item['text']}" in newest[title].split("\n")
        assert item["text"] in chain[hop - 1].read_text(encoding="utf-8")
        if hop > 1:
            assert item["text"] not in chain[hop - 2].read_text(encoding="utf-8")
        if item.get("visible_in_reads") is not None:
            assert (item["text"] in seen) is item["visible_in_reads"], item["id"]


def test_the_skipped_rule_is_outside_everything_the_session_saw(built):
    spec, chain, history = built["re-skipped-rule"]
    hidden = [
        i["text"]
        for i in spec["seed"]["predecessor"]["injections"]
        if i.get("visible_in_reads") is False
    ]
    assert len(hidden) == 2
    everything = json.dumps(history)
    for text in hidden:
        assert text in chain[-1].read_text(encoding="utf-8")
        assert json.dumps(text)[1:-1] not in everything


def test_a_wrong_visibility_claim_is_refused(built):
    spec, chain, _ = built["re-skipped-rule"]
    wrong = copy.deepcopy(spec)
    wrong["seed"]["predecessor"]["injections"][0]["visible_in_reads"] = True
    with pytest.raises(ValueError, match="governing-rule"):
        resume_cases.seed_history(wrong, chain)


def test_a_work_turn_restating_a_hidden_rule_is_refused(built):
    spec, chain, _ = built["re-skipped-rule"]
    leaky = copy.deepcopy(spec)
    rule = leaky["seed"]["predecessor"]["injections"][0]["text"]
    leaky["seed"]["history"]["work"].append({"role": "assistant", "text": rule})
    with pytest.raises(ValueError, match="restates hidden"):
        resume_cases.seed_history(leaky, chain)


def _kinds(check):
    yield check["kind"]
    for inner in check.get("checks", []):
        yield from _kinds(inner)


@pytest.mark.parametrize("case_dir", CASE_DIRS, ids=CASE_NAMES)
def test_case_probes_are_well_formed(case_dir):
    spec = resume_cases.load_case(case_dir)
    assert spec["name"] == case_dir.name and "resume-eval" in spec["tags"]
    assert spec["maps_to"]
    assert spec["writer"]["interrupt"]["text"]
    probes = spec["probes"]
    assert len({p["id"] for p in probes}) == len(probes)
    assert {p["type"] for p in probes} == {
        "recall",
        "artifact",
        "continuation",
        "decision",
    }
    for probe in probes:
        if probe["type"] in ("continuation", "decision"):
            assert probe["grade"] in ("must-act", "must-not-do"), probe["id"]
        if probe["grade"] == "text":
            assert probe["question"] and probe["criteria"].startswith("PASS only if")
            sample = json.loads(
                (case_dir / "samples" / f"{probe['id']}.json").read_text(
                    encoding="utf-8"
                )
            )
            assert len(sample["pass"]) >= 3 and len(sample["fail"]) >= 3
        else:
            assert set(_kinds(probe["check"])) <= CHECK_KINDS, probe["id"]
    assert any(p["id"] == "recall-no-recap-request" for p in probes)
    for grade in ("must-act", "must-not-do"):
        assert any(
            p["grade"] == grade and p["type"] in ("continuation", "decision")
            for p in probes
        )


SAMPLE_KEYS = {
    "answer",
    "texts",
    "commands",
    "reads",
    "edits",
    "gh_calls",
    "files",
    "handoff",
}


def _sample_context(item: dict, repo: Path) -> resume_eval.GradeContext:
    """A grading context from one sample: `answer` or `texts` (reader text), `commands`
    (shell commands), `reads` (Read targets), `edits` (edited paths), `gh_calls`, `files` ({path: content} in
    the workspace) and `handoff` (the produced handoff's text)."""
    blocks = [{"type": "text", "text": t} for t in item.get("texts", [])]
    if "answer" in item:
        blocks.append({"type": "text", "text": item["answer"]})
    blocks += [
        {"type": "tool_use", "name": "Bash", "input": {"command": c}}
        for c in item.get("commands", [])
    ]
    blocks += [
        {"type": "tool_use", "name": "Read", "input": {"file_path": p}}
        for p in item.get("reads", [])
    ]
    blocks += [
        {"type": "tool_use", "name": "Edit", "input": {"file_path": p}}
        for p in item.get("edits", [])
    ]
    for rel, content in item.get("files", {}).items():
        (repo / rel).parent.mkdir(parents=True, exist_ok=True)
        (repo / rel).write_text(content, encoding="utf-8")
    return resume_eval.GradeContext(
        reader="claude-code",
        events=[{"type": "assistant", "message": {"content": blocks}}],
        gh_calls=item.get("gh_calls", []),
        repo=repo,
        seeded={},
        handoff_text=item.get("handoff"),
    )


@pytest.mark.parametrize("case_dir", CASE_DIRS, ids=CASE_NAMES)
def test_check_samples_grade_as_labeled(case_dir, tmp_path):
    """Every text_regex probe has samples, and any other graded check may: each pass
    sample passes the probe through the real grader and each fail sample fails it."""
    spec = resume_cases.load_case(case_dir)
    for probe in spec["probes"]:
        if probe["grade"] == "text":
            continue
        path = case_dir / "samples" / f"{probe['id']}.json"
        if probe["check"]["kind"] != "text_regex" and not path.is_file():
            continue
        sample = json.loads(path.read_text(encoding="utf-8"))
        assert sample["pass"] and sample["fail"], probe["id"]
        for label, items in sample.items():
            for index, item in enumerate(items):
                assert set(item) - {"why"} <= SAMPLE_KEYS and set(item) - {"why"}, item
                repo = tmp_path / probe["id"] / f"{label}-{index}"
                repo.mkdir(parents=True)
                ctx = _sample_context(item, repo)
                passed = resume_eval.probe_passes(probe, ctx)
                assert passed is (label == "pass"), (probe["id"], item)


@pytest.mark.parametrize("name", CASE_NAMES)
def test_generated_lines_never_name_a_trap_number(built, name):
    """A generic line naming a case's PR, issue or run (say `do-not-merge on #4231`)
    could flip a trap, so only lines the spec wrote may carry one."""
    spec, chain, _ = built[name]
    reserved = resume_cases.reserved_numbers(spec)
    assert reserved
    written = json.dumps(spec, ensure_ascii=False)
    number = re.compile(r"(?<![0-9a-f-])(\d{4}|\d{8})(?![0-9a-f-])")
    for path in chain:
        for line in path.read_text(encoding="utf-8").split("\n"):
            if not {int(n) for n in number.findall(line)} & reserved:
                continue
            body = re.sub(r"^- \[h\d+\] ", "", line)
            parts = (
                body[len("did: ") :].split(" · left: ")
                if body.startswith("did: ")
                else [body]
            )
            assert all(
                json.dumps(p, ensure_ascii=False)[1:-1] in written for p in parts
            ), line


def test_a_steered_build_is_deterministic(tmp_path):
    spec = resume_cases.load_case(EVALS / "re-superseded-rule")
    repo = tmp_path / "repo"
    first = {
        p.name: p.read_bytes() for p in resume_cases.build_predecessor_chain(spec, repo)
    }
    shutil.rmtree(repo)
    second = {
        p.name: p.read_bytes() for p in resume_cases.build_predecessor_chain(spec, repo)
    }
    assert first == second and len(first) == 22
