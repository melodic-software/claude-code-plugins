from __future__ import annotations

import io
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest
from conftest import PLUGIN_SCRIPTS

import transcript_sources


def test_no_file_reads_claude_config_dir():
    sources = transcript_sources.resolve(None, {"CLAUDE_CONFIG_DIR": "/srv/cc-config", "HOME": "/srv/someone"}, platform="linux")
    assert [(s.config_dir, s.platform, s.is_local) for s in sources.all()] == [("/srv/cc-config", "linux", True)]
    assert sources.origin == "default"
    assert sources.warnings == ()


def test_no_file_without_config_dir_reads_home_dot_claude():
    sources = transcript_sources.resolve(None, {"HOME": "/srv/someone"}, platform="wsl")
    assert [s.config_dir for s in sources.all()] == ["/srv/someone/.claude"]
    assert sources.local() == sources.all()


def fleet(**extra) -> dict:
    """Two invented hosts: host-a is the reading host (Windows side through its WSL), host-b is reached over ssh."""
    return {
        "schema": "transcript-sources/v1",
        "sources": [
            {"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": "/srv/user-a/.claude"},
            {"name": "host-a-windows", "host": "host-a", "platform": "windows", "config_dir": "/mnt/c/Users/user-a/.claude"},
            {"name": "host-b-wsl", "host": "host-b", "platform": "wsl", "config_dir": "/srv/user-b/.claude", "via": ["ssh", "host-b"]},
        ],
        **extra,
    }


def test_file_lists_every_source_grouped_by_host():
    sources = transcript_sources.resolve(json.dumps(fleet()), {}, file="fleet.json")
    assert sources.origin == "file"
    assert [(s.name, s.is_local) for s in sources.all()] == [("host-a-wsl", True), ("host-a-windows", True), ("host-b-wsl", False)]
    assert [s.name for s in sources.local()] == ["host-a-wsl", "host-a-windows"]
    assert {host: [s.name for s in group] for host, group in sources.by_host().items()} == {
        "host-a": ["host-a-wsl", "host-a-windows"],
        "host-b": ["host-b-wsl"],
    }
    assert sources.by_host()["host-b"][0].via == ("ssh", "host-b")


def without(doc: dict, key: str) -> dict:
    return {k: v for k, v in doc.items() if k != key}


def with_source(doc: dict, index: int, **changes) -> dict:
    sources = [dict(item) for item in doc["sources"]]
    sources[index] = {k: v for k, v in {**sources[index], **changes}.items() if v is not None}
    return {**doc, "sources": sources}


MALFORMED = {
    "not json": "{",
    "not an object": "[]",
    "no schema": json.dumps(without(fleet(), "schema")),
    "unknown schema": json.dumps(fleet(schema="transcript-sources/v9")),
    "no sources": json.dumps(fleet(sources=[])),
    "unknown top-level key": json.dumps(fleet(source=[])),
    "duplicate name": json.dumps(with_source(fleet(), 1, name="host-a-wsl")),
    "name not a path segment": json.dumps(with_source(fleet(), 0, name="../escape")),
    "unknown source key": json.dumps(with_source(fleet(), 0, config_dri="/x")),
    "missing config_dir": json.dumps(with_source(fleet(), 0, config_dir=None)),
    "unknown platform": json.dumps(with_source(fleet(), 2, platform="beos")),
    "via a string": json.dumps(with_source(fleet(), 2, via="ssh host-b")),
    "via empty": json.dumps(with_source(fleet(), 2, via=[])),
    "windows with no wsl on its host": json.dumps(with_source(fleet(), 0, platform="linux")),
    "windows read by another reader": json.dumps(with_source(fleet(), 1, via=["ssh", "host-a"])),
    "hosts names an unknown host": json.dumps(fleet(hosts={"host-c": {"slow_read_s": 1}})),
    "unknown limit": json.dumps(fleet(defaults={"memory": 1})),
    "both memory limits": json.dumps(fleet(defaults={"memory_bytes": 1, "memory_fraction": 0.5})),
    "memory fraction zero": json.dumps(fleet(defaults={"memory_fraction": 0})),
    "memory fraction over one": json.dumps(fleet(defaults={"memory_fraction": 1.5})),
    "memory bytes a bool": json.dumps(fleet(hosts={"host-a": {"memory_bytes": True}})),
    "check every zero records": json.dumps(fleet(defaults={"check_every_records": 0})),
    "negative lock timeout": json.dumps(fleet(defaults={"lock_timeout_s": -1})),
}


