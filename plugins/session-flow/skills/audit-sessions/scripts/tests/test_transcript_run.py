# test-scope: plugins/session-flow/lib/state-key.sh plugins/session-flow/vendor/gitleaks/gitleaks-rules.json plugins/session-flow/skills/audit-sessions/scripts/tests/fixtures/multi/*

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest
from conftest import FIXTURES, PLUGIN_SCRIPTS

import session_record
import transcript_sources
import transcript_run
from transcript_sources import SourceEntry

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
del _leaked_git_var

STATE_KEY = PLUGIN_SCRIPTS.parent / "lib" / "state-key.sh"
FAKE_CC_VERSION = "9.9.9"
SH_VIA = ("sh", "-c")


@pytest.fixture
def host(tmp_path, monkeypatch):
    """An invented host's configuration directory holding the multi fixture's two proj-a sessions."""
    work = tmp_path / "work" / "repo"
    work.mkdir(parents=True)
    config = tmp_path / "host-a" / "config"
    project = config / "projects" / "-work-repo"
    shutil.copytree(FIXTURES / "multi" / "proj-a", project)
    for path in project.rglob("*.jsonl"):
        text = path.read_text(encoding="utf-8").replace("__CWD_A__", json.dumps(str(work))[1:-1])
        path.write_text(text, encoding="utf-8", newline="\n")
    (config / "settings.json").write_text(json.dumps({"cleanupPeriodDays": 14}), encoding="utf-8")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "claude").write_text(f"#!/bin/sh\necho '{FAKE_CC_VERSION} (Claude Code)'\n", encoding="utf-8")
    (bin_dir / "claude").chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    return config, work


def snapshot(*roots: Path) -> dict[str, tuple[int, int]]:
    return {
        str(path): (path.stat().st_size, path.stat().st_mtime_ns)
        for root in roots
        for path in [root, *root.rglob("*")]
    }


def entry(config: Path, via: tuple[str, ...] | None) -> SourceEntry:
    return SourceEntry(name="host-a-wsl", host="host-a", platform="wsl", config_dir=str(config), via=via)


def data_dir(tmp_path: Path) -> str:
    path = tmp_path / "data"
    path.mkdir(exist_ok=True)
    return str(path)


NO_WAIT = {"limits": {"lock_timeout_s": 0}}


def lock_options(tmp_path: Path) -> dict:
    return {"lock_name": f"transcript-run-test-{os.getpid()}-{tmp_path.name}"}


def held(records: list[dict]) -> list[dict]:
    """What a caller that stored these records sends back: each fingerprint with its stored policy."""
    return [
        {
            "project": r["project"],
            "session_id": r["session_id"],
            "fingerprint": r["record"]["fingerprint"],
            "policy": session_record.stored_policy(r["record"]),
        }
        for r in records
    ]


def probe_twice(config: Path, work: Path, via, options: dict, data: str) -> None:
    before = snapshot(config, work)
    first = transcript_run.read_remote(entry(config, via), options=options, data_dir=data)
    assert first.gaps == [], first.gaps
    assert first.hello["protocol"] == 1
    assert first.hello["cleanup_period_days"] == 14
    assert first.hello["cc_version"] == FAKE_CC_VERSION
    assert sorted(r["session_id"] for r in first.records) == ["sess-a1", "sess-a2"]
    assert snapshot(config, work) == before, "the reading child changed the host's files"

    known = held(first.records)
    second = transcript_run.read_remote(entry(config, via), fingerprints=known, options=options, data_dir=data)
    assert (second.gaps, second.records) == ([], [])
    assert second.end["skipped_unchanged"] == 2
    assert snapshot(config, work) == before, "the second read changed the host's files"


def test_probe_empty_via(host, tmp_path):
    config, work = host
    probe_twice(config, work, None, lock_options(tmp_path), data_dir(tmp_path))


def test_probe_sh_via(host, tmp_path):
    config, work = host
    probe_twice(config, work, SH_VIA, lock_options(tmp_path), data_dir(tmp_path))


@pytest.mark.skipif(sys.platform == "win32", reason="the broken python3 is a POSIX shell script")
def test_local_read_does_not_need_python3_on_path(host, tmp_path):
    config, _ = host
    broken = tmp_path / "bin" / "python3"
    broken.write_text("#!/bin/sh\nexit 127\n", encoding="utf-8")
    broken.chmod(0o755)
    read = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), options=lock_options(tmp_path))
    assert (read.gaps, len(read.records)) == ([], 2), "a local read runs this interpreter, not whatever python3 PATH finds"


def test_remote_repo_identity(host, tmp_path):
    config, work = host
    subprocess.run(["git", "init", "-q", str(work)], check=True)
    local = subprocess.run(["bash", str(STATE_KEY), "--root", str(work)], capture_output=True, text=True, check=True)
    identity, worktree = local.stdout.strip().rsplit("/", 1)

    read = transcript_run.read_remote(entry(config, SH_VIA), options=lock_options(tmp_path))
    assert read.gaps == []
    pairs = {(r["record"]["repo_identity"], r["record"]["worktree"]) for r in read.records}
    assert pairs == {(identity, worktree)}, "repo identity must come from the shipped state-key.sh text"


