# test-scope: plugins/session-flow/.claude-plugin/plugin.json plugins/session-flow/skills/audit-sessions/scripts/tests/fixtures/multi/*

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import pytest
from conftest import FAKE_CC_VERSION, LOCK, PLUGIN_SCRIPTS, envelope
from test_collect import append_record, collect, diag_path, records, state_key, store_root, write_records

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
del _leaked_git_var


def collect_sources(data_dir: Path, sources: Path, env: dict, *extra: str) -> subprocess.CompletedProcess[str]:
    args = [sys.executable, str(PLUGIN_SCRIPTS / "collect.py"), "collect", *LOCK, "--data-dir", str(data_dir)]
    return subprocess.run(
        [*args, "--sources-file", str(sources), *extra], capture_output=True, text=True, encoding="utf-8", timeout=120, env=env
    )


def by_source(data_dir: Path) -> dict[tuple[str, str], dict]:
    return {
        (p.parents[1].name, p.stem): json.loads(p.read_text(encoding="utf-8"))
        for p in store_root(data_dir).glob("*/p-*/*.json")
    }


@pytest.mark.skipif(sys.platform == "win32", reason="the sh -c via and fake claude are POSIX shell")
def test_every_source_is_collected_with_its_provenance(data_dir, fleet):
    import socket

    import transcript_sources

    sources, env, root, other = fleet
    result = collect_sources(data_dir, sources, env)
    assert result.returncode == 0, result.stdout + result.stderr
    stored = by_source(data_dir)
    assert set(stored) == {(s, sid) for s in ("host-a-wsl", "host-b-wsl") for sid in ("sess-a1", "sess-a2", "sess-b1")}
    for (source, _), record in stored.items():
        config = root.parent if source == "host-a-wsl" else other
        assert record["provenance"] == {
            "source": source,
            "host": socket.gethostname(),
            "platform": transcript_sources.local_platform(),
            "config_dir": str(config),
            "cc_version": FAKE_CC_VERSION,
        }
        assert record["status"] == "present"
    data = envelope(result)["data"]
    assert [s["name"] for s in data["sources"]] == ["host-a-wsl", "host-b-wsl"]
    assert Path(data["diagnostics_path"]).is_file()
    again = envelope(collect_sources(data_dir, sources, env))["data"]
    assert (again["ingested"], again["skipped_unchanged"]) == (0, 6), "a second run skips unchanged sessions on both hosts"


@pytest.mark.skipif(sys.platform == "win32", reason="the sh -c via and fake claude are POSIX shell")
def test_source_flag_collects_only_that_source(data_dir, fleet):
    sources, env, *_ = fleet
    result = collect_sources(data_dir, sources, env, "--source", "host-b-wsl")
    assert result.returncode == 0, result.stdout + result.stderr
    assert {source for source, _ in by_source(data_dir)} == {"host-b-wsl"}
    refused = collect_sources(data_dir, sources, env, "--source", "host-z")
    assert (refused.returncode, envelope(refused)["status"]) == (2, "error")


@pytest.mark.skipif(sys.platform == "win32", reason="the via scripts are POSIX shell")
def test_gap_retry_recollects_exactly_the_gap(data_dir, fleet, tmp_path):
    sources, env, root, other = fleet
    spec = json.loads(sources.read_text(encoding="utf-8"))
    spec["sources"][1]["via"] = [str(tmp_path / "no-such-via")]
    sources.write_text(json.dumps(spec), encoding="utf-8")
    first = collect_sources(data_dir, sources, env)
    assert first.returncode == 1
    (gap,) = envelope(first)["data"]["gaps"]
    assert (gap["source"], gap["kind"]) == ("host-b-wsl", "unreachable")
    spec["sources"][1]["via"] = ["sh", "-c"]
    sources.write_text(json.dumps(spec), encoding="utf-8")
    retry = gap["retry_argv"]
    assert retry[:2] == ["python3", str(PLUGIN_SCRIPTS / "collect.py")] and retry[-2:] == ["--source", "host-b-wsl"]
    again = subprocess.run([sys.executable, *retry[1:]], capture_output=True, text=True, encoding="utf-8", timeout=120, env=env)
    assert again.returncode == 0, again.stdout + again.stderr
    assert (envelope(again)["data"]["ingested"], envelope(again)["data"]["gaps"]) == (3, [])


