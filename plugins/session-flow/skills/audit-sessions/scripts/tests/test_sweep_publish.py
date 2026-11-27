# test-scope: plugins/session-flow/.claude-plugin/plugin.json
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import census
import transcript_sources
import pytest
from conftest import envelope
from test_sweep import keyed, record, sweep, tree, typed, write_store, write_verdicts

HOME_B = "/" + "home/user-b"


def fleet_sources(tmp_path: Path) -> Path:
    path = tmp_path / "sources.json"
    sources = [
        {"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": str(tmp_path / "cfg-a")},
        {"name": "host-b-wsl", "host": "host-b", "platform": "wsl", "config_dir": "/srv/user-b/.claude", "via": ["ssh", "host-b"]},
    ]
    path.write_text(json.dumps({"schema": "transcript-sources/v1", "sources": sources}), encoding="utf-8")
    return path


def test_md_report_carries_no_host_home_path_or_email(data_dir, tmp_path):
    leak = f"on host-b see {HOME_B}/notes and mail ops-b" + "@" + "example.org"
    write_store(data_dir, typed("s1", "2026-09-10T08:00:00Z", "github.com/acme/web", leak), record("busy", **{"tools.interrupts": 3}))
    verdicts = write_verdicts(tmp_path / "verdicts.json", ("s1:0", "correction", "sent to host-b"))
    sources = str(fleet_sources(tmp_path))
    md = sweep(data_dir, "--judged", str(verdicts), "--format", "md", "--sources-file", sources)
    assert md.returncode == 0, md.stdout + md.stderr
    assert "`on <host-2> see ~/notes and mail <email>` (reason: `sent to <host-2>`)" in md.stdout
    for value in ("host-b", HOME_B, "example.org"):
        assert value not in md.stdout
    store_text = "".join(p.read_text(encoding="utf-8") for p in census.store_dir(data_dir).rglob("*.json"))
    assert "host-b" in store_text, "stored records stay unredacted"


def test_written_md_report_names_a_session_by_its_host_placeholder(data_dir, tmp_path):
    write_store(data_dir, record("host-b-run", **{"tools.interrupts": 3}))
    result = sweep(data_dir, "--write-report", "--sources-file", str(fleet_sources(tmp_path)))
    assert result.returncode == 0, result.stdout + result.stderr
    [report] = (data_dir / "audit-sessions" / "reports" / "machine").glob("*.md")
    text = report.read_text(encoding="utf-8")
    assert "`tools.interrupts`: <host-2>-run" in text
    assert "host-b" not in text


def test_md_is_not_printed_when_the_sources_file_cannot_be_used(data_dir, tmp_path):
    write_store(data_dir, record("s1"))
    bad = tmp_path / "sources.json"
    bad.write_text("not json", encoding="utf-8")
    result = sweep(data_dir, "--format", "md", "--sources-file", str(bad))
    assert result.returncode == 2
    assert envelope(result)["summary"].startswith("nothing published:")
    assert "sources.json" not in result.stdout


@pytest.mark.parametrize("body", [None, "not json"], ids=["missing", "unusable"])
def test_write_report_writes_nothing_and_exits_2_when_the_sources_file_cannot_be_used(data_dir, tmp_path, body):
    write_store(data_dir, record("s1", **{"tools.interrupts": 3}))
    named = tmp_path / "sources.json"
    if body is not None:
        named.write_text(body, encoding="utf-8")
    before = tree(data_dir)
    result = sweep(data_dir, "--write-report", "--sources-file", str(named))
    assert result.returncode == 2
    assert envelope(result)["summary"].startswith("nothing published:")
    assert tree(data_dir) == before