def test_redaction_rules_shipped(host, tmp_path):
    config, _ = host
    rules = json.loads((PLUGIN_SCRIPTS.parent / "vendor" / "gitleaks" / "gitleaks-rules.json").read_text(encoding="utf-8"))
    read = transcript_run.read_remote(entry(config, SH_VIA), options=lock_options(tmp_path))
    assert read.gaps == []
    for message in read.records:
        redaction = message["record"]["redaction"]
        assert (redaction["rules_loaded"], redaction["excerpts_suppressed"]) == (len(rules["rules"]), False)


def wait_for(child: subprocess.Popen, predicate) -> list[dict]:
    """The child's messages up to the first one `predicate` accepts; the child is killed after 30 s."""
    deadline = threading.Timer(30, child.kill)
    deadline.start()
    seen: list[dict] = []
    try:
        for raw in child.stdout:
            seen.append(json.loads(raw))
            if predicate(seen[-1]):
                return seen
    finally:
        deadline.cancel()
    raise AssertionError(f"the reader never sent the awaited message (exit {child.wait()}): {seen}")


def rest(child: subprocess.Popen) -> list[dict]:
    if not child.stdin.closed:
        child.stdin.close()
    out = [json.loads(raw) for raw in child.stdout]
    assert child.wait(timeout=60) == 0
    return out


def test_busy_gap_has_pid(host, tmp_path):
    config, _ = host
    options = lock_options(tmp_path)
    lock = transcript_run.local_lock(options["lock_name"])
    assert lock.acquired
    try:
        second = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), options={**options, **NO_WAIT})
    finally:
        lock.release()
    assert [(g.kind, g.holder_pid) for g in second.gaps] == [("busy", os.getpid())]
    assert second.records == []


@pytest.mark.skipif(not sys.platform.startswith("linux"), reason="the abstract-socket lock is Linux only")
def test_local_reader_waits_for_the_host_lock(host, tmp_path):
    config, _ = host
    options = {**lock_options(tmp_path), "limits": {"lock_timeout_s": 30}}
    lock = transcript_run.local_lock(options["lock_name"])
    assert lock.acquired
    releaser = threading.Timer(1.0, lock.release)
    releaser.start()
    try:
        read = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), options=options)
    finally:
        releaser.join()
    assert (read.gaps, len(read.records)) == ([], 2), "a local reader waits for a lock released within lock_timeout_s"


@pytest.mark.skipif(not sys.platform.startswith("linux"), reason="the abstract-socket lock is Linux only")
def test_local_reader_gives_up_at_lock_timeout(host, tmp_path):
    config, _ = host
    options = {**lock_options(tmp_path), "limits": {"lock_timeout_s": 0.5}}
    lock = transcript_run.local_lock(options["lock_name"])
    assert lock.acquired
    started = time.monotonic()
    try:
        read = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), options=options)
    finally:
        lock.release()
    assert time.monotonic() - started >= 0.5, "the reader waited out lock_timeout_s"
    assert [(g.kind, g.holder_pid) for g in read.gaps] == [("lock_timeout", os.getpid())]
    assert read.records == []


@pytest.mark.skipif(sys.platform == "win32", reason="the gated bash is a POSIX shell script")
def test_two_remote_readers(host, tmp_path):
    config, _ = host
    options = lock_options(tmp_path)
    gate, release = tmp_path / "gate", tmp_path / "release"
    gate.mkdir()
    (gate / "bash").write_text(
        f'#!/bin/sh\nwhile [ ! -e "{release}" ]; do sleep 0.05; done\nexec {shutil.which("bash")} "$@"\n', encoding="utf-8"
    )
    (gate / "bash").chmod(0o755)
    env = {**os.environ, "PATH": f"{gate}{os.pathsep}{os.environ['PATH']}"}
    first = subprocess.Popen(transcript_run.command(None), stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env)
    first.stdin.write(transcript_run.manifest({"config_dir": str(config), **options}))
    first.stdin.close()
    try:
        wait_for(first, lambda m: m.get("event") == "lock")
        second = transcript_run.read_remote(entry(config, SH_VIA), options=options)
    finally:
        release.touch()
        held_out = rest(first)
    assert ([g.kind for g in second.gaps], second.records) == (["busy"], [])
    assert sorted(m["session_id"] for m in held_out if m["kind"] == "record") == ["sess-a1", "sess-a2"]


def test_stalled_caller_holds_no_lock(host, tmp_path):
    config, _ = host
    options = lock_options(tmp_path)
    stalled = subprocess.Popen(transcript_run.command(None), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    stalled.stdin.write(transcript_run.manifest({"config_dir": str(config), **options}))
    stalled.stdin.flush()
    try:
        wait_for(stalled, lambda m: m["kind"] == "hello")
        second = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), options=options)
    finally:
        late = rest(stalled)
    assert (second.gaps, len(second.records)) == ([], 2), "a reader still waiting on its stdin must not hold the host lock"
    assert len([m for m in late if m["kind"] == "record"]) == 2


@pytest.mark.parametrize("change", [{"collector_digest": "digest-2"}, {"excerpt_chars": 100}, {"excerpt_words": 5}])
def test_changed_policy_reingests(host, tmp_path, change):
    config, _ = host
    options = {**lock_options(tmp_path), "collector_digest": "digest-1"}
    first = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), options=options)
    assert first.gaps == [] and len(first.records) == 2
    same = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), fingerprints=held(first.records), options=options)
    assert same.records == []
    changed = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), fingerprints=held(first.records), options={**options, **change})
    assert changed.gaps == [] and len(changed.records) == 2, "a record built under another policy must be rebuilt"


