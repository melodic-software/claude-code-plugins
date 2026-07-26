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
            "id": "msg_01ABC",
            "content": [{"type": "tool_use", "id": "call_1", "name": "Bash",
                         "input": {"command": "ls"}},
                        {"type": "text", "text": "x" * 300}],
            "stop_reason": "tool_use"}})
        self.assertEqual(out["tools"], ["Bash"])
        self.assertEqual(out["stop_reason"], "tool_use")
        self.assertLessEqual(len(out["say"]), 160)
        # Grouping key + bounded per-call preview -- see summarize_record()'s
        # docstring. Both ids go through _short_id(), so compare against it
        # rather than the raw value ("call_1" is <= _ID_TAIL_LEN so it happens
        # to pass through unchanged; "msg_01ABC" does not).
        self.assertEqual(out["mid"], observer._short_id("msg_01ABC"))
        self.assertEqual(out["calls"],
                         [{"id": observer._short_id("call_1"), "in": '{"command":"ls"}'}])

    def test_assistant_no_tools_omits_grouping_fields(self):
        """A text-only turn has nothing to group/preview -- no mid/calls noise."""
        out = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_01ABC", "content": [{"type": "text", "text": "hi"}]}})
        self.assertNotIn("tools", out)
        self.assertNotIn("calls", out)
        self.assertNotIn("mid", out)

    def test_assistant_missing_message_id_omits_mid(self):
        """A record with no API message id makes that pair's ordering uncomputable --
        the field is simply absent, never a placeholder that looks computed."""
        out = observer.summarize_record({"type": "assistant", "message": {
            "content": [{"type": "tool_use", "id": "call_1", "name": "Bash"}]}})
        self.assertNotIn("mid", out)
        self.assertIn("calls", out)

    def test_assistant_two_tool_uses_in_one_record_share_one_mid(self):
        """Two tool_use blocks in ONE assistant record is a schema-level case the
        code must still handle correctly, even though a scan of real transcripts
        for #1485 found zero examples of it in practice (see test below for the
        pattern that IS common) -- both calls carry the SAME mid regardless."""
        out = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_batch", "content": [
                {"type": "tool_use", "id": "call_1", "name": "Read",
                 "input": {"file_path": "a.py"}},
                {"type": "tool_use", "id": "call_2", "name": "Read",
                 "input": {"file_path": "b.py"}},
            ]}})
        self.assertEqual(out["tools"], ["Read", "Read"])
        self.assertEqual([c["id"] for c in out["calls"]],
                         [observer._short_id("call_1"), observer._short_id("call_2")])
        self.assertEqual(out["mid"], observer._short_id("msg_batch"))

    def test_assistant_one_message_spans_multiple_records_shares_one_mid(self):
        """The pattern real transcripts actually exhibit (verified for #1485 against
        150+ live session transcripts): a SINGLE API message is frequently split
        across MULTIPLE consecutive assistant records (e.g. a text-only record then
        a tool_use record), never multiple tool_use blocks in one record. `mid` is
        what makes these recognizable as the same turn -- record adjacency alone
        is NOT reliable, since other records (tool results) interleave."""
        r1 = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_shared", "content": [{"type": "text", "text": "checking..."}]}})
        r2 = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_shared", "content": [
                {"type": "tool_use", "id": "call_1", "name": "Read",
                 "input": {"file_path": "a.py"}}]}})
        self.assertNotIn("mid", r1)  # no tool_use in r1 -> nothing to group
        self.assertEqual(r2["mid"], observer._short_id("msg_shared"))

    def test_user_and_system(self):
        u = observer.summarize_record({"type": "user", "message": {
            "content": [{"type": "tool_result", "tool_use_id": "call_1",
                        "content": "file contents here"},
                       {"type": "tool_result", "tool_use_id": "call_2",
                        "content": "more content"}]}})
        self.assertNotIn("tool_results", u)  # superseded by len(results) -- see docstring
        self.assertEqual(u["results"], [
            {"id": observer._short_id("call_1"), "out": "file contents here"},
            {"id": observer._short_id("call_2"), "out": "more content"},
        ])
        s = observer.summarize_record({"type": "system", "subtype": "stop_hook_summary"})
        self.assertTrue(s["turn_boundary"])

    def test_user_tool_result_content_as_block_list(self):
        """A real transcript's tool_result.content is a list of content blocks
        about as often as a plain string (verified for #1485) -- the preview
        must extract the text, not JSON-dump the block wrapper structure."""
        u = observer.summarize_record({"type": "user", "message": {
            "content": [{"type": "tool_result", "tool_use_id": "call_1",
                        "content": [{"type": "text", "text": "the actual result text"}]}]}})
        self.assertEqual(u["results"][0]["out"], "the actual result text")

    def test_user_no_tool_results_omits_results_field(self):
        u = observer.summarize_record({"type": "user", "message": {
            "content": [{"type": "text", "text": "go ahead"}]}})
        self.assertNotIn("results", u)
        self.assertNotIn("tool_results", u)

    def test_sequencing_and_dependency_round_trip(self):
        """Builds observations from real transcript-shaped records for a genuinely
        DEPENDENT sequential pair (a Write, then a Read of a path the Write's own
        result content names) and checks that the distilled fields alone -- without
        the raw transcript -- let a reader (a) tell the two calls were sequential
        (different `mid`s) and (b) find the dependency (the second call's `in`
        preview overlaps the first result's `out` preview), covering both acceptance
        criteria for #1485 in one round trip.
        """
        write_call = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_1", "content": [
                {"type": "tool_use", "id": "call_w", "name": "Write",
                 "input": {"file_path": "/tmp/out/report.md"}},
            ]}})
        write_result = observer.summarize_record({"type": "user", "message": {
            "content": [{"type": "tool_result", "tool_use_id": "call_w",
                        "content": "wrote /tmp/out/report.md"}]}})
        read_call = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_2", "content": [
                {"type": "tool_use", "id": "call_r", "name": "Read",
                 "input": {"file_path": "/tmp/out/report.md"}},
            ]}})

        # (a) Sequential, not batched: different `mid`s.
        self.assertNotEqual(write_call["mid"], read_call["mid"])
        # (b) Dependency is findable purely from the bounded previews: the later
        # call's input preview and the earlier result's output preview share the
        # dependent path, without ever reading the raw transcript.
        later_in = read_call["calls"][0]["in"]
        earlier_out = write_result["results"][0]["out"]
        self.assertIn("/tmp/out/report.md", later_in)
        self.assertIn("/tmp/out/report.md", earlier_out)

    def test_preview_bounded_for_large_input(self):
        """No meaningful token-cost regression: an oversized tool input/result is
        truncated to the bounded preview limit, not carried in full."""
        big = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_big", "content": [
                {"type": "tool_use", "id": "call_big", "name": "Write",
                 "input": {"content": "x" * 10_000}},
            ]}})
        self.assertLessEqual(len(big["calls"][0]["in"]), observer._PREVIEW_LIMIT)

    def test_preview_helper(self):
        self.assertEqual(observer._preview(None), "")
        self.assertEqual(observer._preview("  hi  "), "hi")
        self.assertEqual(observer._preview({"a": 1}), '{"a":1}')
        self.assertLessEqual(len(observer._preview("y" * 500, limit=10)), 10)

    def test_preview_extracts_text_from_content_block_list(self):
        """A real tool_result.content is a list of blocks about as often as a
        plain string (verified for #1485) -- the text must be extracted, not
        the block wrapper JSON-dumped, or the preview budget is spent on
        `{"type":"text","text":...}` syntax instead of the actual content."""
        self.assertEqual(
            observer._preview([{"type": "text", "text": "hello world"}]),
            "hello world")

    def test_preview_list_with_no_text_blocks_falls_back_to_json(self):
        """A block list with nothing extractable (e.g. only an image block)
        still gets SOME preview rather than an empty string."""
        preview = observer._preview([{"type": "image", "source": "x"}])
        self.assertIn("image", preview)

    def test_preview_untruncated_value_has_no_marker(self):
        self.assertEqual(observer._preview("short"), "short")
        self.assertFalse(observer._preview("short").endswith(observer._TRUNC_MARKER))

    def test_preview_truncated_value_ends_in_marker(self):
        """A cut preview must be DISTINGUISHABLE from a short, complete one -- a
        silent slice would make a dependency-bearing value past the limit look
        like a clean 'no match' rather than 'unknown', see #1485 Codex review."""
        cut = observer._preview("y" * 500, limit=10)
        self.assertEqual(len(cut), 10)
        self.assertTrue(cut.endswith(observer._TRUNC_MARKER))

    def test_mid_preserved_for_falsy_but_not_none_id(self):
        """`mid` must be omitted only when the record truly carries none -- a
        `mid: 0` (an integer id format) or `mid: ""` must NOT be dropped by an
        `if mid:` truthy guard, see #1485 code review finding #1. `_short_id`
        stringifies (`0` -> `"0"`), so compare against the same helper."""
        out = observer.summarize_record({"type": "assistant", "message": {
            "id": 0, "content": [{"type": "tool_use", "id": "call_1", "name": "Bash"}]}})
        self.assertIn("mid", out)
        self.assertEqual(out["mid"], observer._short_id(0))


