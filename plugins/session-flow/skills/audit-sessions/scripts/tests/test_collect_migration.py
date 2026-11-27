# test-scope: plugins/session-flow/.claude-plugin/plugin.json plugins/session-flow/skills/audit-sessions/scripts/tests/fixtures/multi/*

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import pytest
from conftest import LOCK, PLUGIN_SCRIPTS, config_env, envelope, run_cli
from test_collect import collect, diag_path, records, store_root
from test_collect_fleet import by_source, collect_sources, local_sources


def segment(project_dir: str) -> str:
    return "p-" + hashlib.sha256(project_dir.encode("utf-8")).hexdigest()[:12]


@pytest.fixture
def old_record(tmp_path, multi):
    """A realistic session-record/v1 body: a stored record with its v2-only keys removed and its schema set back."""
    root, _ = multi
    scratch = tmp_path / "scratch-data"
    scratch.mkdir()
    assert collect(scratch, root, "--session", "sess-b1").returncode == 0
    record = records(scratch)["sess-b1"]
    for key in ("provenance", "status"):
        record.pop(key)
    return {**record, "schema": "session-record/v1"}


def write_v1(data_dir: Path, record: dict, project: str, sid: str) -> Path:
    path = data_dir / "audit-sessions" / "store" / "v1" / "sessions" / segment(project) / f"{sid}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({**record, "session_id": sid}), encoding="utf-8")
    return path


def v1_dir(data_dir: Path) -> Path:
    return data_dir / "audit-sessions" / "store" / "v1"


def test_old_orphan_is_carried_over_once_then_the_old_store_is_quarantined(data_dir, multi, old_record):
    import socket

    import transcript_sources

    root, _ = multi
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    write_v1(data_dir, old_record, "proj-a", "sess-a1")
    result = collect(data_dir, root)
    assert result.returncode == 0, result.stdout + result.stderr
    data = envelope(result)["data"]
    assert data["carried_over"] == 1
    carried = records(data_dir)["old-0001"]
    assert carried["schema"] == "session-record/v2"
    assert carried["status"] == "carried-over"
    assert carried["carried_from"] == {
        "v1_store": str(v1_dir(data_dir) / "sessions"),
        "assumed_root": str(root),
        "root_recorded": False,
    }
    assert (carried["provenance"]["source"], carried["provenance"]["host"], carried["provenance"]["platform"]) == (
        "local", socket.gethostname(), transcript_sources.local_platform(),
    )
    assert records(data_dir)["sess-a1"]["status"] == "present", "a session whose transcript is there is rebuilt, not carried"
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    quarantine = data_dir / "audit-sessions" / "store" / f"v1.quarantine-{today}"
    assert (data["migration"]["state"], data["migration"]["quarantine"]) == ("quarantined", str(quarantine))
    assert not v1_dir(data_dir).exists()
    assert (quarantine / "sessions" / segment("proj-b") / "old-0001.json").is_file(), "the old store is moved, not deleted"

    stored = (store_root(data_dir) / "local" / segment("proj-b") / "old-0001.json").read_bytes()
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    again = envelope(collect(data_dir, root))["data"]
    assert again["carried_over"] == 0, "a record the store already holds is not delivered again"
    assert (store_root(data_dir) / "local" / segment("proj-b") / "old-0001.json").read_bytes() == stored
    swept = run_cli("sweep.py", "--data-dir", str(data_dir), "--format", "json")
    assert swept.returncode in (0, 1), swept.stdout + swept.stderr


def test_old_store_is_kept_while_the_local_source_has_a_gap(data_dir, multi, old_record, tmp_path):
    root, _ = multi
    old = write_v1(data_dir, old_record, "proj-b", "old-0001")
    starved = collect(data_dir, root, "--sources-file", str(local_sources(tmp_path, root, memory_bytes=1)))
    data = envelope(starved)["data"]
    assert [g["kind"] for g in data["gaps"]] == ["partial"]
    assert data["migration"]["state"] == "pending"
    assert old.is_file(), "the old store stays while the gap is unexpired"
    data = envelope(collect(data_dir, root))["data"]
    assert data["migration"]["state"] == "quarantined"
    assert not v1_dir(data_dir).exists()