def test_write_report_writes_nothing_and_exits_2_when_the_secret_rules_do_not_load(data_dir, tmp_path, monkeypatch, capsys):
    import sweep

    write_store(data_dir, record("s1", **{"tools.interrupts": 3}))
    real = sweep.publish.publisher
    monkeypatch.setattr(sweep.publish, "publisher", lambda *a, **k: real(*a, **k, rules=tmp_path / "absent-rules.json"))
    before = tree(data_dir)
    code = sweep.main(["--data-dir", str(data_dir), "--write-report", "--sources-file", str(fleet_sources(tmp_path))])
    assert code == 2
    assert json.loads(capsys.readouterr().out)["summary"] == "nothing published: the secret redaction rules did not load"
    assert tree(data_dir) == before


def test_tickets_md_names_a_host_key_by_its_placeholder(data_dir, tmp_path):
    write_store(data_dir, keyed("one", "2026-09-01T10:00:00Z", "2026-09-01T11:00:00Z", branches=["host-b-7"]))
    md = sweep(data_dir, "--tickets", r"host-b-\d+", "--format", "md", "--sources-file", str(fleet_sources(tmp_path)))
    assert md.returncode == 0, md.stdout + md.stderr
    assert "| `<host-2>-7` | 1 |" in md.stdout
    assert "host-b" not in md.stdout


def test_pr_md_names_a_host_repository_and_branch_by_placeholders(data_dir, tmp_path):
    write_store(data_dir, keyed("s1", "2026-09-01T10:00:00Z", "2026-09-01T11:00:00Z", branches=["host-b-fix"]))
    md = sweep(
        data_dir, "--pr", "3", "--repo", "acme/host-b", "--branch", "host-b-fix", "--format", "md",
        "--sources-file", str(fleet_sources(tmp_path)), "--redact-identifiers", "acme",
    )
    assert md.returncode == 0, md.stdout + md.stderr
    assert md.stdout.startswith("# Sessions on `<identifier>/<host-2>` #3 (machine)")
    assert "head branch: `<host-2>-fix`" in md.stdout
    assert "host-b" not in md.stdout and "acme" not in md.stdout


def test_written_json_report_names_a_session_by_its_host_placeholder(data_dir, tmp_path):
    write_store(data_dir, record("host-b-run", **{"tools.interrupts": 3}))
    result = sweep(data_dir, "--write-report", "--sources-file", str(fleet_sources(tmp_path)))
    assert result.returncode == 0, result.stdout + result.stderr
    [report] = (data_dir / "audit-sessions" / "reports" / "machine").glob("*.json")
    text = report.read_text(encoding="utf-8")
    assert "host-b" not in text
    [finding] = [f for f in json.loads(text)["data"]["findings"] if f["metric"] == "tools.interrupts"]
    assert finding["evidence"][0]["session_id"] == "<host-2>-run"


def test_an_invalid_hosts_block_prints_no_host_name(data_dir, tmp_path):
    write_store(data_dir, record("s1"))
    sources = json.loads(fleet_sources(tmp_path).read_text(encoding="utf-8"))
    sources["hosts"] = {"host-b": {"bogus": 1}}
    bad = tmp_path / "bad-sources.json"
    bad.write_text(json.dumps(sources), encoding="utf-8")
    result = sweep(data_dir, "--format", "md", "--sources-file", str(bad))
    assert result.returncode == 2
    assert "host-b" not in result.stdout + result.stderr


def seed_collection(data_dir: Path, tmp_path: Path) -> tuple[Path, list[str], str, Path]:
    """A store whose one ingest run, 20 days ago, read host-a-wsl cleanly and left host-b-wsl an unreachable gap."""
    write_store(data_dir, record("s-header"))
    finished = (datetime.now(timezone.utc) - timedelta(days=20)).strftime("%Y-%m-%dT%H:%M:%SZ")
    retry = ["python3", "/srv/plugin/scripts/collect.py", "collect", "--data-dir", "/srv/data", "--source", "host-b-wsl"]
    diagnostics = census.store_dir(data_dir) / transcript_sources.DIAGNOSTICS_DIR / "run-1.json"
    diagnostics.parent.mkdir(parents=True)
    diagnostics.write_text(json.dumps({
        "schema": "transcript-run.diagnostics/v1", "kind": "ingest", "started_at": finished, "finished_at": finished,
        "sources": [{"name": "host-a-wsl", "gaps": 0, "cleanup_period_days": 30}, {"name": "host-b-wsl", "gaps": 1, "cleanup_period_days": 30}],
        "gaps": [{"source": "host-b-wsl", "kind": "unreachable", "detail": "ssh exited 255", "holder_pid": None, "retry_argv": retry}],
    }), encoding="utf-8")
    sources = tmp_path / "sources.json"
    sources.write_text(json.dumps({"schema": "transcript-sources/v1", "sources": [
        {"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": "/srv/user-a/.claude"},
        {"name": "host-b-wsl", "host": "host-b", "platform": "wsl", "config_dir": "/srv/user-b/.claude", "via": ["ssh", "host-b"]},
    ]}), encoding="utf-8")
    return sources, retry, finished, diagnostics


