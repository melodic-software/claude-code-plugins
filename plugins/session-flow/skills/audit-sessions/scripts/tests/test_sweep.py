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
LENSES = {"cost", "cache", "context", "interruption", "permission", "delegation", "hooks", "churn"}
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
        "time": {"start": v.get("start", "2026-09-01T10:00:00Z"), "active_gap_s": v["time.active_s"]},
        "tokens": {
            "main": {"output": v["tokens.main"], "cache_creation_5m": v.get("main_5m", 0), "cache_creation_1h": v.get("main_1h", 0)},
            "sub": {"output": v["tokens.sub"], "cache_creation_5m": v.get("sub_5m", 0), "cache_creation_1h": v.get("sub_1h", 0)},
        },
        "cache_miss": {"missed_input_tokens": v["cache.missed_input_tokens"]},
        "context": {"clear_commands": v["context.clear_commands"]},
        "human": {"turns": v["human.turns"]},
        "tools": {"interrupts": v["tools.interrupts"], "denials": {"permission-rule": v["tools.denials"]}},
        "subagents": {"count": v["subagents.count"]},
        "stop_hooks": {"ms_p90": v["hooks.stop_ms"] + 1000, "wait_ms_p90": v["hooks.stop_ms"]},
        "census": v.get("census", {}),
        **({"entrypoints": v["entrypoints"]} if "entrypoints" in v else {}),
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
            # A report-only rule may keep its intended route (hooks.stop_ms), but names both or neither.
            assert (rule["route"] is None) == (rule["suggested_skill"] is None), metric
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
    threshold = RULE["tokens.main"]["threshold"]
    assert metrics["tokens.main"] == {"value": 20, "unit": "tokens", "n": 3, "p90": 90, "threshold": threshold, "baseline_stale": False}
    assert metrics["cache.write_5m_share"]["value"] == pytest.approx(0.75)
    assert metrics["cache.write_5m_share"]["p90"] is None
    assert set(metrics) == set(RULE)


def test_trigger_is_pinned_one_sided_at_half_again_the_threshold():
    assert RULES["stale_p90_factor"] == 1.5
    assert "one-sided" in RULES["recheck"] and "threshold of 0" in RULES["recheck"]


def test_p90_uses_collects_percentile_rule():
    import collect
    import sweep

    for values in ([], [7], [1, 2], list(range(10)), list(range(11)), [5, 1, 9, 3, 7, 2]):
        assert sweep.p90(values) == collect._percentile(values, 0.9), values


def test_store_p90_over_half_again_a_threshold_marks_the_row_and_keeps_the_exit_code(data_dir):
    # Ten sessions: the p90 is the ninth value. human.turns's p90 of 22 exceeds
    # 1.5 x 14 = 21; tools.denials's p90 of 40 does not exceed 1.5 x 27 = 40.5.
    turns, denials = RULE["human.turns"]["threshold"], RULE["tools.denials"]["threshold"]
    assert (turns, denials) == (14, 27)
    write_store(
        data_dir,
        *[record(f"s{n}", **{"human.turns": 22 if n >= 8 else 3, "tools.denials": 40 if n >= 8 else 3}) for n in range(10)],
    )
    result = sweep(data_dir)
    assert result.returncode == 0, result.stdout + result.stderr
    env = envelope(result)
    metrics = env["data"]["metrics"]
    assert metrics["human.turns"]["p90"] == 22 and metrics["human.turns"]["threshold"] == 14
    assert metrics["human.turns"]["baseline_stale"] is True
    assert metrics["tools.denials"]["p90"] == 40 and metrics["tools.denials"]["baseline_stale"] is False
    assert env["status"] == "pass" and env["data"]["stale_p90_factor"] == 1.5
    md = sweep(data_dir, "--format", "md")
    assert md.returncode == 0, md.stderr
    table = md.stdout.split("## Metrics", 1)[1].split("## Findings", 1)[0]
    rows = {row.split("|")[1].strip(" `"): row for row in table.splitlines() if row.startswith("| `")}
    assert "| 22 (stale baseline) | 14 |" in rows["human.turns"]
    assert "| 40 | 27 |" in rows["tools.denials"]
    stale_line = next(line for line in table.splitlines() if line.startswith("Stale baseline:"))
    assert "`human.turns`" in stale_line and "`tools.denials`" not in stale_line
    assert "does not change the exit code" in stale_line


