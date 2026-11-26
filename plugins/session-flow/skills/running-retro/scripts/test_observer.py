#!/usr/bin/env python3
# test-scope: plugins/session-flow/.claude-plugin/plugin.json
# test-scope: plugins/session-flow/hooks/observer-catchup.sh
# test-scope: plugins/session-flow/hooks/session-attended.env
# test-scope: plugins/session-flow/hooks/session-attended.sh
# test-scope: plugins/session-flow/lib/python-probe.sh

from __future__ import annotations

import base64
import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import warnings
from pathlib import Path
from unittest import mock

_SPEC = importlib.util.spec_from_file_location(
    "observer", str(Path(__file__).with_name("observer.py"))
)
observer = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(observer)
import claude_cli  # noqa: E402  (observer.py put the plugin scripts dir on sys.path)


def make_observer(tmp: Path, **overrides):
    (tmp / "work").mkdir(exist_ok=True)
    (tmp / "ledger").mkdir(exist_ok=True)
    transcript = tmp / "sess.jsonl"
    if not transcript.exists():
        transcript.write_text("", encoding="utf-8")
    argv = [
        "--transcript",
        str(transcript),
        "--work-dir",
        str(tmp / "work"),
        "--ledger-dir",
        str(tmp / "ledger"),
        "--session-id",
        overrides.get("session_id", "sid"),
        "--topic",
        "test",
    ]
    if overrides.get("analysis"):
        argv.append("--analysis")
    if overrides.get("min_lines") != "":
        argv += ["--min-lines", str(overrides.get("min_lines", 0))]
    if "effort" in overrides:
        argv += ["--effort", overrides["effort"]]
    args = observer.build_parser().parse_args(argv)
    return observer.Observer(args)


def ledger_of(ob):
    return observer.find_session_ledger(ob.ledger_dir, ob.session_id)


USER_RECORD = json.dumps({"type": "user", "message": {"content": "hi"}}) + "\n"


