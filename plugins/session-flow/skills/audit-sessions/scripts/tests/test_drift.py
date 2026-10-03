"""Drift guard tests: census.py's aggregate and classifier, and the `census`/`drift` subcommands.

Classifier cases build store records in memory; the CLI cases read the synthetic store
`drift/store/` (records `drift-s1.json`, `drift-s2.json`, `drift-s3.json`, `drift-s4.json`, census
and unknown blocks only), and the collector case ingests `drift/split/proj-s/split-0001.jsonl`,
where one message's streamed records disagree on input tokens. The bundled
`reference/canaries.json` is checked for shape.
"""

from __future__ import annotations

import json
from pathlib import Path

import census
import pytest
from conftest import FIXTURES, envelope, run_cli

DRIFT_STORE = FIXTURES / "drift" / "store"
TOKENS = {"key": "usage_key:input_tokens", "record_type": "assistant", "feeds": ["tokens.main"]}
SPLIT = {"key": "invariant:usage_split", "record_type": "assistant", "expect": "absent", "feeds": ["tokens.main"]}


def rec(session_id: str, buckets: dict, unknown: dict | None = None) -> dict:
    return {
        "schema": "session-record/v1",
        "session_id": session_id,
        "census": buckets,
        "unknown": {"record_types": unknown or {}, "system_subtypes": {}},
    }


def drift(records, canaries=(), *, min_count=20, versions=2, session_floor=1):
    return census.drift(
        records, list(canaries), min_count=min_count, versions=versions, session_floor=session_floor
    )


def classes(result: dict, cls: str) -> list[str]:
    return [c["key"] for c in result["changes"] if c["class"] == cls]


def test_aggregate_sums_records_sessions_and_keys():
    records = [
        rec("a", {"1.0.1|*": {"record_type:user": 3, "key_path:user:x": 2}}),
        rec("b", {"1.0.1|*": {"record_type:user": 4, "record_type:system": 1}}),
    ]
    agg = census.aggregate(records)
    assert agg["1.0.1|*"] == {
        "records": 8,
        "sessions": 2,
        "keys": {"record_type:user": 7, "key_path:user:x": 2, "record_type:system": 1},
    }


def test_aggregate_filters_by_version_and_model():
    records = [rec("a", {"1.0.1|*": {"record_type:user": 1}, "1.0.1|m": {"record_type:assistant": 1}, "1.0.2|m": {"record_type:assistant": 2}})]
    assert set(census.aggregate(records, version="1.0.1")) == {"1.0.1|*", "1.0.1|m"}
    assert set(census.aggregate(records, model="m")) == {"1.0.1|m", "1.0.2|m"}


def test_new_needs_min_count_in_newest_and_absence_before():
    base = {"record_type:user": 30}
    records = [
        rec("a", {"1.0.1|*": dict(base)}),
        rec("b", {"1.0.2|*": {**base, "key_path:user:loud": 25, "key_path:user:quiet": 5}}),
    ]
    result = drift(records)
    assert classes(result, "new") == ["key_path:user:loud"]
    assert result["window"]["newest_version"] == "1.0.2"


def test_new_is_not_reported_for_a_model_never_seen_before():
    records = [
        rec("a", {"1.0.1|*": {"record_type:user": 30}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30}, "1.0.2|fresh-model": {"record_type:assistant": 30}}),
    ]
    assert classes(drift(records), "new") == []


def test_vanished_needs_min_count_in_the_baseline():
    records = [
        rec("a", {"1.0.1|*": {"record_type:user": 30, "key_path:user:big": 25, "key_path:user:rare": 5}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30}}),
        rec("c", {"1.0.3|*": {"record_type:user": 30}}),
    ]
    result = drift(records)
    assert classes(result, "vanished") == ["key_path:user:big"]
    change = next(c for c in result["changes"] if c["class"] == "vanished")
    assert change["last_seen_version"] == "1.0.1"
    assert result["window"]["baseline_versions"] == ["1.0.1"]