@pytest.mark.parametrize("text", MALFORMED.values(), ids=MALFORMED.keys())
def test_malformed_file_raises_naming_the_file(text):
    with pytest.raises(transcript_sources.SourcesError) as raised:
        transcript_sources.resolve(text, {}, file="/cfg/fleet.json")
    assert str(raised.value).startswith("/cfg/fleet.json: ")


def test_load_missing_file_falls_back_with_a_warning(tmp_path):
    missing = tmp_path / "absent.json"
    sources = transcript_sources.load(str(missing), {"CLAUDE_CONFIG_DIR": "/srv/cc-config"}, platform="linux")
    assert [s.config_dir for s in sources.all()] == ["/srv/cc-config"]
    assert sources.origin == "default"
    assert len(sources.warnings) == 1 and str(missing) in sources.warnings[0]


def test_load_unset_or_empty_path_reads_the_default_without_warning():
    for path in (None, ""):
        sources = transcript_sources.load(path, {"CLAUDE_CONFIG_DIR": "/srv/cc-config"}, platform="linux")
        assert (sources.origin, sources.warnings, [s.config_dir for s in sources.all()]) == ("default", (), ["/srv/cc-config"])


def test_load_reads_the_file(tmp_path):
    path = tmp_path / "fleet.json"
    path.write_text(json.dumps(fleet()), encoding="utf-8")
    assert [s.name for s in transcript_sources.load(str(path), {}).all()] == ["host-a-wsl", "host-a-windows", "host-b-wsl"]


SCRIPT = PLUGIN_SCRIPTS / "transcript_sources.py"


def cli(*args: str, stdin: str = "", env: dict | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        input=stdin,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
        env={"PATH": os.environ.get("PATH", ""), **(env or {})},
    )


def test_check_stdin_malformed_exits_2_naming_stdin():
    result = cli("check", "-", stdin="{")
    assert result.returncode == 2
    assert "<stdin>" in result.stderr


def test_check_file_valid_exits_0_and_malformed_exits_2_naming_it(tmp_path):
    good = tmp_path / "good.json"
    good.write_text(json.dumps(fleet()), encoding="utf-8")
    assert cli("check", str(good)).returncode == 0
    bad = tmp_path / "bad.json"
    bad.write_text(MALFORMED["windows with no wsl on its host"], encoding="utf-8")
    result = cli("check", str(bad))
    assert (result.returncode, str(bad) in result.stderr) == (2, True)


def test_check_missing_file_exits_2(tmp_path):
    missing = tmp_path / "absent.json"
    result = cli("check", str(missing))
    assert (result.returncode, str(missing) in result.stderr) == (2, True)


def test_local_config_dir_prints_the_default_or_the_local_sources(tmp_path):
    env = {"CLAUDE_CONFIG_DIR": "/srv/cc-config"}
    assert (cli("local-config-dir", env=env).stdout, cli("local-config-dir", env=env).returncode) == ("/srv/cc-config\n", 0)
    path = tmp_path / "fleet.json"
    path.write_text(json.dumps(fleet()), encoding="utf-8")
    result = cli("local-config-dir", "--sources-file", str(path), env=env)
    assert (result.stdout, result.returncode) == ("/srv/user-a/.claude\n/mnt/c/Users/user-a/.claude\n", 0)


def test_local_config_dir_missing_file_warns_and_prints_the_default(tmp_path):
    missing = tmp_path / "absent.json"
    result = cli("local-config-dir", "--sources-file", str(missing), env={"CLAUDE_CONFIG_DIR": "/srv/cc-config"})
    assert (result.stdout, result.returncode) == ("/srv/cc-config\n", 0)
    assert str(missing) in result.stderr