def test_migration_is_refused_while_another_reader_holds_the_lock(data_dir, multi, old_record, tmp_path):
    import transcript_run

    root, _ = multi
    old = write_v1(data_dir, old_record, "proj-b", "old-0001")
    before = old.read_bytes()
    lock = transcript_run.data_dir_lock(str(data_dir / transcript_run.DATA_LOCK_FILE))
    assert lock.acquired
    try:
        result = collect(data_dir, root, "--sources-file", str(local_sources(tmp_path, root, lock_timeout_s=0)))
    finally:
        lock.release()
    data = envelope(result)["data"]
    assert [g["kind"] for g in data["gaps"]] == ["busy"]
    assert (data["carried_over"], data["migration"]["state"]) == (0, "pending")
    assert old.read_bytes() == before


@pytest.mark.skipif(sys.platform == "win32", reason="the sh -c via and fake claude are POSIX shell")
def test_another_hosts_old_store_is_read_and_left_untouched(data_dir, fleet, old_record):
    sources, env, root, other = fleet
    remote_data = other / "plugins" / "data" / data_dir.name
    write_v1(remote_data, old_record, "proj-b", "old-0002")
    before = {str(p): (p.stat().st_mtime_ns, p.read_bytes() if p.is_file() else b"") for p in [remote_data, *remote_data.rglob("*")]}
    result = collect_sources(data_dir, sources, env)
    assert result.returncode == 0, result.stdout + result.stderr
    carried = by_source(data_dir)[("host-b-wsl", "old-0002")]
    assert (carried["status"], carried["provenance"]["source"]) == ("carried-over", "host-b-wsl")
    host_b = next(s for s in envelope(result)["data"]["sources"] if s["name"] == "host-b-wsl")
    assert host_b["info"] == ["old store pending local migration"]
    after = {str(p): (p.stat().st_mtime_ns, p.read_bytes() if p.is_file() else b"") for p in [remote_data, *remote_data.rglob("*")]}
    assert after == before, "the remote host's old store is never written"
    assert envelope(collect_sources(data_dir, sources, env))["data"]["carried_over"] == 0


def test_migrate_dry_run_reports_and_changes_nothing(data_dir, multi, old_record):
    root, _ = multi
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    write_v1(data_dir, old_record, "proj-a", "sess-a1")
    before = {str(p): p.stat().st_mtime_ns for p in [data_dir, *data_dir.rglob("*")]}
    args = [sys.executable, str(PLUGIN_SCRIPTS / "collect.py"), "migrate", *LOCK, "--data-dir", str(data_dir)]
    dry = subprocess.run([*args, "--dry-run"], capture_output=True, text=True, encoding="utf-8", timeout=60, env=config_env(root))
    assert dry.returncode == 0, dry.stdout + dry.stderr
    data = envelope(dry)["data"]
    tally = data["tally"]
    assert (tally["records"], tally["orphans"], tally["carried"], tally["rebuild"], data["would_quarantine"]) == (2, 1, 1, 1, True)
    assert {str(p): p.stat().st_mtime_ns for p in [data_dir, *data_dir.rglob("*")]} == before, "a dry run changes nothing"
    real = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", timeout=60, env=config_env(root))
    assert envelope(real)["data"]["migration"]["state"] == "quarantined", real.stdout + real.stderr


def test_a_quarantine_is_deleted_once_past_the_retention(data_dir, multi):
    root, _ = multi
    store = data_dir / "audit-sessions" / "store"
    old_day = datetime.fromtimestamp(time.time() - 40 * 86400, timezone.utc).strftime("%Y-%m-%d")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for day in (old_day, today):
        (store / f"v1.quarantine-{day}" / "sessions").mkdir(parents=True)
    collect(data_dir, root, "--retention-days", "0")
    assert (store / f"v1.quarantine-{old_day}").is_dir(), "retention 0 keeps every quarantine"
    data = envelope(collect(data_dir, root, "--retention-days", "30"))["data"]
    assert data["migration"]["deleted_quarantines"] == [str(store / f"v1.quarantine-{old_day}")]
    assert not (store / f"v1.quarantine-{old_day}").exists() and (store / f"v1.quarantine-{today}").is_dir()


