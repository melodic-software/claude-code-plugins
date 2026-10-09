"""Contract tests for friction.py, and for the `friction` block collect.py writes, by subprocess.

Fixture `fixtures/friction/` is synthetic. `proj-f/sess-f1` (interactive, 2026-09-10) holds, in its
main transcript: a classifier denial ([Git Destructive]), a hook denial from the `shellguard` plugin,
one prompt the person approved, an ask answered "yes, go with recommended", a hand-off answered
"done", one `!` command, a correction, a 400 s `gh run watch`, a `sleep 30` and an interrupt, with
900 s of turn time. Its subagent (`general-purpose`) holds a deny-rule denial and a classifier denial
([Self-Modification]). `proj-f/sess-f2` (headless, 2026-09-12) holds two rule denials, one of them
also listed in the closing `result` record's `permission_denials`. `proj-g/sess-g1` (2026-08-01)
holds one approved prompt.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
COLLECT = SCRIPTS.parents[1] / "audit-sessions" / "scripts" / "collect.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "friction"
WINDOW = ("--since", "2026-09-01", "--until", "2026-09-30")
HOOK_KEY = "denied/hook/shellguard/BLOCKED: file write through the shell. Use the Write tool."


def run(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True, encoding="utf-8", timeout=120)


def friction(*args: str) -> subprocess.CompletedProcess[str]:
    return run(SCRIPTS / "friction.py", *args)


def data_of(result: subprocess.CompletedProcess[str]) -> dict:
    return json.loads(result.stdout)["data"]


def copy_projects(dest: Path, tmp_path: Path, *projects: str) -> Path:
    """Copy fixture projects under `dest`, pointing each project's `__CWD__` at its own directory."""
    for name in projects:
        shutil.copytree(FIXTURES / name, dest / name)
        cwd = tmp_path / "work" / {"proj-f": "alpha", "proj-g": "beta"}[name]
        cwd.mkdir(parents=True, exist_ok=True)
        for path in (dest / name).rglob("*.jsonl"):
            path.write_text(path.read_text(encoding="utf-8").replace("__CWD__", cwd.as_posix()), encoding="utf-8", newline="\n")
    return dest


@pytest.fixture
def store(tmp_path: Path) -> Path:
    root = copy_projects(tmp_path / "projects", tmp_path, "proj-f", "proj-g")
    data_dir = tmp_path / "data"
    done = run(COLLECT, "collect", "--data-dir", str(data_dir), "--projects-root", str(root))
    assert done.returncode == 0, done.stdout + done.stderr
    return data_dir


def stored(data_dir: Path, session: str) -> dict:
    path = next((data_dir / "audit-sessions" / "store" / "v1" / "sessions").glob(f"p-*/{session}.json"))
    return json.loads(path.read_text(encoding="utf-8"))


def test_collect_writes_the_friction_block(store):
    block = stored(store, "sess-f1")["friction"]
    assert block["counts"] == {
        "main": {
            "denied/classifier/Git Destructive": 1,
            HOOK_KEY: 1,
            "prompt-approved": 1,
            "agent-ask/approve": 1,
            "handoff/other": 1,
            "user-command": 1,
            "correction": 1,
            "interrupt": 1,
        },
        "sub": {"denied/rule/rule": 1, "denied/classifier/Self-Modification": 1},
    }
    assert block["perf"] == {
        "tool_waits_gt5m": 1,
        "polling_calls": 1,
        "ci_wait_calls": 1,
        "merge_conflicts": 0,
        "max_tool_wait_s": 400,
    }
    assert block["events_dropped"] == 0
    first = block["events"][0]
    assert (first["kind"], first["cause"], first["tool"], first["shape"], first["flags"], first["no_prompt_host"]) == (
        "denied", "classifier", "Bash", "git push", ["cd-prefix"], False,
    )
    sub = [e for e in block["events"] if e["side"] == "sub"]
    assert [(e["agent"], e["cause"]) for e in sub] == [("general-purpose", "rule"), ("general-purpose", "classifier")]
    assert "claude-config" in sub[1]["flags"]


def test_headless_result_denials_count_once_per_call(store):
    block = stored(store, "sess-f2")["friction"]
    assert block["counts"] == {"main": {"denied/rule/rule": 2}, "sub": {}}
    assert {e["source"] for e in block["events"]} == {"config", "result"}
    assert all(e["no_prompt_host"] for e in block["events"])


def test_mine_scopes_to_the_window_and_hints_classes(store):
    result = friction("mine", "--data-dir", str(store), *WINDOW)
    assert result.returncode == 0, result.stdout + result.stderr
    data = data_of(result)
    assert data["sessions"] == 2
    assert data["session_classes"] == {"interactive": 1, "automated": 1}
    assert data["active_hours"] == 0.25
    rows = {(r["side"], r["key"]): r for r in data["rows"]}
    assert (rows[("main", "denied/rule/rule")]["count"], rows[("main", "denied/rule/rule")]["sessions"]) == (2, 1)
    assert rows[("main", "prompt-approved")]["per_active_hour"] == 4.0
    assert data["class_totals"] == {"D": 7, "C": 1, "B": 2, "A": 2}
    assert len(data["events"]) == 12