@pytest.mark.skipif(sys.platform == "win32", reason="the via scripts are POSIX shell")
def test_status_follows_the_transcripts(data_dir, fleet, tmp_path):
    sources, env, root, other = fleet
    assert collect_sources(data_dir, sources, env).returncode == 0
    (root / "proj-a" / "sess-a2.jsonl").unlink()
    assert collect_sources(data_dir, sources, env).returncode == 0
    stored = by_source(data_dir)
    assert stored[("host-a-wsl", "sess-a2")]["status"] == "transcript-gone", "the reader found the transcript gone"
    assert stored[("host-b-wsl", "sess-a2")]["status"] == "present"

    spec = json.loads(sources.read_text(encoding="utf-8"))
    spec["sources"][1]["via"] = [str(tmp_path / "no-such-via")]
    sources.write_text(json.dumps(spec), encoding="utf-8")
    assert collect_sources(data_dir, sources, env).returncode == 1
    stored = by_source(data_dir)
    assert {stored[("host-b-wsl", s)]["status"] for s in ("sess-a1", "sess-a2", "sess-b1")} == {"presumed-gone-unverified"}, (
        "a source that cannot be read keeps records that ended past the default 30-day cleanup as presumed gone"
    )
    spec["sources"][1]["via"] = ["sh", "-c"]
    sources.write_text(json.dumps(spec), encoding="utf-8")
    assert collect_sources(data_dir, sources, env).returncode == 0
    assert by_source(data_dir)[("host-b-wsl", "sess-a1")]["status"] == "present", "a clean read finds the transcript again"


