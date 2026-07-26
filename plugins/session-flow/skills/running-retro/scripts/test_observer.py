#!/usr/bin/env python3
"""Unit + integration tests for the detached observer (stdlib unittest, no deps).

Mirrors retro's `test_parse_transcript.py` convention. Covers the pieces the
observer's correctness rests on: distillation, the two-hop redaction sweep, the
`-p` result parsing, the atomic one-observer-per-session lock (including the race
and stale reclaim), ledger discovery/append with redaction, and the retention
rule (collect-only keeps observations, a consumed analysis deletes them).
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import shutil
import sys
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

    def test_assistant_one_message_spans_multiple_tool_bearing_records_shares_one_mid(self):
        """The pattern real transcripts actually exhibit (verified for #1485: of
        6352 tool-bearing message ids across 200 live session transcripts, 1412
        (~22%) span 2+ tool-bearing records -- confirmed again as a positive
        control against this repo's OWN session transcripts, 580/5431, ~11%): a
        SINGLE API message's tool calls are frequently split across MULTIPLE
        assistant records rather than packed into one record's content list.
        `mid` is what makes these recognizable as the SAME batched turn -- record
        adjacency alone is NOT reliable, since other records (tool results, text-
        only records) interleave. This is the invariant the analysis prompt's
        batching computation actually depends on, so both records here carry a
        tool_use (not one text-only + one tool-bearing, which wouldn't exercise
        cross-record mid-sharing between two calls at all)."""
        r1 = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_shared", "content": [
                {"type": "tool_use", "id": "call_1", "name": "Read",
                 "input": {"file_path": "a.py"}}]}})
        r2 = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_shared", "content": [
                {"type": "tool_use", "id": "call_2", "name": "Read",
                 "input": {"file_path": "b.py"}}]}})
        self.assertEqual(r1["mid"], r2["mid"])
        self.assertEqual(r1["mid"], observer._short_id("msg_shared"))

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
        self.assertEqual(observer._preview(None), ("", False))
        self.assertEqual(observer._preview("  hi  "), ("hi", False))
        self.assertEqual(observer._preview({"a": 1}), ('{"a":1}', False))
        self.assertEqual(observer._preview("y" * 500, limit=10), ("y" * 10, True))

    def test_preview_extracts_text_from_content_block_list(self):
        """A real tool_result.content is a list of blocks about as often as a
        plain string (verified for #1485) -- the text must be extracted, not
        the block wrapper JSON-dumped, or the preview budget is spent on
        `{"type":"text","text":...}` syntax instead of the actual content."""
        self.assertEqual(
            observer._preview([{"type": "text", "text": "hello world"}]),
            ("hello world", False))

    def test_preview_list_with_no_text_blocks_falls_back_to_json(self):
        """A block list with nothing extractable (e.g. only an image block)
        still gets SOME preview rather than an empty string."""
        preview, _ = observer._preview([{"type": "image", "source": "x"}])
        self.assertIn("image", preview)

    def test_untruncated_entry_omits_cut_flag(self):
        out = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_1", "content": [
                {"type": "tool_use", "id": "call_1", "name": "Bash",
                 "input": {"command": "ls"}}]}})
        self.assertNotIn("cut", out["calls"][0])

    def test_truncated_entry_carries_cut_flag(self):
        """A cut preview must be DISTINGUISHABLE from a short, complete one -- a
        silent slice would make a dependency-bearing value past the limit look
        like a clean 'no match' rather than 'unknown', see #1485 Codex review."""
        out = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_1", "content": [
                {"type": "tool_use", "id": "call_1", "name": "Write",
                 "input": {"content": "x" * 10_000}}]}})
        self.assertTrue(out["calls"][0]["cut"])
        self.assertEqual(len(out["calls"][0]["in"]), observer._PREVIEW_LIMIT)

    def test_value_ending_in_ellipsis_is_not_reported_cut(self):
        """An in-band trailing marker is ambiguous: a complete tool result that
        naturally ends in `...` would read as truncated and wrongly suppress an
        otherwise computable sequencing finding, see #1485 Codex review. The
        cut signal is out-of-band, so a literal trailing `...` is just text."""
        u = observer.summarize_record({"type": "user", "message": {
            "content": [{"type": "tool_result", "tool_use_id": "call_1",
                         "content": "Processing complete..."}]}})
        self.assertEqual(u["results"][0]["out"], "Processing complete...")
        self.assertNotIn("cut", u["results"][0])

    def test_failed_tool_result_carries_err_flag(self):
        """A failed call's own output is routinely empty or generic, so without
        `err` a retry reads as an independent unbatched sibling rather than a
        call that could only be chosen after the failure, see #1485 Codex
        review."""
        u = observer.summarize_record({"type": "user", "message": {
            "content": [
                {"type": "tool_result", "tool_use_id": "call_1", "content": "",
                 "is_error": True},
                {"type": "tool_result", "tool_use_id": "call_2", "content": "ok"},
            ]}})
        self.assertTrue(u["results"][0]["err"])
        self.assertNotIn("err", u["results"][1])

    def test_mixed_block_result_reported_incomplete(self):
        """Text alongside an image block keeps only the text -- the omitted
        block could carry the dependency, so the preview is not complete even
        though it fits the limit, see #1485 Codex review."""
        u = observer.summarize_record({"type": "user", "message": {
            "content": [{"type": "tool_result", "tool_use_id": "call_1", "content": [
                {"type": "text", "text": "see attached"},
                {"type": "image", "source": "x"},
            ]}]}})
        self.assertEqual(u["results"][0]["out"], "see attached")
        self.assertTrue(u["results"][0]["cut"])

    def test_text_only_block_list_not_reported_incomplete(self):
        """The mixed-block rule must not fire on an all-text block list."""
        u = observer.summarize_record({"type": "user", "message": {
            "content": [{"type": "tool_result", "tool_use_id": "call_1", "content": [
                {"type": "text", "text": "a"}, {"type": "text", "text": "b"},
            ]}]}})
        self.assertNotIn("cut", u["results"][0])

    def test_narration_cut_flag(self):
        """The dependency check reads `say` for a control/resource/side-effect
        dependency, so a silently cut narration would read as showing none."""
        short = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_1", "content": [{"type": "text", "text": "brief"}]}})
        self.assertNotIn("say_cut", short)
        long = observer.summarize_record({"type": "assistant", "message": {
            "id": "msg_2", "content": [{"type": "text", "text": "z" * 500}]}})
        self.assertTrue(long["say_cut"])
        self.assertEqual(len(long["say"]), observer._NARRATION_LIMIT)

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
    """The headless run has no delegation prompt to fall back on, so the
    compute-don't-assert rule (#1473) must be inline in this prompt text itself,
    not only documented in checkpoint.md's Method section -- and the prompt must
    reference the distilled fields #1485 added, otherwise the analyzer has the
    capability but is never told to use it, which reproduces the original "can
    only ever drop the finding" gap under a different cause."""

    def setUp(self):
        self.prompt = observer._analysis_prompt(
            observations="/obs.ndjson", checkpoint="/checkpoint.md", session_id="sid")

    def test_compute_dont_assert_rule_present(self):
        self.assertIn("Compute, don't assert", self.prompt)
        # Names the failure modes the validation report actually observed.
        self.assertIn("sequencing", self.prompt)
        self.assertIn("batching", self.prompt)
        self.assertIn("delegation", self.prompt)
        self.assertIn("occurrence count", self.prompt)
        self.assertIn("message id", self.prompt)
        # Uncomputable structural claims must be dropped, not asserted anyway.
        self.assertIn("drop the claim", self.prompt)

    def test_absent_grouping_key_reads_as_uncomputable(self):
        """`summarize_record()` now carries a message id as `mid`, but only when
        the raw record had one -- so the prompt must still say that an ABSENT
        grouping key makes the claim uncomputable rather than licensing an
        assertion from impression."""
        self.assertIn('NO "mid" at all', self.prompt)
        self.assertIn("UNCOMPUTABLE", self.prompt)
        rec = observer.summarize_record(
            {"type": "assistant",
             "message": {"content": [{"type": "tool_use", "name": "Read"}]}})
        self.assertNotIn("mid", rec)

    def test_dependency_check_before_batching_finding_present(self):
        # A correctly computed sequencing fact doesn't by itself prove a missed
        # batching opportunity -- genuinely dependent calls are correctly
        # sequential, not a miss. The compute-don't-assert rule must cover the
        # Efficiency judgment built on top of a computed structural fact, not
        # only the fact itself, and "dependent" must not be narrowed to data
        # flow alone -- control, resource, and side-effect dependencies are
        # just as real a reason two calls had to run in order.
        self.assertIn("missed batching opportunity", self.prompt)
        self.assertIn("dependency", self.prompt)
        self.assertIn("control", self.prompt)
        self.assertIn("resource", self.prompt)
        self.assertIn("side-effect", self.prompt)

    def test_references_grouping_key(self):
        self.assertIn('"mid"', self.prompt)
        self.assertIn("batched", self.prompt)
        self.assertIn("sequential", self.prompt)

    def test_references_call_result_preview_fields(self):
        self.assertIn('"calls', self.prompt)
        self.assertIn('"results', self.prompt)
        self.assertIn("dependency", self.prompt)

    def test_references_cut_flags_as_unknown_not_absent(self):
        """A cut value must be treated as UNKNOWN, never a clean 'no dependency'
        -- otherwise the silent-slice gap Codex flagged reproduces the exact
        asserted-and-wrong finding this whole prompt exists to stop. The rule
        must key off the out-of-band flags, not off how a preview ends."""
        self.assertIn('"cut": true', self.prompt)
        self.assertIn('"say_cut"', self.prompt)
        self.assertIn('"human_cut"', self.prompt)
        self.assertIn("UNKNOWN", self.prompt)
        self.assertIn("never by how a preview happens to end", self.prompt)

    def test_missing_grouping_key_is_not_asserted_sequential(self):
        """The no-`mid` case must NOT also be listed as "ran sequentially" --
        the same clause asserting sequential execution and the drop rule calling
        it uncomputable are contradictory instructions, see #1485 Codex review."""
        self.assertIn("never evidence of sequential execution", self.prompt)

    def test_candidate_pair_confined_to_one_user_turn(self):
        """Calls answering two different human prompts have different `mid`s but
        could never have been batched -- the later request didn't exist yet. The
        turn-boundary gate must run before the dependency test, see #1485 Codex
        review. Both signals it names are real distilled fields."""
        self.assertIn("ONE user turn", self.prompt)
        self.assertIn('"turn_boundary": true', self.prompt)
        boundary = observer.summarize_record(
            {"type": "system", "subtype": "stop_hook_summary"})
        self.assertTrue(boundary["turn_boundary"])
        human = observer.summarize_record(
            {"type": "user", "message": {"content": "do the next thing"}})
        self.assertIn("human", human)

    def test_error_retry_treated_as_control_dependent(self):
        """An error-then-retry pair sits in two `mid` groups with no data
        dependency to find, so without an explicit rule it routes as a missed
        batch, see #1485 Codex review."""
        self.assertIn('"err": true', self.prompt)
        self.assertIn("retry", self.prompt)
        self.assertIn("control-dependent", self.prompt)
        # Tool-name equality alone is not a retry -- a failed Read of one file
        # followed by a Read of another is two independent calls, and calling
        # that control-dependent suppresses a genuine finding (#1485 review).
        self.assertIn("NOT evidence of a retry", self.prompt)
        self.assertIn("SAME resource or repeat the same arguments", self.prompt)

    def test_resource_dependency_compares_call_inputs(self):
        """A side-effecting call (`mkdir /tmp/out` before `Write /tmp/out/x.md`)
        returns nothing and narrates nothing, so comparing the later input only
        against earlier RESULTS and narration reads a required sequence as a
        missed batch -- the earlier call's own input must be in the comparison,
        see #1485 Codex review."""
        self.assertIn("against the later call's \"calls[].in\"", self.prompt)
        self.assertIn("creates or mutates", self.prompt)

    def test_drop_if_uncomputable_still_present(self):
        self.assertIn("drop the claim", self.prompt)
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