def test_oversize_fingerprint_line_is_a_protocol_gap(host, tmp_path):
    config, _ = host
    huge = {"project": "x" * (transcript_run.MAX_FINGERPRINT_LINE + 1), "session_id": "s", "fingerprint": {}, "policy": {}}
    read = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), fingerprints=[huge], options=lock_options(tmp_path))
    assert ([g.kind for g in read.gaps], read.records) == (["protocol"], [])


def test_oversize_message_is_a_protocol_gap(host, tmp_path, monkeypatch):
    config, _ = host
    monkeypatch.setattr(transcript_run, "MAX_MESSAGE_BYTES", 1000)
    read = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), options=lock_options(tmp_path))
    assert ([g.kind for g in read.gaps], read.records) == (["protocol"], [])


@pytest.mark.skipif(os.name != "posix" or os.geteuid() == 0, reason="needs POSIX permissions a non-root user cannot bypass")
def test_unreadable_session_gap_names_only_the_exception_type(host, tmp_path):
    config, _ = host
    locked = next((config / "projects").glob("*/sess-a2.jsonl"))
    locked.chmod(0)
    try:
        read = transcript_run.read_remote(entry(config, None), data_dir=data_dir(tmp_path), options=lock_options(tmp_path))
    finally:
        locked.chmod(0o644)
    assert [(g.kind, g.detail) for g in read.gaps] == [("unreadable", "a session could not be read (PermissionError)")]
    assert [r["session_id"] for r in read.records] == ["sess-a1"]


@pytest.mark.skipif(sys.platform == "win32", reason="the cd-ing via is a POSIX shell script")
@pytest.mark.parametrize("via_kind", ["empty", "cd"])
def test_planted_module_in_the_child_cwd_is_not_imported(host, tmp_path, monkeypatch, via_kind):
    config, _ = host
    plant, marker = tmp_path / "plant", tmp_path / "planted-json-ran"
    plant.mkdir()
    (plant / "json.py").write_text(f"open({str(marker)!r}, 'w').close()\n", encoding="utf-8")
    via = None
    if via_kind == "empty":
        monkeypatch.chdir(plant)
    else:
        cd_via = tmp_path / "bin" / "cd-via"
        cd_via.write_text(f'#!/bin/sh\nshift\ncd "{plant}" || exit 255\nexec sh -c "$1"\n', encoding="utf-8")
        cd_via.chmod(0o755)
        via = (str(cd_via), "host-a")
    read = transcript_run.read_remote(entry(config, via), data_dir=data_dir(tmp_path), options=lock_options(tmp_path))
    assert read.gaps == [] and len(read.records) == 2
    assert not marker.exists(), "a json.py in the reader's working directory ran before the loader"


def test_data_dir_lock_follows_no_symlink(tmp_path):
    target = tmp_path / "target"
    target.write_text("untouched", encoding="utf-8")
    (tmp_path / transcript_run.DATA_LOCK_FILE).symlink_to(target)
    lock = transcript_run.data_dir_lock(str(tmp_path / transcript_run.DATA_LOCK_FILE))
    assert (lock.acquired, lock.gap) == (False, "unreadable")
    assert target.read_text(encoding="utf-8") == "untouched"


def test_imports_without_fcntl_resource(tmp_path):
    probe = (
        "import sys\n"
        "sys.modules['fcntl'] = None\n"
        "sys.modules['resource'] = None\n"
        f"sys.path.insert(0, {str(PLUGIN_SCRIPTS)!r})\n"
        "import transcript_run\n"
        f"lock = transcript_run.local_lock({lock_options(tmp_path)['lock_name']!r}, platform='win32')\n"
        "print(lock.mechanism, lock.acquired, transcript_run.peak_rss_bytes())\n"
    )
    done = subprocess.run([sys.executable, "-c", probe], capture_output=True, text=True, timeout=60)
    assert done.returncode == 0, done.stderr
    mechanism, acquired, peak = done.stdout.split()
    assert (mechanism, acquired) == ("missing", "True")
    if sys.platform.startswith("linux") or sys.platform == "win32":
        assert int(peak) > 0, "Linux reads the peak from /proc and Windows from K32GetProcessMemoryInfo, neither through resource"
    else:
        assert peak == "None", "with no /proc and no resource module there is no peak to report"


@pytest.mark.skipif(sys.platform == "win32", reason="the fake ssh is a POSIX shell script")
def test_via_runs_the_loader_as_one_shell_command(host, tmp_path):
    config, _ = host
    fake_ssh = tmp_path / "bin" / "fake-ssh"
    fake_ssh.write_text(
        '#!/bin/sh\nshift\n[ "$#" -eq 1 ] || exit 255\ntouch "$0.ran"\nexec sh -c "$1"\n', encoding="utf-8"
    )
    fake_ssh.chmod(0o755)
    read = transcript_run.read_remote(entry(config, (str(fake_ssh), "host-a")), options=lock_options(tmp_path))
    assert read.gaps == [] and len(read.records) == 2
    assert Path(f"{fake_ssh}.ran").exists(), "the read must go through the via, as ssh would carry it"