class Distillation(unittest.TestCase):
    def test_assistant(self):
        out = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_01ABC",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_1",
                            "name": "Bash",
                            "input": {"command": "ls"},
                        },
                        {"type": "text", "text": "x" * 300},
                    ],
                    "stop_reason": "tool_use",
                },
            }
        )
        self.assertEqual(out["tools"], ["Bash"])
        self.assertEqual(out["stop_reason"], "tool_use")
        self.assertLessEqual(len(out["say"]), 160)
        self.assertEqual(out["mid"], observer._short_id("msg_01ABC"))
        self.assertEqual(
            out["calls"],
            [{"id": observer._short_id("call_1"), "in": '{"command":"ls"}'}],
        )

    def test_assistant_no_tools_omits_grouping_fields(self):
        """A text-only turn has nothing to group/preview -- no mid/calls noise."""
        out = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_01ABC",
                    "content": [{"type": "text", "text": "hi"}],
                },
            }
        )
        self.assertNotIn("tools", out)
        self.assertNotIn("calls", out)
        self.assertNotIn("mid", out)

    def test_assistant_missing_message_id_omits_mid(self):
        """A record with no API message id makes that pair's ordering uncomputable --
        the field is simply absent, never a placeholder that looks computed."""
        out = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "content": [{"type": "tool_use", "id": "call_1", "name": "Bash"}]
                },
            }
        )
        self.assertNotIn("mid", out)
        self.assertIn("calls", out)

    def test_assistant_two_tool_uses_in_one_record_share_one_mid(self):
        """Two tool_use blocks in ONE assistant record is a schema-level case the
        code must still handle correctly, even though a scan of real transcripts
        for #1485 found zero examples of it in practice (see test below for the
        pattern that IS common) -- both calls carry the SAME mid regardless."""
        out = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_batch",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_1",
                            "name": "Read",
                            "input": {"file_path": "a.py"},
                        },
                        {
                            "type": "tool_use",
                            "id": "call_2",
                            "name": "Read",
                            "input": {"file_path": "b.py"},
                        },
                    ],
                },
            }
        )
        self.assertEqual(out["tools"], ["Read", "Read"])
        self.assertEqual(
            [c["id"] for c in out["calls"]],
            [observer._short_id("call_1"), observer._short_id("call_2")],
        )
        self.assertEqual(out["mid"], observer._short_id("msg_batch"))

    def test_assistant_one_message_spans_multiple_tool_bearing_records_shares_one_mid(
        self,
    ):
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
        r1 = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_shared",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_1",
                            "name": "Read",
                            "input": {"file_path": "a.py"},
                        }
                    ],
                },
            }
        )
        r2 = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_shared",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_2",
                            "name": "Read",
                            "input": {"file_path": "b.py"},
                        }
                    ],
                },
            }
        )
        self.assertEqual(r1["mid"], r2["mid"])
        self.assertEqual(r1["mid"], observer._short_id("msg_shared"))

    def test_user_and_system(self):
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_1",
                            "content": "file contents here",
                        },
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_2",
                            "content": "more content",
                        },
                    ]
                },
            }
        )
        self.assertNotIn(
            "tool_results", u
        )
        self.assertEqual(
            u["results"],
            [
                {"id": observer._short_id("call_1"), "out": "file contents here"},
                {"id": observer._short_id("call_2"), "out": "more content"},
            ],
        )
        s = observer.summarize_record(
            {"type": "system", "subtype": "stop_hook_summary"}
        )
        self.assertTrue(s["turn_boundary"])

    def test_user_tool_result_content_as_block_list(self):
        """A real transcript's tool_result.content is a list of content blocks
        about as often as a plain string (verified for #1485) -- the preview
        must extract the text, not JSON-dump the block wrapper structure."""
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_1",
                            "content": [
                                {"type": "text", "text": "the actual result text"}
                            ],
                        }
                    ]
                },
            }
        )
        self.assertEqual(u["results"][0]["out"], "the actual result text")

    def test_user_no_tool_results_omits_results_field(self):
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {"content": [{"type": "text", "text": "go ahead"}]},
            }
        )
        self.assertNotIn("results", u)
        self.assertNotIn("tool_results", u)

    def test_user_bare_string_in_content_list_is_a_human_message(self):
        """`content: ["next request"]` is a human prompt for the observer, though
        the shared reader skips the shape. Extracting only dict `text`
        blocks emitted neither `human` nor `turn_boundary`, so in a session with
        no `stop_hook_summary` records the analysis prompt's "same user turn"
        precondition saw no boundary at all and calls answering prompts on either
        side of it became a candidate pair (#1485 review)."""
        u = observer.summarize_record(
            {"type": "user", "message": {"content": ["next request"]}}
        )
        self.assertEqual(u["human"], "next request")

    def test_user_bare_string_and_text_block_mix(self):
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {"content": ["first", {"type": "text", "text": "second"}]},
            }
        )
        self.assertEqual(u["human"], "first second")

    def test_non_tool_result_user_content_is_a_turn_boundary(self):
        """The boundary is structural, not text-dependent. An image- or
        document-only prompt yields no readable `human` narration at all, so
        keying the boundary off extractable text let the dependency check span a
        new human request in transcripts with no `stop_hook_summary` at that
        point (#1485 review). Anything in a user record that is not a
        `tool_result` is the human speaking -- including a block type that does
        not exist yet."""
        for content in (
            [{"type": "image", "source": {"type": "base64", "data": "..."}}],
            [{"type": "document", "source": {"type": "base64", "data": "..."}}],
            [{"type": "some_future_block"}],
            ["a bare string"],
            [{"type": "text", "text": "plain text"}],
            "a plain string content",
        ):
            with self.subTest(content=content):
                u = observer.summarize_record(
                    {"type": "user", "message": {"content": content}}
                )
                self.assertTrue(u.get("turn_boundary"))

    def test_tool_result_only_user_record_is_not_a_turn_boundary(self):
        """The counterpart: a pure tool-result record is the harness answering a
        call, not the human speaking. Marking it a boundary would split every
        genuinely batched turn and suppress real findings."""
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_1",
                            "content": "ok",
                        },
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_2",
                            "content": "ok",
                        },
                    ]
                },
            }
        )
        self.assertNotIn("turn_boundary", u)

    def test_sequencing_and_dependency_round_trip(self):
        """Builds observations from real transcript-shaped records for a genuinely
        DEPENDENT sequential pair (a Write, then a Read of a path the Write's own
        result content names) and checks that the distilled fields alone -- without
        the raw transcript -- let a reader (a) tell the two calls were sequential
        (different `mid`s) and (b) find the dependency (the second call's `in`
        preview overlaps the first result's `out` preview), covering both acceptance
        criteria for #1485 in one round trip.
        """
        write_call = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_1",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_w",
                            "name": "Write",
                            "input": {"file_path": "/tmp/out/report.md"},
                        },
                    ],
                },
            }
        )
        write_result = observer.summarize_record(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_w",
                            "content": "wrote /tmp/out/report.md",
                        }
                    ]
                },
            }
        )
        read_call = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_2",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_r",
                            "name": "Read",
                            "input": {"file_path": "/tmp/out/report.md"},
                        },
                    ],
                },
            }
        )

        self.assertNotEqual(write_call["mid"], read_call["mid"])
        later_in = read_call["calls"][0]["in"]
        earlier_out = write_result["results"][0]["out"]
        self.assertIn("/tmp/out/report.md", later_in)
        self.assertIn("/tmp/out/report.md", earlier_out)

    def test_preview_bounded_for_large_input(self):
        """No meaningful token-cost regression: an oversized tool input/result is
        truncated to the bounded preview limit, not carried in full."""
        big = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_big",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_big",
                            "name": "Write",
                            "input": {"content": "x" * 10_000},
                        },
                    ],
                },
            }
        )
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
            ("hello world", False),
        )

    def test_preview_list_with_no_text_blocks_falls_back_to_json(self):
        """A block list with nothing extractable (e.g. only an image block)
        still gets SOME preview rather than an empty string."""
        preview, _ = observer._preview([{"type": "image", "source": "x"}])
        self.assertIn("image", preview)

    def test_untruncated_entry_omits_cut_flag(self):
        out = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_1",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_1",
                            "name": "Bash",
                            "input": {"command": "ls"},
                        }
                    ],
                },
            }
        )
        self.assertNotIn("cut", out["calls"][0])

    def test_truncated_entry_carries_cut_flag(self):
        """A cut preview must be DISTINGUISHABLE from a short, complete one -- a
        silent slice would make a dependency-bearing value past the limit look
        like a clean 'no match' rather than 'unknown', see #1485 Codex review."""
        out = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_1",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "call_1",
                            "name": "Write",
                            "input": {"content": "x" * 10_000},
                        }
                    ],
                },
            }
        )
        self.assertTrue(out["calls"][0]["cut"])
        self.assertEqual(len(out["calls"][0]["in"]), observer._PREVIEW_LIMIT)

    def test_value_ending_in_ellipsis_is_not_reported_cut(self):
        """An in-band trailing marker is ambiguous: a complete tool result that
        naturally ends in `...` would read as truncated and wrongly suppress an
        otherwise computable sequencing finding, see #1485 Codex review. The
        cut signal is out-of-band, so a literal trailing `...` is just text."""
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_1",
                            "content": "Processing complete...",
                        }
                    ]
                },
            }
        )
        self.assertEqual(u["results"][0]["out"], "Processing complete...")
        self.assertNotIn("cut", u["results"][0])

    def test_failed_tool_result_carries_err_flag(self):
        """A failed call's own output is routinely empty or generic, so without
        `err` a retry reads as an independent unbatched sibling rather than a
        call that could only be chosen after the failure, see #1485 Codex
        review."""
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_1",
                            "content": "",
                            "is_error": True,
                        },
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_2",
                            "content": "ok",
                        },
                    ]
                },
            }
        )
        self.assertTrue(u["results"][0]["err"])
        self.assertNotIn("err", u["results"][1])

    def test_mixed_block_result_reported_incomplete(self):
        """Text alongside an image block keeps only the text -- the omitted
        block could carry the dependency, so the preview is not complete even
        though it fits the limit, see #1485 Codex review."""
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_1",
                            "content": [
                                {"type": "text", "text": "see attached"},
                                {"type": "image", "source": "x"},
                            ],
                        }
                    ]
                },
            }
        )
        self.assertEqual(u["results"][0]["out"], "see attached")
        self.assertTrue(u["results"][0]["cut"])

    def test_text_only_block_list_not_reported_incomplete(self):
        """The mixed-block rule must not fire on an all-text block list."""
        u = observer.summarize_record(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "call_1",
                            "content": [
                                {"type": "text", "text": "a"},
                                {"type": "text", "text": "b"},
                            ],
                        }
                    ]
                },
            }
        )
        self.assertNotIn("cut", u["results"][0])

    def test_narration_cut_flag(self):
        """The dependency check reads `say` for a control/resource/side-effect
        dependency, so a silently cut narration would read as showing none."""
        short = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_1",
                    "content": [{"type": "text", "text": "brief"}],
                },
            }
        )
        self.assertNotIn("say_cut", short)
        long = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": "msg_2",
                    "content": [{"type": "text", "text": "z" * 500}],
                },
            }
        )
        self.assertTrue(long["say_cut"])
        self.assertEqual(len(long["say"]), observer._NARRATION_LIMIT)

    def test_mid_preserved_for_falsy_but_not_none_id(self):
        """`mid` must be omitted only when the record truly carries none -- a
        `mid: 0` (an integer id format) or `mid: ""` must NOT be dropped by an
        `if mid:` truthy guard, see #1485 code review finding #1. `_short_id`
        stringifies (`0` -> `"0"`), so compare against the same helper."""
        out = observer.summarize_record(
            {
                "type": "assistant",
                "message": {
                    "id": 0,
                    "content": [{"type": "tool_use", "id": "call_1", "name": "Bash"}],
                },
            }
        )
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
        # cant-fail-ok: determinism contract
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
            observations="/obs.ndjson", checkpoint="/checkpoint.md", session_id="sid"
        )

    def test_compute_dont_assert_rule_present(self):
        self.assertIn("Compute, don't assert", self.prompt)
        self.assertIn("sequencing", self.prompt)
        self.assertIn("batching", self.prompt)
        self.assertIn("delegation", self.prompt)
        self.assertIn("occurrence count", self.prompt)
        self.assertIn("message id", self.prompt)
        self.assertIn("drop the claim", self.prompt)

    def test_absent_grouping_key_reads_as_uncomputable(self):
        """`summarize_record()` carries a message id as `mid`, but only when
        the raw record has one -- so the prompt must still say that an ABSENT
        grouping key makes the claim uncomputable rather than licensing an
        assertion from impression."""
        self.assertIn('NO "mid" at all', self.prompt)
        self.assertIn("UNCOMPUTABLE", self.prompt)
        rec = observer.summarize_record(
            {
                "type": "assistant",
                "message": {"content": [{"type": "tool_use", "name": "Read"}]},
            }
        )
        self.assertNotIn("mid", rec)

    def test_dependency_check_before_batching_finding_present(self):
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
            {"type": "system", "subtype": "stop_hook_summary"}
        )
        self.assertTrue(boundary["turn_boundary"])
        human = observer.summarize_record(
            {"type": "user", "message": {"content": "do the next thing"}}
        )
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
        self.assertIn("NOT evidence", self.prompt)
        # ...but a corrected-argument retry (`git stats` -> `git status`) names
        # no shared resource and repeats no argument, so requiring either would
        # swing the rule too far the other way (#1485 review).
        self.assertIn("CORRECTION", self.prompt)
        self.assertIn("UNKNOWN, not independent", self.prompt)

    def test_state_wide_consumer_after_a_mutation_is_dependent(self):
        """`Edit foo.py` then `Bash pytest` shares no path, echoes nothing, and
        need not be narrated, yet the test had to observe the edit -- the most
        common sequential pair in a coding session, and the one the resource
        check (which needs a shared named resource) structurally cannot see
        (#1485 review)."""
        self.assertIn("STATE-WIDE CONSUMER", self.prompt)
        self.assertIn("MUTATED state", self.prompt)
        self.assertIn("whether the earlier call mutated anything", self.prompt)
        self.assertIn("all five of these places", self.prompt)

    def test_resource_dependency_compares_call_inputs(self):
        """A side-effecting call (`mkdir /tmp/out` before `Write /tmp/out/x.md`)
        returns nothing and narrates nothing, so comparing the later input only
        against earlier RESULTS and narration reads a required sequence as a
        missed batch -- the earlier call's own input must be in the comparison,
        see #1485 Codex review."""
        self.assertIn('against the later call\'s "calls[].in"', self.prompt)
        self.assertIn("creates or mutates", self.prompt)

    def test_drop_if_uncomputable_still_present(self):
        self.assertIn("drop the claim", self.prompt)
        self.assertIn("uncomputed", self.prompt)

    def test_mandatory_redaction_pass_not_crowded_out(self):
        self.assertIn("MANDATORY redaction pass", self.prompt)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