def test_trigger_never_fires_without_a_threshold_or_below_one():
    import sweep

    assert sweep.baseline_stale(10**9, None, 1.5) is False
    assert sweep.baseline_stale(None, 10, 1.5) is False
    assert sweep.baseline_stale(1, 0, 1.5) is True and sweep.baseline_stale(0, 0, 1.5) is False
    assert sweep.baseline_stale(1, 10, 1.5) is False


def test_no_stale_line_when_no_row_is_marked(data_dir):
    write_store(data_dir, record("s1"))
    md = sweep(data_dir, "--format", "md").stdout
    assert "Stale baseline:" not in md and "(stale baseline)" not in md


@pytest.mark.parametrize("factor", [None, "1.5", 0.5, True])
def test_rules_file_without_a_usable_factor_is_rejected(tmp_path, factor):
    import sweep

    rules = {key: value for key, value in RULES.items() if key != "stale_p90_factor"}
    if factor is not None:
        rules["stale_p90_factor"] = factor
    path = tmp_path / "sweep-rules.json"
    path.write_text(json.dumps(rules), encoding="utf-8")
    with pytest.raises(ValueError, match="stale_p90_factor"):
        sweep.load_rules(path)


@pytest.mark.parametrize("bad", ["wrong-schema", "not-json"])
def test_unusable_store_record_exits_2(data_dir, bad):
    write_store(data_dir, record("s1"))
    target = census.store_dir(data_dir) / "p-000000000001" / "s2.json"
    target.write_text('{"schema": "session-record/v0"}' if bad == "wrong-schema" else "{", encoding="utf-8")
    result = sweep(data_dir)
    assert result.returncode == 2
    assert envelope(result)["status"] == "error"


def tree(path: Path) -> dict[str, bytes]:
    return {str(p.relative_to(path)): p.read_bytes() if p.is_file() else b"" for p in sorted(path.rglob("*"))}


def test_missing_store_exits_3_and_writes_nothing(data_dir):
    result = sweep(data_dir, "--format", "md", "--write-report")
    assert result.returncode == 3
    env = envelope(result)
    assert (env["schema"], env["status"]) == ("audit-sessions.sweep/v1", "error")
    assert not any(data_dir.iterdir())


def test_sweep_without_write_report_leaves_the_data_dir_unchanged(data_dir):
    write_store(data_dir, record("s1", **{"tools.interrupts": 2}))
    before = tree(data_dir)
    result = sweep(data_dir, "--format", "json")
    assert result.returncode == 0, result.stdout + result.stderr
    assert envelope(result)["schema"] == "audit-sessions.sweep/v1"
    assert tree(data_dir) == before