def test_mine_project_and_session_filters(store):
    by_project = data_of(friction("mine", "--data-dir", str(store), "--since", "2026-07-01", "--project", "beta"))
    assert by_project["sessions"] == 1
    assert [(r["key"], r["count"]) for r in by_project["rows"]] == [("prompt-approved", 1)]
    by_session = data_of(friction("mine", "--data-dir", str(store), *WINDOW, "--session", "sess-f2"))
    assert by_session["sessions"] == 1


def test_mine_without_a_store_is_an_error(tmp_path):
    result = friction("mine", "--data-dir", str(tmp_path / "empty"))
    assert result.returncode == 2
    assert json.loads(result.stdout)["status"] == "error"


def test_source_dirs_collect_into_their_own_store(tmp_path):
    machine = copy_projects(tmp_path / "machine", tmp_path, "proj-g")
    extra = copy_projects(tmp_path / "extra", tmp_path, "proj-f")
    data_dir = tmp_path / "data"
    assert run(COLLECT, "collect", "--data-dir", str(data_dir), "--projects-root", str(machine)).returncode == 0
    data = data_of(friction("mine", "--data-dir", str(data_dir), "--since", "2026-07-01", "--source", str(extra)))
    assert data["sessions"] == 3
    assert data["sources"][0]["status"] == "pass"
    assert len(list((data_dir / "audit-sessions" / "store" / "v1" / "sessions").glob("p-*/*.json"))) == 1


def test_source_collect_uses_the_given_excerpt_limits(tmp_path):
    machine = copy_projects(tmp_path / "machine", tmp_path, "proj-g")
    extra = copy_projects(tmp_path / "extra", tmp_path, "proj-f")
    data_dir = tmp_path / "data"
    assert run(COLLECT, "collect", "--data-dir", str(data_dir), "--projects-root", str(machine)).returncode == 0
    data = data_of(friction("mine", "--data-dir", str(data_dir), "--since", "2026-07-01", "--source", str(extra),
                            "--excerpt-chars", "0", "--excerpt-words", "5"))
    assert data["sources"][0]["status"] == "pass"
    assert stored(Path(data["sources"][0]["store"]), "sess-f1")["excerpt_limits"] == {"chars": 0, "words": 5}


MERGE = """CAVEAT: synthetic
effective allow scopes=user precedence_basis=uncontested Bash(gh run watch *)
effective ask scopes=project precedence_basis=uncontested Bash(rm -rf *)
effective deny scopes=user precedence_basis=evaluation-order Bash(git branch -D *)
inert allow scopes=user outranked_by=deny Bash(git branch -D *)
"""


def test_cause_maps_events_to_rules(store, tmp_path):
    mined = tmp_path / "friction.json"
    assert friction("mine", "--data-dir", str(store), *WINDOW, "--out", str(mined)).returncode == 0
    merge = tmp_path / "merge.txt"
    merge.write_text(MERGE, encoding="utf-8")
    result = friction("cause", "--friction", str(mined), "--merge", str(merge))
    assert result.returncode == 0, result.stdout
    data = data_of(result)
    assert data["rules_read"] == 3
    hints = {(g["shape"], g["hint"]) for g in data["groups"]}
    assert hints == {
        ("git push", "classifier"),
        ("cat", "hook"),
        ("npm test", "no-allow-rule"),
        ("git branch", "deny-rule"),
        ("Edit .json", "classifier"),
        ("rm", "ask-without-prompt-host"),
        ("git push", "rule-unmatched"),
    }
    deny = next(g for g in data["groups"] if g["hint"] == "deny-rule")
    assert deny["rules"] == [{"kind": "deny", "rule": "Bash(git branch -D *)", "scopes": "user"}]


def test_cause_without_merge_input_warns(store, tmp_path):
    mined = tmp_path / "friction.json"
    friction("mine", "--data-dir", str(store), *WINDOW, "--out", str(mined))
    result = friction("cause", "--friction", str(mined))
    assert result.returncode == 1
    assert data_of(result)["rules_read"] == 0