# A stateless installation token is ghs_ then a JWT of about 520 characters, with
# no app id. The RS256 header encodes to exactly 36 alphanumerics, the length
# gh[pousr]_ accepts; the kid header carries a '-' 16 characters in, before any
# alphanumeric minimum is met. Payload and signature are fake.
STATELESS_HEADERS = (
    b64url(b'{"alg":"RS256","typ":"JWT"}'),
    b64url(b'{"kid":"k?~>","alg":"RS256","typ":"JWT"}'),
)
FAKE_PAYLOAD = b64url(b'{"sub":"FAKE-not-a-real-token","iat":0}')
FAKE_SIGNATURE = b64url(b"\xfb\xff\xfeFAKE signature, not a real token" * 9)


def stateless_jwt(header):
    return f"{header}.{FAKE_PAYLOAD}.{FAKE_SIGNATURE}"


class Redaction(unittest.TestCase):
    def test_shapes(self):
        r = observer._redact
        self.assertIn("<REDACTED: API key>", r("tok sk-ABC1234567890XYZ890 z"))
        self.assertIn(
            "<REDACTED: GitHub token>", r("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345")
        )
        # ghs_<APPID>_<JWT> installation token, about 520 characters; the
        # segments spell FAKE.
        jwt = "eyJFAKE.FAKEpayload" + "A" * 450 + ".FAKEsignatureNOTreal"
        self.assertEqual(
            "tok <REDACTED: GitHub token> z", r("tok ghs" + "_1234567_" + jwt + " z")
        )
        self.assertIn("<REDACTED: connection string>", r("postgres://u:p@h/db"))
        self.assertIn("<REDACTED: email>", r("a.b+c@ex.co"))
        self.assertIn("<REDACTED: secret>", r("password" + ': "hunter2hunter2"'))

    def test_stateless_installation_token_is_redacted_whole(self):
        r = observer._redact
        for header in STATELESS_HEADERS:
            for prefix in ("ghs" + "_", "ghs" + "_123456_"):
                token = prefix + stateless_jwt(header)
                with self.subTest(header=header[:20], prefix=prefix):
                    self.assertGreater(len(token), 500)
                    text = r(f"tok {token} z")
                    self.assertEqual("tok <REDACTED: GitHub token> z", text)
                    for fragment in (FAKE_PAYLOAD[:12], FAKE_SIGNATURE[-12:]):
                        self.assertNotIn(fragment, text)

    def test_token_placeholders_are_not_redacted(self):
        for text in ("ghs_job", "ghs_lane", "3e7fef0587433cfb07332dbeabf0d79fc0baadf3"):
            self.assertEqual(text, observer._redact(text))

    def test_clean_passthrough(self):
        self.assertEqual(observer._redact("no secrets here"), "no secrets here")

    def test_github_token_pattern_finishes_promptly_on_adversarial_text(self):
        github = [
            p
            for p, marker in observer._REDACTIONS
            if marker == "<REDACTED: GitHub token>"
        ]
        self.assertEqual(len(github), 1)
        for text in (
            "ghs_1_-" * 50000,
            "ghs_1_eyJ" * 30000,
            "ghs_1_eyJa." * 30000,
            "ghs_1_eyJ-" * 30000,
            ("ghs_1_eyJ" + "A" * 600) * 1000,
        ):
            with self.subTest(text=text[:12]):
                start = time.monotonic()
                for pattern in github:
                    pattern.sub("x", text)
                self.assertLess(time.monotonic() - start, 1.0)

    def test_jwt_url_and_email_patterns_finish_promptly_on_adversarial_text(self):
        patterns = [
            p
            for p, marker in observer._REDACTIONS
            if marker
            in (
                "<REDACTED: JWT>",
                "<REDACTED: connection string>",
                "<REDACTED: email>",
            )
        ]
        self.assertEqual(len(patterns), 4)
        for text in (
            "ghs_1_-" * 50000,
            "ghs_1_eyJa." * 30000,
            "ghs_1_eyJ-" * 30000,
            "-eyJ" * 75000,
            "eyJ" + "A" * 600000,
            ("eyJ" + "A" * 600) * 1000,
            ("-eyJ" * 127 + " ") * 600,
            "a." * 150000,
            "a." * 32 + "a@" + "a." * 150000,
        ):
            with self.subTest(text=text[:12]):
                start = time.monotonic()
                for pattern in patterns:
                    pattern.sub("x", text)
                self.assertLess(time.monotonic() - start, 1.0)

    def test_private_key_pattern_finishes_promptly_on_adversarial_text(self):
        (key,) = (
            p
            for p, marker in observer._REDACTIONS
            if marker == "<REDACTED: private key>"
        )
        header = "-----BEGIN a PRIVATE" " KEY-----"
        for text in (
            header * 20000,
            header + "-----END" * 70000,
            "-----BEGIN" + "a" * 600000,
        ):
            with self.subTest(text=text[:40]):
                start = time.monotonic()
                key.sub("x", text)
                self.assertLess(time.monotonic() - start, 1.0)

    def test_bounded_patterns_still_redact_realistic_secrets(self):
        r = observer._redact
        # Header, payload and signature spell FAKE.
        jwt = "eyJhbGciOiJIUzI1NiJ9" ".eyJzdWIiOiJGQUtFIn0.FAKEsignatureNOTreal"
        self.assertEqual("auth <REDACTED: JWT> x", r(f"auth {jwt} x"))
        long_header = "eyJ" + "A" * 509 + ".eyJzdWIiOiJGQUtFIn0.FAKEsignatureNOTreal"
        self.assertEqual("<REDACTED: JWT>", r(long_header))
        for size in (513, 4000):
            with self.subTest(header=size):
                token = (
                    "eyJ" + "A" * size + ".eyJzdWIiOiJGQUtFIn0" ".FAKEsignatureNOTreal"
                )
                self.assertEqual("auth <REDACTED: JWT> x", r(f"auth {token} x"))
                ghs = "ghs" + "_1234567_" + token
                self.assertEqual(
                    "tok <REDACTED: GitHub token> z", r(f"tok {ghs} z")
                )
        long_payload = "eyJhbGciOiJIUzI1NiJ9" ".eyJ" + "B" * 2000 + ".FAKEsignature"
        self.assertEqual("<REDACTED: JWT>", r(long_payload))
        self.assertEqual(
            "dsn <REDACTED: connection string>",
            r("dsn postgresql+psycopg2://user:FAKEpass@db.example.com:5432/app"),
        )
        self.assertEqual("<REDACTED: connection string>", r("m" * 64 + "://u:p@h"))
        self.assertEqual(
            "to <REDACTED: email> x", r("to first.last+tag@mail.example.co.uk x")
        )
        local = "l" * 64
        domain = ".".join(["d" * 63] * 3) + ".example"
        self.assertEqual("<REDACTED: email>", r(f"{local}@{domain}"))
        # A 4096-bit RSA PKCS#8 PEM is about 3.2 KB in 64-character lines
        # (RFC 7468); this body spells FAKE.
        body = "\n".join(["FAKE" * 16] * 52)
        for label in ("", "RSA ", "OPENSSH "):
            with self.subTest(label=label):
                pem = (
                    f"-----BEGIN {label}PRIVATE KEY-----\n{body}\n"
                    f"-----END {label}PRIVATE KEY-----"
                )
                self.assertGreater(len(pem), 3200)
                self.assertEqual("key <REDACTED: private key> x", r(f"key {pem} x"))