def iso_days_ago(days: int) -> str:
    return datetime.fromtimestamp(time.time() - days * 86400, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_aged_session(root: Path, sid: str, days_ago: int) -> None:
    stamp = iso_days_ago(days_ago)
    lines = [
        {"type": "user", "uuid": "u0", "timestamp": stamp, "promptSource": "typed", "message": {"role": "user", "content": "hi"}},
        {"type": "assistant", "uuid": "a0", "timestamp": stamp,
         "message": {"id": "m0", "model": "claude-opus-5-5", "content": [{"type": "text", "text": "ok"}]}},
    ]
    write_records(root / "proj-old", sid, lines)


def test_retention_below_a_source_cleanup_period_warns(data_dir, multi):
    root, _ = multi
    (root.parent / "settings.json").write_text(json.dumps({"cleanupPeriodDays": 400}), encoding="utf-8")
    result = collect(data_dir, root, "--retention-days", "180")
    assert result.returncode == 1
    (warning,) = envelope(result)["data"]["warnings"]
    assert "180" in warning and "400" in warning


def test_unset_retention_rises_to_the_longest_cleanup_period(data_dir, multi):
    root, _ = multi
    (root.parent / "settings.json").write_text(json.dumps({"cleanupPeriodDays": 400}), encoding="utf-8")
    write_aged_session(root, "aged-0001", 300)
    result = collect(data_dir, root)
    assert result.returncode == 0, result.stdout + result.stderr
    data = envelope(result)["data"]
    assert data["retention"] == {"requested_days": None, "days": 400, "floor_applied": True}
    assert data["warnings"] == []
    assert "aged-0001" in records(data_dir), "a session 300 days old is inside the 400-day floor, though past 180 days"
    again = envelope(collect(data_dir, root))["data"]
    assert (again["pruned"], "aged-0001" in records(data_dir)) == (0, True), "the floor keeps it on the next run too"


def test_unset_retention_below_the_default_is_the_default_unraised(data_dir, multi):
    root, _ = multi
    data = envelope(collect(data_dir, root))["data"]
    assert data["retention"] == {"requested_days": None, "days": 180, "floor_applied": False}, (
        "a 30-day cleanup period raises nothing above the 180-day default"
    )


def test_user_set_retention_below_the_floor_is_kept_and_warns(data_dir, multi):
    root, _ = multi
    (root.parent / "settings.json").write_text(json.dumps({"cleanupPeriodDays": 400}), encoding="utf-8")
    write_aged_session(root, "aged-0001", 300)
    result = collect(data_dir, root, "--retention-days", "90")
    assert result.returncode == 1
    data = envelope(result)["data"]
    assert data["retention"]["days"] == 90
    (warning,) = data["warnings"]
    assert "90" in warning and "400" in warning
    assert "aged-0001" not in records(data_dir), "a value the user set below the floor is honored"


def test_sources_file_missing_warns_and_malformed_exits_2(data_dir, multi, tmp_path):
    root, _ = multi
    missing = collect(data_dir, root, "--sources-file", str(tmp_path / "absent.json"))
    assert missing.returncode == 1 and envelope(missing)["data"]["ingested"] == 3, "the local default is read"
    bad = tmp_path / "bad.json"
    bad.write_text("{", encoding="utf-8")
    malformed = collect(data_dir, root, "--sources-file", str(bad))
    assert (malformed.returncode, envelope(malformed)["data"]["sources_file"]) == (2, str(bad))


def test_history_only_prompts_are_stored_with_their_pastes(data_dir, multi):
    root, _ = multi
    config = root.parent
    (config / "paste-cache").mkdir()
    (config / "paste-cache" / "abc123.txt").write_text("the pasted body", encoding="utf-8")
    entries = [
        {"display": "fix this [Pasted text #1 +3 lines] please", "timestamp": 1790000000000, "project": "/w/repo",
         "sessionId": "gone-0001", "pastedContents": {"1": {"id": 1, "type": "text", "contentHash": "abc123"}}},
        {"display": "inline [Pasted text #2] and [Pasted text #3]", "timestamp": 1790000001000, "project": "/w/repo",
         "sessionId": "gone-0002",
         "pastedContents": {"2": {"id": 2, "type": "text", "content": "inline body"}, "3": {"id": 3, "type": "text"}}},
        {"display": "has a transcript", "timestamp": 1790000002000, "project": "/w/repo", "sessionId": "sess-a1"},
    ]
    (config / "history.jsonl").write_text("".join(json.dumps(e) + "\n" for e in entries), encoding="utf-8")
    result = collect(data_dir, root)
    assert result.returncode == 0, result.stdout + result.stderr
    assert envelope(result)["data"]["history_prompts"] == 2
    prompts = {
        p["session_id"]: p
        for p in (json.loads(f.read_text(encoding="utf-8")) for f in store_root(data_dir).glob("local/history/*.json"))
    }
    assert set(prompts) == {"gone-0001", "gone-0002"}, "a prompt whose session has a transcript is not stored"
    assert prompts["gone-0001"]["excerpt"] == "fix this the pasted body please"
    assert prompts["gone-0001"]["schema"] == "history-prompt/v1"
    assert prompts["gone-0001"]["provenance"]["source"] == "local"
    assert prompts["gone-0002"]["excerpt"] == "inline inline body and [Pasted text #3]"
    assert prompts["gone-0002"]["pastes"] == {"restored": 1, "missing": 1}
    assert envelope(collect(data_dir, root))["data"]["history_prompts"] == 0, "a stored prompt is not written again"


def test_a_history_prompt_under_a_home_keeps_its_raw_project_slug_beside_the_redacted_project(data_dir, multi):
    root, _ = multi
    project = "/" + "home/user-a/repos/orders.api"
    entry = {"display": "rename the flag", "timestamp": 1790000000000, "project": project, "sessionId": "gone-0001"}
    (root.parent / "history.jsonl").write_text(json.dumps(entry) + "\n", encoding="utf-8")
    assert collect(data_dir, root).returncode == 0
    (path,) = store_root(data_dir).glob("local/history/*.json")
    stored = json.loads(path.read_text(encoding="utf-8"))
    assert (stored["project"], stored["project_slug"]) == ("~/repos/orders.api", "-home-user-a-repos-orders-api")


def test_stored_history_prompt_is_rewritten_when_its_payload_changes(data_dir, multi):
    root, _ = multi
    entry = {"display": "rename the flag", "timestamp": 1790000000000, "project": "/w/repo", "sessionId": "gone-0001"}
    (root.parent / "history.jsonl").write_text(json.dumps(entry) + "\n", encoding="utf-8")

    def stored() -> dict:
        (path,) = store_root(data_dir).glob("local/history/*.json")
        return json.loads(path.read_text(encoding="utf-8"))

    assert envelope(collect(data_dir, root, "--excerpt-chars", "0"))["data"]["history_prompts"] == 1
    assert stored()["excerpt"] is None
    assert envelope(collect(data_dir, root))["data"]["history_prompts"] == 1, "a prompt stored without its excerpt is rewritten"
    assert stored()["excerpt"] == "rename the flag"
    assert envelope(collect(data_dir, root))["data"]["history_prompts"] == 0, "an unchanged prompt is not written again"


@pytest.mark.skipif(sys.platform == "win32", reason="a Windows-form cwd maps under the automount root on POSIX only")
def test_windows_cwd_maps_to_automount(tmp_path):
    import session_record

    mapped = tmp_path / "mnt" / "c" / "work" / "repo"
    mapped.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(mapped)], check=True)
    identity = session_record.RepoIdentity(on_warn=lambda _m: None, automount_root=str(tmp_path / "mnt"))
    assert identity.lookup("C:\\work\\repo") == tuple(state_key(mapped).rsplit("/", 1))
    assert identity.lookup("D:\\nowhere") == (None, None), "a Windows cwd whose mapped directory is missing keeps null"