HELLO = '{"kind": "hello", "protocol": 1}'
RECORD = '{"kind": "record", "project": "p-0123456789ab", "session_id": "s1", "record": {}}'
END = '{"kind": "diag", "event": "end"}'


@pytest.mark.skipif(sys.platform == "win32", reason="the hostile host is a POSIX shell script")
@pytest.mark.parametrize(
    ("lines", "tail", "kept"),
    [
        ([HELLO, RECORD.replace('"s1"', '"../../outside"'), END], "", 0),
        ([HELLO, RECORD.replace('"p-0123456789ab"', '"../p"'), END], "", 0),
        ([HELLO, RECORD], '{"kind": "re', 1),
        (['{"kind": "hello", "protocol": 2}', END], "", 0),
        ([HELLO, '{"kind": "exec", "argv": ["rm"]}', END], "", 0),
        ([HELLO, RECORD], "", 1),
    ],
    ids=["path-in-session-id", "path-in-project", "truncated", "other-protocol", "unknown-kind", "no-end-line"],
)
def test_hostile_stream_is_a_protocol_gap(tmp_path, lines, tail, kept):
    host = tmp_path / "hostile-host"
    quoted = " ".join(f"'{line}'" for line in lines)
    host.write_text(f"#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' {quoted}\nprintf '%s' '{tail}'\n", encoding="utf-8")
    host.chmod(0o755)
    read = transcript_run.read_remote(entry(tmp_path, (str(host), "host-b")))
    assert [g.kind for g in read.gaps] == ["protocol"]
    assert len(read.records) == kept


@pytest.mark.skipif(not sys.platform.startswith("linux"), reason="the abstract-socket lock is Linux only")
def test_many_waiting_readers_each_get_busy_quickly(tmp_path):
    name = lock_options(tmp_path)["lock_name"]
    holder = transcript_run.local_lock(name)
    assert holder.acquired
    results: list = []

    def probe() -> None:
        started = time.monotonic()
        lock = transcript_run.local_lock(name)
        results.append((lock.acquired, lock.holder_pid, time.monotonic() - started))

    try:
        probes = [threading.Thread(target=probe) for _ in range(12)]
        for thread in probes:
            thread.start()
        for thread in probes:
            thread.join(timeout=10)
    finally:
        holder.release()
    assert len(results) == 12, "a probe hung on the holder's socket"
    assert {(acquired, pid) for acquired, pid, _ in results} == {(False, os.getpid())}
    assert max(elapsed for *_, elapsed in results) < 5


def test_relock_after_release_in_one_process(tmp_path):
    name = lock_options(tmp_path)["lock_name"]
    first = transcript_run.local_lock(name)
    first.release()
    second = transcript_run.local_lock(name)
    second.release()
    assert (first.acquired, second.acquired) == (True, True), "a released lock must be free for this process again"


def test_local_readers_share_the_data_dir_lock_across_socket_names(host, tmp_path):
    config, _ = host
    data = data_dir(tmp_path)
    other_reader = transcript_run.data_dir_lock(str(Path(data) / transcript_run.DATA_LOCK_FILE))
    assert other_reader.acquired
    try:
        read = transcript_run.read_remote(entry(config, None), data_dir=data, options={**lock_options(tmp_path), **NO_WAIT})
    finally:
        other_reader.release()
    assert ([g.kind for g in read.gaps], read.records) == (["busy"], []), "a reader the abstract socket cannot see is still found"


def _unshare_net_works() -> bool:
    if shutil.which("unshare") is None:
        return False
    return subprocess.run(["unshare", "-rn", "true"], capture_output=True, timeout=30).returncode == 0


@pytest.mark.skipif(not _unshare_net_works(), reason="unshare -rn (a user and network namespace) is not available here")
def test_local_reader_in_another_network_namespace_sees_the_file_lock(host, tmp_path):
    config, _ = host
    data = data_dir(tmp_path)
    holder = transcript_run.data_dir_lock(str(Path(data) / transcript_run.DATA_LOCK_FILE))
    assert holder.acquired
    args = {"config_dir": str(config), **lock_options(tmp_path), **NO_WAIT, "data_lock": str(Path(data) / transcript_run.DATA_LOCK_FILE)}
    try:
        done = subprocess.run(
            ["unshare", "-rn", *transcript_run.command(None)],
            input=transcript_run.manifest(args),
            capture_output=True,
            timeout=60,
        )
    finally:
        holder.release()
    gaps = [m["gap"] for m in map(json.loads, done.stdout.splitlines()) if m["kind"] == "gap"]
    assert gaps == ["busy"], done.stdout.decode("utf-8", "replace")


@pytest.mark.skipif(os.name != "posix" or os.geteuid() == 0, reason="needs POSIX permissions a non-root user cannot bypass")
def test_unwritable_data_dir_is_a_sandboxed_gap(host, tmp_path):
    config, _ = host
    data = Path(data_dir(tmp_path))
    data.chmod(0o500)
    try:
        read = transcript_run.read_remote(entry(config, None), data_dir=str(data), options=lock_options(tmp_path))
        capped = transcript_run.read_remote(
            entry(config, None), data_dir=str(data), options={**lock_options(tmp_path), "capped": True}
        )
    finally:
        data.chmod(0o700)
    assert ([g.kind for g in read.gaps], read.records) == (["sandboxed"], [])
    assert (capped.gaps, len(capped.records)) == ([], 2), "a capped lookup takes no lock, so it still reads"