def test_header_gaps_and_stale(tmp_path):
    data_dir = tmp_path / "data"
    sources, retry, finished, diagnostics = seed_collection(data_dir, tmp_path)
    data = envelope(sweep(data_dir, "--format", "json", "--sources-file", str(sources)))["data"]
    assert data["header"] == [
        "Gap: host-b-wsl unreachable: ssh exited 255. Retry: " + " ".join(retry),
        f"Stale: host-a-wsl was last collected without a gap at {finished}, past half its cleanupPeriodDays of 30.",
        "Stale: host-b-wsl has no collection without a gap in the retained diagnostics.",
        f"Diagnostics: {diagnostics}",
    ]
    md = sweep(data_dir, "--format", "md", "--sources-file", str(sources)).stdout
    assert "- Gap: " in md and "unreachable: ssh exited 255. Retry: python3 " in md
    assert md.count("- Stale: ") == 2
    assert "host-b" not in md and "host-a" not in md


def test_header_is_absent_after_a_clean_recent_collection(tmp_path):
    data_dir = tmp_path / "data"
    write_store(data_dir, record("s-clean"))
    diagnostics = census.store_dir(data_dir) / transcript_sources.DIAGNOSTICS_DIR / "run-1.json"
    diagnostics.parent.mkdir(parents=True)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    diagnostics.write_text(json.dumps({
        "schema": "transcript-run.diagnostics/v1", "kind": "ingest", "started_at": now, "finished_at": now,
        "sources": [{"name": "local", "gaps": 0, "cleanup_period_days": 30}], "gaps": [],
    }), encoding="utf-8")
    assert envelope(sweep(data_dir, "--format", "json"))["data"]["header"] == []


def test_excerpts_pass_the_publish_redactor(tmp_path):
    data_dir = tmp_path / "data"
    sources, _retry, _finished, _diagnostics = seed_collection(data_dir, tmp_path)
    rec = record("s-excerpt")
    rec["human"]["flagged"] = [{"idx": 3, "flags": ["correction"], "excerpt": "ask host-b about /srv/user-b/notes or ops-b@example.org"}]
    write_store(data_dir, rec)
    done = sweep(data_dir, "--excerpts", "--sources-file", str(sources))
    assert done.returncode == 0, done.stdout + done.stderr
    line = json.loads(done.stdout.splitlines()[0])
    assert line["session"] == "s-excerpt"
    for leaked in ("host-b", "/srv/user-b", "example.org"):
        assert leaked not in line["excerpt"]
    absent = sweep(data_dir, "--excerpts", "--sources-file", str(tmp_path / "absent.json"))
    assert (absent.returncode, envelope(absent)["status"]) == (2, "error")
    assert "s-excerpt" not in absent.stdout


def test_a_missing_sources_file_warns_once_on_stderr_in_json(tmp_path):
    data_dir = tmp_path / "data"
    write_store(data_dir, record("s-warn"))
    done = sweep(data_dir, "--format", "json", "--sources-file", str(tmp_path / "absent.json"))
    assert (done.returncode, done.stderr.count("not found")) == (0, 1), done.stderr