class ResultParsing(unittest.TestCase):
    def test_extract(self):
        self.assertEqual(observer._extract_result('{"result":"BLOCK"}'), "BLOCK")
        self.assertEqual(observer._extract_result('{"is_error":true,"result":"x"}'), "")
        self.assertEqual(observer._extract_result("plain"), "")

    def test_error(self):
        self.assertTrue(
            observer._result_error('{"is_error":true,"result":"Not logged in"}')
        )
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
            ob.lock_path.write_text(
                json.dumps(
                    {"pid": 2**30, "started": observer.now_iso(), "session_id": "sid"}
                ),
                encoding="utf-8",
            )
            self.assertTrue(
                ob.acquire_lock(), "stale (dead-pid) lock must be reclaimed"
            )
            ob.release_lock()

    def test_partial_write_lock_treated_live(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp)
            ob.lock_path.write_text("", encoding="utf-8")
            self.assertFalse(
                ob.acquire_lock(),
                "empty/mid-write lock (fresh mtime) must not be reclaimed",
            )

    def test_live_lock_not_reclaimed_by_age(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp)
            ob.lock_path.write_text(
                json.dumps(
                    {
                        "pid": os.getpid(),
                        "started": "2000-01-01T00:00:00+00:00",
                        "session_id": "sid",
                    }
                ),
                encoding="utf-8",
            )
            self.assertFalse(
                ob.acquire_lock(), "a live pid must not be reclaimed regardless of age"
            )

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

    def test_unreadable_lock_reclaimed_only_past_the_analysis_timeout_bound(self):
        with tempfile.TemporaryDirectory() as d:
            ob = make_observer(Path(d))
            bound = ob.analysis_timeout_secs + observer._LOCK_STALE_MARGIN_SECONDS
            ob.lock_path.write_text("", encoding="utf-8")
            young = time.time() - bound + 60
            os.utime(ob.lock_path, (young, young))
            self.assertFalse(ob.acquire_lock(), "inside the bound: treated live")
            old = time.time() - bound - 1
            os.utime(ob.lock_path, (old, old))
            self.assertTrue(ob.acquire_lock(), "past the bound: reclaimed")
            self.assertEqual(
                os.getpid(),
                json.loads(ob.lock_path.read_text(encoding="utf-8"))["pid"],
            )

    def test_run_exits_without_work_while_another_run_holds_the_lock(self):
        with tempfile.TemporaryDirectory() as d:
            ob = make_observer(Path(d), analysis=True)
            ob.transcript.write_text(USER_RECORD * 3, encoding="utf-8")
            ob.lock_path.write_text(json.dumps({"pid": os.getpid()}), encoding="utf-8")
            captured: dict = {}
            with fake_analysis_run(captured):
                self.assertEqual(0, ob.run())
            self.assertNotIn("cmd", captured)
            self.assertFalse(ob.status_path.exists())
            self.assertFalse(ob.obs_path.exists())
            self.assertTrue(ob.lock_path.exists(), "the holder's lock is left alone")


@contextlib.contextmanager
def fake_tasklist(stdout: bytes, captured: dict | None = None):
    """Force `_pid_alive`'s "nt" branch with a canned `tasklist` stdout.

    Forcing the branch regardless of the host platform keeps these assertions
    from being skipped on Linux/mac CI. `observer.os` IS the `os` module, so
    `os.name` is patched process-wide until the `finally` restores it. Pass
    `captured` to record the kwargs `_pid_alive` handed `subprocess.run`.
    """
    class FakeProc:
        pass

    proc = FakeProc()
    proc.stdout = stdout

    def fake_run(cmd, **kw):
        if captured is not None:
            captured.update(kw)
        return proc

    saved_name, saved_run = observer.os.name, observer.subprocess.run
    observer.os.name = "nt"
    observer.subprocess.run = fake_run
    try:
        yield
    finally:
        observer.os.name, observer.subprocess.run = saved_name, saved_run


class PidAlive(unittest.TestCase):
    def test_tasklist_call_uses_no_fixed_decoder(self):
        # #1512: tasklist's piped output follows the console output code page,
        # which is not fixed -- it varies by locale/session and can even
        # differ between shells in the same session, so neither a hardcoded
        # "utf-8" (the earlier #1483 fix) nor a hardcoded "oem" decodes
        # correctly everywhere. _pid_alive must not pass any encoding/text
        # kwarg to subprocess.run and must match the PID against raw bytes.
        captured: dict = {}
        with fake_tasklist(b"12345 Console 1 10,000 K", captured):
            self.assertTrue(observer._pid_alive(12345))
        self.assertNotIn("encoding", captured)
        self.assertNotIn("text", captured)
        self.assertNotIn("errors", captured)

    def test_tasklist_call_matches_pid_despite_undecodable_process_name(self):
        # A cp437 console plus a process name containing characters undefined
        # in cp1252 (e.g. \x81) defeats any fixed decoder: it raises
        # UnicodeDecodeError inside subprocess's reader thread and leaves
        # out.stdout as None (#1512), a crash class errors="replace" alone
        # (#1496) does not cover. Raw-bytes matching sidesteps decoding
        # entirely, so this mojibake name must not affect the ASCII-digit
        # PID match.
        stdout = b"\r\nt\x81st\x82.exe" + b" " * 20 + b"12345 Console 1  10,000 K"
        with fake_tasklist(stdout):
            self.assertTrue(observer._pid_alive(12345))

    def test_tasklist_call_no_match_when_pid_absent(self):
        with fake_tasklist(
            b"INFO: No tasks are running which match the specified criteria."
        ):
            self.assertFalse(observer._pid_alive(12345))


PRODUCED_RUN = json.loads(
    Path(__file__)
    .with_name("fixtures")
    .joinpath("claude-p-result.json")
    .read_text(encoding="utf-8")
)
COMPLETED_RUN = dict(PRODUCED_RUN, result="### Checkpoint findings\n\nok")
PRODUCED_RUN_RECORD = {
    "usage": {
        "input_tokens": 2,
        "cache_creation_input_tokens": 98015,
        "cache_read_input_tokens": 0,
        "output_tokens": 4,
    },
    "duration_ms": 1855,
    "total_cost_usd": PRODUCED_RUN["total_cost_usd"],
}


def without_at(run: dict) -> dict:
    return {k: v for k, v in run.items() if k != "at"}


@contextlib.contextmanager
def fake_analysis_run(
    captured: dict,
    version: tuple[int, int, int] | None = (2, 1, 259),
    stdout: str | None = None,
    on_run=None,
):
    """Drive `_run_analysis` against a stubbed `claude -p`, recording the call.

    Patches `_find_claude` (so no CLI need exist) and `subprocess.run` (so
    nothing is spawned), recording the command list under `cmd` and every
    kwarg the analysis run passes, so a caller can assert on the command
    shape, the stdin prompt, or the subprocess kwargs. `version` is what
    `claude --version` reports to the flag gate (None: unparsable). `stdout`
    replaces the completed run's JSON body. `captured["runs"]` counts the
    calls, and `on_run`, when given, is called on each before it returns.
    """
    class FakeProc:
        returncode = 0
        stderr = ""

    FakeProc.stdout = json.dumps(COMPLETED_RUN) if stdout is None else stdout

    def fake_run(cmd, **kw):
        captured["cmd"] = cmd
        captured.update(kw)
        captured["runs"] = captured.get("runs", 0) + 1
        if on_run:
            on_run()
        return FakeProc()

    saved_find, saved_run = observer._find_claude, observer.subprocess.run
    saved_version = claude_cli._CLAUDE_VERSION_CACHE
    observer._find_claude = lambda: "claude"
    observer.subprocess.run = fake_run
    claude_cli._CLAUDE_VERSION_CACHE = version
    with mock.patch.object(observer.Observer, "_stamp_plugin_usage"):
        try:
            yield
        finally:
            observer._find_claude, observer.subprocess.run = saved_find, saved_run
            claude_cli._CLAUDE_VERSION_CACHE = saved_version


