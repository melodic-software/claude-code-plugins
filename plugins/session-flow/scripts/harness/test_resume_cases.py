# test-scope: plugins/session-flow/evals/*/samples/*.json

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


CHECKOUT_ARM = "after"


@pytest.fixture(scope="session")
def built(tmp_path_factory):
    root = tmp_path_factory.mktemp("cases")
    out = {}
    for case_dir in CASE_DIRS:
        spec = resume_cases.load_case(case_dir)
        repo = root / spec["name"]
        repo.mkdir()
        chain = resume_cases.build_predecessor_chain(
            spec, repo, save_point=SAVE_POINT, arm=CHECKOUT_ARM
        )
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


def test_the_committed_cases_are_the_known_set():
    assert CASE_NAMES == sorted(
        [
            "re-decision-trimmed-to-fit",
            "re-rule-after-size-fail",
            "re-retired-id-reused",
            "re-oversized-brief",
            "re-shape3-near-cap",
            "re-late-event",
            "re-transition-2-to-4",
            "re-transition-3-to-4",
            "re-retired-amendment",
            "re-writer-keeps-binding-amendment",
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
    spec, chain, _ = built[name]
    projects = chain[0].parents[1] / "predecessor-transcripts"
    stated = resume_cases._expected_fail(
        spec["seed"]["predecessor"], spec["name"], len(chain), CHECKOUT_ARM
    )
    for hop, path in enumerate(chain, 1):
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
        if hop in stated:
            fails = [
                ln.removeprefix("FAIL: ")
                for ln in done.stdout.splitlines()
                if ln.startswith("FAIL: ")
            ]
            assert done.returncode == 1 and fails, done.stdout
            assert all(stated[hop].search(ln) for ln in fails), done.stdout
        else:
            assert done.returncode == 0, done.stdout
        assert "secret-shaped" not in done.stdout
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
    if resume_cases.seed_shape(spec, SAVE_POINT) >= 3:
        return
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


SHAPE3_TITLES = {
    "amendment": ("Original goal", "**Amended"),
    "trail": ("Direction changes", "- [h"),
    "rules": ("Current rules", "- [R"),
    "open-questions": ("Open questions", "- [Q"),
    "decisions": ("Decisions in force", "- [D"),
}


def _landed_3(item: dict, chain: list[Path], newest: dict[str, str]) -> None:
    title, prefix = SHAPE3_TITLES[item["section"]]
    retire = item.get("retire")
    if retire is None:
        first = item["text"].split("\n")[0]
        lines = newest[title].split("\n")
        assert any(
            line.startswith(prefix) and line.endswith(first) for line in lines
        ), item["id"]
        return
    assert item["text"] not in chain[-1].read_text(encoding="utf-8"), item["id"]
    hop_files = list((chain[0].parent / "archive").glob(f"*/h{retire['hop']}-*.md"))
    assert len(hop_files) == 1, hop_files
    listed = hop_files[0].read_text(encoding="utf-8")
    assert f"{item['text']}\nRetired: {retire['reason']}" in listed, item["id"]


@pytest.mark.parametrize("name", CASE_NAMES)
def test_injections_land_where_the_spec_says(built, name):
    spec, chain, history = built[name]
    newest = sections(chain[-1])
    seen = "\n".join(t["result"] for t in history if t["role"] == "tool")
    shape = resume_cases.seed_shape(spec, SAVE_POINT)
    for item in spec["seed"]["predecessor"].get("injections", []):
        hop = item["hop"]
        if shape >= 3:
            _landed_3(item, chain, newest)
        else:
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
    spec, chain, _ = built[name]
    reserved = resume_cases.reserved_numbers(spec)
    assert reserved
    written = json.dumps(spec, ensure_ascii=False)
    number = re.compile(r"(?<![0-9a-f-])(\d{4}|\d{8})(?![0-9a-f-])")
    for path in chain:
        for line in path.read_text(encoding="utf-8").split("\n"):
            if not {int(n) for n in number.findall(line)} & reserved:
                continue
            body = re.sub(r"^- \[[hRQD]\d+\] ", "", line)
            parts = (
                body[len("did: ") :].split(" · left: ")
                if body.startswith("did: ")
                else [body]
            )
            assert all(
                json.dumps(p, ensure_ascii=False)[1:-1] in written for p in parts
            ), line


def _stub_copy(root: Path, body: str) -> Path:
    script = root / "scripts" / "save_point.py"
    script.parent.mkdir(parents=True)
    script.write_text(body, encoding="utf-8")
    return script


def test_a_case_without_a_shape_seeds_in_the_shape_its_arm_copy_writes(tmp_path):
    spec = resume_cases.load_case(EVALS / "re-stale-github-fact")
    spec["seed"]["predecessor"].pop("shape", None)
    three = _stub_copy(tmp_path / "three", "HANDOFF_SHAPE = 3\n")
    assert resume_cases.seed_shape(spec, three) == 3
    spec["seed"]["predecessor"]["shape"] = 2
    assert resume_cases.seed_shape(spec, three) == 2


def test_shape_6_is_an_unsupported_seed_shape(tmp_path):
    spec = resume_cases.load_case(EVALS / "re-stale-github-fact")
    spec["seed"]["predecessor"].pop("shape", None)
    six = _stub_copy(tmp_path / "six", "X = 1\nHANDOFF_SHAPE = 6\n")
    repo = tmp_path / "repo"
    with pytest.raises(ValueError, match="unsupported seed shape 6"):
        resume_cases.build_predecessor_chain(spec, repo, save_point=six)
    assert not (repo / ".work" / "handoffs").exists()


def test_a_shape5_chain_carries_reminders_in_place_of_pending_commands(tmp_path):
    spec = _shape3_target_spec(20_000)
    spec["seed"]["predecessor"]["shape"] = 5
    chain = resume_cases.build_predecessor_chain(
        spec, tmp_path / "repo", arm=CHECKOUT_ARM
    )
    text = chain[-1].read_text(encoding="utf-8")
    assert "handoff_shape: 5" in text, "the newest hop is written as shape 5"
    assert "\n## Reminders\n" in text, "shape 5 has a Reminders section"
    assert "\n## Pending commands\n" not in text, "Reminders replace Pending commands"


def test_the_chain_is_built_by_the_pinned_save_point(tmp_path):
    spec = resume_cases.load_case(EVALS / "re-stale-github-fact")
    spec["seed"]["predecessor"]["shape"] = 2
    stub = _stub_copy(
        tmp_path / "stub",
        "import sys\nHANDOFF_SHAPE = 3\nprint('pinned stub ran')\nsys.exit(1)\n",
    )
    with pytest.raises(SystemExit, match="pinned stub ran"):
        resume_cases.build_predecessor_chain(spec, tmp_path / "repo", save_point=stub)


@pytest.mark.parametrize("name", ["re-stale-github-fact", "re-retired-amendment"])
def test_the_seed_hash_ignores_where_the_run_lives_and_sees_any_content_change(
    tmp_path, name
):
    spec = resume_cases.load_case(EVALS / name)
    here, there = tmp_path / "runs" / "0" / "repo", tmp_path / "elsewhere" / "repo"
    resume_cases.build_predecessor_chain(spec, here)
    resume_cases.build_predecessor_chain(spec, there)
    assert resume_cases.seed_hash(here) == resume_cases.seed_hash(there)
    changed = copy.deepcopy(spec)
    changed["seed"]["predecessor"]["goal"] += " Then stop."
    other = tmp_path / "changed" / "repo"
    resume_cases.build_predecessor_chain(changed, other)
    assert resume_cases.seed_hash(other) != resume_cases.seed_hash(here)


def _shape3_target_spec(target: int) -> dict:
    spec = copy.deepcopy(resume_cases.load_case(EVALS / "re-retired-amendment"))
    spec["seed"]["predecessor"].update(hops=8, target_bytes=target, shape=3)
    return spec


def test_a_shape3_chain_is_steered_to_its_target_hot_file_size(tmp_path):
    target = 20_000
    chain = resume_cases.build_predecessor_chain(
        _shape3_target_spec(target), tmp_path / "repo"
    )
    newest = chain[-1]
    assert "handoff_shape: 3" in newest.read_text(encoding="utf-8")
    assert abs(newest.stat().st_size - target) <= 0.10 * target


def test_a_shape4_chain_is_steered_to_its_target_hot_file_size(tmp_path):
    target = 20_000
    spec = _shape3_target_spec(target)
    spec["seed"]["predecessor"]["shape"] = 4
    chain = resume_cases.build_predecessor_chain(
        spec, tmp_path / "repo", arm=CHECKOUT_ARM
    )
    newest = chain[-1]
    assert "handoff_shape: 4" in newest.read_text(encoding="utf-8")
    assert abs(newest.stat().st_size - target) <= 0.10 * target
    hop_files = list((newest.parent / "archive").glob("*/h*-*.md"))
    assert len(hop_files) == len(chain)


def test_a_steered_shape3_build_is_deterministic(tmp_path):
    spec = _shape3_target_spec(20_000)
    repo = tmp_path / "repo"
    first = {
        p.name: p.read_bytes() for p in resume_cases.build_predecessor_chain(spec, repo)
    }
    shutil.rmtree(repo)
    again = {
        p.name: p.read_bytes() for p in resume_cases.build_predecessor_chain(spec, repo)
    }
    assert first == again and len(first) == 8


def test_a_case_tag_is_same_or_boundary(tmp_path):
    spec = json.loads((EVALS / "re-stale-github-fact" / "resume-eval.json").read_text())
    for value in ("same", "boundary", "compaction"):
        case_dir = tmp_path / value
        case_dir.mkdir()
        tagged = {**spec, "task_relation": value}
        (case_dir / "resume-eval.json").write_text(json.dumps(tagged), encoding="utf-8")
        if value == "compaction":
            with pytest.raises(ValueError, match="task_relation"):
                resume_cases.load_case(case_dir)
        else:
            assert resume_cases.load_case(case_dir)["task_relation"] == value


OVERSIZE_DECISION = "Cap the drain at the measured batch size. " * 700


def _oversize_spec(expected_fail: list[dict] | None) -> dict:
    spec = copy.deepcopy(resume_cases.load_case(EVALS / "re-retired-amendment"))
    pred = spec["seed"]["predecessor"]
    pred["injections"] = [
        {
            "id": "oversize",
            "hop": 2,
            "section": "decisions",
            "text": OVERSIZE_DECISION.strip(),
            "retire": {"hop": 3, "reason": "moved to docs/lane-runbook.md"},
        }
    ]
    pred["final"] = {}
    pred["shape"] = 3
    if expected_fail is not None:
        pred["expected_fail"] = expected_fail
    return spec


def test_a_hop_stated_to_fail_builds_on_when_it_fails_as_stated(tmp_path):
    spec = _oversize_spec([{"hop": 2, "fail": r"^size: \d+ bytes is over"}])
    chain = resume_cases.build_predecessor_chain(spec, tmp_path / "repo")
    assert len(chain) == spec["seed"]["predecessor"]["hops"]
    assert chain[1].stat().st_size > 24_600
    assert chain[-1].stat().st_size < 24_600


REFUSING_FILL = f"""import json
import runpy
import sys
from pathlib import Path

REAL = {str(SAVE_POINT)!r}
argv = sys.argv[1:]
if argv[:1] == ["fill"] and "{OVERSIZE_DECISION[:20]}" in Path(argv[3]).read_text(encoding="utf-8"):
    marker = Path(__file__).with_name(Path(argv[1]).name + ".refused")
    if not marker.exists():
        marker.write_text("1", encoding="utf-8")
        print("error: slot 'brief' is 9 bytes, 8 bytes over its 1-byte budget; nothing written.")
        sys.exit(1)
sys.argv = [REAL, *argv]
runpy.run_path(REAL, run_name="__main__")
"""


def test_a_stated_hop_whose_fill_refuses_on_budget_writes_on_the_second_call(tmp_path):
    spec = _oversize_spec([{"hop": 2, "fail": r"^size: \d+ bytes is over"}])
    stub = _stub_copy(tmp_path / "stub", REFUSING_FILL)
    chain = resume_cases.build_predecessor_chain(
        spec, tmp_path / "repo", save_point=stub
    )
    assert len(chain) == spec["seed"]["predecessor"]["hops"]
    assert chain[1].stat().st_size > 24_600


def test_an_unstated_hop_whose_fill_refuses_on_budget_stops_the_build(tmp_path):
    spec = _oversize_spec(None)
    stub = _stub_copy(tmp_path / "stub", REFUSING_FILL)
    with pytest.raises(SystemExit, match="`fill` failed at hop 2"):
        resume_cases.build_predecessor_chain(spec, tmp_path / "repo", save_point=stub)


def test_an_unstated_failing_hop_still_stops_the_build(tmp_path):
    with pytest.raises(SystemExit, match="hop 2 does not validate"):
        resume_cases.build_predecessor_chain(_oversize_spec(None), tmp_path / "repo")


def test_a_hop_failing_other_than_stated_stops_the_build(tmp_path):
    spec = _oversize_spec([{"hop": 2, "fail": r"^order:"}])
    with pytest.raises(SystemExit, match="hop 2 was stated to FAIL"):
        resume_cases.build_predecessor_chain(spec, tmp_path / "repo")


def test_a_hop_stated_to_fail_that_validates_stops_the_build(tmp_path):
    spec = _oversize_spec([{"hop": 3, "fail": r"^size:"}])
    spec["seed"]["predecessor"]["expected_fail"].append(
        {"hop": 2, "fail": r"^size: \d+ bytes is over"}
    )
    with pytest.raises(SystemExit, match="hop 3 was stated to FAIL"):
        resume_cases.build_predecessor_chain(spec, tmp_path / "repo")


def test_a_stated_failure_naming_arms_holds_only_for_those_arms(tmp_path):
    spec = _oversize_spec([{"hop": 2, "fail": r"^size:", "arms": ["after"]}])
    chain = resume_cases.build_predecessor_chain(spec, tmp_path / "after", arm="after")
    assert len(chain) == spec["seed"]["predecessor"]["hops"]
    with pytest.raises(SystemExit, match="hop 2 does not validate"):
        resume_cases.build_predecessor_chain(spec, tmp_path / "before", arm="before")


def test_an_amend_lands_on_the_newest_hop_through_save_point(tmp_path):
    spec = copy.deepcopy(resume_cases.load_case(EVALS / "re-retired-amendment"))
    late = "1. Answer the changes-requested review on PR #4318 before anything else."
    spec["seed"]["predecessor"]["amend"] = {
        "sections": {"Remaining actions, in order": late},
        "next": ["Answer the review on PR #4318."],
    }
    chain = resume_cases.build_predecessor_chain(spec, tmp_path / "repo")
    newest = sections(chain[-1])
    assert late in newest["Remaining actions, in order"]
    assert "Answer the review on PR #4318." in newest["Resume prompt"]
    assert late not in chain[-2].read_text(encoding="utf-8")


def _reuse_spec(retire_hop: int) -> dict:
    spec = copy.deepcopy(resume_cases.load_case(EVALS / "re-retired-amendment"))
    pred = spec["seed"]["predecessor"]
    pred["injections"] = [
        {
            "id": "old-rule",
            "hop": 1,
            "section": "rules",
            "text": "Export files are written in UTC dates only.",
            "retire": {
                "hop": retire_hop,
                "reason": "dropped at hop 2: dates follow the ledger's zone",
            },
        },
        {
            "id": "new-rule",
            "hop": 3,
            "section": "rules",
            "text": "Refund rows sort after the sale they reverse.",
            "reuse": "old-rule",
        },
    ]
    pred["final"] = {}
    pred["expected_fail"] = [
        {"hop": hop, "fail": "id_reuse", "arms": ["after"]}
        for hop in range(3, pred["hops"] + 1)
    ]
    return spec


def test_a_reuse_injection_takes_the_id_a_retired_injection_held(tmp_path):
    chain = resume_cases.build_predecessor_chain(
        _reuse_spec(2), tmp_path / "repo", arm=CHECKOUT_ARM
    )
    hop_file = next((chain[0].parent / "archive").glob("*/h2-*.md"))
    old = re.search(
        r"^- (\[R\d+\]) Export files are written in UTC dates only\.$",
        hop_file.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    assert old, "the retired rule is listed in hop 2's file"
    rules = sections(chain[-1])["Current rules"]
    assert f"- {old.group(1)} Refund rows sort after the sale they reverse." in rules
    assert "UTC dates only" not in rules


def test_a_reuse_of_an_entry_not_yet_retired_is_refused(tmp_path):
    with pytest.raises(ValueError, match="reuse"):
        resume_cases.build_predecessor_chain(_reuse_spec(4), tmp_path / "repo")


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


@pytest.mark.parametrize("case_dir", CASE_DIRS, ids=CASE_NAMES)
def test_every_open_pr_names_a_head_branch_seeded_on_origin(case_dir):
    spec = resume_cases.load_case(case_dir)
    refs = set(spec["seed"].get("remote_refs", []))
    for answer in spec["seed"]["gh_fixture"].get("responses", []):
        if "pr view" not in answer["match"].replace("\\s+", " "):
            continue
        pr = json.loads(answer["stdout"])
        if pr.get("state") != "OPEN":
            continue
        head = pr.get("headRefName")
        assert head, f"#{pr['number']} is open but its pr view names no headRefName"
        assert f"refs/heads/{head}" in refs
        assert f"refs/pull/{pr['number']}/head" in refs


@pytest.mark.parametrize(
    ("name", "present", "absent", "story"),
    [
        (
            "re-decision-trimmed-to-fit",
            {"refs/heads/release/2.8"},
            r"v?2\.8\.\d",
            "release/2.8 is cut; 2.8.0 not tagged yet",
        ),
        (
            "re-late-event",
            {"refs/heads/feat/stop-reason", "refs/pull/4460/head"},
            None,
            "Branch feat/stop-reason in the lane worktree; PR #4460 is open",
        ),
        (
            "re-multi-hop",
            {"refs/heads/feat/stop-reason"},
            None,
            "Branch feat/stop-reason in the lane worktree",
        ),
        ("re-retired-id-reused", set(), r"v?1\.8\.0", "release 1.8.0 not cut"),
        ("re-skipped-rule", set(), r"v?2\.14\.0", "the v2.14.0 tag is not cut yet"),
    ],
)
def test_remote_refs_follow_the_story(name, present, absent, story):
    refs = set(resume_cases.load_case(EVALS / name)["seed"].get("remote_refs", []))
    assert present <= refs, f"{name}: the story says {story}"
    if absent:
        assert not [ref for ref in refs if re.search(absent, ref)], (
            f"{name}: the story says {story}"
        )