class PidAlive(unittest.TestCase):
    def test_tasklist_call_is_utf8_explicit(self):
        # #1483: _pid_alive's Windows branch shells out to `tasklist`, whose
        # subprocess.run call (unlike #1472's already-fixed _run_analysis) had no
        # explicit encoding= -- Python's default text-mode decode is the platform
        # code page (cp1252 on Windows), not UTF-8. Force the "nt" branch
        # regardless of the host platform running this test so the assertion is
        # not skipped on Linux/mac CI.
        captured = {}

        class FakeProc:
            stdout = "12345 Console 1 10,000 K"

        def fake_run(cmd, **kw):
            captured.update(kw)
            return FakeProc()

        on, orr = observer.os.name, observer.subprocess.run
        observer.os.name = "nt"
        observer.subprocess.run = fake_run
        try:
            self.assertTrue(observer._pid_alive(12345))
        finally:
            observer.os.name, observer.subprocess.run = on, orr
        self.assertEqual(captured.get("encoding"), "utf-8")
        self.assertEqual(captured.get("errors"), "replace")


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

    def test_analysis_subprocess_encoding_and_creationflags(self):
        # #1472: the analysis subprocess.run must (a) always decode captured
        # output as UTF-8 explicitly, with errors="replace" so a truncated
        # byte sequence decodes rather than raising past the try block's
        # TimeoutExpired/OSError handling -- claude -p writes UTF-8, but
        # Python's default text encoding is the platform code page (cp1252 on
        # Windows), which corrupted non-ASCII ledger entries into mojibake --
        # and (b) on Windows only, pass CREATE_NO_WINDOW so the run doesn't
        # flash a console window, matching arm_observer.py's spawn_detached
        # windowless spawn. Runs on every platform: the encoding/errors
        # assertions are unconditional, and the creationflags assertion
        # branches on the real os.name rather than skipping off-Windows.
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="enc")
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            captured = {}

            class FakeProc:
                returncode = 0
                stdout = json.dumps({"is_error": False,
                                     "result": "### Checkpoint findings\n\nok"})
                stderr = ""

            def fake_run(cmd, **kw):
                captured.update(kw)
                return FakeProc()

            of, orr = observer._find_claude, observer.subprocess.run
            observer._find_claude = lambda: "claude"
            observer.subprocess.run = fake_run
            try:
                self.assertTrue(ob._run_analysis())
            finally:
                observer._find_claude, observer.subprocess.run = of, orr
            # encoding="utf-8" and errors="replace" are unconditional --
            # required on every platform, not just Windows (Linux/mac default
            # UTF-8 already, but explicit beats implicit and keeps behavior
            # identical everywhere).
            self.assertEqual(captured.get("encoding"), "utf-8")
            self.assertEqual(captured.get("errors"), "replace")
            if os.name == "nt":
                # CREATE_NO_WINDOW only -- not DETACHED_PROCESS/CREATE_NEW_PROCESS_GROUP,
                # which are for escaping the parent's process tree and unneeded for a
                # waited (non-detached) child.
                self.assertEqual(captured.get("creationflags"), 0x08000000)
            else:
                self.assertNotIn("creationflags", captured)

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

    def _run_main(self, argv: list[str], arm=None) -> tuple[int, str]:
        """Run arm_observer.py's main() with `argv` and capture its stdout.

        Drives `main()` all the way through to the `spawn_detached` call (not
        just argument parsing or an early-return branch) -- the real spawn
        call is exercised, not mocked, so a regression at that call site
        (e.g. an undefined name) surfaces exactly as it does for a live
        caller. Pass a pre-built `arm` module (from `self._arm()`) to run
        `main()` against a module a caller already monkeypatched (e.g. to
        force a spawn-time exception) -- `_arm()` re-execs the file fresh
        each time, so a patch applied to a separately-loaded module would
        never reach the module this method actually runs.
        """
        if arm is None:
            arm = self._arm()
        old_argv = sys.argv
        buf = io.StringIO()
        try:
            sys.argv = ["arm_observer.py", *argv]
            with contextlib.redirect_stdout(buf):
                rc = arm.main()
        finally:
            sys.argv = old_argv
        return rc, buf.getvalue()

    @staticmethod
    def _terminate_and_wait(pid: int, timeout: float = 5.0):
        """Best-effort cleanup for a spawned detached observer.

        `os.kill` maps onto `TerminateProcess` for a non-Windows-specific
        signal like SIGTERM even on Windows (CPython's `os.kill` docs), so
        this is portable. Errors are swallowed -- the process may already
        have exited on its own (it is armed with a tiny --idle-seconds) --
        and we wait briefly afterward so the caller's tempdir teardown does
        not race a still-open file handle held by the child (observed on
        Windows: a live child holding `observations-<sid>.ndjson` open makes
        `TemporaryDirectory.cleanup()` raise `PermissionError`).

        The wait is per-platform because liveness and reaping differ. On
        POSIX the detached child is still a direct child of this test
        process, so after SIGTERM it lingers as a zombie until reaped and
        `_pid_alive`'s `os.kill(pid, 0)` keeps reporting it alive -- polling
        liveness there would burn the whole timeout and leave the zombie
        behind. `waitpid` is the correct wait on that platform: it returns
        as soon as the child dies and reaps it in the same call. Windows has
        no zombie state and no `waitpid`, so liveness polling stays.
        """
        import signal
        with contextlib.suppress(OSError, ProcessLookupError):
            os.kill(pid, signal.SIGTERM)
        deadline = time.time() + timeout
        if os.name != "nt":
            while time.time() < deadline:
                try:
                    if os.waitpid(pid, os.WNOHANG)[0] == pid:
                        return
                except ChildProcessError:
                    return  # already reaped (subprocess's own _active cleanup)
                except OSError:
                    return
                time.sleep(0.05)
            return
        arm = ArmLauncher._arm()
        while time.time() < deadline and arm._observer_mod()._pid_alive(pid):
            time.sleep(0.05)

    def _assert_reaches_spawn_success(self, sid: str, extra_args: list[str]):
        """Shared body: drive `main()` through the real spawn call and assert
        the success-path outcome (armed message + a real live child pid) for
        one caller's flag shape. Both entry points -- the running-retro `arm`
        action and the opt-in SessionStart auto-arm hook
        (`hooks/observer-arm.sh`) -- invoke this same launcher `main()` and
        differ only in which flags they pass, never in the code path
        executed; `extra_args` supplies each caller's distinguishing shape.
        """
        d = tempfile.mkdtemp()
        pid = None
        try:
            tmp = Path(d)
            transcript = tmp / "sess.jsonl"
            transcript.write_text("", encoding="utf-8")
            argv = [
                "--transcript", str(transcript),
                "--work-dir", str(tmp / "work"),
                "--ledger-dir", str(tmp / "ledger"),
                "--session-id", sid,
                "--plugin-root", str(tmp),
                "--model", "claude-haiku-4-5",
                # Analysis-free (no `claude -p` call) keeps this fast and
                # hermetic; the spawn call itself -- the site of the bug --
                # is still real. --idle-seconds is set well above the time
                # this test needs to parse output, reload arm_observer.py,
                # and probe liveness after spawn_detached returns, so the
                # child cannot legitimately self-exit mid-assertion (that
                # raced intermittently at 0.05s under load); --max-seconds
                # is the leak backstop, short enough that a missed
                # _terminate_and_wait still dies fast on its own.
                "--idle-seconds", "30",
                "--max-seconds", "15",
                *extra_args,
            ]
            rc, out = self._run_main(argv)
            self.assertEqual(rc, 0)
            self.assertIn(f"observer: armed for session {sid} (pid ", out)
            self.assertNotIn("NameError", out)
            self.assertNotIn("Traceback", out)
            pid = int(out.rsplit("(pid ", 1)[1].rstrip(")\n"))
            arm = self._arm()
            self.assertTrue(
                arm._observer_mod()._pid_alive(pid),
                f"spawned observer pid {pid} is not alive right after spawn",
            )
        finally:
            if pid is not None:
                self._terminate_and_wait(pid)
            shutil.rmtree(d, ignore_errors=True)

    def test_manual_arm_reaches_spawn_success(self):
        """Manual `arm` action's flag shape (SKILL.md): no --poll-seconds,
        includes --previous-running-retro / --previous-session-id (empty when
        there is no continuity chain)."""
        self._assert_reaches_spawn_success(
            "manual-sid",
            ["--previous-running-retro", "", "--previous-session-id", ""],
        )

    def test_sessionstart_autoarm_reaches_spawn_success(self):
        """SessionStart auto-arm hook's flag shape (hooks/observer-arm.sh):
        includes --poll-seconds, omits --previous-running-retro /
        --previous-session-id / --topic (the headless hook cannot infer
        continuity in-session)."""
        self._assert_reaches_spawn_success(
            "autoarm-sid",
            ["--poll-seconds", "0.05"],
        )

    def test_non_oserror_at_spawn_degrades_gracefully(self):
        """A non-OSError exception at the spawn call (e.g. a resurfaced
        undefined-name regression) must degrade the same as any other spawn
        failure -- a graceful `observer: failed to spawn: ...` message and
        exit 0, never a raw traceback escaping to the caller.

        Forces the failure by monkeypatching `spawn_detached` on an
        already-loaded module (rather than relying on a real crash), so this
        test is independent of whatever the current spawn-call implementation
        is. Uses `_run_main(argv, arm=...)` -- passing a *pre-built* module
        -- because `_run_main`'s own default re-execs arm_observer.py fresh
        each call; patching a separately-loaded module would never reach the
        module `main()` actually runs from.
        """
        arm = self._arm()

        def _boom(*_args, **_kwargs):
            raise RuntimeError("boom")

        arm.spawn_detached = _boom

        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            transcript = tmp / "sess.jsonl"
            transcript.write_text("", encoding="utf-8")
            argv = [
                "--transcript", str(transcript),
                "--work-dir", str(tmp / "work"),
                "--ledger-dir", str(tmp / "ledger"),
                "--session-id", "boom-sid",
                "--idle-seconds", "30",
                "--max-seconds", "15",
            ]
            rc, out = self._run_main(argv, arm=arm)
            self.assertEqual(rc, 0)
            self.assertIn("observer: failed to spawn: boom", out)
            self.assertNotIn("Traceback", out)
            self.assertNotIn("armed for session", out)


if __name__ == "__main__":
    unittest.main()