def test_vanished_needs_absence_in_every_recent_qualifying_version():
    records = [
        rec("a", {"1.0.1|*": {"record_type:user": 30, "key_path:user:k": 30}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30, "key_path:user:k": 1}}),
        rec("c", {"1.0.3|*": {"record_type:user": 30}}),
    ]
    assert classes(drift(records), "vanished") == []


def test_vanish_window_skips_versions_below_min_count():
    # 1.0.3 has too few records to count, so the last two versions are 1.0.2 and 1.0.4.
    records = [
        rec("a", {"1.0.1|*": {"record_type:user": 30, "key_path:user:k": 30}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30}}),
        rec("c", {"1.0.3|*": {"record_type:user": 5}}),
        rec("d", {"1.0.4|*": {"record_type:user": 30}}),
    ]
    result = drift(records)
    assert classes(result, "vanished") == ["key_path:user:k"]
    assert result["window"]["newest_version"] == "1.0.4"
    assert result["window"]["baseline_versions"] == ["1.0.1"]


def test_key_still_seen_in_a_thin_recent_version_has_not_vanished():
    records = [
        rec("a", {"1.0.1|*": {"record_type:user": 30, "key_path:user:k": 30}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30}}),
        rec("c", {"1.0.3|*": {"record_type:user": 5, "key_path:user:k": 5}}),
        rec("d", {"1.0.4|*": {"record_type:user": 30}}),
    ]
    assert classes(drift(records), "vanished") == []


@pytest.mark.parametrize(
    ("later_m_versions", "vanished"),
    [((), []), (("1.0.5", "1.0.6"), ["key_path:assistant:k"])],
    ids=["one-m-version-without-k", "three-m-versions-without-k"],
)
def test_vanish_window_counts_only_versions_where_the_model_has_min_count_records(later_m_versions, vanished):
    # Other models fill 1.0.2 and 1.0.3, but m has no records there, so with only 1.0.4 after it
    # m's last three qualifying versions are 1.0.1 and 1.0.4, and k is present in 1.0.1.
    records = [
        rec("a", {"1.0.1|m": {"record_type:assistant": 30, "key_path:assistant:k": 30}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30}}),
        rec("c", {"1.0.3|*": {"record_type:user": 30}}),
        rec("d", {"1.0.4|m": {"record_type:assistant": 30}}),
        *(rec(v, {f"{v}|m": {"record_type:assistant": 30}}) for v in later_m_versions),
    ]
    assert classes(drift(records, versions=3), "vanished") == vanished


def test_unknown_version_bucket_is_outside_every_window():
    # Were `unknown` a version, it would sort oldest and make `ghost` a vanished baseline key.
    records = [
        rec("u", {"unknown|*": {"record_type:user": 500, "key_path:user:ghost": 500}}),
        rec("a", {"1.0.1|*": {"record_type:user": 30}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30}}),
        rec("c", {"1.0.3|*": {"record_type:user": 30}}),
    ]
    result = drift(records)
    assert result["window"]["newest_version"] == "1.0.3"
    assert result["window"]["baseline_versions"] == ["1.0.1"]
    assert result["changes"] == []


def test_canary_lost_when_newest_version_has_its_record_type_but_not_the_key():
    records = [
        rec("a", {"1.0.1|m": {"record_type:assistant": 30, "usage_key:input_tokens": 30}}),
        rec("b", {"1.0.2|m": {"record_type:assistant": 30}}),
    ]
    result = drift(records, [TOKENS])
    assert classes(result, "canary-lost") == ["usage_key:input_tokens"]
    assert result["degraded_metrics"] == ["tokens.main"]
    assert result["counts"]["canary-lost"] == 1


@pytest.mark.parametrize(
    ("assistant_records", "session_floor"),
    [(10, 1), (30, 2)],
    ids=["below-min-count", "below-session-floor"],
)
def test_canary_holds_when_the_newest_version_is_too_thin(assistant_records, session_floor):
    records = [
        rec("a", {"1.0.1|m": {"record_type:assistant": 30, "usage_key:input_tokens": 30}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30}, "1.0.2|m": {"record_type:assistant": assistant_records}}),
    ]
    result = drift(records, [TOKENS], session_floor=session_floor)
    assert classes(result, "canary-lost") == []
    assert result["degraded_metrics"] == []