def test_finding_names_outlier_sessions_worst_first(data_dir):
    write_store(
        data_dir,
        record("calm", **{"human.turns": 14}),
        record("busy", **{"human.turns": 15, "tools.interrupts": 2}),
        record("worst", **{"human.turns": 40, "tools.interrupts": 3}),
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


def test_one_interrupt_is_not_a_finding_and_two_are(data_dir):
    write_store(data_dir, record("one", **{"tools.interrupts": 1}))
    assert "tools.interrupts" not in findings_by_metric(envelope(sweep(data_dir)))
    write_store(data_dir, record("two", **{"tools.interrupts": 2}))
    finding = findings_by_metric(envelope(sweep(data_dir)))["tools.interrupts"]
    assert finding["evidence"] == [{"session_id": "two"}] and finding["threshold"] == 1


def test_automated_sessions_are_set_aside_from_medians_and_findings(data_dir):
    write_store(
        data_dir,
        record("cli", entrypoints=["cli"], **{"tokens.main": 10, "human.turns": 3}),
        record("headless", entrypoints=["sdk-cli"], **{"tokens.main": 10**7, "tools.interrupts": 5}),
    )
    result = sweep(data_dir)
    assert result.returncode == 0, result.stdout + result.stderr
    env = envelope(result)
    data = env["data"]
    assert (data["metrics"]["tokens.main"]["value"], data["metrics"]["tokens.main"]["n"]) == (10, 1)
    assert data["metrics"]["human.turns"]["value"] == 3
    assert data["findings"] == []
    assert (data["window"]["sessions"], data["window"]["automated_set_aside"]) == (1, 1)
    assert "1 automated set aside" in env["summary"]
    md = sweep(data_dir, "--format", "md").stdout
    assert "Sessions: 1 (start to now)" in md and "1 automated session set aside" in md


def test_session_class_reads_every_entrypoint_and_keeps_unknowns(data_dir):
    write_store(
        data_dir,
        record("no-field", **{"tokens.main": 1}),
        record("unknown", entrypoints=["unknown"], **{"tokens.main": 2}),
        record("resumed-in-desktop", entrypoints=["claude-desktop", "sdk-cli"], **{"tokens.main": 3}),
        record("agent-sdk", entrypoints=["sdk-py", "sdk-ts"], **{"tokens.main": 10**7}),
    )
    data = envelope(sweep(data_dir))["data"]
    assert data["metrics"]["tokens.main"]["n"] == 3
    window = data["window"]
    assert (window["sessions"], window["automated_set_aside"], window["unclassified"]) == (3, 1, 2)
    md = sweep(data_dir, "--format", "md").stdout
    assert "2 sessions without an entrypoint kept" in md


def test_drift_still_reads_automated_sessions(data_dir):
    headless = record("headless", entrypoints=["sdk-cli"])
    headless["unknown"] = {"record_types": {"relocated": 1}}
    write_store(data_dir, record("cli", entrypoints=["cli"]), headless)
    data = envelope(sweep(data_dir))["data"]
    assert data["drift"]["counts"]["unknown-record-type"] == 1


def test_impact_sums_excess_over_threshold_in_its_unit(data_dir):
    over = RULE["tokens.main"]["threshold"]
    write_store(data_dir, record("a", **{"tokens.main": over + 100}), record("b", **{"tokens.main": over + 50}))
    found = findings_by_metric(envelope(sweep(data_dir)))
    assert found["tokens.main"]["impact"] == {"amount": 150, "unit": "tokens"}
    write_store(data_dir, record("d", **{"tools.denials": 99}))
    assert findings_by_metric(envelope(sweep(data_dir)))["tools.denials"]["impact"] is None


def test_stop_wait_and_active_time_read_the_new_keys_and_report_only(data_dir):
    assert RULE["hooks.stop_ms"]["threshold"] is None and RULE["time.active_s"]["threshold"] is None
    write_store(data_dir, record("s1", **{"hooks.stop_ms": 100, "time.active_s": 900}))
    env = envelope(sweep(data_dir))
    metrics = env["data"]["metrics"]
    assert metrics["hooks.stop_ms"]["value"] == 100 and metrics["time.active_s"]["value"] == 900
    assert not {"hooks.stop_ms", "time.active_s"} & set(findings_by_metric(env))


def test_report_only_metric_never_finds_and_is_listed_unchecked(data_dir):
    write_store(data_dir, record("s1", **{"context.clear_commands": 50}))
    env = envelope(sweep(data_dir))
    assert "context.clear_commands" not in findings_by_metric(env)
    unchecked = {row["what"] for row in env["data"]["unchecked"]}
    assert {"context.clear_commands", "cache.write_5m_share"} <= unchecked
    assert env["data"]["metrics"]["context.clear_commands"]["p90"] == 50
    assert env["data"]["metrics"]["context.clear_commands"]["baseline_stale"] is False


def test_report_only_reasons_attribute_basis_numbers_to_the_reference_machine(data_dir):
    write_store(data_dir, record("s1"))
    reasons = [u["reason"] for u in envelope(sweep(data_dir))["data"]["unchecked"] if u["reason"].startswith("reported only")]
    assert len(reasons) == sum(rule["threshold"] is None for rule in RULE.values())
    assert all("measured on the reference machine, not this store" in reason for reason in reasons)


def test_metrics_without_a_canary_are_listed_unchecked(data_dir):
    write_store(data_dir, record("s1"))
    unchecked = {row["what"]: row["reason"] for row in envelope(sweep(data_dir))["data"]["unchecked"]}
    assert "canary" in unchecked["tools.denials"] and "canary" in unchecked["subagents.count"]
    assert "tokens.main" not in unchecked


def test_suggested_skill_absent_from_catalog_renders_not_installed(data_dir):
    write_store(data_dir, record("s1", **{"tools.interrupts": 2, "tokens.sub": 10**6}))
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
    write_store(data_dir, record("s1", **{"tools.interrupts": 2}))
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
    assert env["data"]["metrics"]["tools.interrupts"] == {
        "value": None,
        "unit": "count",
        "n": 2,
        "p90": None,
        "threshold": 1,
        "baseline_stale": False,
        "degraded": True,
    }
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
    md = sweep(data_dir, "--format", "md")
    assert md.returncode == 0
    for metric in RULE:
        assert f"`{metric}`" in md.stdout
    assert "tools.interrupts" in md.stdout.split("## Findings", 1)[1]


def test_md_names_each_findings_sessions_worst_first(data_dir):
    write_store(data_dir, record("s-low", **{"tools.interrupts": 2}), record("s-high", **{"tools.interrupts": 3}), record("s-none"))
    findings = sweep(data_dir, "--format", "md").stdout.split("## Findings", 1)[1].split("## Drift", 1)[0]
    line = next(row for row in findings.splitlines() if row.startswith("- `tools.interrupts`"))
    assert line.index("s-high") < line.index("s-low") and "s-none" not in line


def test_md_caps_each_findings_sessions_and_names_the_remainder(data_dir):
    write_store(data_dir, *[record(f"s{n}", **{"tools.interrupts": 10 + n}) for n in range(8)])
    result = sweep(data_dir, "--format", "md")
    findings = result.stdout.split("## Findings", 1)[1].split("## Drift", 1)[0]
    line = next(row for row in findings.splitlines() if row.startswith("- `tools.interrupts`"))
    assert [f"s{n}" in line for n in range(7, -1, -1)] == [True] * 5 + [False] * 3
    assert "and 3 more (the JSON report lists all 8)" in line
    kept = envelope(sweep(data_dir))["data"]["findings"]
    assert len(next(f for f in kept if f["metric"] == "tools.interrupts")["evidence"]) == 8


def test_md_names_the_statistic_of_the_two_metrics_that_are_not_medians(data_dir):
    write_store(data_dir, record("s1"))
    table = sweep(data_dir, "--format", "md").stdout.split("## Metrics", 1)[1].split("## Findings", 1)[0]
    rows = {row.split("|")[1].strip(" `"): row for row in table.splitlines() if row.startswith("| `")}
    assert "machine-wide ratio" in rows["cache.write_5m_share"]
    assert "median of per-session p90" in rows["hooks.stop_ms"]
    assert "median" not in rows["cache.write_5m_share"] and "(median)" not in table.splitlines()[2]


def test_write_report_writes_a_pair_and_keeps_20(data_dir):
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
    assert not (reports / "history.jsonl").exists()


def test_scope_project_filters_on_identity_and_keys_reports(data_dir):
    write_store(
        data_dir,
        record("mine", **{"identity": "github.com/o/r", "tools.interrupts": 2}),
        record("theirs", **{"identity": "github.com/o/other", "tools.interrupts": 2}),
    )
    result = sweep(data_dir, "--scope", "project", "--state-key", "github.com/o/r/abcd1234", "--write-report")
    assert result.returncode == 0, result.stdout + result.stderr
    data = envelope(result)["data"]
    assert data["scope"] == "repo:github.com/o/r" and data["window"]["sessions"] == 1
    finding = findings_by_metric({"data": data})["tools.interrupts"]
    assert finding["evidence"] == [{"session_id": "mine"}] and finding["scope"] == "repo:github.com/o/r"
    keyed = data_dir / "audit-sessions" / "reports" / "github.com" / "o" / "r" / "abcd1234"
    assert len(list(keyed.glob("*.json"))) == 1
    assert not (keyed / "history.jsonl").exists()


def test_two_report_runs_keep_two_pairs_and_write_no_history(data_dir):
    write_store(data_dir, record("s1"))
    assert sweep(data_dir, "--write-report").returncode == 0
    assert sweep(data_dir, "--write-report").returncode == 0
    reports = data_dir / "audit-sessions" / "reports" / "machine"
    stamps = sorted(p.stem for p in reports.glob("*.json"))
    assert len(stamps) == 2
    assert not (reports / "history.jsonl").exists()


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


def typed(session_id: str, start: str, identity: str, *excerpts: str | None, suppressed: bool = False) -> dict:
    """A store record holding typed-turn excerpts, shaped as collect.py writes `human.flagged`."""
    rec = record(session_id, start=start, identity=identity)
    rec["human"]["flagged"] = [{"idx": i, "words": 3, "flags": ["short-after-assistant"], "excerpt": e} for i, e in enumerate(excerpts)]
    rec["redaction"] = {"excerpts_suppressed": suppressed}
    return rec


def excerpt_lines(result) -> list[dict]:
    return [json.loads(line) for line in result.stdout.splitlines()]


def test_excerpts_print_stored_typed_turns_inside_since_and_scope(data_dir):
    write_store(
        data_dir,
        typed("kept", "2026-09-10T08:00:00Z", "github.com/acme/web", "prefer pnpm here", None, "no emoji in commits"),
        typed("other-repo", "2026-09-11T08:00:00Z", "github.com/acme/api", "run the linter first"),
        typed("too-early", "2026-08-01T08:00:00Z", "github.com/acme/web", "old habit"),
    )
    result = sweep(data_dir, "--excerpts", "--since", "2026-09-01", "--scope", "project", "--state-key", "github.com/acme/web/main")
    assert result.returncode == 0, result.stdout + result.stderr
    assert excerpt_lines(result) == [
        {"project": "github.com/acme/web", "session": "kept", "started": "2026-09-10T08:00:00Z", "excerpt": "prefer pnpm here"},
        {"project": "github.com/acme/web", "session": "kept", "started": "2026-09-10T08:00:00Z", "excerpt": "no emoji in commits"},
    ]
    machine = excerpt_lines(sweep(data_dir, "--excerpts", "--since", "2026-09-01"))
    assert [(line["project"], line["excerpt"]) for line in machine] == [
        ("github.com/acme/web", "prefer pnpm here"),
        ("github.com/acme/web", "no emoji in commits"),
        ("github.com/acme/api", "run the linter first"),
    ]


def test_excerpt_with_shell_syntax_round_trips_as_one_json_string(data_dir, tmp_path):
    # Absolute marker paths: any shell that ever evaluates the text, in any
    # working directory, creates them where this test looks.
    marker = tmp_path / "PWNED"
    hostile = f"tabs\there\nsecond line $(touch {marker}) `touch {marker}2`"
    write_store(data_dir, typed("s1", "2026-09-10T08:00:00Z", "github.com/acme/web", hostile))
    result = sweep(data_dir, "--excerpts")
    assert result.returncode == 0, result.stderr
    assert len(result.stdout.splitlines()) == 1
    assert excerpt_lines(result)[0]["excerpt"] == hostile
    assert not marker.exists() and not marker.with_name("PWNED2").exists()


def test_excerpts_leave_out_automated_sessions(data_dir):
    headless = typed("headless", "2026-09-10T08:00:00Z", "github.com/acme/web", "from a pipeline")
    headless["entrypoints"] = ["sdk-cli"]
    write_store(data_dir, headless, typed("typed", "2026-09-10T09:00:00Z", "github.com/acme/web", "from a person"))
    result = sweep(data_dir, "--excerpts")
    assert result.returncode == 0, result.stderr
    assert [line["session"] for line in excerpt_lines(result)] == ["typed"]


def test_suppressed_excerpts_print_nothing_and_exit_1(data_dir):
    write_store(data_dir, typed("s1", "2026-09-10T08:00:00Z", "github.com/acme/web", "should never print", suppressed=True))
    result = sweep(data_dir, "--excerpts")
    assert result.returncode == 1
    assert result.stdout == ""
    assert "redaction" in result.stderr


def edited(session_id: str, prs: list[tuple[str, int]] | None, paths: dict | None) -> dict:
    """A store record carrying `prs` and `edits.by_relpath` as collect.py writes them; None drops the field."""
    rec = record(session_id)
    if prs is not None:
        rec["prs"] = [{"repo": repo, "number": number} for repo, number in prs]
    if paths is not None:
        rec["edits"] = {"files": len(paths), "by_relpath": paths}
    return rec


def test_churn_sums_one_paths_edits_across_the_sessions_of_one_pr(data_dir):
    # The rule's threshold is 5: a.py is edited 4 + 3 = 7 times within PR 12, so it is over;
    # b.py's 2 + 3 = 5 is not, and PR 13's a.py (6) is its own ticket. The placeholders collect.py
    # stores in place of a path name no file, so PR 14 has no pair. Ties order by repo, then PR number.
    write_store(
        data_dir,
        edited("s1", [("o/r", 12)], {"a.py": 4, "b.py": 2}),
        edited("s2", [("o/r", 12)], {"a.py": 3, "b.py": 3}),
        edited("s3", [("o/r", 13)], {"a.py": 6}),
        edited("s4", [("o/r", 12), ("o/r", 13)], {"a.py": 50}),
        edited("s5", [("o/r", 14)], {"<suppressed>": 40}),
        edited("s6", [("o/r", 14)], {"<too-long>": 40}),
        edited("s7", [("o/r", 100)], {"c.py": 6}),
        edited("s8", [("o/r", 9)], {"c.py": 6}),
    )
    result = sweep(data_dir)
    assert result.returncode == 0, result.stdout + result.stderr
    env = envelope(result)
    churn_row = env["data"]["metrics"]["edits.churn_per_pr"]
    assert churn_row == {"value": 6, "unit": "count", "n": 5, "p90": 7, "threshold": 5, "baseline_stale": False}
    churn = findings_by_metric(env)["edits.churn_per_pr"]
    assert churn["threshold"] == 5 and churn["value"] == 7 and churn["lens"] == "churn"
    assert churn["evidence"] == [
        {"repo": "o/r", "number": 12, "path": "a.py", "edits": 7, "sessions": ["s1", "s2"]},
        {"repo": "o/r", "number": 9, "path": "c.py", "edits": 6, "sessions": ["s8"]},
        {"repo": "o/r", "number": 13, "path": "a.py", "edits": 6, "sessions": ["s3"]},
        {"repo": "o/r", "number": 100, "path": "c.py", "edits": 6, "sessions": ["s7"]},
    ]
    reasons = [u["reason"] for u in env["data"]["unchecked"] if u["what"] == "edits.churn_per_pr"]
    assert any(reason.startswith("review outcome not linked") for reason in reasons)
    md = sweep(data_dir, "--format", "md").stdout.split("## Findings", 1)[1].split("## Drift", 1)[0]
    line = next(row for row in md.splitlines() if row.startswith("- `edits.churn_per_pr`"))
    assert line == (
        "- `edits.churn_per_pr`: `o/r`#12 `a.py` (7 edits: s1, s2), `o/r`#9 `c.py` (6 edits: s8), "
        "`o/r`#13 `a.py` (6 edits: s3), `o/r`#100 `c.py` (6 edits: s7)"
    )


def test_churn_joins_each_path_onto_its_sessions_working_directory(data_dir):
    # One file edited from the checkout root and from a subdirectory is one path (3 + 3 = 6, over 5);
    # same-named files in two subdirectories stay two paths (3 each, not over).
    def at(session_id, cwd, paths):
        rec = edited(session_id, [("o/r", 12)], paths)
        rec["cwd"] = cwd
        return rec

    write_store(
        data_dir,
        at("s1", "/w", {"sub/a.py": 3}),
        at("s2", "/w/sub", {"a.py": 3}),
        at("s3", "/w/front", {"package.json": 3}),
        at("s4", "/w/back", {"package.json": 3}),
    )
    env = envelope(sweep(data_dir))
    assert findings_by_metric(env)["edits.churn_per_pr"]["evidence"] == [
        {"repo": "o/r", "number": 12, "path": "/w/sub/a.py", "edits": 6, "sessions": ["s1", "s2"]},
    ]


def test_records_without_prs_or_edits_sweep_cleanly(data_dir):
    write_store(
        data_dir,
        edited("no-prs", None, {"a.py": 30}),
        edited("no-edits", [("o/r", 12)], None),
        edited("empty-prs", [], {"a.py": 30}),
        record("neither"),
    )
    result = sweep(data_dir, "--format", "md")
    assert result.returncode == 0, result.stdout + result.stderr
    env = envelope(sweep(data_dir))
    churn_row = env["data"]["metrics"]["edits.churn_per_pr"]
    assert churn_row == {"value": None, "unit": "count", "n": 0, "p90": None, "threshold": 5, "baseline_stale": False}
    assert "edits.churn_per_pr" not in findings_by_metric(env)