def test_estimate_sizes_each_mode(tmp_path):
    claims = (
        [{"id": f"c{i}", "type": "fact", "consequential": True} for i in range(9)]
        + [{"id": f"r{i}", "type": "recommendation", "consequential": True} for i in range(4)]
        + [{"id": f"n{i}", "type": "specific", "consequential": False} for i in range(10)]
        + [{"id": f"m{i}", "type": "recommendation", "consequential": False} for i in range(2)]
    )
    inventory = tmp_path / "inventory.json"
    inventory.write_text(json.dumps({"claims": claims}), encoding="utf-8")
    data = data_of(friction("estimate", "--inventory", str(inventory), "--probes", "3"))
    assert (data["claims"], data["consequential"]) == (25, 13)
    # Hand-computed from the constants: tokens = agents x (100K, 125K) + 320K + probes x (6K, 9K); minutes = the
    # larger of (waves + 2) x (12, 18) and probes x (3, 5).
    assert data["modes"]["probes"] == {
        "claims_checked": 0, "verifier_agents": 0, "waves": 0, "probe_cases": 3, "tokens": [18_000, 27_000], "minutes": [9, 15],
    }
    assert data["modes"]["consequential"] == {
        "claims_checked": 13, "verifier_agents": 4, "waves": 1, "probe_cases": 3, "tokens": [738_000, 847_000], "minutes": [36, 54],
    }
    assert data["modes"]["full"] == {
        "claims_checked": 25, "verifier_agents": 5, "waves": 1, "probe_cases": 3, "tokens": [838_000, 972_000], "minutes": [36, 54],
    }
    md = friction("estimate", "--inventory", str(inventory), "--probes", "3", "--format", "md").stdout
    assert "| consequential | 13 | 4 | 1 | 3 | 0.74M-0.85M | 36-54 min |" in md


def test_estimate_ranges_hold_the_measured_run(tmp_path):
    # The measured fact-check: 32 verify batches of 12 claims and 16 challenge agents of 3 recommendations,
    # 5.53M tokens in 119 min; the probe agent: 17 cases, 0.12M tokens in 64 min.
    claims = [{"id": f"c{i}", "type": "fact"} for i in range(32 * 12 - 16 * 3)]
    claims += [{"id": f"r{i}", "type": "recommendation"} for i in range(16 * 3)]
    inventory = tmp_path / "inventory.json"
    inventory.write_text(json.dumps({"claims": claims}), encoding="utf-8")
    full = data_of(friction("estimate", "--inventory", str(inventory)))["modes"]["full"]
    assert (full["verifier_agents"], full["waves"]) == (48, 6)
    assert full["tokens"][0] <= 5_530_000 <= full["tokens"][1]
    assert full["minutes"][0] <= 119 <= full["minutes"][1]
    probes = data_of(friction("estimate", "--inventory", str(inventory), "--probes", "17"))["modes"]["probes"]
    assert probes["tokens"][0] <= 120_000 <= probes["tokens"][1]
    assert probes["minutes"][0] <= 64 <= probes["minutes"][1]


def payload(rows: list[tuple[str, str, float]], sessions: int, since: str) -> dict:
    return {
        "schema": "audit-friction.mine/v1",
        "data": {
            "window": {"since": since, "until": since},
            "sessions": sessions,
            "rows": [{"side": s, "key": k, "count": 1, "per_session": r} for s, k, r in rows],
        },
    }


def test_diff_reports_fewer_gone_new_and_same(tmp_path):
    baseline, current = tmp_path / "before.json", tmp_path / "after.json"
    baseline.write_text(json.dumps(payload(
        [("main", "prompt-approved", 2.0), ("main", "denied/classifier/X", 1.0), ("sub", "handoff/other", 0.5)], 4, "2026-09-01"
    )), encoding="utf-8")
    current.write_text(json.dumps(payload(
        [("main", "prompt-approved", 0.5), ("sub", "handoff/other", 0.5), ("main", "agent-ask/approve", 1.0)], 2, "2026-09-20"
    )), encoding="utf-8")
    result = friction("diff", "--baseline", str(baseline), "--current", str(current))
    assert result.returncode == 1
    data = data_of(result)
    verdicts = {(r["side"], r["key"]): (r["verdict"], r["delta"]) for r in data["rows"]}
    assert verdicts == {
        ("main", "prompt-approved"): ("fewer", -1.5),
        ("main", "denied/classifier/X"): ("gone", -1.0),
        ("sub", "handoff/other"): ("same", 0.0),
        ("main", "agent-ask/approve"): ("new", 1.0),
    }
    assert data["worse"] == 1


def test_diff_finds_the_newest_saved_baseline(store, tmp_path):
    assert friction("mine", "--data-dir", str(store), *WINDOW, "--save-baseline").returncode == 0
    current = tmp_path / "now.json"
    assert friction("mine", "--data-dir", str(store), *WINDOW, "--out", str(current)).returncode == 0
    result = friction("diff", "--data-dir", str(store), "--current", str(current))
    assert result.returncode == 0, result.stdout
    data = data_of(result)
    assert Path(data["baseline"]).parent == store / "audit-friction" / "baselines"
    assert {r["verdict"] for r in data["rows"]} == {"same"}