def test_an_unreadable_old_record_keeps_the_old_store_and_is_reported(data_dir, multi, old_record):
    root, _ = multi
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    corrupt = write_v1(data_dir, old_record, "proj-b", "old-0002")
    corrupt.write_text("{not json", encoding="utf-8")
    other = write_v1(data_dir, {**old_record, "schema": "session-record/v0"}, "proj-b", "old-0003")
    dry = envelope(migrate(data_dir, root, "--dry-run"))["data"]
    assert (dry["would_quarantine"], dry["tally"]["unreadable"], dry["tally"]["other_schema"]) == (False, 1, 1)
    result = collect(data_dir, root)
    migration = envelope(result)["data"]["migration"]
    assert migration["state"] == "pending"
    assert corrupt.is_file() and other.is_file(), "files the reader could not account for stay in the old store"
    (local,) = json.loads(Path(diag_path(data_dir)).read_text(encoding="utf-8"))["sources"]
    assert (local["v1"]["unreadable"], local["v1"]["other_schema"]) == (1, 1)


def migrate(data_dir: Path, root: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    args = [sys.executable, str(PLUGIN_SCRIPTS / "collect.py"), "migrate", *LOCK, "--data-dir", str(data_dir), *extra]
    return subprocess.run(args, capture_output=True, text=True, encoding="utf-8", timeout=60, env=config_env(root))


def test_dry_run_predicts_what_a_filtered_migrate_decides(data_dir, multi, old_record):
    root, _ = multi
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    write_v1(data_dir, old_record, "proj-a", "sess-a1")
    dry = envelope(migrate(data_dir, root, "--dry-run", "--session", "sess-b1"))["data"]
    assert (dry["would_quarantine"], dry["tally"]["filtered"]) == (False, 1)
    real = envelope(migrate(data_dir, root, "--session", "sess-b1"))["data"]["migration"]
    assert real["state"] == "pending", "sess-a1 is left out, so the old store stays"
    assert envelope(migrate(data_dir, root, "--dry-run"))["data"]["would_quarantine"] is True
    assert envelope(migrate(data_dir, root))["data"]["migration"]["state"] == "quarantined"


def test_a_quarantine_whose_date_does_not_parse_is_left_alone_with_a_warning(data_dir, multi):
    root, _ = multi
    bad = data_dir / "audit-sessions" / "store" / "v1.quarantine-2026-13-01"
    (bad / "sessions").mkdir(parents=True)
    result = collect(data_dir, root, "--retention-days", "30")
    assert result.returncode == 1, result.stdout + result.stderr
    data = envelope(result)["data"]
    assert data["migration"]["unparsed_quarantines"] == ["v1.quarantine-2026-13-01"]
    assert any("v1.quarantine-2026-13-01" in w for w in data["warnings"]) and bad.is_dir()


@pytest.mark.skipif(sys.platform == "win32", reason="symlinks need privileges on Windows")
@pytest.mark.parametrize("linked", ["project-dir", "record-file"])
def test_a_symlink_in_the_old_store_is_counted_and_keeps_it(data_dir, multi, old_record, tmp_path, linked):
    root, _ = multi
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    elsewhere = tmp_path / "elsewhere" / segment("proj-z")
    elsewhere.mkdir(parents=True)
    (elsewhere / "old-0009.json").write_text(json.dumps({**old_record, "session_id": "old-0009"}), encoding="utf-8")
    sessions = v1_dir(data_dir) / "sessions"
    if linked == "project-dir":
        (sessions / segment("proj-z")).symlink_to(elsewhere, target_is_directory=True)
    else:
        (sessions / segment("proj-b") / "old-0009.json").symlink_to(elsewhere / "old-0009.json")
    data = envelope(collect(data_dir, root))["data"]
    assert data["migration"]["state"] == "pending"
    assert data["migration"]["tally"]["unrecognized"] == 1, "the symlink is counted, never followed"
    assert v1_dir(data_dir).is_dir() and (elsewhere / "old-0009.json").is_file()


def test_unset_retention_without_a_readable_default_is_an_error(data_dir, multi, plugin_copy):
    root, _ = multi
    manifest = plugin_copy / ".claude-plugin" / "plugin.json"
    spec = json.loads(manifest.read_text(encoding="utf-8"))
    del spec["userConfig"]["audit_sessions_retention_days"]
    manifest.write_text(json.dumps(spec), encoding="utf-8")
    args = [sys.executable, str(plugin_copy / "scripts" / "collect.py"), "collect", *LOCK, "--data-dir", str(data_dir)]
    unset = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", timeout=60, env=config_env(root))
    assert (unset.returncode, envelope(unset)["status"]) == (2, "error")
    given = subprocess.run([*args, "--retention-days", "0"], capture_output=True, text=True, encoding="utf-8", timeout=60, env=config_env(root))
    assert given.returncode == 0, given.stdout + given.stderr


@pytest.mark.parametrize("beside", [None, "notes.txt"])
def test_an_old_store_without_sessions_is_quarantined_only_when_empty(data_dir, multi, beside):
    root, _ = multi
    v1_dir(data_dir).mkdir(parents=True)
    if beside:
        (v1_dir(data_dir) / beside).write_text("x", encoding="utf-8")
    migration = envelope(collect(data_dir, root))["data"]["migration"]
    if beside:
        assert migration["state"] == "pending" and beside in migration["reason"], "the reason names the entry that keeps it"
        assert (v1_dir(data_dir) / beside).is_file()
    else:
        assert migration["state"] == "quarantined" and not v1_dir(data_dir).exists()


def linked_away(old_record: dict, tmp_path: Path, link: Path) -> Path:
    """An orphan old record placed outside the old store, reached only through the directory symlink `link`; its file."""
    target = tmp_path / "elsewhere"
    (target / "sessions" / segment("proj-z")).mkdir(parents=True)
    record = target / "sessions" / segment("proj-z") / "old-0009.json"
    record.write_text(json.dumps({**old_record, "session_id": "old-0009"}), encoding="utf-8")
    link.parent.mkdir(parents=True, exist_ok=True)
    link.symlink_to(target / "sessions" if link.name == "sessions" else target, target_is_directory=True)
    return record


def settle_as_the_link_appears(data_dir: Path, root: Path, monkeypatch, appear, tally: dict | None = None) -> dict:
    """settle_v1 with `tally` (an empty old store's by default) as the own source's reader account, and
    `appear` run as the host locks are taken."""
    import collect as collect_module
    import transcript_sources

    (v1_dir(data_dir) / "sessions").mkdir(parents=True, exist_ok=True)
    writer = collect_module.StoreWriter(collect_module.census.store_dir(data_dir))
    writer.held("local")
    tally = {**dict.fromkeys(collect_module.transcript_run.V1_TALLY, 0), "rebuild_keys": [], "entries": [], **(tally or {})}
    writer.v1_tallies["local"] = tally
    writer.carried["local"] = tally["carried"]
    take = collect_module.transcript_run.host_locks

    def taken(*args, **kwargs):
        locks = take(*args, **kwargs)
        appear()
        return locks

    monkeypatch.setattr(collect_module.transcript_run, "host_locks", taken)
    own = transcript_sources.SourceEntry("local", "local", transcript_sources.local_platform(), str(root.parent))
    return collect_module.settle_v1(data_dir, writer, own, ["local"], 0, time.time())


@pytest.mark.parametrize("change", [None, "added", "swapped", "swapped-for-a-link", "empty-dir-added"])
def test_a_change_after_the_tally_keeps_the_old_store(data_dir, multi, old_record, tmp_path, monkeypatch, change):
    root, _ = multi
    first = write_v1(data_dir, old_record, "proj-b", "old-0001")
    elsewhere = tmp_path / "old-0001.json"
    elsewhere.write_text(first.read_text(encoding="utf-8"), encoding="utf-8")

    def appear():
        if change in ("swapped", "swapped-for-a-link"):
            first.unlink()
        if change in ("added", "swapped"):
            write_v1(data_dir, old_record, "proj-b", "old-0002")
        if change == "swapped-for-a-link":
            first.symlink_to(elsewhere)
        if change == "empty-dir-added":
            (v1_dir(data_dir) / "sessions" / segment("proj-c")).mkdir()

    entries = [[segment("proj-b"), "dir"], [f"{segment('proj-b')}/old-0001.json", "file"]]
    tally = {"records": 1, "orphans": 1, "carried": 1, "entries": entries}
    report = settle_as_the_link_appears(data_dir, root, monkeypatch, appear, tally)
    if change is None:
        assert report["state"] == "quarantined" and not v1_dir(data_dir).exists()
    else:
        assert report["state"] == "pending" and "changed since its reader's tally" in report["reason"]
        assert v1_dir(data_dir).is_dir() and elsewhere.is_file()


@pytest.mark.skipif(sys.platform == "win32", reason="symlinks need privileges on Windows")
def test_a_symlinked_sessions_dir_is_never_followed(data_dir, multi, old_record, tmp_path, monkeypatch):
    root, _ = multi
    record = linked_away(old_record, tmp_path, v1_dir(data_dir) / "sessions")
    dry = envelope(migrate(data_dir, root, "--dry-run"))["data"]
    assert dry["would_quarantine"] is False and "sessions/ is a symlink" in dry["reason"]
    assert (dry["tally"]["unrecognized"], dry["tally"]["carried"]) == (1, 0)
    data = envelope(collect(data_dir, root))["data"]
    migration = data["migration"]
    assert migration["state"] == "pending" and "sessions/ is a symlink" in migration["reason"]
    assert (migration["tally"]["unrecognized"], migration["carried"]) == (1, 0), "nothing is carried from the link's target"
    recorded = [s["v1"] for s in json.loads(Path(data["diagnostics_path"]).read_text(encoding="utf-8"))["sources"] if s.get("v1")]
    assert [v1["state"] for v1 in recorded] == ["pending"] and "sessions/ is a symlink" in recorded[0]["reason"], "diagnostics carry the reason"
    assert (v1_dir(data_dir) / "sessions").is_symlink() and record.is_file()

    sessions = v1_dir(data_dir) / "sessions"
    sessions.unlink()
    report = settle_as_the_link_appears(data_dir, root, monkeypatch, lambda: (sessions.rmdir(), linked_away(old_record, tmp_path / "late", sessions)))
    assert report["state"] == "pending" and "sessions/ is a symlink" in report["reason"], "the recheck under the locks refuses the link"
    assert sessions.is_symlink()


@pytest.mark.skipif(sys.platform == "win32", reason="symlinks need privileges on Windows")
def test_a_symlinked_old_store_root_is_never_renamed(data_dir, multi, old_record, tmp_path, monkeypatch):
    root, _ = multi
    record = linked_away(old_record, tmp_path, v1_dir(data_dir))
    dry = envelope(migrate(data_dir, root, "--dry-run"))["data"]
    assert dry["would_quarantine"] is False and "the old store is a symlink" in dry["reason"]
    assert dry["tally"]["carried"] == 0
    migration = envelope(collect(data_dir, root))["data"]["migration"]
    assert migration["state"] == "pending" and "the old store is a symlink" in migration["reason"]
    assert migration["carried"] == 0, "nothing is read through the link"
    assert v1_dir(data_dir).is_symlink() and record.is_file()

    v1_dir(data_dir).unlink()
    report = settle_as_the_link_appears(
        data_dir, root, monkeypatch, lambda: (shutil.rmtree(v1_dir(data_dir)), linked_away(old_record, tmp_path / "late", v1_dir(data_dir)))
    )
    assert report["state"] == "pending" and "the old store is a symlink" in report["reason"], "the recheck under the locks refuses the link"
    assert v1_dir(data_dir).is_symlink()


@pytest.mark.parametrize("empty", ["junk", "p-0123456789ab/sub", "p-0123456789ab"])
def test_an_empty_directory_in_the_old_store_blocks_unless_it_is_a_project_dir(data_dir, multi, empty):
    root, _ = multi
    (v1_dir(data_dir) / "sessions" / empty).mkdir(parents=True)
    migration = envelope(collect(data_dir, root))["data"]["migration"]
    if empty == "p-0123456789ab":
        assert migration["state"] == "quarantined", "an empty project directory holds nothing to lose"
    else:
        assert migration["state"] == "pending" and "1 old files unrecognized" in migration["reason"]
        assert migration["tally"]["unrecognized"] == 1 and (v1_dir(data_dir) / "sessions" / empty).is_dir()


def diagnosed_migration(data: dict) -> dict:
    return json.loads(Path(data["diagnostics_path"]).read_text(encoding="utf-8"))["v1_migration"]


def test_the_migration_reaches_diagnostics_when_the_own_source_is_not_read(data_dir, multi, old_record, tmp_path):
    root, _ = multi
    extra = tmp_path / "extra" / "projects"
    shutil.copytree(root / "proj-a", extra / "proj-a")
    first = envelope(collect(data_dir, root, "--config-dir", str(extra)))["data"]
    (added,) = {s["name"] for s in first["sources"]} - {"local"}
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    data = envelope(collect(data_dir, root, "--config-dir", str(extra), "--source", added, "--force"))["data"]
    assert diagnosed_migration(data) == {"state": "pending", "reason": "the source local was not read"}
    assert data["migration"]["reason"] == "the source local was not read"


def test_the_migration_reaches_diagnostics_with_no_own_source(data_dir, multi, old_record, tmp_path):
    root, _ = multi
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    sources = tmp_path / "sources.json"
    sources.write_text(json.dumps({
        "schema": "transcript-sources/v1",
        "sources": [{"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": str(root.parent)}],
    }), encoding="utf-8")
    elsewhere = tmp_path / "another-config"
    (elsewhere / "projects").mkdir(parents=True)
    data = envelope(collect_sources(data_dir, sources, config_env(elsewhere / "projects")))["data"]
    reason = "no source reads this host's configuration directory"
    assert diagnosed_migration(data) == {"state": "pending", "reason": reason} and data["migration"]["reason"] == reason
    assert v1_dir(data_dir).is_dir()


def test_dry_run_resolves_retention_as_the_real_migrate_does(data_dir, multi, old_record):
    root, _ = multi
    (root.parent / "settings.json").write_text(json.dumps({"cleanupPeriodDays": 400}), encoding="utf-8")
    write_v1(data_dir, old_record, "proj-b", "old-0001")
    dated = datetime.fromtimestamp(time.time() - 300 * 86400, timezone.utc)
    old_quarantine = v1_dir(data_dir).parent / f"v1.quarantine-{dated:%Y-%m-%d}"
    old_quarantine.mkdir()
    unset = migrate(data_dir, root, "--dry-run")
    assert unset.returncode == 0, unset.stdout + unset.stderr
    data = envelope(unset)["data"]
    assert (data["retention_days"], data["quarantines_past_retention"], data["warnings"]) == (400, [], []), (
        "a 300-day-old quarantine is inside the 400-day floor"
    )
    given = migrate(data_dir, root, "--dry-run", "--retention-days", "180")
    data = envelope(given)["data"]
    assert (given.returncode, data["retention_days"], data["quarantines_past_retention"]) == (1, 180, [str(old_quarantine)])
    (warning,) = data["warnings"]
    assert "180" in warning and "400" in warning
    real = envelope(migrate(data_dir, root, "--retention-days", "180"))["data"]
    assert real["warnings"] == data["warnings"], "the dry run warns as the real migrate does"