def test_local_config_dir_malformed_file_exits_2(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("{", encoding="utf-8")
    result = cli("local-config-dir", "--sources-file", str(bad), env={"CLAUDE_CONFIG_DIR": "/srv/cc-config"})
    assert (result.stdout, result.returncode, str(bad) in result.stderr) == ("", 2, True)


def test_limits_default_then_file_defaults_then_host():
    built_in = transcript_sources.resolve(json.dumps(fleet()), {}).limits_for("host-a")
    assert built_in == transcript_sources.HostLimits(
        memory_bytes=None, memory_fraction=0.25, check_every_records=5000, lock_timeout_s=300, slow_read_s=120
    )
    tuned = transcript_sources.resolve(
        json.dumps(fleet(defaults={"slow_read_s": 30}, hosts={"host-b": {"memory_bytes": 2_000_000_000, "lock_timeout_s": 0}})), {}
    )
    assert tuned.limits_for("host-a") == transcript_sources.HostLimits(memory_fraction=0.25, slow_read_s=30)
    assert tuned.limits_for("host-b") == transcript_sources.HostLimits(
        memory_bytes=2_000_000_000, memory_fraction=None, lock_timeout_s=0, slow_read_s=30
    )


def test_run_limits_are_tunable_per_host():
    tuned = transcript_sources.resolve(
        json.dumps(fleet(defaults={"read_timeout_s": 600, "nice": 5}, hosts={"host-b": {"peak_headroom": 1.5, "backstop_ratio": 3}})), {}
    )
    assert (tuned.limits_for("host-a").read_timeout_s, tuned.limits_for("host-a").nice) == (600, 5)
    assert (tuned.limits_for("host-b").peak_headroom, tuned.limits_for("host-b").backstop_ratio) == (1.5, 3)


@pytest.mark.parametrize(
    "layer",
    [{"read_timeout_s": 0}, {"nice": 20}, {"nice": -1}, {"nice": 1.5}, {"peak_headroom": 0.5}, {"backstop_ratio": 0.9}],
)
def test_run_limits_out_of_range_are_refused(layer):
    with pytest.raises(transcript_sources.SourcesError):
        transcript_sources.resolve(json.dumps(fleet(defaults=layer)), {}, file="fleet.json")


def test_load_expands_a_home_relative_sources_path(tmp_path):
    (tmp_path / ".config").mkdir()
    (tmp_path / ".config" / "sources.json").write_text(json.dumps(fleet()), encoding="utf-8")
    sources = transcript_sources.load("~/.config/sources.json", {"HOME": str(tmp_path)})
    assert (sources.origin, [s.name for s in sources.all()]) == ("file", ["host-a-wsl", "host-a-windows", "host-b-wsl"])
    assert sources.warnings == ()


def test_local_config_dir_expands_a_home_relative_sources_file(tmp_path):
    (tmp_path / "sources.json").write_text(json.dumps(fleet()), encoding="utf-8")
    done = subprocess.run(
        [sys.executable, str(SCRIPT), "local-config-dir", "--sources-file", "~/sources.json"],
        capture_output=True, text=True, timeout=30, env={**os.environ, "HOME": str(tmp_path)},
    )
    assert (done.returncode, done.stdout.splitlines()) == (0, ["/srv/user-a/.claude", "/mnt/c/Users/user-a/.claude"])


def diag_record(path, finished: str, sources: list[tuple[str, int, int]], gaps: list[dict], kind: str = "ingest") -> None:
    """One diagnostics record finished at `finished`, each source given as (name, gap count, cleanupPeriodDays)."""
    path.write_text(json.dumps({
        "schema": "transcript-run.diagnostics/v1", "kind": kind, "started_at": finished, "finished_at": finished,
        "sources": [{"name": n, "gaps": g, "cleanup_period_days": d} for n, g, d in sources], "gaps": gaps,
    }), encoding="utf-8")


def gap(source: str, kind: str = "unreachable") -> dict:
    return {"source": source, "kind": kind, "detail": "ssh exited 255", "holder_pid": None,
            "retry_argv": ["python3", "collect.py", "collect", "--source", source]}


NOW = datetime(2026, 11, 18, 11, 6, 40, tzinfo=timezone.utc).timestamp()


def test_run_status_takes_each_source_gaps_from_its_latest_read_and_flags_stale_sources(tmp_path):
    diag_record(tmp_path / "2026-11-01-a.json", "2026-11-01T00:00:00Z", [("host-a-wsl", 0, 30), ("host-b-wsl", 1, 30)], [gap("host-b-wsl")])
    diag_record(tmp_path / "2026-11-17-b.json", "2026-11-17T00:00:00Z", [("host-a-wsl", 0, 30)], [])
    diag_record(tmp_path / "2026-11-18-c.json", "2026-11-18T00:00:00Z", [], [gap("host-a-wsl", "unreadable")], kind="lookup")
    status = transcript_sources.run_status(tmp_path, ["host-a-wsl", "host-b-wsl", "host-c-wsl"], now=NOW)
    assert status.path == tmp_path / "2026-11-17-b.json"
    assert [(g["source"], g["kind"]) for g in status.gaps] == [("host-b-wsl", "unreachable")]
    assert status.stale == [
        {"source": "host-b-wsl", "last_ok": None, "cleanup_period_days": 30},
        {"source": "host-c-wsl", "last_ok": None, "cleanup_period_days": 30},
    ]


def test_run_status_flags_a_source_past_half_its_cleanup_period(tmp_path):
    diag_record(tmp_path / "2026-11-02-a.json", "2026-11-02T00:00:00Z", [("host-a-wsl", 0, 30), ("host-b-wsl", 0, 60)], [])
    status = transcript_sources.run_status(tmp_path, now=NOW)
    assert status.stale == [{"source": "host-a-wsl", "last_ok": "2026-11-02T00:00:00Z", "cleanup_period_days": 30}]
    assert status.gaps == []


def test_run_status_orders_a_whole_second_record_before_a_later_fraction(tmp_path):
    diag_record(tmp_path / "2026-11-17-b.json", "2026-11-17T00:00:00Z", [("host-a-wsl", 0, 30)], [])
    diag_record(tmp_path / "2026-11-17-a.json", "2026-11-17T00:00:00.500000Z", [("host-a-wsl", 1, 30)], [gap("host-a-wsl")])
    status = transcript_sources.run_status(tmp_path, now=NOW)
    assert status.path == tmp_path / "2026-11-17-a.json", "00:00:00.5 finished after 00:00:00"
    assert [g["kind"] for g in status.gaps] == ["unreachable"]


def test_run_status_of_no_diagnostics_is_empty(tmp_path):
    status = transcript_sources.run_status(tmp_path / "absent", now=NOW)
    assert (status.path, status.gaps, status.stale) == (None, [], [])


def test_report_header_names_each_gap_with_its_retry_and_each_stale_source():
    lines = transcript_sources.report_header(
        "/srv/data/diagnostics/2026-11-17-b.json",
        [gap("host-b-wsl")],
        [{"source": "host-a-wsl", "last_ok": "2026-11-02T00:00:00Z", "cleanup_period_days": 30},
         {"source": "host-c-wsl", "last_ok": None, "cleanup_period_days": 30}],
    )
    assert lines == [
        "Gap: host-b-wsl unreachable: ssh exited 255. Retry: python3 collect.py collect --source host-b-wsl",
        "Stale: host-a-wsl was last collected without a gap at 2026-11-02T00:00:00Z, past half its cleanupPeriodDays of 30.",
        "Stale: host-c-wsl has no collection without a gap in the retained diagnostics.",
        "Diagnostics: /srv/data/diagnostics/2026-11-17-b.json",
    ]


def test_report_header_is_empty_without_gaps_or_stale_sources():
    assert transcript_sources.report_header("/srv/data/diagnostics/x.json", [], []) == []


def test_lookup_gaps_names_a_projects_directory_that_cannot_be_listed(tmp_path):
    (tmp_path / "blocked").mkdir()
    (tmp_path / "blocked" / "projects").write_text("not a directory", encoding="utf-8")
    (tmp_path / "fine" / "projects").mkdir(parents=True)
    sources = transcript_sources.Sources((
        transcript_sources.SourceEntry("host-a-wsl", "host-a", "wsl", str(tmp_path / "blocked")),
        transcript_sources.SourceEntry("host-a-windows", "host-a", "windows", str(tmp_path / "fine")),
        transcript_sources.SourceEntry("host-a-none", "host-a", "wsl", str(tmp_path / "absent")),
        transcript_sources.SourceEntry("host-b-wsl", "host-b", "wsl", "/srv/user-b/.claude", ("ssh", "host-b")),
    ), "file")
    retry = ["python3", "audit.py", "--sources-file", "/srv/sources.json"]
    assert transcript_sources.lookup_gaps(sources, retry) == [transcript_sources.Gap(
        "host-a-wsl", "unreadable", "its projects directory could not be listed (NotADirectoryError)", None, tuple(retry),
    )]


def test_write_lookup_records_gaps_and_writes_nothing_for_a_clean_read(tmp_path):
    assert transcript_sources.write_lookup(tmp_path / transcript_sources.DIAGNOSTICS_DIR, [], now=NOW) is None
    assert not (tmp_path / transcript_sources.DIAGNOSTICS_DIR).exists()
    path = transcript_sources.write_lookup(tmp_path / transcript_sources.DIAGNOSTICS_DIR, [gap("host-a-wsl", "unreadable")], now=NOW)
    record = json.loads(path.read_text(encoding="utf-8"))
    assert (path.parent, path.name[:11]) == (tmp_path / transcript_sources.DIAGNOSTICS_DIR, "2026-11-18-")
    assert (record["schema"], record["kind"], record["gaps"]) == ("transcript-run.diagnostics/v1", "lookup", [gap("host-a-wsl", "unreadable")])


def test_a_local_config_dir_under_home_is_expanded_and_a_remote_one_is_kept():
    data = fleet()
    data["sources"][0]["config_dir"] = "~/.claude"
    data["sources"][2]["config_dir"] = "~/.claude"
    sources = transcript_sources.resolve(json.dumps(data), {"HOME": "/srv/someone"})
    assert [s.config_dir for s in sources.all()] == ["/srv/someone/.claude", "/mnt/c/Users/user-a/.claude", "~/.claude"]


def test_local_config_dir_prints_a_home_relative_config_dir_expanded(tmp_path):
    data = fleet()
    data["sources"][0]["config_dir"] = "~/cc"
    (tmp_path / "sources.json").write_text(json.dumps(data), encoding="utf-8")
    done = subprocess.run(
        [sys.executable, str(SCRIPT), "local-config-dir", "--sources-file", str(tmp_path / "sources.json")],
        capture_output=True, text=True, timeout=30, env={**os.environ, "HOME": str(tmp_path)},
    )
    assert (done.returncode, done.stdout.splitlines()) == (0, [f"{tmp_path}/cc", "/mnt/c/Users/user-a/.claude"])


def test_first_local_config_dir_is_the_first_local_source_else_the_local_default():
    assert transcript_sources.first_local_config_dir(transcript_sources.resolve(json.dumps(fleet()), {})) == Path("/srv/user-a/.claude")
    remote_only = fleet(sources=[fleet()["sources"][2]])
    env = {"CLAUDE_CONFIG_DIR": "/srv/cc-config"}
    assert transcript_sources.first_local_config_dir(transcript_sources.resolve(json.dumps(remote_only), env), env) == Path("/srv/cc-config")


def test_retry_argv_is_the_interpreter_the_resolved_script_and_the_arguments(tmp_path):
    script = tmp_path / "audit.py"
    assert transcript_sources.retry_argv(str(script), ["--json"]) == ["python3", str(script.resolve()), "--json"]
    assert transcript_sources.retry_argv(str(script), [], interpreter="bash") == ["bash", str(script.resolve())]


def test_lookup_report_prints_the_missing_file_warning_once_and_reads_the_default(tmp_path):
    stream = io.StringIO()
    report = transcript_sources.lookup_report(str(tmp_path / "absent.json"), ["python3", "x.py"], stream=stream)
    assert stream.getvalue() == transcript_sources.MISSING_WARNING.format(path=str(tmp_path / "absent.json")) + "\n"
    assert (report.sources.origin, report.gaps, report.header) == ("default", [], [])


def test_load_reported_prints_warnings_and_reads_a_malformed_file_as_none(tmp_path):
    stream = io.StringIO()
    assert transcript_sources.load_reported(str(tmp_path / "absent.json"), stream=stream).origin == "default"
    assert stream.getvalue().count("not found") == 1
    (tmp_path / "bad.json").write_text("{}", encoding="utf-8")
    assert transcript_sources.load_reported(str(tmp_path / "bad.json"), stream=stream) is None


def test_lookup_report_writes_and_renders_a_gap(tmp_path):
    (tmp_path / "cfg").mkdir()
    (tmp_path / "cfg" / "projects").write_text("not a directory", encoding="utf-8")
    data = fleet(sources=[{"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": str(tmp_path / "cfg")}])
    (tmp_path / "sources.json").write_text(json.dumps(data), encoding="utf-8")
    report = transcript_sources.lookup_report(str(tmp_path / "sources.json"), ["python3", "x.py"], tmp_path / "diag", stream=io.StringIO())
    (record,) = (tmp_path / "diag").glob("*.json")
    assert report.header == [
        "Gap: host-a-wsl unreadable: its projects directory could not be listed (NotADirectoryError). Retry: python3 x.py",
        f"Diagnostics: {record}",
    ]


def test_write_lookup_prunes_lookup_records_past_the_retention(tmp_path):
    diagnostics = tmp_path / transcript_sources.DIAGNOSTICS_DIR
    diagnostics.mkdir()
    old = diagnostics / "2026-01-01-aaaaaaaaaaaa.json"
    old.write_text("{}", encoding="utf-8")
    os.utime(old, (NOW - 200 * 86400, NOW - 200 * 86400))
    kept = transcript_sources.write_lookup(diagnostics, [gap("host-a-wsl", "unreadable")])
    assert sorted(diagnostics.glob("*.json")) == [kept]
    assert transcript_sources.LOOKUP_RETENTION_DAYS == 180


def test_store_header_reads_the_store_diagnostics_against_the_sources(tmp_path):
    diagnostics = tmp_path / transcript_sources.DIAGNOSTICS_DIR
    diagnostics.mkdir()
    diag_record(diagnostics / "a.json", "2026-11-17T00:00:00Z", [("host-a-wsl", 1, 30)], [gap("host-a-wsl")])
    sources = transcript_sources.resolve(json.dumps(fleet()), {})
    assert transcript_sources.store_header(tmp_path, sources, now=NOW) == [
        "Gap: host-a-wsl unreachable: ssh exited 255. Retry: python3 collect.py collect --source host-a-wsl",
        "Stale: host-a-wsl has no collection without a gap in the retained diagnostics.",
        "Stale: host-a-windows has no collection without a gap in the retained diagnostics.",
        "Stale: host-b-wsl has no collection without a gap in the retained diagnostics.",
        f"Diagnostics: {diagnostics / 'a.json'}",
    ]


def test_run_status_reads_a_timestamp_without_a_zone_as_utc(tmp_path):
    diag_record(tmp_path / "a.json", "2026-11-17T00:00:00", [("host-a-wsl", 0, 30)], [])
    assert transcript_sources.run_status(tmp_path, now=NOW).stale == []


def test_report_header_md_lists_the_lines_then_a_blank_line():
    assert transcript_sources.report_header_md(["Gap: a", "Stale: b"]) == ["- Gap: a", "- Stale: b", ""]
    assert transcript_sources.report_header_md([]) == []


def test_report_header_takes_a_gap_object():
    line = transcript_sources.report_header(None, [transcript_sources.Gap("host-a-wsl", "busy", "held", 7, ("bash", "x.sh"))], [])
    assert line == ["Gap: host-a-wsl busy: held. Retry: bash x.sh"]
