#!/usr/bin/env python3
"""Unit + integration tests for the detached observer (stdlib unittest, no deps).

Mirrors retro's `test_parse_transcript.py` convention. Covers the pieces the
observer's correctness rests on: distillation, the two-hop redaction sweep, the
`-p` result parsing, the atomic one-observer-per-session lock (including the race
and stale reclaim), ledger discovery/append with redaction, and the retention
rule (collect-only keeps observations, a consumed analysis deletes them).
"""
from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import threading
import time
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "observer", str(Path(__file__).with_name("observer.py")))
observer = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(observer)


def make_observer(tmp: Path, **overrides):
    """Build an Observer via the real parser so defaults always match production."""
    (tmp / "work").mkdir(exist_ok=True)
    (tmp / "ledger").mkdir(exist_ok=True)
    transcript = tmp / "sess.jsonl"
    transcript.write_text("", encoding="utf-8")
    argv = [
        "--transcript", str(transcript),
        "--work-dir", str(tmp / "work"),
        "--ledger-dir", str(tmp / "ledger"),
        "--session-id", overrides.get("session_id", "sid"),
        "--topic", "test",
        "--idle-seconds", str(overrides.get("idle_seconds", 1.0)),
        "--poll-seconds", str(overrides.get("poll_seconds", 0.2)),
        "--max-seconds", str(overrides.get("max_seconds", 10.0)),
    ]
    if overrides.get("analysis"):
        argv.append("--analysis")
    args = observer.build_parser().parse_args(argv)
    return observer.Observer(args)


class Distillation(unittest.TestCase):
    def test_assistant(self):
        out = observer.summarize_record({"type": "assistant", "message": {
            "content": [{"type": "tool_use", "name": "Bash"},
                        {"type": "text", "text": "x" * 300}],
            "stop_reason": "tool_use"}})
        self.assertEqual(out["tools"], ["Bash"])
        self.assertEqual(out["stop_reason"], "tool_use")
        self.assertLessEqual(len(out["say"]), 160)

    def test_user_and_system(self):
        u = observer.summarize_record({"type": "user", "message": {
            "content": [{"type": "tool_result"}, {"type": "tool_result"}]}})
        self.assertEqual(u["tool_results"], 2)
        s = observer.summarize_record({"type": "system", "subtype": "stop_hook_summary"})
        self.assertTrue(s["turn_boundary"])


class Redaction(unittest.TestCase):
    def test_shapes(self):
        r = observer._redact
        self.assertIn("<REDACTED: API key>", r("tok sk-ABC1234567890XYZ890 z"))
        self.assertIn("<REDACTED: GitHub token>", r("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"))
        self.assertIn("<REDACTED: connection string>", r("postgres://u:p@h/db"))
        self.assertIn("<REDACTED: email>", r("a.b+c@ex.co"))
        self.assertIn("<REDACTED: secret>", r('password: "hunter2hunter2"'))

    def test_clean_passthrough(self):
        self.assertEqual(observer._redact("no secrets here"), "no secrets here")


class ResultParsing(unittest.TestCase):
    def test_extract(self):
        self.assertEqual(observer._extract_result('{"result":"BLOCK"}'), "BLOCK")
        self.assertEqual(observer._extract_result('{"is_error":true,"result":"x"}'), "")
        self.assertEqual(observer._extract_result("plain"), "plain")

    def test_error(self):
        self.assertTrue(observer._result_error('{"is_error":true,"result":"Not logged in"}'))
        self.assertEqual(observer._result_error('{"is_error":false,"result":"ok"}'), "")