def test_config_dir_adds_a_named_local_source(data_dir, multi, tmp_path):
    root, _ = multi
    extra = tmp_path / "extra" / "projects"
    shutil.copytree(root / "proj-a", extra / "proj-a")
    result = collect(data_dir, root, "--config-dir", str(extra))
    assert result.returncode == 0, result.stdout + result.stderr
    names = {source for source, _ in by_source(data_dir)}
    (added,) = names - {"local"}
    assert added.startswith("dir-") and "local" in names
    only = envelope(collect(data_dir, root, "--config-dir", str(extra.parent), "--source", added, "--force"))["data"]
    assert [s["name"] for s in only["sources"]] == [added], "the parent configuration directory names the same source"
    missing = collect(data_dir, root, "--config-dir", str(tmp_path / "nothing"))
    assert (missing.returncode, envelope(missing)["status"]) == (2, "error")


def statuses(data_dir: Path) -> dict[str, str]:
    return {sid: rec["status"] for sid, rec in records(data_dir).items()}


def test_force_keeps_a_gone_transcript_gone(data_dir, multi):
    root, _ = multi
    assert collect(data_dir, root).returncode == 0
    (root / "proj-a" / "sess-a2.jsonl").unlink()
    assert collect(data_dir, root).returncode == 0
    forced = collect(data_dir, root, "--force")
    assert forced.returncode == 0, forced.stdout + forced.stderr
    assert envelope(forced)["data"]["ingested"] == 2, "--force re-reads every session still on disk"
    assert statuses(data_dir) == {"sess-a1": "present", "sess-a2": "transcript-gone", "sess-b1": "present"}


def local_sources(tmp_path: Path, root: Path, **defaults) -> Path:
    path = tmp_path / "local-sources.json"
    source = {"name": "local", "host": "local", "platform": "linux", "config_dir": str(root.parent)}
    path.write_text(json.dumps({"schema": "transcript-sources/v1", "defaults": defaults, "sources": [source]}), encoding="utf-8")
    return path


def test_a_partial_read_presumes_nothing_it_listed(data_dir, multi, tmp_path):
    root, _ = multi
    assert collect(data_dir, root).returncode == 0
    starved = collect(data_dir, root, "--force", "--sources-file", str(local_sources(tmp_path, root, memory_bytes=1)))
    assert [g["kind"] for g in envelope(starved)["data"]["gaps"]] == ["partial"]
    assert set(statuses(data_dir).values()) == {"present"}, "every session was listed before the read stopped"


