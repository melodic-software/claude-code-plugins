"""Contract tests for sweep.py: metrics, findings, drift degradation, rendering and reports.

Runs sweep.py by subprocess over stores the tests write (seam 2). Records carry only the fields
sweep reads; `census` rows are added where a test needs the drift guard. Reads
`reference/sweep-rules.json` and `reference/canaries.json`.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import census
import pytest
from conftest import SCRIPTS, envelope, run_cli

RULES = json.loads((SCRIPTS.parent / "reference" / "sweep-rules.json").read_text(encoding="utf-8"))
RULE = {rule["metric"]: rule for rule in RULES["rules"]}
LENSES = {"cost", "cache", "context", "interruption", "permission", "delegation", "hooks"}
ROUTES = {"retro-codify", "work-item", "unhobble-experiment", "config-change"}
UNITS = {"tokens", "s", "ms", "count", "ratio", "usd"}


def record(session_id: str, **values) -> dict:
    """A store record whose per-session metrics default to zero; keyword args set metric ids."""
    v = {metric: 0 for metric in RULE}
    v.update(values)
    return {
        "schema": "session-record/v1",
        "session_id": session_id,
        "repo_identity": v.get("identity", "github.com/o/r"),
        "cc_versions": v.get("cc_versions", ["2.0.1"]),
        "time": {"start": v.get("start", "2026-09-01T10:00:00Z"), "active_s": v["time.active_s"]},
        "tokens": {
            "main": {"output": v["tokens.main"], "cache_creation_5m": v.get("main_5m", 0), "cache_creation_1h": v.get("main_1h", 0)},
            "sub": {"output": v["tokens.sub"], "cache_creation_5m": v.get("sub_5m", 0), "cache_creation_1h": v.get("sub_1h", 0)},
        },
        "cache_miss": {"missed_input_tokens": v["cache.missed_input_tokens"]},
        "context": {"clear_commands": v["context.clear_commands"]},
        "human": {"turns": v["human.turns"]},
        "tools": {"interrupts": v["tools.interrupts"], "denials": {"permission-rule": v["tools.denials"]}},
        "subagents": {"count": v["subagents.count"]},
        "stop_hooks": {"ms_p90": v["hooks.stop_ms"]},
        "census": v.get("census", {}),
    }


def write_store(data_dir: Path, *records: dict) -> None:
    for rec in records:
        path = census.store_dir(data_dir) / "p-000000000001" / f"{rec['session_id']}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(rec), encoding="utf-8")


def sweep(data_dir: Path, *args: str):
    return run_cli("sweep.py", "--data-dir", str(data_dir), *args)


def findings_by_metric(env: dict) -> dict:
    return {f["metric"]: f for f in env["data"]["findings"]}


def test_every_canary_feed_is_a_rule_metric():
    canaries = census.load_canaries(census.BUNDLED_CANARIES)["canaries"]
    feeds = {metric for canary in canaries for metric in canary["feeds"]}
    assert feeds <= set(RULE), feeds - set(RULE)


def test_rules_are_well_formed():
    assert len(RULE) == len(RULES["rules"])
    for metric, rule in RULE.items():
        assert rule["lens"] in LENSES and rule["unit"] in UNITS, metric
        assert rule["confidence"] in {"measured", "heuristic"} and rule["basis"], metric
        if rule["threshold"] is None:
            assert rule["route"] is None and rule["suggested_skill"] is None, metric
        else:
            assert rule["route"] in ROUTES and rule["suggested_skill"].startswith("/"), metric


def test_store_round_trip_yields_per_session_medians(data_dir):
    write_store(
        data_dir,
        record("s1", **{"tokens.main": 10, "main_1h": 100}),
        record("s2", **{"tokens.main": 90, "sub_5m": 300}),
        record("s3", **{"tokens.main": 20}),
    )
    result = sweep(data_dir)
    assert result.returncode == 0, result.stdout + result.stderr
    metrics = envelope(result)["data"]["metrics"]
    assert metrics["tokens.main"] == {"value": 20, "unit": "tokens", "n": 3}
    assert metrics["cache.write_5m_share"]["value"] == pytest.approx(0.75)
    assert set(metrics) == set(RULE)


@pytest.mark.parametrize("bad", ["wrong-schema", "not-json"])
def test_unusable_store_record_exits_2(data_dir, bad):
    write_store(data_dir, record("s1"))
    target = census.store_dir(data_dir) / "p-000000000001" / "s2.json"
    target.write_text('{"schema": "session-record/v0"}' if bad == "wrong-schema" else "{", encoding="utf-8")
    result = sweep(data_dir)
    assert result.returncode == 2
    assert envelope(result)["status"] == "error"


def test_missing_store_exits_2(data_dir):
    result = sweep(data_dir)
    assert result.returncode == 2
    assert envelope(result)["schema"] == "audit-sessions.sweep/v1"


def test_finding_names_outlier_sessions_worst_first(data_dir):
    write_store(
        data_dir,
        record("calm", **{"human.turns": 14}),
        record("busy", **{"human.turns": 15, "tools.interrupts": 1}),
        record("worst", **{"human.turns": 40, "tools.interrupts": 2}),
    )
    env = envelope(sweep(data_dir))
    turns = findings_by_metric(env)["human.turns"]
    assert turns["value"] == 40 and turns["threshold"] == 14 and turns["unit"] == "count"
    assert turns["evidence"] == [{"session_id": "worst"}, {"session_id": "busy"}]
    assert turns["finding_id"] == hashlib.sha256(b"interruption|human.turns|machine").hexdigest()[:16]
    assert turns["lens"] == "interruption" and turns["scope"] == "machine"
    assert turns["route"] == "retro-codify" and turns["confidence"] == "heuristic"
    assert turns["basis"] == "sweep-rules.json:human.turns" and turns["degraded"] is False
    assert findings_by_metric(env)["tools.interrupts"]["evidence"] == [{"session_id": "worst"}, {"session_id": "busy"}]


def test_impact_sums_excess_over_threshold_in_its_unit(data_dir):
    over = RULE["tokens.main"]["threshold"]
    write_store(data_dir, record("a", **{"tokens.main": over + 100}), record("b", **{"tokens.main": over + 50}))
    found = findings_by_metric(envelope(sweep(data_dir)))
    assert found["tokens.main"]["impact"] == {"amount": 150, "unit": "tokens"}
    write_store(data_dir, record("c", **{"time.active_s": RULE["time.active_s"]["threshold"] + 600}))
    found = findings_by_metric(envelope(sweep(data_dir)))
    assert found["time.active_s"]["impact"] == {"amount": 10, "unit": "min"}
    write_store(data_dir, record("d", **{"tools.denials": 99}))
    assert findings_by_metric(envelope(sweep(data_dir)))["tools.denials"]["impact"] is None


def test_report_only_metric_never_finds_and_is_listed_unchecked(data_dir):
    write_store(data_dir, record("s1", **{"context.clear_commands": 50}))
    env = envelope(sweep(data_dir))
    assert "context.clear_commands" not in findings_by_metric(env)
    unchecked = {row["what"] for row in env["data"]["unchecked"]}
    assert {"context.clear_commands", "cache.write_5m_share"} <= unchecked


def test_metrics_without_a_canary_are_listed_unchecked(data_dir):
    write_store(data_dir, record("s1"))
    unchecked = {row["what"]: row["reason"] for row in envelope(sweep(data_dir))["data"]["unchecked"]}
    assert "canary" in unchecked["tools.denials"] and "canary" in unchecked["subagents.count"]
    assert "tokens.main" not in unchecked


def test_suggested_skill_absent_from_catalog_renders_not_installed(data_dir):
    write_store(data_dir, record("s1", **{"tools.interrupts": 1, "tokens.sub": 10**6}))
    plain = findings_by_metric(envelope(sweep(data_dir)))
    assert plain["tokens.sub"]["suggested_skill"] == "/harness-ops:observability"
    env = envelope(sweep(data_dir, "--catalog", "session-flow:retro"))
    found = findings_by_metric(env)
    assert found["tools.interrupts"]["suggested_skill"] == "/session-flow:retro"
    assert found["tokens.sub"]["suggested_skill"] == "/harness-ops:observability (not installed)"
    assert {s["skill"] for s in env["data"]["suggestions"]} == {
        "/session-flow:retro",
        "/harness-ops:observability (not installed)",
    }


def test_catalog_entries_match_with_or_without_leading_slash(data_dir):
    write_store(data_dir, record("s1", **{"tools.interrupts": 1}))
    found = findings_by_metric(envelope(sweep(data_dir, "--catalog", "/session-flow:retro")))
    assert found["tools.interrupts"]["suggested_skill"] == "/session-flow:retro"


def test_canary_lost_degrades_metric(data_dir, tmp_path):
    canaries = tmp_path / "canaries.json"
    canaries.write_text(
        json.dumps(
            {
                "schema": census.CANARY_SCHEMA,
                "canaries": [{"key": "key_path:user:message.content", "record_type": "user", "feeds": ["tools.interrupts"]}],
            }
        ),
        encoding="utf-8",
    )
    old = {"2.0.1|*": {"record_type:user": 5, "key_path:user:message.content": 5}}
    new = {"2.0.2|*": {"record_type:user": 5}}
    write_store(
        data_dir,
        record("old", **{"census": old, "tools.interrupts": 3}),
        record("new", **{"census": new, "tools.interrupts": 3, "cc_versions": ["2.0.2"]}),
    )
    args = ("--canaries", str(canaries), "--min-count", "1", "--versions", "1", "--session-floor", "1")
    result = sweep(data_dir, *args)
    assert result.returncode == 1
    env = envelope(result)
    assert env["status"] == "warning"
    assert "tools.interrupts" not in findings_by_metric(env)
    assert env["data"]["metrics"]["tools.interrupts"] == {"value": None, "unit": "count", "n": 2, "degraded": True}
    assert env["data"]["drift"]["degraded_metrics"] == ["tools.interrupts"]
    assert env["data"]["window"]["cc_versions"] == ["2.0.1", "2.0.2"]
    md = sweep(data_dir, *args, "--format", "md")
    assert md.returncode == 1 and "unavailable" in md.stdout
    drift_md = md.stdout.split("## Drift", 1)[1].split("## Unchecked", 1)[0]
    assert "- canary-lost: `key_path:user:message.content`" in drift_md


def test_drift_markdown_keeps_a_hostile_key_inside_one_bullet():
    import sweep

    key = "x`\n- injected\n![a](https://evil.example/beacon)"
    lines = sweep.drift_key_lines([{"class": "unknown-record-type", "key": key, "model": "m`\n## heading"}])
    assert len(lines) == 1
    assert "\n" not in lines[0]
    assert lines[0].startswith("- unknown-record-type: ")
    assert "![a](https://evil.example/beacon)" in lines[0]
    # The fence is longer than the backtick inside the key, so the span stays closed.
    assert lines[0].split("unknown-record-type: ", 1)[1].startswith("``")


def test_md_names_unknown_record_types(data_dir):
    stored = record("s1")
    stored["unknown"] = {"record_types": {"relocated": 1}}
    write_store(data_dir, stored)
    md = sweep(data_dir, "--format", "md")
    assert md.returncode == 0, md.stderr
    drift_md = md.stdout.split("## Drift", 1)[1].split("## Unchecked", 1)[0]
    assert "- unknown-record-type: `relocated`" in drift_md
    assert "1 unknown-record-type" in drift_md


def test_md_renders_metrics_and_findings_from_the_same_data(data_dir):
    write_store(data_dir, record("s1", **{"tools.interrupts": 2}))
    env = envelope(sweep(data_dir))
    md = sweep(data_dir, "--format", "md")
    assert md.returncode == 0
    for metric in env["data"]["metrics"]:
        assert f"`{metric}`" in md.stdout
    assert "tools.interrupts" in md.stdout.split("## Findings", 1)[1]


def test_md_names_each_findings_sessions_worst_first(data_dir):
    write_store(data_dir, record("s-low", **{"tools.interrupts": 1}), record("s-high", **{"tools.interrupts": 3}), record("s-none"))
    findings = sweep(data_dir, "--format", "md").stdout.split("## Findings", 1)[1].split("## Drift", 1)[0]
    line = next(row for row in findings.splitlines() if row.startswith("- `tools.interrupts`"))
    assert line.index("s-high") < line.index("s-low") and "s-none" not in line


def test_write_report_writes_a_pair_appends_history_and_keeps_20(data_dir):
    write_store(data_dir, record("s1"))
    reports = data_dir / "audit-sessions" / "reports" / "machine"
    reports.mkdir(parents=True)
    for n in range(21):
        (reports / f"20000101T0000{n:02d}Z.json").write_text("{}", encoding="utf-8")
        if n != 0:  # the oldest pair, which a concurrent run already half-removed
            (reports / f"20000101T0000{n:02d}Z.md").write_text("", encoding="utf-8")
    result = sweep(data_dir, "--write-report")
    assert result.returncode == 0, result.stdout + result.stderr
    kept = sorted(p.name for p in reports.glob("*.json"))
    assert len(kept) == 20 and not kept[-1].startswith("2000")
    assert sorted(p.stem for p in reports.glob("*.md")) == [Path(k).stem for k in kept]
    written = json.loads((reports / kept[-1]).read_text(encoding="utf-8"))
    assert written["schema"] == "audit-sessions.sweep/v1" and written["data"]["window"]["sessions"] == 1
    lines = (reports / "history.jsonl").read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    entry = json.loads(lines[0])
    assert entry["stamp"] == Path(kept[-1]).stem and entry["scope"] == "machine" and entry["sessions"] == 1
    assert entry["metrics"]["tokens.main"] == 0


def test_scope_project_filters_on_identity_and_keys_reports(data_dir):
    write_store(
        data_dir,
        record("mine", **{"identity": "github.com/o/r", "tools.interrupts": 1}),
        record("theirs", **{"identity": "github.com/o/other", "tools.interrupts": 1}),
    )
    result = sweep(data_dir, "--scope", "project", "--state-key", "github.com/o/r/abcd1234", "--write-report")
    assert result.returncode == 0, result.stdout + result.stderr
    data = envelope(result)["data"]
    assert data["scope"] == "repo:github.com/o/r" and data["window"]["sessions"] == 1
    finding = findings_by_metric({"data": data})["tools.interrupts"]
    assert finding["evidence"] == [{"session_id": "mine"}] and finding["scope"] == "repo:github.com/o/r"
    keyed = data_dir / "audit-sessions" / "reports" / "github.com" / "o" / "r" / "abcd1234"
    assert len(list(keyed.glob("*.json"))) == 1
    assert (keyed / "history.jsonl").is_file()


def test_two_report_runs_keep_two_pairs_and_two_history_lines(data_dir):
    write_store(data_dir, record("s1"))
    assert sweep(data_dir, "--write-report").returncode == 0
    assert sweep(data_dir, "--write-report").returncode == 0
    reports = data_dir / "audit-sessions" / "reports" / "machine"
    stamps = sorted(p.stem for p in reports.glob("*.json"))
    assert len(stamps) == 2
    history = [json.loads(line)["stamp"] for line in (reports / "history.jsonl").read_text(encoding="utf-8").splitlines()]
    assert history == stamps


@pytest.mark.parametrize("key", [None, "../../evil/x", "github.com/o/r/../x", "/abs/x", "noworktree"])
def test_scope_project_needs_a_safe_state_key(data_dir, key):
    write_store(data_dir, record("s1"))
    args = ["--scope", "project", "--write-report"] + (["--state-key", key] if key else [])
    assert sweep(data_dir, *args).returncode == 2
    assert not (data_dir / "audit-sessions" / "reports").exists()


def test_since_until_window_filters_on_session_start(data_dir):
    write_store(
        data_dir,
        record("early", start="2026-09-04T23:59:59Z"),
        record("on-since", start="2026-09-05T00:00:00Z"),
        record("inside", start="2026-09-10T10:00:00Z"),
        record("on-until", start="2026-09-15T23:59:59Z"),
        record("late", start="2026-09-16T00:00:00Z"),
    )
    window = envelope(sweep(data_dir, "--since", "2026-09-05", "--until", "2026-09-15"))["data"]["window"]
    assert window["sessions"] == 3 and window["since"] == "2026-09-05" and window["until"] == "2026-09-15"
    assert sweep(data_dir, "--since", "Sept 5").returncode == 2