class Locking(unittest.TestCase):
    def test_single_and_release(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            a = make_observer(tmp)
            self.assertTrue(a.acquire_lock())
            b = make_observer(tmp)
            self.assertFalse(b.acquire_lock(), "second observer must be refused")
            a.release_lock()
            c = make_observer(tmp)
            self.assertTrue(c.acquire_lock(), "re-arm after release must succeed")
            c.release_lock()

    def test_stale_reclaim(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp)
            # A lock from a dead pid must be reclaimable.
            ob.lock_path.write_text(json.dumps(
                {"pid": 2 ** 30, "started": observer.now_iso(), "session_id": "sid"}),
                encoding="utf-8")
            self.assertTrue(ob.acquire_lock(), "stale (dead-pid) lock must be reclaimed")
            ob.release_lock()

    def test_partial_write_lock_treated_live(self):
        # A just-created lock the winner has not finished writing (empty/partial,
        # fresh mtime) must be treated as LIVE, never reclaimed -- otherwise a
        # racing loser could unlink it and both proceed.
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp)
            ob.lock_path.write_text("", encoding="utf-8")  # created, not yet written
            self.assertFalse(ob.acquire_lock(),
                             "empty/mid-write lock (fresh mtime) must not be reclaimed")

    def test_live_lock_not_reclaimed_by_age(self):
        # A lock held by a LIVE pid must never be reclaimed, even if its recorded
        # start is far past the tailing cap -- an idle-ended observer can hold its
        # lock for the whole analysis run (its own timeout).
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp)
            ob.lock_path.write_text(json.dumps({
                "pid": os.getpid(), "started": "2000-01-01T00:00:00+00:00",
                "session_id": "sid"}), encoding="utf-8")
            self.assertFalse(ob.acquire_lock(),
                             "a live pid must not be reclaimed regardless of age")

    def test_race_exactly_one_winner(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            obs = [make_observer(tmp) for _ in range(12)]
            wins: list[bool] = []
            lock = threading.Lock()
            barrier = threading.Barrier(len(obs))

            def run(o):
                barrier.wait()
                got = o.acquire_lock()
                with lock:
                    wins.append(got)

            threads = [threading.Thread(target=run, args=(o,)) for o in obs]
            for t in threads:
                t.start()
            for t in threads:
                t.join()
            self.assertEqual(sum(wins), 1, "exactly one racer may win the lock")


class LedgerAndRetention(unittest.TestCase):
    def test_find_and_append_with_redaction(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="s-1")
            self.assertIsNone(ob._find_session_ledger())
            ob._append_ledger("finding with token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345")
            led = ob._find_session_ledger()
            self.assertIsNotNone(led)
            text = led.read_text(encoding="utf-8")
            self.assertIn("session_id: s-1", text)
            self.assertIn("<REDACTED: GitHub token>", text)
            self.assertNotIn("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", text)
            # Second append reuses the same file (one ledger per session).
            ob._append_ledger("second block")
            self.assertEqual(len(list((tmp / "ledger").glob("*-running-retro-*.md"))), 1)

    def test_other_session_ledger_not_matched(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            (tmp / "ledger" / "20260101T000000Z-running-retro-x.md").parent.mkdir(
                parents=True, exist_ok=True)
            (tmp / "ledger" / "20260101T000000Z-running-retro-x.md").write_text(
                "---\nsession_id: other\n---\n", encoding="utf-8")
            ob = make_observer(tmp, session_id="mine")
            self.assertIsNone(ob._find_session_ledger())

    def test_analysis_command_is_tool_restricted(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="tr")
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            captured = {}

            class FakeProc:
                returncode = 0
                stdout = json.dumps({"is_error": False,
                                     "result": "### Checkpoint findings\n\nok"})
                stderr = ""

            def fake_run(cmd, input=None, **kw):
                captured["cmd"], captured["input"] = cmd, input
                return FakeProc()

            of, orr = observer._find_claude, observer.subprocess.run
            observer._find_claude = lambda: "claude"
            observer.subprocess.run = fake_run
            try:
                self.assertTrue(ob._run_analysis())
            finally:
                observer._find_claude, observer.subprocess.run = of, orr
            cmd = captured["cmd"]
            # Genuinely tool-restricted, MCP-off, prompt via stdin, --bare default off.
            self.assertEqual(cmd[cmd.index("--tools") + 1], "Read")
            self.assertIn("--strict-mcp-config", cmd)
            self.assertEqual(cmd[cmd.index("--permission-mode") + 1], "dontAsk")
            self.assertIsInstance(captured["input"], str)
            self.assertNotIn("--bare", cmd)
            self.assertIsNotNone(ob._find_session_ledger())

    def test_analysis_unavailable_retains(self):
        # claude CLI absent -> _run_analysis must report "not consumed" so run()
        # keeps the observations as the collect fallback rather than deleting them.
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True)
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            orig = observer._find_claude
            observer._find_claude = lambda: None
            try:
                self.assertFalse(ob._run_analysis(), "unavailable claude -> retain")
            finally:
                observer._find_claude = orig
            self.assertTrue(ob.obs_path.exists())

    def test_tail_no_duplicate_events_on_growth(self):
        # The offset must advance by bytes read, not the stat size, or a session
        # that grows across polls re-emits its tail. Run the tailer while the file
        # grows in batches and assert exactly one observation per record.
        import threading
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=False, idle_seconds=2.0, poll_seconds=0.15,
                               max_seconds=30.0)
            rec = '{"type":"user","message":{"content":"x"}}\n'
            total = 9

            tailer = threading.Thread(target=ob._tail_until_idle)
            tailer.start()
            time.sleep(0.3)  # let the tailer begin polling before growth starts
            for _ in range(3):
                with ob.transcript.open("a", encoding="utf-8") as f:
                    for _ in range(3):
                        f.write(rec)
                time.sleep(0.5)
            tailer.join(30)
            lines = [ln for ln in ob.obs_path.read_text(encoding="utf-8").splitlines() if ln]
            self.assertEqual(len(lines), total,
                             f"expected {total} distilled events, got {len(lines)} (dupes/underread?)")

    def test_resume_offset_from_prior_status(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="rs")
            self.assertEqual(ob._resume_offset(), 0)  # no prior status
            ob.status_path.write_text(json.dumps(
                {"target_session": "rs", "byte_offset": 4096}), encoding="utf-8")
            self.assertEqual(ob._resume_offset(), 4096)
            # A status file for a DIFFERENT session must not be resumed from.
            ob.status_path.write_text(json.dumps(
                {"target_session": "other", "byte_offset": 999}), encoding="utf-8")
            self.assertEqual(ob._resume_offset(), 0)

    def test_continuity_pointers_in_frontmatter(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            # Without pointers: only session_id + observer marker.
            a = make_observer(tmp, session_id="c1")
            a._append_ledger("f")
            self.assertNotIn("previous_running_retro",
                             a._find_session_ledger().read_text(encoding="utf-8"))
            # With pointers (as the in-session arm entry would pass): carried through.
            b = make_observer(tmp, session_id="c2")
            b.prev_running_retro = "/mem/running-retros/20260101T000000Z-running-retro-x.md"
            b.prev_session_id = "prior-sid"
            b._append_ledger("f")
            head = b._find_session_ledger().read_text(encoding="utf-8")
            self.assertIn("previous_running_retro: /mem/running-retros/", head)
            self.assertIn("previous_session_id: prior-sid", head)

    def test_memory_root_self_ignore_guard(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="gi")  # ledger_dir = tmp/ledger
            ob._append_ledger("finding")
            gi = ob.ledger_dir.parent / ".gitignore"
            self.assertTrue(gi.exists() and gi.read_text().strip() == "*",
                            "memory root must self-ignore with '*'")

    def test_guard_refuses_repo_root_and_aborts_write(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            # memory root == a repo root (has .git): the guard must NOT create a
            # .gitignore there, AND the ledger write must be refused (not left as
            # an untracked committable file under the repo).
            (tmp / "ledger").mkdir()
            (tmp / ".git").mkdir()
            ob = make_observer(tmp, session_id="rr")
            self.assertFalse(ob._ensure_memory_root_ignored())
            self.assertFalse(ob._append_ledger("f"), "write must be refused")
            self.assertFalse((tmp / ".gitignore").exists(),
                             "guard must never write a repo-root .gitignore")
            self.assertEqual(list((tmp / "ledger").glob("*.md")), [],
                             "no ledger may be written under a repo-root memory dir")

    def test_guard_ensures_star_in_existing_gitignore(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="ex")  # memory root = tmp/ledger's parent = tmp
            root = ob.ledger_dir.parent
            (root / ".gitignore").write_text("# notes\n!keep.txt\n", encoding="utf-8")
            self.assertTrue(ob._ensure_memory_root_ignored())
            body = (root / ".gitignore").read_text(encoding="utf-8")
            self.assertIn("*", body.splitlines())
            self.assertIn("# notes", body)  # existing content preserved

    def test_retention_rule(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            # Collect-only (analysis off): observations retained.
            ob = make_observer(tmp, analysis=False)
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            consumed = False  # mirrors run(): no analysis -> not consumed -> retained
            if consumed:
                ob._cleanup_observations()
            self.assertTrue(ob.obs_path.exists(), "collect-only must retain observations")
            # Consumed analysis: observations deleted.
            ob._cleanup_observations()
            self.assertFalse(ob.obs_path.exists())


class ArmLauncher(unittest.TestCase):
    @staticmethod
    def _arm():
        spec = importlib.util.spec_from_file_location(
            "arm_observer", str(Path(__file__).with_name("arm_observer.py")))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        return m

    def test_live_observer_detected_for_manual_arm(self):
        arm = self._arm()
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            self.assertIsNone(arm.live_observer_pid(str(tmp), "s"))  # no lock
            (tmp / "observer-s.lock").write_text(
                json.dumps({"pid": os.getpid()}), encoding="utf-8")
            self.assertEqual(arm.live_observer_pid(str(tmp), "s"), os.getpid())
            (tmp / "observer-s.lock").write_text(
                json.dumps({"pid": 2 ** 30}), encoding="utf-8")  # dead pid
            self.assertIsNone(arm.live_observer_pid(str(tmp), "s"))


if __name__ == "__main__":
    unittest.main()