@pytest.mark.parametrize("platform", [None, "darwin"], ids=["this-platform", "no-abstract-socket"])
def test_remote_read_writes_no_file(host, tmp_path, monkeypatch, platform):
    config, _ = host
    data = data_dir(tmp_path)
    tmpdir = tmp_path / "tmpdir"
    tmpdir.mkdir()
    monkeypatch.setenv("TMPDIR", str(tmpdir))
    options = {**lock_options(tmp_path), **({"lock_platform": platform} if platform else {})}
    before = snapshot(tmp_path)
    read = transcript_run.read_remote(entry(config, SH_VIA), data_dir=data, options=options)
    assert read.gaps == [] and len(read.records) == 2
    assert snapshot(tmp_path) == before, "a read over a via must create no lock file, in TMPDIR or anywhere else"
    if platform:
        assert [d["mechanism"] for d in read.diags if d.get("event") == "lock"] == ["missing"]


MIB = 1024 * 1024
RETRY = ("collect.py", "collect")


def sources_of(*entries: SourceEntry, **limits) -> transcript_sources.Sources:
    return transcript_sources.Sources(entries, "file", transcript_sources.HostLimits(**limits))


def add_bulk_session(config: Path, mib: int) -> None:
    """A session after the fixture's two whose one record is `mib` MiB of empty JSON lists.

    Each three-byte `[],` parses to a list object of about 64 bytes, so a small file grows the
    reader by some twenty times its size within one record.
    """
    blob = "[" + ",".join(["[]"] * (mib * MIB // 3)) + "]"
    record = '{"type": "fixture-bulk", "blob": ' + blob + "}"
    (config / "projects" / "-work-repo" / "sess-z-bulk.jsonl").write_text(record + "\n", encoding="utf-8")


def baseline_peak(config: Path, tmp_path: Path) -> int:
    """The reader's peak resident memory over the fixture's two sessions, from a first run's diagnostics."""
    result, _ = collect(sources_of(entry(config, None)), tmp_path)
    peak = source_diag(diagnostics(result), "host-a-wsl")["peak_rss"]
    assert isinstance(peak, int) and peak > 0
    return peak


def collect(sources, tmp_path: Path, **kwargs):
    seen: list[tuple[str, str]] = []
    result = transcript_run.run(
        sources,
        lambda source, message: seen.append((source.name, message["session_id"])) if message["kind"] == "record" else None,
        store_dir=tmp_path / "store",
        data_dir=data_dir(tmp_path),
        retry_argv=RETRY,
        options=kwargs.pop("options", {}),
        lock_name=lock_options(tmp_path)["lock_name"],
        retention_days=kwargs.pop("retention_days", 0),
        **kwargs,
    )
    return result, seen


def diagnostics(result) -> dict:
    assert result.diagnostics_path is not None, "the run wrote no diagnostics record"
    record = json.loads(Path(result.diagnostics_path).read_text(encoding="utf-8"))
    assert record["schema"] == "transcript-run.diagnostics/v1"
    return record


def source_diag(record: dict, name: str) -> dict:
    return next(source for source in record["sources"] if source["name"] == name)


class _SameSecondClock:
    """`time` for transcript_run with `time()` stepping 1 ms at a time inside one wall-clock second."""

    def __init__(self) -> None:
        self.now = 1_790_000_000.1

    def time(self) -> float:
        self.now += 0.001
        return self.now

    def __getattr__(self, name):
        return getattr(time, name)


@pytest.mark.skipif(sys.platform == "win32", reason="the failing via is a POSIX shell")
def test_run_status_takes_the_later_of_two_runs_in_one_second(host, tmp_path, monkeypatch):
    config, _ = host
    run_ids = iter(["f" * 12, "0" * 12])
    monkeypatch.setattr(transcript_sources.secrets, "token_hex", lambda _n: next(run_ids))
    monkeypatch.setattr(transcript_run, "time", _SameSecondClock())
    clean, _ = collect(sources_of(entry(config, None)), tmp_path)
    failed, _ = collect(sources_of(entry(config, ("sh", "-c", "exit 255"))), tmp_path)
    assert ([g.kind for g in clean.gaps], [g.kind for g in failed.gaps]) == ([], ["unreachable"])
    status = transcript_sources.run_status(tmp_path / "store" / "diagnostics")
    assert status.path == Path(failed.diagnostics_path), "the run that finished last is the latest, whatever its file name"
    assert [g["kind"] for g in status.gaps] == ["unreachable"]


def test_ceiling_partial(host, tmp_path):
    config, _ = host
    ceiling = baseline_peak(config, tmp_path) + 6 * MIB
    add_bulk_session(config, 2)
    sources = sources_of(entry(config, None), memory_bytes=ceiling, check_every_records=1, backstop_ratio=64)
    result, seen = collect(sources, tmp_path)
    assert [(g.kind, g.source) for g in result.gaps] == [("partial", "host-a-wsl")]
    assert sorted(session for _, session in seen) == ["sess-a1", "sess-a2"], "records finished before the ceiling are kept"
    assert result.exit_code == 1
    assert source_diag(diagnostics(result), "host-a-wsl")["limits_applied"]["memory_bytes"] == ceiling


def test_ceiling_from_prior_peak(host, tmp_path):
    config, _ = host
    seeded = tmp_path / "store" / "diagnostics" / "2026-11-01-seed.json"
    seeded.parent.mkdir(parents=True)
    seeded.write_text(
        json.dumps({"schema": "transcript-run.diagnostics/v1", "sources": [{"name": "host-a-wsl", "peak_rss": 123_456_789}]}),
        encoding="utf-8",
    )
    baseline, _ = collect(sources_of(entry(config, None)), tmp_path)
    applied = source_diag(diagnostics(baseline), "host-a-wsl")["limits_applied"]
    assert (applied["memory_bytes"], applied["memory_basis"]) == (185_185_183, "prior-peak"), "1.5 times the seeded peak"

    capped, _ = collect(sources_of(entry(config, None), memory_bytes=100_000_000), tmp_path)
    applied = source_diag(diagnostics(capped), "host-a-wsl")["limits_applied"]
    assert applied["memory_bytes"] == 100_000_000, "a prior peak never lifts the ceiling past the configured limit"


@pytest.mark.skipif(not sys.platform.startswith("linux"), reason="RLIMIT_AS is enforced on Linux only")
def test_backstop_kill(host, tmp_path):
    config, _ = host
    ceiling = baseline_peak(config, tmp_path) + 6 * MIB
    other = tmp_path / "host-b" / "config"
    shutil.copytree(config, other)
    add_bulk_session(config, 4)
    first = entry(config, None)
    second = SourceEntry(name="host-b-wsl", host="host-b", platform="wsl", config_dir=str(other), via=SH_VIA)
    sources = sources_of(first, second, memory_bytes=ceiling, check_every_records=10**9, backstop_ratio=1)
    result, seen = collect(sources, tmp_path)
    assert [(g.kind, g.source) for g in result.gaps] == [("backstop_kill", "host-a-wsl")]
    assert sorted(seen) == [
        ("host-a-wsl", "sess-a1"), ("host-a-wsl", "sess-a2"), ("host-b-wsl", "sess-a1"), ("host-b-wsl", "sess-a2"),
    ], "the run goes on to the next source after the backstop kill"
    assert result.exit_code == 1


def test_off_unix_limits(host, tmp_path):
    config, _ = host
    options = {"limits_platform": "windows"}
    result, seen = collect(sources_of(entry(config, None), slow_read_s=1e-6), tmp_path, options=options)
    assert result.gaps == () and len(seen) == 2
    record = diagnostics(result)
    source = source_diag(record, "host-a-wsl")
    assert {"cpu_priority", "disk_priority", "backstop"} <= set(source["limits_missing"])
    assert source["limits_applied"]["check_every_records"] == 5000
    assert source["limits_applied"]["memory_basis"] == "fraction-of-physical"
    assert [w for w in record["warnings"] if "host-a-wsl" in w and "slow" in w], record["warnings"]

    starved, kept = collect(sources_of(entry(config, None), memory_bytes=1), tmp_path, options=options)
    assert ([g.kind for g in starved.gaps], kept) == (["partial"], []), "off Unix the memory check still stops the read"


@pytest.mark.skipif(sys.platform == "win32", reason="the flaky via is a POSIX shell script")
def test_retry_reads_only_gaps(host, tmp_path):
    config, _ = host
    flaky = tmp_path / "bin" / "flaky-via"
    flaky.write_text(
        f'#!/bin/sh\nshift\nif [ ! -e "{tmp_path}/up" ]; then touch "{tmp_path}/up"; exit 255; fi\nexec sh -c "$1"\n',
        encoding="utf-8",
    )
    flaky.chmod(0o755)
    remote = SourceEntry(name="host-b-wsl", host="host-b", platform="wsl", config_dir=str(config), via=(str(flaky), "host-b"))
    sources = sources_of(entry(config, None), remote)
    first, seen = collect(sources, tmp_path)
    assert [(g.kind, g.source) for g in first.gaps] == [("unreachable", "host-b-wsl")]
    assert {name for name, _ in seen} == {"host-a-wsl"}
    retry = first.gaps[0].retry_argv
    assert retry == (*RETRY, "--source", "host-b-wsl")
    only = [retry[i + 1] for i, arg in enumerate(retry) if arg == "--source"]
    again, seen_again = collect(sources, tmp_path, only=only)
    assert again.gaps == () and again.exit_code == 0
    assert sorted(seen_again) == [("host-b-wsl", "sess-a1"), ("host-b-wsl", "sess-a2")], "the retry reads only the gap's source"
    assert again.sources_done == ("host-b-wsl",)


@pytest.mark.skipif(sys.platform == "win32", reason="the hung via is a POSIX shell script")
@pytest.mark.parametrize(("says_hello", "kind"), [(False, "unreachable"), (True, "partial")])
def test_wall_time_limit_kills_a_hung_via(tmp_path, says_hello, kind):
    hung = tmp_path / "hung-via"
    hello = f"printf '%s\\n' '{HELLO}'\n" if says_hello else ""
    hung.write_text(f"#!/bin/sh\ncat >/dev/null\n{hello}sleep 120\n", encoding="utf-8")
    hung.chmod(0o755)
    source = SourceEntry(name="host-b-wsl", host="host-b", platform="wsl", config_dir=str(tmp_path), via=(str(hung), "host-b"))
    started = time.monotonic()
    result, _ = collect(sources_of(source, read_timeout_s=0.2), tmp_path)
    assert time.monotonic() - started < 30, "the hung via (and the sleep it started) must be killed at the wall-time limit"
    assert [(g.kind, g.source) for g in result.gaps] == [(kind, "host-b-wsl")]
    assert result.gaps[0].retry_argv == (*RETRY, "--source", "host-b-wsl")


def test_lookup_writes_diagnostics_only_for_a_gap(host, tmp_path):
    config, _ = host
    clean, _ = collect(sources_of(entry(config, None)), tmp_path, kind="lookup")
    assert (clean.gaps, clean.diagnostics_path) == ((), None)
    assert not (tmp_path / "store" / "diagnostics").exists(), "a clean lookup writes nothing"
    missing = SourceEntry(name="host-b-wsl", host="host-b", platform="wsl", config_dir=str(config), via=(str(tmp_path / "no-such-via"),))
    gapped, _ = collect(sources_of(missing), tmp_path, kind="lookup")
    assert diagnostics(gapped)["kind"] == "lookup"
    assert gapped.gaps[0].retry_argv == RETRY, "a lookup's retry is the same invocation, verbatim"


def test_diagnostics_past_retention_are_pruned(host, tmp_path):
    config, _ = host
    diag_dir = tmp_path / "store" / "diagnostics"
    diag_dir.mkdir(parents=True)
    old, orphan = diag_dir / "2020-01-01-old.json", diag_dir / "2020-01-01-crashed.json.tmp"
    for path in (old, orphan):
        path.write_text("{}", encoding="utf-8")
    aged = time.time() - 200 * 86400
    os.utime(old, (aged, aged))
    hours_ago = time.time() - 2 * 3600
    os.utime(orphan, (hours_ago, hours_ago))

    kept, _ = collect(sources_of(entry(config, None)), tmp_path, retention_days=0)
    assert old.exists(), "a store retention of 0 keeps every record"
    assert not orphan.exists(), "a staging file a crashed write left behind is pruned whatever the retention"

    result, _ = collect(sources_of(entry(config, None)), tmp_path, retention_days=180)
    assert not old.exists(), "a record older than the store's 180-day retention is pruned"
    assert Path(kept.diagnostics_path).exists() and Path(result.diagnostics_path).exists()


def test_reader_stops_at_its_own_deadline(host, tmp_path):
    config, _ = host
    options = {**lock_options(tmp_path), "limits": {"read_timeout_s": 1e-6}}
    read = transcript_run.read_remote(entry(config, SH_VIA), options=options, timeout_s=None)
    assert ([g.kind for g in read.gaps], read.records) == (["partial"], []), "the reader enforces read_timeout_s with no caller timer"
    assert read.end is not None and read.returncode == 0, "the reader ends its stream and exits on its own"
    relock = transcript_run.local_lock(options["lock_name"])
    relock.release()
    assert relock.acquired, "the reader released its host lock when it stopped"


class CountingMeter:
    def __init__(self, stop_at_tick: int | None = None) -> None:
        self.checks = self.ticks = 0
        self.stop_at_tick = stop_at_tick

    def check(self) -> None:
        self.checks += 1

    def tick(self) -> None:
        self.ticks += 1
        if self.ticks == self.stop_at_tick:
            raise transcript_run.CeilingReached(0)


def build_with(meter: CountingMeter, main: Path) -> dict:
    import redact

    return session_record.build_record(
        main, [], session_record.fingerprint(main, []), version="test", digest="d", redactor=redact.load_redactor(),
        identity=session_record.RepoIdentity(on_warn=lambda _m: None), excerpt_chars=240, excerpt_words=60, meter=meter,
    )


def test_build_record_meters_through_the_meter_it_is_given(host):
    config, _ = host
    main = config / "projects" / "-work-repo" / "sess-a2.jsonl"
    meter = CountingMeter()
    build_with(meter, main)
    assert (meter.checks, meter.ticks) == (1, 3), "one file checked, and a tick for each of its three good lines"
    with pytest.raises(transcript_run.CeilingReached):
        build_with(CountingMeter(stop_at_tick=2), main)


def test_diagnostics_carry_drift_counts(host, tmp_path):
    config, _ = host
    result, _ = collect(sources_of(entry(config, None)), tmp_path)
    drift = source_diag(diagnostics(result), "host-a-wsl")["drift"]
    assert set(drift) == {"bad_lines", "incomplete", "unknown", "platform_mismatch"}
    assert drift["bad_lines"] == 1, "sess-a2 holds one line that is not JSON"


def test_same_size_rerun_after_a_recorded_peak_is_not_partial(host, tmp_path):
    config, _ = host
    baseline_peak(config, tmp_path)
    rerun, seen = collect(sources_of(entry(config, None)), tmp_path)
    assert (rerun.gaps, len(seen)) == ((), 2), "a rerun of the same sessions must fit under a ceiling taken from its own peak"
    assert source_diag(diagnostics(rerun), "host-a-wsl")["limits_applied"]["memory_basis"] == "prior-peak"


def test_mounted_platform_is_windows_only_for_a_wsl_reader_under_the_automount_root(tmp_path):
    mount = tmp_path / "mnt"
    under = mount / "c" / "Users" / "someone" / ".claude"
    under.mkdir(parents=True)
    elsewhere = tmp_path / "home" / ".claude"
    elsewhere.mkdir(parents=True)
    assert session_record.mounted_platform(under, "wsl", str(mount)) == "windows"
    assert session_record.mounted_platform(elsewhere, "wsl", str(mount)) is None
    assert session_record.mounted_platform(under, "linux", str(mount)) is None, "only a WSL reader sees Windows drives there"
    assert session_record.mounted_platform(mount, "wsl", str(mount)) is None, "the root itself is no drive"


READER = {"host": "host-a", "platform": "wsl", "config_dir": "/mnt/c/Users/someone/.claude", "cc_version": FAKE_CC_VERSION}


@pytest.mark.parametrize(
    ("declared", "mounted", "stamped_platform", "stamped_cc"),
    [
        ("windows", "windows", "windows", None),
        ("windows", None, "wsl", FAKE_CC_VERSION),
        ("wsl", None, "wsl", FAKE_CC_VERSION),
    ],
    ids=["windows-through-the-mount", "windows-not-under-the-mount", "same-platform"],
)
def test_provenance_of_a_source_read_through_another_platforms_mount(declared, mounted, stamped_platform, stamped_cc):
    hello = {**READER, "mounted_platform": mounted}
    assert session_record.provenance("host-a-src", hello, declared) == {
        "source": "host-a-src", "host": "host-a", "platform": stamped_platform,
        "config_dir": READER["config_dir"], "cc_version": stamped_cc,
    }


@pytest.mark.skipif(sys.platform == "win32", reason="the scripted reader is a POSIX shell script")
@pytest.mark.parametrize(("declared", "mounted", "mismatch"), [("windows", "windows", 0), ("windows", None, 1), ("wsl", None, 0)])
def test_diagnostics_keep_the_readers_report_and_count_a_platform_mismatch(tmp_path, declared, mounted, mismatch):
    hello = json.dumps({"kind": "hello", "protocol": 1, **READER, "cleanup_period_days": 30, "mounted_platform": mounted})
    end = json.dumps({"kind": "diag", "event": "end", "drift": {"bad_lines": 0, "incomplete": 0, "unknown": 0}})
    reader = tmp_path / "scripted-reader"
    reader.write_text(f"#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' '{hello}' '{end}'\n", encoding="utf-8")
    reader.chmod(0o755)
    source = SourceEntry(name="host-a-src", host="host-a", platform=declared, config_dir=READER["config_dir"], via=(str(reader), "host-a"))
    result, _ = collect(sources_of(source), tmp_path)
    diag = source_diag(diagnostics(result), "host-a-src")
    assert diag["drift"]["platform_mismatch"] == mismatch
    assert (diag["reported"]["platform"], diag["reported"]["cc_version"]) == ("wsl", FAKE_CC_VERSION), "the reader's own report is kept"
    assert diag["provenance"] == session_record.provenance("host-a-src", json.loads(hello), declared)


def test_the_child_hello_reports_its_own_platform(host, tmp_path):
    config, _ = host
    options = {**lock_options(tmp_path), "reader_platform": "windows", "automount_root": str(tmp_path)}
    read = transcript_run.read_remote(entry(config, None), options=options, data_dir=data_dir(tmp_path))
    assert read.hello["platform"] == transcript_sources.local_platform(), "no header arg rewrites the reader's self-report"
    assert read.hello["mounted_platform"] is None


def test_run_takes_the_lock_name_only_as_its_parameter(host, tmp_path):
    config, _ = host
    with pytest.raises(ValueError, match="lock_name"):
        collect(sources_of(entry(config, None)), tmp_path, options={"lock_name": "elsewhere"})
    with pytest.raises(ValueError, match="lock_name"):
        collect(sources_of(entry(config, None)), tmp_path, source_options=lambda _entry: {"lock_name": "elsewhere"})


def test_checked_lock_name_bounds_the_name_below_the_socket_limit():
    assert transcript_run.checked_lock_name("a" * 80) == "a" * 80
    for bad in ("a" * 81, "bad/name", "", "-lead"):
        with pytest.raises(ValueError):
            transcript_run.checked_lock_name(bad)


def test_lock_refusal_words_a_held_and_a_timed_out_lock():
    held = transcript_run.HostLock("abstract-socket", False, 42)
    assert transcript_run.lock_refusal(held) == {"gap": "busy", "detail": "another reader holds the host lock by pid 42", "holder_pid": 42}
    assert transcript_run.lock_refusal(held, waited_s=5) == {
        "gap": "lock_timeout", "detail": "another reader holds the host lock by pid 42, still after waiting 5 s", "holder_pid": 42,
    }
    sandboxed = transcript_run.HostLock("data-dir-flock", False, gap="sandboxed", detail="read-only data dir")
    assert transcript_run.lock_refusal(sandboxed) == {"gap": "sandboxed", "detail": "read-only data dir", "holder_pid": None}