@pytest.mark.skipif(sys.platform == "win32" or os.geteuid() == 0, reason="needs POSIX permissions that bind")
def test_one_unreadable_session_presumes_nothing_else(data_dir, multi):
    root, _ = multi
    assert collect(data_dir, root).returncode == 0
    locked = root / "proj-a" / "sess-a2.jsonl"
    append_record(locked, {"type": "user", "uuid": "b-u8", "timestamp": "2026-09-21T09:06:00Z", "message": {"role": "user", "content": "x"}})
    locked.chmod(0)
    try:
        result = collect(data_dir, root)
    finally:
        locked.chmod(0o644)
    assert [g["kind"] for g in envelope(result)["data"]["gaps"]] == ["unreadable"]
    assert set(statuses(data_dir).values()) == {"present"}


@pytest.mark.skipif(sys.platform == "win32" or os.geteuid() == 0, reason="needs POSIX permissions that bind")
def test_an_unlistable_project_is_a_gap_never_gone(data_dir, multi):
    root, _ = multi
    assert collect(data_dir, root).returncode == 0
    (root / "proj-b").chmod(0)
    try:
        result = collect(data_dir, root)
    finally:
        (root / "proj-b").chmod(0o755)
    assert [g["kind"] for g in envelope(result)["data"]["gaps"]] == ["unreadable"]
    got = statuses(data_dir)
    assert got["sess-b1"] == "presumed-gone-unverified", "unchecked and past the default 30-day cleanup, not confirmed gone"
    assert (got["sess-a1"], got["sess-a2"]) == ("present", "present")


def test_retention_prunes_only_the_sources_read(data_dir, multi, tmp_path):
    root, _ = multi
    assert collect(data_dir, root).returncode == 0
    other = tmp_path / "other" / "projects"
    shutil.copytree(root / "proj-a", other / "proj-a")
    data = envelope(collect(data_dir, root, "--config-dir", str(other), "--retention-days", "0"))["data"]
    (added,) = {s["name"] for s in data["sources"]} - {"local"}
    pruned = envelope(collect(data_dir, root, "--config-dir", str(other), "--source", added, "--retention-days", "1"))["data"]
    assert pruned["pruned"] == 2
    assert {source for source, _ in by_source(data_dir)} == {"local"}, "the local source's records stay"


@pytest.mark.skipif(sys.platform == "win32", reason="the via scripts are POSIX shell")
def test_a_source_without_hello_is_judged_by_its_last_reported_cleanup_period(data_dir, fleet, tmp_path):
    sources, env, root, other = fleet
    (other / "settings.json").write_text(json.dumps({"cleanupPeriodDays": 400}), encoding="utf-8")
    spec = json.loads(sources.read_text(encoding="utf-8"))
    broken = {**spec, "sources": [spec["sources"][0], {**spec["sources"][1], "via": [str(tmp_path / "no-such-via")]}]}
    fresh = tmp_path / "fresh-data"
    fresh.mkdir()
    assert collect_sources(fresh, sources, env).returncode == 0
    sources.write_text(json.dumps(broken), encoding="utf-8")
    assert collect_sources(fresh, sources, env).returncode == 1
    (diag,) = [s for s in json.loads(Path(diag_path(fresh)).read_text(encoding="utf-8"))["sources"] if s["name"] == "host-b-wsl"]
    assert (diag["cleanup_period_days"], diag["cleanup_period_days_basis"]) == (400, "prior-diagnostics")
    assert {r["status"] for (s, _), r in by_source(fresh).items() if s == "host-b-wsl"} == {"present"}, (
        "sessions that ended about 66 days ago are inside the 400 days the source last reported"
    )
    assert collect_sources(data_dir, sources, env).returncode == 1
    (diag,) = [s for s in json.loads(Path(diag_path(data_dir)).read_text(encoding="utf-8"))["sources"] if s["name"] == "host-b-wsl"]
    assert (diag["cleanup_period_days"], diag["cleanup_period_days_basis"]) == (30, "default"), "no report on record falls back to 30"