class LedgerAndRetention(unittest.TestCase):
    def test_find_and_append_with_redaction(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="s-1")
            self.assertIsNone(ledger_of(ob))
            ob._append_ledger("finding with token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345")
            led = ledger_of(ob)
            self.assertIsNotNone(led)
            text = led.read_text(encoding="utf-8")
            self.assertIn("session_id: s-1", text)
            self.assertIn("<REDACTED: GitHub token>", text)
            self.assertNotIn("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", text)
            ob._append_ledger("second block")
            self.assertEqual(
                len(list((tmp / "ledger").glob("*-running-retro-*.md"))), 1
            )

    def test_append_stamps_the_session_plugin_usage(self):
        block = {
            "type": "tool_use",
            "name": "Skill",
            "input": {"skill": "plugin-quality:audit"},
        }
        event = {"type": "assistant", "message": {"content": [block]}}
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="sess")
            ob.transcript.write_text(json.dumps(event) + "\n", encoding="utf-8")
            ob._append_ledger("first")
            ob.transcript.write_text((json.dumps(event) + "\n") * 2, encoding="utf-8")
            ob._append_ledger("second")
            text = ledger_of(ob).read_text(encoding="utf-8")
            self.assertEqual(1, text.count("plugin_usage:"))
            self.assertIn(
                'plugin_usage: {"skills": {"plugin-quality:audit": 2}}\n---\n', text
            )
            self.assertIn("first", text)
            self.assertIn("second", text)

    def test_a_failed_stamp_write_leaves_the_ledger_whole(self):
        spec = importlib.util.spec_from_file_location(
            "stamp_plugin_usage", Path(__file__).with_name("stamp_plugin_usage.py")
        )
        stamp_plugin_usage = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(stamp_plugin_usage)

        with tempfile.TemporaryDirectory() as d:
            ledger = Path(d) / "x-running-retro-t.md"
            text = "---\nsession_id: sid\n---\n\nfindings\n"
            ledger.write_text(text, encoding="utf-8")
            with mock.patch.object(
                stamp_plugin_usage.os, "replace", side_effect=OSError(28, "full")
            ):
                self.assertFalse(stamp_plugin_usage.stamp(ledger, {"skills": {}}))
            self.assertEqual(text, ledger.read_text(encoding="utf-8"))
            self.assertEqual([ledger], list(Path(d).iterdir()))

    def test_unstamped_append_still_keeps_the_findings(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp)
            ob.transcript.unlink()
            self.assertTrue(ob._append_ledger("kept"))
            text = ledger_of(ob).read_text(encoding="utf-8")
            self.assertIn("kept", text)
            self.assertNotIn("plugin_usage:", text)

    def test_other_session_ledger_not_matched(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            other = tmp / "ledger" / "20260101T000000Z-running-retro-x.md"
            other.parent.mkdir(parents=True, exist_ok=True)
            other.write_text("---\nsession_id: other\n---\n", encoding="utf-8")
            ob = make_observer(tmp, session_id="mine")
            self.assertIsNone(ledger_of(ob))

    def test_analysis_command_is_tool_restricted(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="tr")
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            captured: dict = {}
            with fake_analysis_run(captured):
                self.assertTrue(ob._run_analysis())
            cmd = captured["cmd"]
            self.assertEqual(cmd[cmd.index("--tools") + 1], "Read")
            self.assertIn("--strict-mcp-config", cmd)
            self.assertEqual(cmd[cmd.index("--permission-mode") + 1], "dontAsk")
            self.assertEqual(cmd[cmd.index("--permission-prompts") + 1], "none")
            self.assertIsInstance(captured["input"], str)
            self.assertNotIn("--bare", cmd)
            self.assertIsNotNone(ledger_of(ob))

    def test_permission_prompts_flag_needs_a_cli_that_knows_it(self):
        for version in (None, (2, 1, 258)):
            with tempfile.TemporaryDirectory() as d:
                tmp = Path(d)
                ob = make_observer(tmp, analysis=True, session_id="pp")
                ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
                captured: dict = {}
                with fake_analysis_run(captured, version=version):
                    self.assertTrue(ob._run_analysis())
                cmd = captured["cmd"]
                self.assertNotIn("--permission-prompts", cmd)
                self.assertNotIn("none", cmd)
                self.assertEqual(cmd[cmd.index("--permission-mode") + 1], "dontAsk")
                self.assertEqual(cmd[cmd.index("--tools") + 1], "Read")

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
            captured: dict = {}
            with fake_analysis_run(captured):
                self.assertTrue(ob._run_analysis())
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

    def test_unset_model_and_effort_come_from_the_manifest(self):
        manifest_path = observer._PLUGIN_DIR / ".claude-plugin" / "plugin.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))["userConfig"]
        for overrides, effort in (
            ({}, manifest["observer_analysis_effort"]["default"]),
            ({"effort": "high"}, "high"),
        ):
            with tempfile.TemporaryDirectory() as d:
                tmp = Path(d)
                ob = make_observer(tmp, analysis=True, session_id="ef", **overrides)
                ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
                captured: dict = {}
                with (
                    mock.patch.dict(os.environ, {"CLAUDE_CODE_EFFORT_LEVEL": "max"}),
                    fake_analysis_run(captured),
                ):
                    self.assertTrue(ob._run_analysis())
                cmd = captured["cmd"]
                self.assertNotIn("CLAUDE_CODE_EFFORT_LEVEL", captured["env"])
                self.assertEqual(cmd[cmd.index("--effort") + 1], effort)
                self.assertEqual(
                    cmd[cmd.index("--model") + 1],
                    manifest["observer_analysis_model"]["default"],
                )
                # A settings-file `env` re-applies CLAUDE_CODE_EFFORT_LEVEL in the
                # child and it overrides --effort; --settings outranks those files.
                settings = json.loads(cmd[cmd.index("--settings") + 1])
                self.assertEqual(
                    settings, {"env": {"CLAUDE_CODE_EFFORT_LEVEL": effort}}
                )
                # --settings must precede the variadic --add-dir block.
                self.assertLess(cmd.index("--settings"), cmd.index("--add-dir"))
                self.assertEqual(captured["env"]["SESSION_FLOW_OBSERVER_ANALYSIS"], "1")

    def test_incomplete_run_retains_observations(self):
        cases = {
            "terminal_reason": dict(COMPLETED_RUN, terminal_reason="max_turns"),
            "subtype": dict(COMPLETED_RUN, subtype="error_max_turns"),
            "no subtype": {k: v for k, v in COMPLETED_RUN.items() if k != "subtype"},
            "permission_denials": dict(
                COMPLETED_RUN, permission_denials=[{"tool_name": "Bash"}]
            ),
        }
        for name, body in cases.items():
            with self.subTest(name), tempfile.TemporaryDirectory() as d:
                tmp = Path(d)
                ob = make_observer(tmp, analysis=True, session_id="inc")
                ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
                with fake_analysis_run({}, stdout=json.dumps(body)):
                    self.assertFalse(ob._run_analysis())
                self.assertIsNone(ledger_of(ob))
                self.assertTrue(ob.obs_path.exists())

    def test_absent_terminal_reason_still_completes(self):
        body = {k: v for k, v in COMPLETED_RUN.items() if k != "terminal_reason"}
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="nt")
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            with fake_analysis_run({}, stdout=json.dumps(body)):
                self.assertTrue(ob._run_analysis())
            self.assertIsNotNone(ledger_of(ob))

    def test_non_json_output_is_a_failed_run(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="nj")
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            with fake_analysis_run({}, stdout="### Checkpoint findings\n\nplain"):
                self.assertFalse(ob._run_analysis())
            self.assertIsNone(ledger_of(ob))
            self.assertTrue(ob.obs_path.exists())

    def test_below_min_lines_skips_analysis_and_records_it(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="short", min_lines=3)
            ob.obs_path.write_text('{"t":"user"}\n' * 2, encoding="utf-8")
            captured: dict = {}
            with fake_analysis_run(captured):
                self.assertFalse(ob._run_analysis())
            self.assertNotIn("cmd", captured, "no claude -p run below the minimum")
            self.assertIsNone(ledger_of(ob))
            self.assertTrue(ob.obs_path.exists())
            status = json.loads(ob.status_path.read_text(encoding="utf-8"))
            reason = "analysis skipped: 2 lines < min 3"
            (run,) = status["analysis_runs"]
            self.assertEqual({"skipped": reason, "lines": 2}, without_at(run))
            self.assertIn(reason, ob.log_path.read_text(encoding="utf-8"))

    def test_at_min_lines_fires_analysis(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="full", min_lines=3)
            ob.obs_path.write_text('{"t":"user"}\n' * 3, encoding="utf-8")
            captured: dict = {}
            with fake_analysis_run(captured):
                self.assertTrue(ob._run_analysis())
            self.assertIn("cmd", captured)
            self.assertIsNotNone(ledger_of(ob))

    def test_unset_min_lines_comes_from_the_manifest(self):
        manifest_path = observer._PLUGIN_DIR / ".claude-plugin" / "plugin.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))["userConfig"]
        with tempfile.TemporaryDirectory() as d:
            ob = make_observer(Path(d), min_lines="")
            self.assertEqual(ob.min_lines, manifest["observer_min_lines"]["default"])

    def test_run_usage_is_recorded_in_status_and_log(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="use")
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            with fake_analysis_run({}):
                self.assertTrue(ob._run_analysis())
            status = json.loads(ob.status_path.read_text(encoding="utf-8"))
            (run,) = status["analysis_runs"]
            self.assertEqual(PRODUCED_RUN_RECORD, without_at(run))
            log = ob.log_path.read_text(encoding="utf-8")
            self.assertEqual(1, log.count("analysis usage: "))
            self.assertIn('"cache_creation_input_tokens":98015', log)

    def test_failed_run_usage_is_still_recorded(self):
        body = dict(
            COMPLETED_RUN, subtype="error_max_turns", terminal_reason="max_turns"
        )
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="fail")
            ob.obs_path.write_text('{"t":"user"}\n', encoding="utf-8")
            with fake_analysis_run({}, stdout=json.dumps(body)):
                self.assertFalse(ob._run_analysis())
            status = json.loads(ob.status_path.read_text(encoding="utf-8"))
            (run,) = status["analysis_runs"]
            self.assertEqual(PRODUCED_RUN_RECORD, without_at(run))

    def test_analysis_runs_survive_a_status_write_and_a_new_observer(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="keep")
            ob._add_analysis_run({"lines": 1})
            ob._write_status({"target_session": "keep", "byte_offset": 1})
            status = json.loads(ob.status_path.read_text(encoding="utf-8"))
            self.assertEqual(
                [{"lines": 1}], [without_at(r) for r in status["analysis_runs"]]
            )
            again = make_observer(tmp, session_id="keep")
            again._add_analysis_run({"lines": 2})
            status = json.loads(again.status_path.read_text(encoding="utf-8"))
            self.assertEqual(
                [{"lines": 1}, {"lines": 2}],
                [without_at(r) for r in status["analysis_runs"]],
            )

    def test_new_ledger_frontmatter(self):
        with tempfile.TemporaryDirectory() as d:
            ob = make_observer(Path(d), session_id="c1")
            ob._append_ledger("f")
            text = ledger_of(ob).read_text(encoding="utf-8")
            self.assertTrue(
                text.startswith(
                    "---\nsession_id: c1\nobserver: autonomous\n---\n\n"
                    "# Running retro ledger — test\n"
                ),
                text[:200],
            )

    def test_memory_root_self_ignore_guard(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="gi")
            ob._append_ledger("finding")
            gi = ob.ledger_dir.parent / ".gitignore"
            self.assertTrue(
                gi.exists() and gi.read_text().strip() == "*",
                "memory root must self-ignore with '*'",
            )

    def test_guard_refuses_repo_root_and_aborts_write(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            (tmp / "ledger").mkdir()
            (tmp / ".git").mkdir()
            ob = make_observer(tmp, session_id="rr")
            self.assertFalse(ob._ensure_memory_root_ignored())
            self.assertFalse(ob._append_ledger("f"), "write must be refused")
            self.assertFalse(
                (tmp / ".gitignore").exists(),
                "guard must never write a repo-root .gitignore",
            )
            self.assertEqual(
                list((tmp / "ledger").glob("*.md")),
                [],
                "no ledger may be written under a repo-root memory dir",
            )

    def test_guard_ensures_star_in_existing_gitignore(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, session_id="ex")
            root = ob.ledger_dir.parent
            (root / ".gitignore").write_text("# notes\n!keep.txt\n", encoding="utf-8")
            self.assertTrue(ob._ensure_memory_root_ignored())
            body = (root / ".gitignore").read_text(encoding="utf-8")
            self.assertIn("*", body.splitlines())
            self.assertIn("# notes", body)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class OneShotRun(unittest.TestCase):
    def test_finished_transcript_is_distilled_analyzed_and_ledgered(self):
        with tempfile.TemporaryDirectory() as d:
            ob = make_observer(Path(d), analysis=True, session_id="done")
            ob.transcript.write_text(USER_RECORD * 3, encoding="utf-8")
            seen: dict = {}

            def snapshot():
                seen["obs"] = ob.obs_path.read_text(encoding="utf-8").splitlines()

            captured: dict = {}
            with fake_analysis_run(captured, on_run=snapshot):
                self.assertEqual(0, ob.run())
            self.assertEqual(1, captured["runs"])
            self.assertIn(str(ob.obs_path), captured["input"])
            self.assertEqual(3, len(seen["obs"]))
            self.assertEqual("user", json.loads(seen["obs"][0])["t"])
            text = ledger_of(ob).read_text(encoding="utf-8")
            self.assertIn("(autonomous post-end)\n\n### Checkpoint findings\n\nok\n", text)
            self.assertFalse(ob.obs_path.exists(), "consumed observations deleted")
            self.assertFalse(ob.lock_path.exists(), "lock released")
            status = read_json(ob.status_path)
            self.assertEqual(ob.transcript.stat().st_size, status["byte_offset"])
            self.assertEqual(3, status["lines_observed"])
            self.assertEqual("analyzed", status["state"])
            self.assertEqual(
                [PRODUCED_RUN_RECORD], [without_at(r) for r in status["analysis_runs"]]
            )

    def test_rerun_reads_only_the_span_past_the_stored_offset(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="re", min_lines=3)
            ob.transcript.write_text(USER_RECORD * 5, encoding="utf-8")
            obs_lines: list[int] = []
            captured: dict = {}

            def count():
                obs_lines.append(len(ob.obs_path.read_text(encoding="utf-8").splitlines()))

            with fake_analysis_run(captured, on_run=count):
                ob.run()
                unchanged = make_observer(tmp, analysis=True, session_id="re", min_lines=3)
                unchanged.run()
                self.assertEqual(1, captured["runs"], "no growth: no second analysis")
                self.assertEqual("analyzed", read_json(ob.status_path)["state"])
                with ob.transcript.open("a", encoding="utf-8") as f:
                    f.write(USER_RECORD)
                grown = make_observer(tmp, analysis=True, session_id="re", min_lines=3)
                grown.run()
            self.assertEqual(2, captured["runs"])
            self.assertEqual([5, 1], obs_lines, "the follow-up saw only the new line")
            text = ledger_of(ob).read_text(encoding="utf-8")
            self.assertEqual(2, text.count("(autonomous post-end)"))
            runs = read_json(ob.status_path)["analysis_runs"]
            self.assertEqual([PRODUCED_RUN_RECORD] * 2, [without_at(r) for r in runs])

    def test_below_min_lines_skip_is_recorded_and_re_evaluated_after_growth(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="short", min_lines=3)
            ob.transcript.write_text(USER_RECORD * 2, encoding="utf-8")
            captured: dict = {}
            with fake_analysis_run(captured):
                ob.run()
            self.assertNotIn("cmd", captured)
            status = read_json(ob.status_path)
            reason = "analysis skipped: 2 lines < min 3"
            self.assertEqual(
                [{"skipped": reason, "lines": 2}],
                [without_at(r) for r in status["analysis_runs"]],
            )
            self.assertEqual(ob.transcript.stat().st_size, status["byte_offset"])
            self.assertEqual("skipped", status["state"])
            self.assertTrue(ob.obs_path.exists())
            with ob.transcript.open("a", encoding="utf-8") as f:
                f.write(USER_RECORD)
            with fake_analysis_run(captured):
                make_observer(tmp, analysis=True, session_id="short", min_lines=3).run()
            self.assertEqual(1, captured["runs"], "3 lines now: analyzed")
            self.assertIsNotNone(ledger_of(ob))

    def test_failed_analysis_of_an_unchanged_span_is_retried_once(self):
        failed = json.dumps(dict(COMPLETED_RUN, is_error=True, result="API Error"))
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="flaky")
            ob.transcript.write_text(USER_RECORD * 3, encoding="utf-8")
            captured: dict = {}
            states = []
            for _ in range(3):
                with fake_analysis_run(captured, stdout=failed):
                    make_observer(tmp, analysis=True, session_id="flaky").run()
                status = read_json(ob.status_path)
                states.append((status["state"], status["failed_attempts"]))
            self.assertEqual(2, captured["runs"], "one first try, one retry, then none")
            self.assertEqual([("retained", 1), ("retained", 2), ("retained", 2)], states)
            self.assertEqual(3, len(ob.obs_path.read_text(encoding="utf-8").splitlines()))

    def test_retry_over_retained_observations_can_succeed(self):
        failed = json.dumps(dict(COMPLETED_RUN, is_error=True, result="API Error"))
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            ob = make_observer(tmp, analysis=True, session_id="heal")
            ob.transcript.write_text(USER_RECORD * 3, encoding="utf-8")
            with fake_analysis_run({}, stdout=failed):
                ob.run()
            seen: list[int] = []

            def count():
                seen.append(len(ob.obs_path.read_text(encoding="utf-8").splitlines()))

            with fake_analysis_run({}, on_run=count):
                make_observer(tmp, analysis=True, session_id="heal").run()
            self.assertEqual([3], seen, "the retry read the retained observations")
            status = read_json(ob.status_path)
            self.assertEqual(("analyzed", 0), (status["state"], status["failed_attempts"]))
            self.assertIsNotNone(ledger_of(ob))

    def test_collect_only_run_keeps_observations(self):
        with tempfile.TemporaryDirectory() as d:
            ob = make_observer(Path(d), session_id="co")
            ob.transcript.write_text(USER_RECORD * 2, encoding="utf-8")
            captured: dict = {}
            with fake_analysis_run(captured):
                self.assertEqual(0, ob.run())
            self.assertNotIn("cmd", captured)
            self.assertEqual(2, len(ob.obs_path.read_text(encoding="utf-8").splitlines()))
            self.assertEqual("collected", read_json(ob.status_path)["state"])
            self.assertIsNone(ledger_of(ob))

    def test_transcript_shorter_than_the_stored_offset_is_read_from_the_start(self):
        with tempfile.TemporaryDirectory() as d:
            ob = make_observer(Path(d), session_id="tr")
            ob.transcript.write_text(USER_RECORD * 2, encoding="utf-8")
            ob.status_path.write_text(
                json.dumps({"target_session": "tr", "byte_offset": 10**6}),
                encoding="utf-8",
            )
            self.assertTrue(ob._distill())
            self.assertEqual(2, len(ob.obs_path.read_text(encoding="utf-8").splitlines()))
            self.assertEqual(
                ob.transcript.stat().st_size, read_json(ob.status_path)["byte_offset"]
            )

    def test_distill_decodes_through_shared_reader_and_keeps_streamed_message_whole(self):
        def tool_use(call_id: str) -> str:
            return json.dumps(
                {
                    "type": "assistant",
                    "message": {
                        "id": "msg_stream",
                        "content": [
                            {"type": "tool_use", "id": call_id, "name": "Bash", "input": {}}
                        ],
                    },
                }
            )

        with tempfile.TemporaryDirectory() as d:
            ob = make_observer(Path(d))
            ob.transcript.write_text(
                "\n".join([tool_use("c1"), "{not json", "[1]", tool_use("c2")]),
                encoding="utf-8",
            )
            self.assertTrue(ob._distill())
            events = [
                json.loads(ln)
                for ln in ob.obs_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(2, len(events))
            self.assertEqual({"g_stream"}, {e["mid"] for e in events})
            status = read_json(ob.status_path)
            self.assertEqual(2, status["lines_observed"])
            self.assertEqual(2, status["parse_errors"])
            self.assertEqual(ob.transcript.stat().st_size, status["byte_offset"])

    def test_stored_offset_reads_only_this_sessions_status(self):
        with tempfile.TemporaryDirectory() as d:
            work = Path(d)
            self.assertEqual(0, observer.stored_offset(observer.read_status(work, "rs")))
            (work / "status-rs.json").write_text(
                json.dumps({"target_session": "rs", "byte_offset": 4096}),
                encoding="utf-8",
            )
            self.assertEqual(
                4096, observer.stored_offset(observer.read_status(work, "rs"))
            )
            (work / "status-rs.json").write_text(
                json.dumps({"target_session": "other", "byte_offset": 999}),
                encoding="utf-8",
            )
            self.assertEqual(0, observer.stored_offset(observer.read_status(work, "rs")))


def load_arm():
    spec = importlib.util.spec_from_file_location(
        "arm_observer", str(Path(__file__).with_name("arm_observer.py"))
    )
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


IDLE = 900.0


class CatchUpSelection(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.projects = root / "projects"
        self.work = root / "data" / "session-flow-observer"
        self.ledgers = root / "repo" / ".work" / "running-retros"
        for p in (self.projects, self.work, self.ledgers):
            p.mkdir(parents=True)
        self.now = time.time()
        self.current = self.transcript("current", age=IDLE * 10)
        self.arm = load_arm()

    def tearDown(self):
        self._tmp.cleanup()

    def transcript(self, sid: str, age: float, lines: int = 1) -> Path:
        path = self.projects / f"{sid}.jsonl"
        path.write_text(USER_RECORD * lines, encoding="utf-8")
        os.utime(path, (self.now - age, self.now - age))
        return path

    def picked(self) -> list[str]:
        return [
            p.stem
            for p in self.arm.catch_up_candidates(
                self.current, "current", self.work, self.ledgers, IDLE, now=self.now
            )
        ]

    def test_ended_session_is_picked_and_the_current_one_is_not(self):
        self.transcript("ended", age=IDLE + 60)
        self.assertEqual(["ended"], self.picked())

    def test_too_fresh_and_too_old_are_skipped(self):
        self.transcript("fresh", age=IDLE - 60)
        self.transcript("old", age=self.arm.MAX_AGE_SECONDS + 60)
        self.assertEqual([], self.picked())

    def test_session_with_live_checks_is_skipped(self):
        self.transcript("live", age=IDLE + 60)
        (self.work / "live-live.jsonl").write_text("{}\n", encoding="utf-8")
        self.assertEqual([], self.picked())

    def test_session_with_a_ledger_is_skipped(self):
        self.transcript("ledgered", age=IDLE + 60)
        (self.ledgers / "20260101T000000Z-running-retro-x.md").write_text(
            "---\nsession_id: ledgered\nobserver: live\n---\n", encoding="utf-8"
        )
        self.assertEqual([], self.picked())

    def test_analyzed_session_is_skipped_until_it_grows(self):
        path = self.transcript("seen", age=IDLE + 60)
        status = self.work / "status-seen.json"
        status.write_text(
            json.dumps({"target_session": "seen", "byte_offset": path.stat().st_size}),
            encoding="utf-8",
        )
        self.assertEqual([], self.picked())
        self.transcript("seen", age=IDLE + 60, lines=2)
        self.assertEqual(["seen"], self.picked())

    def test_resumed_follow_up_of_an_analyzed_session_is_picked(self):
        path = self.transcript("resumed", age=IDLE + 60)
        size = path.stat().st_size
        (self.ledgers / "20260101T000000Z-running-retro-x.md").write_text(
            "---\nsession_id: resumed\nobserver: autonomous\n---\n", encoding="utf-8"
        )
        (self.work / "status-resumed.json").write_text(
            json.dumps(
                {"target_session": "resumed", "byte_offset": size, "state": "analyzed"}
            ),
            encoding="utf-8",
        )
        self.assertEqual([], self.picked())
        self.transcript("resumed", age=IDLE + 60, lines=2)
        self.assertEqual(["resumed"], self.picked())

    def test_failed_session_is_picked_until_its_retry_is_spent(self):
        path = self.transcript("failed", age=IDLE + 60)
        status = self.work / "status-failed.json"
        for attempts, picked in ((1, ["failed"]), (2, [])):
            status.write_text(
                json.dumps(
                    {
                        "target_session": "failed",
                        "byte_offset": path.stat().st_size,
                        "state": "retained",
                        "failed_attempts": attempts,
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(picked, self.picked(), attempts)

    def test_at_most_two_newest_first(self):
        for sid, age in (("a", IDLE + 300), ("b", IDLE + 100), ("c", IDLE + 200)):
            self.transcript(sid, age=age)
        self.assertEqual(["b", "c"], self.picked())


class CatchUpLauncher(unittest.TestCase):
    def run_main(self, arm, argv: list[str]) -> tuple[int, str]:
        buf = io.StringIO()
        with mock.patch.object(sys, "argv", ["arm_observer.py", *argv]):
            with contextlib.redirect_stdout(buf):
                rc = arm.main()
        return rc, buf.getvalue()

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.projects = self.root / "projects"
        self.projects.mkdir()
        self.current = self.projects / "current.jsonl"
        self.current.write_text(USER_RECORD, encoding="utf-8")
        self.argv = [
            "--transcript",
            str(self.current),
            "--session-id",
            "current",
            "--work-dir",
            str(self.root / "work"),
            "--ledger-dir",
            str(self.root / "ledger"),
        ]

    def tearDown(self):
        self._tmp.cleanup()

    def ended(self, sid: str) -> Path:
        path = self.projects / f"{sid}.jsonl"
        path.write_text(USER_RECORD, encoding="utf-8")
        then = time.time() - IDLE - 60
        os.utime(path, (then, then))
        return path

    def test_each_pick_launches_observer_with_its_own_transcript_and_settings(self):
        ended = self.ended("ended")
        arm = load_arm()
        cmds: list[list[str]] = []

        def capture(cmd, cwd):
            cmds.append(cmd)
            return 999999

        arm.spawn_detached = capture
        argv = self.argv + ["--effort", "low", "--min-lines", "42", "--analysis"]
        rc, out = self.run_main(arm, argv)
        self.assertEqual(0, rc)
        self.assertEqual("observer: catch-up for session ended (pid 999999)\n", out)
        (cmd,) = cmds
        self.assertEqual(str(Path(arm.__file__).with_name("observer.py")), cmd[1])
        self.assertEqual(str(ended.resolve()), cmd[cmd.index("--transcript") + 1])
        self.assertEqual("ended", cmd[cmd.index("--session-id") + 1])
        self.assertEqual("low", cmd[cmd.index("--effort") + 1])
        self.assertEqual("42", cmd[cmd.index("--min-lines") + 1])
        self.assertIn("--analysis", cmd)
        self.assertNotIn("--bare", cmd)

    def test_nothing_to_catch_up_spawns_nothing(self):
        arm = load_arm()
        arm.spawn_detached = mock.Mock()
        rc, out = self.run_main(arm, self.argv)
        self.assertEqual(0, rc)
        self.assertEqual("observer: no ended session to catch up\n", out)
        arm.spawn_detached.assert_not_called()

    def test_spawn_failure_degrades_gracefully(self):
        self.ended("boom")
        arm = load_arm()

        def boom(*_args, **_kwargs):
            raise RuntimeError("boom")

        arm.spawn_detached = boom
        rc, out = self.run_main(arm, self.argv)
        self.assertEqual(0, rc)
        self.assertEqual("observer: failed to spawn for boom: boom\n", out)

    def test_real_detached_launch_runs_observer_to_completion(self):
        ended = self.ended("real")
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", ResourceWarning)
            rc, out = self.run_main(load_arm(), self.argv)
        self.assertEqual(0, rc)
        pid = int(out.rsplit("(pid ", 1)[1].rstrip(")\n"))
        status = self.root / "work" / "status-real.json"
        wait_for(status, pid)
        self.assertEqual("collected", read_json(status)["state"])
        self.assertEqual(ended.stat().st_size, read_json(status)["byte_offset"])


def wait_for(path: Path, pid: int, timeout: float = 15.0) -> None:
    """Wait for a detached child to exit (reaping it on POSIX), then for `path`."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.name != "nt":
            with contextlib.suppress(ChildProcessError):
                if os.waitpid(pid, os.WNOHANG)[0] == pid:
                    break
        elif not observer._pid_alive(pid):
            break
        time.sleep(0.05)
    while time.time() < deadline and not path.exists():
        time.sleep(0.05)
    if not path.exists():
        raise AssertionError(f"{path} not written within {timeout}s")


HOOK = Path(__file__).resolve().parents[3] / "hooks" / "observer-catchup.sh"


@unittest.skipUnless(
    shutil.which("bash") and shutil.which("jq") and os.name != "nt",
    "needs bash and jq",
)
class CatchUpHook(unittest.TestCase):
    """Each guard stops the hook before any launch; with none tripped it launches."""

    def run_hook(self, root: Path, name: str, env: dict, stdin: dict) -> Path:
        data = root / name
        projects = root / "projects"
        projects.mkdir(exist_ok=True)
        ended = projects / "ended.jsonl"
        if not ended.exists():
            ended.write_text(USER_RECORD, encoding="utf-8")
            then = time.time() - IDLE - 60
            os.utime(ended, (then, then))
        base = {
            "PATH": os.environ["PATH"],
            "HOME": str(root),
            "CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED": "true",
            "CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_ENABLED": "true",
            "CLAUDE_PLUGIN_OPTION_OBSERVER_MIN_LINES": "1000000",
            "CLAUDE_CODE_SESSION_ATTENDED": "1",
            "CLAUDE_CODE_ENTRYPOINT": "cli",
            "CLAUDE_PLUGIN_DATA": str(data),
            "CLAUDE_PROJECT_DIR": str(root / "repo"),
        }
        payload = {
            "source": "startup",
            "session_id": "current",
            "transcript_path": str(projects / "current.jsonl"),
            **stdin,
        }
        proc = subprocess.run(
            ["bash", str(HOOK)],
            input=json.dumps({k: v for k, v in payload.items() if v is not None}),
            env={k: v for k, v in {**base, **env}.items() if v is not None},
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        return data / "session-flow-observer" / "status-ended.json"

    def test_guards_and_launch(self):
        blocked = {
            "disabled": ({"CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED": None}, {}),
            "analysis off": ({"CLAUDE_PLUGIN_OPTION_OBSERVER_ANALYSIS_ENABLED": "false"}, {}),
            "headless": ({"CLAUDE_CODE_ENTRYPOINT": "sdk-cli"}, {}),
            "unattended": ({"CLAUDE_CODE_SESSION_ATTENDED": "0"}, {}),
            "analysis run": ({"SESSION_FLOW_OBSERVER_ANALYSIS": "1"}, {}),
            "compact": ({}, {"source": "compact"}),
            "subagent": ({}, {"agent_type": "Explore"}),
        }
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            statuses = {
                name: self.run_hook(root, name.replace(" ", "-"), env, stdin)
                for name, (env, stdin) in blocked.items()
            }
            launched = self.run_hook(root, "launch", {}, {})
            deadline = time.time() + 15
            while time.time() < deadline and not launched.exists():
                time.sleep(0.05)
            self.assertTrue(launched.exists(), "unguarded start must launch")
            time.sleep(0.5)
            for name, status in statuses.items():
                self.assertFalse(status.exists(), f"{name}: guard did not stop it")


if __name__ == "__main__":
    unittest.main()