def test_session_floor_counts_only_sessions_holding_the_population():
    hooks = {
        "key": "key_path:system:hookInfos[].durationMs",
        "record_type": "system",
        "population": "system_subtype:stop_hook_summary",
        "feeds": ["hooks.stop_ms"],
    }
    records = [
        rec("a", {"1.0.2|*": {"record_type:system": 25, "system_subtype:stop_hook_summary": 25}}),
        rec("b", {"1.0.2|*": {"record_type:user": 30}}),
        rec("c", {"1.0.2|*": {"record_type:user": 30}}),
    ]
    assert drift(records, [hooks], session_floor=3)["degraded_metrics"] == []


def test_malformed_store_values_are_ignored():
    records = [
        rec("a", {"1.0.2|*": {"record_type:user": 30, "key_path:user:flag": True}}),
        {"schema": "session-record/v1", "session_id": "b", "census": ["not", "a", "map"], "unknown": {"record_types": ["mode"]}},
    ]
    result = drift(records)
    assert census.aggregate(records)["1.0.2|*"]["keys"] == {"record_type:user": 30}
    assert result["counts"]["unknown-record-type"] == 0


def test_canary_population_narrows_to_its_subtype():
    # Stop-hook timing is checked only where stop_hook_summary records exist: a machine without
    # stop hooks never loses the canary.
    hooks = {
        "key": "key_path:system:hookInfos[].durationMs",
        "record_type": "system",
        "population": "system_subtype:stop_hook_summary",
        "feeds": ["hooks.stop_ms"],
    }
    without_hooks = [rec("a", {"1.0.2|*": {"record_type:system": 30}})]
    assert drift(without_hooks, [hooks])["degraded_metrics"] == []
    lost = [rec("a", {"1.0.2|*": {"record_type:system": 30, "system_subtype:stop_hook_summary": 25}})]
    assert drift(lost, [hooks])["degraded_metrics"] == ["hooks.stop_ms"]


@pytest.mark.parametrize(("splits", "lost"), [(0, False), (2, False), (20, True)])
def test_invariant_canary_lost_when_streamed_usage_disagrees_at_min_count(splits, lost):
    # A few split groups are legitimate (cumulative usage over two API iterations); a format
    # change splits many.
    records = [rec("a", {"1.0.2|m": {"record_type:assistant": 30, "invariant:usage_split": splits}})]
    result = drift(records, [SPLIT])
    assert classes(result, "canary-lost") == (["invariant:usage_split"] if lost else [])
    assert result["degraded_metrics"] == (["tokens.main"] if lost else [])


def test_unknown_record_types_surface_with_counts():
    records = [
        rec("a", {"1.0.1|*": {"record_type:mode": 3}}, unknown={"mode": 3}),
        rec("b", {"1.0.2|*": {"record_type:mode": 2, "record_type:relocated": 1}}, unknown={"mode": 2, "relocated": 1}),
    ]
    result = drift(records)
    rows = {c["key"]: c for c in result["changes"] if c["class"] == "unknown-record-type"}
    assert {k: v["count"] for k, v in rows.items()} == {"mode": 5, "relocated": 1}
    assert rows["mode"]["last_seen_version"] == "1.0.2"
    assert result["counts"]["unknown-record-type"] == 2


def test_collector_counts_a_split_usage_group_once(data_dir, copy_fixture):
    root = copy_fixture("drift/split")
    collected = run_cli("collect.py", "collect", "--data-dir", str(data_dir), "--projects-root", str(root))
    assert collected.returncode == 0, collected.stderr
    (stored,) = (data_dir / "audit-sessions" / "store" / "v1" / "sessions").glob("p-*/split-0001.json")
    bucket = json.loads(stored.read_text(encoding="utf-8"))["census"]["2.0.9|model-s"]
    assert bucket["invariant:usage_split"] == 1


@pytest.fixture
def canaries_file(tmp_path: Path) -> Path:
    path = tmp_path / "canaries.json"
    path.write_text(json.dumps({"schema": "audit-sessions.canaries/v1", "canaries": [TOKENS]}), encoding="utf-8")
    return path