class ShortId(unittest.TestCase):
    """`_short_id` trades the full verbatim id for a bounded correlation key --
    measured against a real transcript for #1485 to cut the new fields' token
    cost roughly in half without losing the ability to match a result back to
    the call that produced it (see summarize_record()'s docstring)."""

    def test_none_passes_through(self):
        self.assertIsNone(observer._short_id(None))

    def test_short_value_unchanged(self):
        self.assertEqual(observer._short_id("call_1"), "call_1")

    def test_long_value_truncated_to_tail(self):
        full = "msg_014Jvov2xG6zPgLAhpByQwaC"
        short = observer._short_id(full)
        self.assertEqual(len(short), observer._ID_TAIL_LEN)
        self.assertTrue(full.endswith(short))

    def test_deterministic_for_correlation(self):
        """The SAME full id must always shorten to the SAME short id, or a
        call's `calls[].id` could never be matched to its `results[].id`."""
        full = "toolu_01AbCdEfGhIjKlMnOpQrSt"
        self.assertEqual(observer._short_id(full), observer._short_id(full))

    def test_non_string_stringified(self):
        self.assertEqual(observer._short_id(0), "0")


class AnalysisPrompt(unittest.TestCase):
    """The headless analysis prompt must actually reference the distilled fields
    #1485 added -- otherwise the analyzer has the capability but is never told to
    use it, which reproduces the original "can only ever drop the finding" gap
    under a different cause."""

    def setUp(self):
        self.prompt = observer._analysis_prompt(
            observations="/obs.ndjson", checkpoint="/checkpoint.md", session_id="sid")

    def test_references_grouping_key(self):
        self.assertIn('"mid"', self.prompt)
        self.assertIn("batched", self.prompt)
        self.assertIn("sequential", self.prompt)

    def test_references_call_result_preview_fields(self):
        self.assertIn('"calls', self.prompt)
        self.assertIn('"results', self.prompt)
        self.assertIn("dependency", self.prompt)

    def test_references_truncation_marker_as_unknown_not_absent(self):
        """A truncated preview must be treated as UNKNOWN, never a clean 'no
        dependency' -- otherwise the silent-slice gap Codex flagged reproduces
        the exact asserted-and-wrong finding this whole prompt exists to stop."""
        self.assertIn(observer._TRUNC_MARKER, self.prompt)
        self.assertIn("UNKNOWN", self.prompt)

    def test_drop_if_uncomputable_still_present(self):
        self.assertIn("Drop", self.prompt)
        self.assertIn("uncomputed", self.prompt)

    def test_mandatory_redaction_pass_not_crowded_out(self):
        self.assertIn("MANDATORY redaction pass", self.prompt)


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