def test_drift_cli_reports_each_class_and_exits_1(canaries_file):
    result = run_cli(
        "collect.py", "drift", "--data-dir", str(DRIFT_STORE), "--min-count", "20", "--versions", "2",
        "--session-floor", "2", "--canaries", str(canaries_file),
    )
    assert result.returncode == 1, result.stderr
    env = envelope(result)
    assert env["schema"] == "audit-sessions.drift/v1"
    assert env["status"] == "warning"
    data = env["data"]
    assert data["counts"] == {"new": 1, "vanished": 1, "canary-lost": 1, "unknown-record-type": 1}
    assert data["degraded_metrics"] == ["tokens.main"]
    assert data["window"] == {
        "newest_version": "2.0.3",
        "baseline_versions": ["2.0.1"],
        "min_count": 20,
        "versions_n": 2,
    }


def test_drift_cli_passes_when_nothing_moved(tmp_path, canaries_file):
    sessions = tmp_path / "audit-sessions" / "store" / "v1" / "sessions" / "p-0000000000aa"
    sessions.mkdir(parents=True)
    for name in ("drift-s1.json", "drift-s2.json"):
        source = DRIFT_STORE / "audit-sessions" / "store" / "v1" / "sessions" / "p-0000000000aa" / name
        (sessions / name).write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
    result = run_cli("collect.py", "drift", "--data-dir", str(tmp_path), "--canaries", str(canaries_file))
    assert result.returncode == 0, result.stdout
    assert envelope(result)["data"]["changes"] == []


def test_census_cli_filters():
    result = run_cli("collect.py", "census", "--data-dir", str(DRIFT_STORE), "--version", "2.0.3", "--model", "*")
    assert result.returncode == 0, result.stderr
    env = envelope(result)
    assert env["schema"] == "audit-sessions.census/v1"
    assert list(env["data"]["census"]) == ["2.0.3|*"]
    assert env["data"]["census"]["2.0.3|*"]["sessions"] == 2


@pytest.mark.parametrize("make_store", [False, True], ids=["no-data-dir", "no-store"])
def test_cli_missing_store_exits_2(tmp_path, make_store):
    data = tmp_path / "data"
    if make_store:
        data.mkdir()
    for command in ("census", "drift"):
        result = run_cli("collect.py", command, "--data-dir", str(data))
        assert result.returncode == 2
        assert envelope(result)["status"] == "error"


@pytest.mark.parametrize(
    "canaries",
    [{"key": "usage_key:input_tokens", "feeds": ["tokens.main"]}, "not-a-list", [{"key": "x", "record_type": "user", "feeds": "tokens.main"}]],
    ids=["no-record-type", "not-a-list", "feeds-not-a-list"],
)
def test_drift_cli_malformed_canaries_exit_2(tmp_path, canaries):
    path = tmp_path / "canaries.json"
    entries = canaries if isinstance(canaries, (str, list)) else [canaries]
    path.write_text(json.dumps({"schema": "audit-sessions.canaries/v1", "canaries": entries}), encoding="utf-8")
    result = run_cli("collect.py", "drift", "--data-dir", str(DRIFT_STORE), "--canaries", str(path))
    assert result.returncode == 2, result.stdout + result.stderr
    assert envelope(result)["schema"] == "audit-sessions.drift/v1"


@pytest.mark.parametrize("command", ["census", "drift"])
def test_bad_arguments_use_the_subcommand_schema(command):
    result = run_cli("collect.py", command, "--data-dir", str(DRIFT_STORE), "--bogus")
    assert result.returncode == 2
    assert envelope(result)["schema"] == f"audit-sessions.{command}/v1"


def test_bundled_canaries_are_well_formed():
    bundled = census.load_canaries(census.BUNDLED_CANARIES)
    assert bundled["schema"] == "audit-sessions.canaries/v1"
    for field in ("validated_against", "verified", "recheck"):
        assert bundled[field]
    for canary in bundled["canaries"]:
        assert canary["key"].split(":", 1)[0] in census.SECTIONS
        assert canary["feeds"]
        assert canary.get("expect", "present") in ("present", "absent")
