"""Tests for the exporters and import-ledger (AC27 to AC29), driven through round.py's CLI.

Sessions are built in temporary data dirs: questions.json written directly, responses.json
derived from a hand-written event log with the server's own rebuild function. The ledger and
Brief outputs are graded by the plugin's `scripts/check-open-questions.sh`.
"""

from __future__ import annotations

import base64
import html.parser
import json
import random
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import exporters  # noqa: E402
from server import rebuild_responses  # noqa: E402

ROUND = HERE / "round.py"
CHECK = HERE.parent / "scripts" / "check-open-questions.sh"
BASH = shutil.which("bash")
AT = "2026-09-24T10:00:00Z"


def question(qid, **extra):
    q = {
        "id": qid,
        "short": f"Short {qid}",
        "title": f"Question {qid}?",
        "recommendation": f"Recommended answer for {qid}.",
        "commits": [],
        "alternatives": [
            {"key": "a", "text": f"Alt a of {qid}"},
            {"key": "b", "text": "Later"},
        ],
        "round": 1,
        "history": [{"at": AT, "by": "claude", "text": "Asked."}],
    }
    q.update(extra)
    return q


def event(seq, qid, kind, alt=None, text=""):
    return {"seq": seq, "id": qid, "kind": kind, "alt": alt, "text": text, "at": AT}


class SessionCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="iv-export-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.dir = self.tmp / "data"
        self.dir.mkdir()

    def session(
        self, questions, events, meta=None, restatement=None, restatements=None
    ):
        doc = {
            "meta": meta or {"title": "Export test", "eyebrow": "surface eyebrow text"},
            "rev": 1,
            "groups": [],
            "questions": questions,
            "visuals": [],
        }
        if restatements:
            doc["restatements"] = restatements
            doc["restatement"] = restatements[-1]
        if restatement:
            doc["restatement"] = restatement
        (self.dir / "questions.json").write_text(json.dumps(doc), encoding="utf-8")
        responses, history = rebuild_responses(events)
        (self.dir / "responses.json").write_text(
            json.dumps(
                {
                    "seq": max([e["seq"] for e in events] or [0]),
                    "events": events,
                    "responses": responses,
                    "history": history,
                }
            ),
            encoding="utf-8",
        )

    def rp(self, *args, d=None):
        p = subprocess.run(
            [sys.executable, str(ROUND), "--dir", str(d or self.dir), *args],
            capture_output=True,
            text=True,
            timeout=60,
        )
        return p.returncode, p.stdout + p.stderr

    def export(self, what, d=None):
        out = self.tmp / f"{what}-{len(list(self.tmp.iterdir()))}.out"
        rc, text = self.rp(f"export-{what}", "--out", str(out), d=d)
        self.assertEqual(rc, 0, text)
        return out

    def check(self, *args):
        self.assertIsNotNone(BASH, "bash not on PATH")
        p = subprocess.run(
            [BASH, str(CHECK), *[str(a) for a in args]],
            capture_output=True,
            text=True,
            timeout=60,
        )
        return p.returncode, p.stdout + p.stderr

    def decided(self):
        """Q1 accepted with both commitments confirmed, Q2 alt, Q3 own, Q4 archived."""
        qs = [
            question("Q1", commits=["One writer only", "No network"]),
            question("Q2"),
            question("Q3"),
            question("Q4", archived={"why": "Off the chosen path.", "at": AT}),
        ]
        events = [
            event(1, "Q1", "accept"),
            event(2, "Q1", "confirm", alt="0"),
            event(3, "Q2", "alt", alt="a", text="with a note"),
            event(4, "Q3", "own", text="My own words."),
            event(5, "Q1", "confirm", alt="1"),
        ]
        self.session(qs, events)


def register_rows(path):
    text = Path(path).read_text(encoding="utf-8")
    return [line for line in text.splitlines() if re.match(r"^- Q\d+ \|", line)]


class TestExportLedger(SessionCase):
    """AC27."""

    def test_decided_session_passes_the_gate(self):
        self.decided()
        ledger = self.export("ledger")
        rc, out = self.check("--ledger", ledger)
        self.assertEqual(rc, 0, out + ledger.read_text(encoding="utf-8"))
        self.assertIn("status=clean", out)

    def test_one_open_question_exits_1(self):
        self.decided()
        doc = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))
        doc["questions"].append(question("Q5"))
        (self.dir / "questions.json").write_text(json.dumps(doc), encoding="utf-8")
        rc, out = self.check("--ledger", self.export("ledger"))
        self.assertEqual(rc, 1, out)

    def test_row_shapes_and_status_mapping(self):
        self.decided()
        text = self.export("ledger").read_text(encoding="utf-8")
        self.assertEqual(text.count("## Open-question register"), 1)
        rows = register_rows(self.export("ledger"))
        self.assertEqual(len(rows), 4)
        self.assertRegex(
            rows[0],
            r"^- Q1 \| answered \| round 1 \| Question Q1\? \| answer:: accepted: ",
        )
        self.assertIn("commitments:: +One writer only; +No network", rows[0])
        self.assertIn("alt a: Alt a of Q2", rows[1])
        self.assertIn("free-text: My own words.", rows[2])
        self.assertRegex(rows[3], r"^- Q4 \| withdrawn \| .*Off the chosen path\.")
        self.assertIn("**Decision tree:**", text)
        self.assertLess(
            text.index("**Decision tree:**"), text.index("## Open-question register")
        )
        self.assertIn("### Deferred questions", text)
        self.assertNotIn("surface eyebrow text", text)

    def test_a_waiting_question_stays_open_even_with_a_decision(self):
        qs = [
            question(
                "Q1", waiting=True, waitingBy="user", waitsOn="your confirmation of X"
            ),
            question("Q2", waiting=True, waitsOn="research"),
        ]
        self.session(qs, [event(1, "Q1", "own", text="Yes if X holds.")])
        rows = register_rows(self.export("ledger"))
        self.assertRegex(
            rows[0], r"^- Q1 \| open \| .*hold:: user your confirmation of X"
        )
        self.assertRegex(rows[1], r"^- Q2 \| open \| .*hold:: claude research")

    def test_a_decision_set_aside_by_a_user_hold_does_not_count(self):
        later = "2026-09-24T10:00:05Z"
        qs = [
            question("Q1", setAsideAt=AT),
            question("Q2", setAsideAt=AT),
            question(
                "Q3",
                setAsideAt=AT,
                terminal={
                    "decision": "accept",
                    "alt": None,
                    "text": "",
                    "updatedAt": AT,
                },
            ),
        ]
        newer = dict(event(2, "Q2", "accept"), at=later)
        self.session(qs, [event(1, "Q1", "own", text="If X?"), newer])
        rows = register_rows(self.export("ledger"))
        self.assertRegex(rows[0], r"^- Q1 \| open \|")
        self.assertRegex(rows[1], r"^- Q2 \| answered \| .*accepted: ")
        self.assertRegex(rows[2], r"^- Q3 \| open \|")

    def test_a_page_decision_is_set_aside_by_seq_and_a_terminal_one_by_time(self):
        q = {"id": "Q1", "setAsideAt": AT, "setAsideSeq": 3}
        page = {"decision": "accept", "updatedAt": AT, "seq": 4}
        self.assertIs(exporters.latest_decision(q, {"Q1": page}), page)
        self.assertIsNone(exporters.latest_decision(q, {"Q1": {**page, "seq": 3}}))
        term = {"decision": "accept", "updatedAt": AT}
        self.assertIsNone(exporters.latest_decision({**q, "terminal": term}, {}))

    def test_a_terminal_decision_with_a_rev_is_set_aside_by_rev(self):
        q = {"id": "Q1", "setAsideAt": AT, "setAsideRev": 5}
        term = {"decision": "accept", "updatedAt": AT, "rev": 6}
        self.assertIs(exporters.latest_decision({**q, "terminal": term}, {}), term)
        held = {**term, "rev": 5}
        self.assertIsNone(exporters.latest_decision({**q, "terminal": held}, {}))

    def test_non_contiguous_ids_are_renumbered_with_the_original_id(self):
        self.session(
            [question("J2"), question("J1"), question("Q7")],
            [
                event(1, "J1", "accept"),
                event(2, "J2", "accept"),
                event(3, "Q7", "accept"),
            ],
        )
        ledger = self.export("ledger")
        rows = register_rows(ledger)
        self.assertEqual([r.split(" | ")[0] for r in rows], ["- Q1", "- Q2", "- Q3"])
        self.assertIn("[J1]", rows[0])
        self.assertIn("[J2]", rows[1])
        self.assertIn("[Q7]", rows[2])
        rc, out = self.check("--ledger", ledger)
        self.assertEqual(rc, 0, out)

    def test_pipes_and_newlines_in_text_do_not_break_rows(self):
        self.session(
            [question("Q1", title="A | B\n## heading?")],
            [event(1, "Q1", "own", text="line one\n```\nline | two")],
        )
        ledger = self.export("ledger")
        rc, out = self.check("--ledger", ledger)
        self.assertEqual(rc, 0, out + ledger.read_text(encoding="utf-8"))


class TestExportBrief(SessionCase):
    """AC28 and the Brief's sections."""

    def deferred_session(self):
        qs = [
            question("Q1", commits=["Unticked promise"]),
            question("Q2"),
            question("Q3"),
        ]
        events = [
            event(1, "Q1", "own", text="Mine."),
            event(2, "Q2", "defer", text="after the pilot"),
            event(3, "Q3", "accept"),
        ]
        self.session(qs, events)

    def test_deferred_questions_pass_the_brief_cross_check(self):
        self.deferred_session()
        ledger, brief = self.export("ledger"), self.export("brief")
        rc, out = self.check("--ledger", ledger, "--brief", brief)
        self.assertEqual(rc, 0, out + brief.read_text(encoding="utf-8"))
        self.assertIn("brief=ok", out)

    def test_brief_shape(self):
        self.deferred_session()
        text = self.export("brief").read_text(encoding="utf-8")
        headings = [line for line in text.splitlines() if line.startswith("#")]
        self.assertEqual(
            headings,
            [
                "## Brief",
                "### TLDR",
                "### Goal",
                "### Constraints",
                "### Acceptance criteria",
                "### Captured assumptions",
                "### Out-of-scope",
                "### Deferred questions",
                "## Plan",
            ],
        )
        self.assertIn("Export test", text)
        self.assertIn("risk: Unticked promise (unconfirmed)", text)
        self.assertRegex(text, r"- Q2: .*\*\*arbiter: USER-RESERVED\*\*")
        self.assertTrue(text.rstrip().endswith("## Plan"))
        self.assertNotIn("superseded-by-plan", text)

    def acceptance_section(self, acceptance, verdicts=("confirm",)):
        self.session(
            [question("Q1")],
            [event(1, "Q1", "accept")]
            + [
                {**event(2 + i, None, "confirm-understanding", alt), "contentRev": 1}
                for i, alt in enumerate(verdicts)
            ],
            restatement={"rev": 1, "at": AT, "sections": {"acceptance": acceptance}},
        )
        text = self.export("brief").read_text(encoding="utf-8")
        return text, text.split("### Acceptance criteria")[1].split("###")[0]

    def test_restated_acceptance_criteria_become_plain_bullets(self):
        text, section = self.acceptance_section(
            "- AC one is testable\n\n- [ ] AC two\n[x] AC three"
        )
        self.assertEqual(
            [x for x in section.splitlines() if x],
            ["- AC one is testable", "- AC two", "- AC three"],
        )
        self.assertNotIn("none recorded in the interview surface", text)

    def test_unconfirmed_or_rejected_restatement_exports_no_criteria(self):
        for verdicts in ((), ("off",), ("confirm", "off")):
            with self.subTest(verdicts=verdicts):
                text, section = self.acceptance_section("- AC one", verdicts)
                self.assertNotIn("AC one", text)
                self.assertIn("- none recorded in the interview surface", section)

    def test_later_confirm_after_off_exports_criteria(self):
        _, section = self.acceptance_section("- AC one", ("off", "confirm"))
        self.assertIn("- AC one", section)

    def test_no_restatement_keeps_the_none_line(self):
        self.deferred_session()
        text = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("- none recorded in the interview surface", text)

    def test_restated_acceptance_cannot_add_a_heading_or_fence(self):
        text, section = self.acceptance_section("# Sneaky\n```\n~~~")
        headings = [x for x in text.splitlines() if x.startswith("#")]
        self.assertEqual(
            headings[:5],
            [
                "## Brief",
                "### TLDR",
                "### Goal",
                "### Constraints",
                "### Acceptance criteria",
            ],
        )
        self.assertNotIn("# Sneaky", headings)
        self.assertFalse(
            any(x.startswith(("- `", "- ~")) for x in section.splitlines())
        )
        rc, out = self.check(
            "--ledger", self.export("ledger"), "--brief", self.export("brief")
        )
        self.assertEqual(rc, 0, out)
        self.assertIn("brief=ok", out)

    def test_confirmed_commitment_is_an_assumption_and_archived_is_out_of_scope(self):
        self.decided()
        text = self.export("brief").read_text(encoding="utf-8")
        assumptions = text.split("### Captured assumptions")[1].split("###")[0]
        self.assertIn("One writer only", assumptions)
        self.assertIn("No network: confirmed on Q1", assumptions)
        self.assertNotIn("risk:", assumptions)
        scope = text.split("### Out-of-scope")[1].split("###")[0]
        self.assertIn("Off the chosen path.", scope)


LEDGER_HEAD = "# Interview ledger\n\n## Open-question register\n\n"


class TestBriefIds(SessionCase):
    """The Brief numbers questions as the ledger does and carries the ledger's own rows."""

    def gapped(self):
        """Page ids Q1, Q2 and Q5; the ledger also holds Q3 and Q4, deferred there only."""
        self.session(
            [question("Q1"), question("Q2"), question("Q5")],
            [
                event(1, "Q1", "accept"),
                event(2, "Q2", "alt", alt="a"),
                event(3, "Q5", "defer", text="the pilot"),
            ],
        )
        ledger = self.tmp / "hand-ledger.md"
        ledger.write_text(
            LEDGER_HEAD + "- Q1 | answered | round 1 | Question Q1? | accepted\n"
            "- Q2 | answered | round 1 | Question Q2? | a\n"
            "- Q3 | deferred | round 1 | Four unclaimed? | deferred to planning\n"
            "- Q4 | deferred | round 1 | Which cap? | USER-RESERVED until the pilot\n"
            "- Q5 | deferred | round 1 | Question Q5? | the pilot\n",
            encoding="utf-8",
        )
        return ledger

    def brief_with(self, ledger):
        out = self.tmp / "brief-with.md"
        rc, text = self.rp("export-brief", "--out", str(out), "--ledger", str(ledger))
        self.assertEqual(rc, 0, text)
        return out.read_text(encoding="utf-8")

    def test_ledger_only_deferred_rows_reach_the_brief_under_their_real_ids(self):
        ledger = self.gapped()
        text = self.brief_with(ledger)
        deferred = text.split("### Deferred questions")[1].split("##")[0]
        self.assertRegex(
            deferred,
            r"- Q3: Four unclaimed\?, defer until deferred to planning; \*\*arbiter: /planning:plan\*\*",
        )
        self.assertRegex(
            deferred,
            r"- Q4: Which cap\?, defer until USER-RESERVED until the pilot; \*\*arbiter: USER-RESERVED\*\*",
        )
        self.assertRegex(deferred, r"- Q5: Question Q5\?, defer until the pilot;")
        self.assertIn("- 5 questions: 2 answered, 3 deferred", text)
        self.assertNotIn("[Q", text)
        brief = self.tmp / "brief-with.md"
        rc, out = self.check("--ledger", ledger, "--brief", brief)
        self.assertEqual(rc, 0, out)
        self.assertIn("brief=ok", out)

    def test_constraint_lines_carry_the_real_id_not_a_position(self):
        text = self.brief_with(self.gapped())
        constraints = text.split("### Constraints")[1].split("###")[0]
        self.assertIn("- Q2 Short Q2: alt a:", constraints)
        self.assertNotIn("Q3 Short Q2", constraints)

    def test_without_a_ledger_a_gap_keeps_the_register_number_and_adds_the_id(self):
        self.session(
            [question("Q1"), question("Q3"), question("Q4")],
            [
                event(1, "Q1", "accept"),
                event(2, "Q3", "defer", text="later"),
                event(3, "Q4", "accept"),
            ],
        )
        text = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("- Q2 [Q3]: Question Q3?, defer until later;", text)
        self.assertIn("- Q3 [Q4] Short Q4: accepted:", text)
        self.assertNotIn("[Q3] [Q3]", text)
        rc, out = self.check(
            "--ledger", self.export("ledger"), "--brief", self.export("brief")
        )
        self.assertEqual(rc, 0, out)
        self.assertIn("brief=ok", out)


class TestBriefRestatements(SessionCase):
    """Goal, Constraints, Acceptance criteria and Out-of-scope come from the newest confirmed rev."""

    def rev(self, n, **sections):
        return {"rev": n, "at": f"2026-09-24T10:0{n}:00Z", "sections": sections}

    def confirm(self, seq, rev, alt="confirm"):
        return {
            **event(seq, None, "confirm-understanding", alt),
            "contentRev": rev,
            "at": f"2026-09-24T11:0{seq}:00Z",
        }

    def brief(self, restatements, verdicts):
        self.session(
            [question("Q1", archived={"why": "Dropped.", "at": AT}), question("Q2")],
            [event(1, "Q2", "accept"), *verdicts],
            restatements=restatements,
        )
        return self.export("brief").read_text(encoding="utf-8")

    def section(self, text, name):
        return text.split(f"### {name}")[1].split("###")[0].strip().splitlines()

    def test_a_confirmed_rev_one_survives_an_unconfirmed_rev_three(self):
        text = self.brief(
            [
                self.rev(
                    1,
                    goal="Cut p75 load time.",
                    constraints="- stdlib only",
                    acceptance="- p75 is 2.0 s or less\n- no new dependency",
                    outOfScope="- mobile layouts",
                ),
                self.rev(2, goal="Draft two.", acceptance="- narrowed"),
                self.rev(3, goal="Draft three.", acceptance="- narrower"),
            ],
            [self.confirm(2, 1)],
        )
        self.assertIn(
            "- Restatement: UNCONFIRMED (latest rev 3); the sections below are from confirmed rev 1",
            text,
        )
        self.assertEqual(self.section(text, "Goal"), ["Cut p75 load time."])
        self.assertEqual(
            self.section(text, "Acceptance criteria"),
            ["- p75 is 2.0 s or less", "- no new dependency"],
        )
        self.assertEqual(self.section(text, "Constraints")[0], "- stdlib only")
        self.assertEqual(self.section(text, "Out-of-scope")[0], "- mobile layouts")
        self.assertIn("Dropped.", "\n".join(self.section(text, "Out-of-scope")))
        self.assertNotIn("Draft", text)

    def test_a_confirmed_latest_rev_is_stamped_with_its_time(self):
        text = self.brief(
            [self.rev(1, goal="One."), self.rev(2, goal="Two.")],
            [self.confirm(2, 2)],
        )
        self.assertIn("- Restatement: confirmed at rev 2, 2026-09-24T11:02:00Z", text)
        self.assertNotIn("UNCONFIRMED", text)
        self.assertEqual(self.section(text, "Goal"), ["Two."])

    def test_no_rev_confirmed_is_stamped_unconfirmed_and_keeps_the_title_goal(self):
        text = self.brief(
            [self.rev(1, goal="One.", acceptance="- a")], [self.confirm(2, 1, "off")]
        )
        self.assertIn(
            "- Restatement: UNCONFIRMED (latest rev 1); no rev was confirmed", text
        )
        self.assertEqual(self.section(text, "Goal"), ["Export test"])
        self.assertIn("- none recorded in the interview surface", text)

    def test_a_withdrawn_confirm_does_not_count(self):
        text = self.brief(
            [self.rev(1, goal="One.")],
            [{**self.confirm(2, 1), "withdrawn": True}],
        )
        self.assertIn("UNCONFIRMED (latest rev 1)", text)

    def test_a_file_with_only_a_restatement_is_still_read(self):
        self.session(
            [question("Q1")],
            [event(1, "Q1", "accept"), self.confirm(2, 1)],
            restatement=self.rev(1, goal="Legacy goal."),
        )
        text = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("- Restatement: confirmed at rev 1,", text)
        self.assertEqual(self.section(text, "Goal"), ["Legacy goal."])

    def test_no_restatement_writes_no_stamp(self):
        self.session([question("Q1")], [event(1, "Q1", "accept")])
        self.assertNotIn(
            "Restatement:", self.export("brief").read_text(encoding="utf-8")
        )

    def test_restated_goal_constraints_and_scope_cannot_add_a_heading_or_fence(self):
        text = self.brief(
            [
                self.rev(
                    1,
                    goal="# Sneaky goal",
                    constraints="# Sneaky\n```\n~~~",
                    outOfScope="## Also sneaky",
                )
            ],
            [self.confirm(2, 1)],
        )
        headings = [x for x in text.splitlines() if x.startswith("#")]
        self.assertEqual(len(headings), 9, headings)
        self.assertFalse(
            any(x.startswith(("```", "~~~", "# Sneaky")) for x in text.splitlines())
        )

    def test_the_gate_fails_an_unconfirmed_brief_and_passes_a_confirmed_one(self):
        revs = [self.rev(1, goal="One."), self.rev(2, goal="Two.")]
        unconfirmed = self.brief(revs, [self.confirm(2, 1)])
        self.assertIn("UNCONFIRMED", unconfirmed)
        ledger = self.export("ledger")
        brief = self.export("brief")
        rc, out = self.check("--ledger", ledger, "--brief", brief)
        self.assertEqual(rc, 1, out)
        self.assertIn("brief=unconfirmed status=incomplete", out)
        self.brief(revs, [self.confirm(2, 2)])
        rc, out = self.check(
            "--ledger", self.export("ledger"), "--brief", self.export("brief")
        )
        self.assertEqual(rc, 0, out)
        self.assertIn("brief=ok", out)


class TestSupersededCommitments(SessionCase):
    """A commitment list a later revise replaced never reaches the Brief."""

    def test_only_the_replacing_list_is_a_named_risk(self):
        self.session(
            [question("Q1", commits=["PR 1 ships the parser", "PR 6 ships docs"])],
            [event(1, "Q1", "accept"), event(2, "Q1", "confirm", alt="0")],
        )
        rc, out = self.rp(
            "revise", "Q1", "--commit", "One PR ships everything", "--force"
        )
        self.assertEqual(rc, 0, out)
        text = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("risk: One PR ships everything (unconfirmed); from Q1", text)
        self.assertNotIn("PR 1", text)
        self.assertNotIn("PR 6", text)
        self.assertIn("- 0 commitments confirmed; 1 unconfirmed", text)


class TestResolvedOwnAnswer(SessionCase):
    """A resolution is the row's answer and the user's words its note, through every export."""

    TYPED = "YES I AGREE DAMMIT"
    READ = "2.0 s or less at p75"

    def resolved(self):
        self.session(
            [question("Q1", commits=["Measure at p75"]), question("Q2")],
            [event(1, "Q1", "own", text=self.TYPED), event(2, "Q2", "accept")],
        )
        rc, out = self.rp("reply", "Q1", "--resolution", self.READ)
        self.assertEqual(rc, 0, out)

    def row(self, ledger):
        return register_rows(ledger)[0]

    def test_the_ledger_row_answers_with_the_resolution_and_notes_the_typed_words(self):
        self.resolved()
        row = self.row(self.export("ledger"))
        self.assertIn(
            f"answer:: free-text: {self.READ}; note:: {self.TYPED}; commitments::", row
        )

    def test_the_brief_gives_the_resolution_and_labels_the_typed_words_a_note(self):
        self.resolved()
        text = self.export("brief").read_text(encoding="utf-8")
        self.assertIn(
            f"- Q1 Short Q1: free-text: {self.READ}; note: {self.TYPED}", text
        )

    def test_a_later_answer_does_not_inherit_the_resolution(self):
        self.resolved()
        responses = json.loads((self.dir / "responses.json").read_text("utf-8"))
        events = responses["events"]
        events.append(
            {
                **event(3, "Q1", "own", text="Actually, p95."),
                "at": "2026-09-25T10:00:00Z",
            }
        )
        doc = json.loads((self.dir / "questions.json").read_text("utf-8"))
        self.session(doc["questions"], events)
        row = self.row(self.export("ledger"))
        self.assertIn("answer:: free-text: Actually, p95.", row)
        self.assertNotIn(self.READ, row)
        self.assertNotIn("note::", row)

    def test_an_exported_resolution_round_trips_through_import_ledger(self):
        self.resolved()
        first = self.export("ledger")
        again = self.tmp / "again"
        again.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=again)
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.row(self.export("ledger", d=again)), self.row(first))
        text = self.export("brief", d=again).read_text(encoding="utf-8")
        self.assertIn(f"free-text: {self.READ}; note: {self.TYPED}", text)

    def test_a_set_aside_answer_does_not_use_the_resolution(self):
        self.resolved()
        ops = self.tmp / "wait.json"
        ops.write_text(
            json.dumps(
                {
                    "ops": [
                        {"op": "wait", "id": "Q1", "waitsOn": "a figure", "by": "user"}
                    ]
                }
            ),
            encoding="utf-8",
        )
        rc, out = self.rp("apply", "--file", str(ops))
        self.assertEqual(rc, 0, out)
        row = self.row(self.export("ledger"))
        self.assertIn(f"aside:: free-text: {self.TYPED}", row)
        self.assertNotIn(self.READ, row)


class TestConfirmsAgainstAnEarlierList(unittest.TestCase):
    def test_a_confirm_at_or_below_commits_since_seq_does_not_tick(self):
        q = question("Q1", commits=["A", "B"], commitsSinceSeq=5)
        old = [event(4, "Q1", "confirm", alt="0"), event(5, "Q1", "confirm", alt="1")]
        self.assertEqual(exporters.commitments(q, old), ([], ["A", "B"]))
        later = [*old, event(6, "Q1", "confirm", alt="1")]
        self.assertEqual(exporters.commitments(q, later), (["B"], ["A"]))


class TestConfirmedInTheTerminal(SessionCase):
    def test_commits_confirmed_by_claude_count_as_confirmed(self):
        qs = [
            question(
                "Q1",
                commits=["One writer only", "No network"],
                commitsConfirmed=[{"index": 1, "reason": "said in chat", "at": AT}],
            )
        ]
        self.session(qs, [event(1, "Q1", "accept"), event(2, "Q1", "confirm", alt="0")])
        brief = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("- 2 commitments confirmed; 0 unconfirmed", brief)
        self.assertIn("- No network: confirmed on Q1", brief)
        [row] = register_rows(self.export("ledger"))
        self.assertIn("commitments:: +One writer only; +No network", row)


PENDING = "pending agent validation"


class TestAcceptAuditExport(SessionCase):
    """An accept an accept-audit made exports as accepted pending agent validation."""

    def audited(self, extra=(), terminal=None):
        items = [{"id": "Q1", "contentRev": 0}, {"id": "Q2", "contentRev": 0}]
        qs = [
            question("Q1", commits=["One writer only"], **(terminal or {})),
            question("Q2"),
            question("Q3"),
        ]
        events = [
            {**event(1, None, "accept-audit", alt="1"), "items": items},
            {**event(2, "Q1", "accept"), "auditSeq": 1},
            {**event(3, "Q2", "accept"), "auditSeq": 1},
            event(4, "Q3", "accept"),
            *extra,
        ]
        self.session(qs, events)

    def test_audit_accepts_carry_the_note_and_a_hand_accept_does_not(self):
        self.audited()
        ledger = self.export("ledger")
        q1, q2, q3 = register_rows(ledger)
        self.assertIn(
            f"| open | round 1 | Question Q1? | answer:: accepted: Recommended answer for "
            f"Q1.; note:: {PENDING}; commitments:: -One writer only",
            q1,
        )
        self.assertIn(f"note:: {PENDING}", q2)
        self.assertRegex(q3, r"\| answer:: accepted: Recommended answer for Q3\.$")
        rc, out = self.check("--ledger", ledger)
        self.assertEqual(rc, 1, out)
        self.assertIn("open=1", out)
        brief = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("- Q3 Short Q3: accepted: Recommended answer for Q3.\n", brief)

    def test_commitments_stay_unconfirmed(self):
        self.audited()
        brief = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("- 0 commitments confirmed; 1 unconfirmed", brief)
        self.assertIn("- risk: One writer only (unconfirmed); from Q1", brief)

    def test_a_later_decision_or_terminal_answer_reads_as_its_own(self):
        later = "2099-01-01T00:00:00Z"
        self.audited(
            extra=[event(5, "Q2", "alt", alt="a")],
            terminal={
                "terminal": {"decision": "accept", "text": "", "updatedAt": later}
            },
        )
        q1, q2, _ = register_rows(self.export("ledger"))
        self.assertNotIn(PENDING, q1)
        self.assertIn("alt a: Alt a of Q2", q2)
        self.assertNotIn(PENDING, q2)

    def test_the_note_survives_import_and_re_export(self):
        self.audited()
        ledger = self.export("ledger")
        rows = register_rows(ledger)
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)


class TestCommitmentsCarriedByAnswerKind(SessionCase):
    """Q24: accept and own carry a recommendation's commitments; alt and defer carry none."""

    def test_only_accept_and_own_carry_risks(self):
        qs = [question(f"Q{i}", commits=[f"Part of Q{i}"]) for i in range(1, 5)]
        events = [
            event(1, "Q1", "accept"),
            event(2, "Q2", "alt", alt="a"),
            event(3, "Q3", "own", text="My words."),
            event(4, "Q4", "defer"),
        ]
        self.session(qs, events)
        brief = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("- 0 commitments confirmed; 2 unconfirmed", brief)
        self.assertIn("- risk: Part of Q1 (unconfirmed); from Q1", brief)
        self.assertIn("- risk: Part of Q3 (unconfirmed); from Q3", brief)
        self.assertNotIn("Part of Q2", brief)
        self.assertNotIn("Part of Q4", brief)
        report = self.export("report").read_text(encoding="utf-8")
        risks = report.split("<h2>Named risks</h2>", 1)[1]
        self.assertIn("Part of Q1", risks)
        self.assertNotIn("Part of Q2", risks)


class TestExportReport(SessionCase):
    def test_report_is_self_contained_html(self):
        svg = "<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>"
        qs = [
            question("Q1", visuals=[{"id": "v1", "format": "svg", "content": svg}]),
            question("Q2", title="See https://example.com/doc for <b>why</b>"),
        ]
        self.session(
            qs, [event(1, "Q1", "accept"), event(2, None, "note", text="Ends mid")]
        )
        doc = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))
        doc["visuals"] = [
            {
                "id": "v2",
                "scope": "all",
                "title": "Flow",
                "kind": "mermaid",
                "content": "graph TD; A-->B",
            },
            {
                "id": "v3",
                "scope": "all",
                "title": "Page",
                "format": "html",
                "content": "<p>hi</p>",
            },
            {
                "id": "v4",
                "scope": "all",
                "title": "Doc",
                "format": "markdown",
                "file": "doc.md",
            },
        ]
        (self.dir / "questions.json").write_text(json.dumps(doc), encoding="utf-8")
        text = self.export("report").read_text(encoding="utf-8")

        class Walk(html.parser.HTMLParser):
            def __init__(self):
                super().__init__()
                self.tags, self.iframes = [], []

            def handle_starttag(self, tag, attrs):
                self.tags.append(tag)
                if tag == "iframe":
                    self.iframes.append(dict(attrs))

        w = Walk()
        w.feed(text)
        w.close()
        self.assertIn("table", w.tags)
        self.assertNotIn("script", w.tags)
        self.assertNotIn("link", w.tags)
        self.assertEqual(len(w.iframes), 2)
        for f in w.iframes:
            self.assertEqual(f.get("sandbox"), "")
            self.assertIn("srcdoc", f)
        for qid in ("Q1", "Q2"):
            self.assertIn(qid, text)
        self.assertIn("graph TD; A--&gt;B", text)
        self.assertIn("doc.md", text)
        self.assertNotIn("<b>why</b>", text)
        data = (self.dir / "questions.json").read_text(encoding="utf-8")
        for url in re.findall(r"https?://[^\s\"'<>&]+", text):
            self.assertIn(url, data)

    def test_report_head_carries_a_csp_with_no_network_source(self):
        svg = (
            "<svg xmlns='http://www.w3.org/2000/svg'>"
            "<image href='http://127.0.0.1:9/x.png' width='10' height='10'/></svg>"
        )
        page = "<img src='http://127.0.0.1:9/y.png'>"
        qs = [
            question(
                "Q1",
                visuals=[
                    {"id": "v1", "format": "svg", "content": svg},
                    {"id": "v2", "format": "html", "content": page},
                ],
            )
        ]
        self.session(qs, [event(1, "Q1", "accept")])
        text = self.export("report").read_text(encoding="utf-8")

        class Head(html.parser.HTMLParser):
            def __init__(self):
                super().__init__()
                self.in_head, self.csp, self.srcdocs = False, [], []

            def handle_starttag(self, tag, attrs):
                a = dict(attrs)
                if tag == "head":
                    self.in_head = True
                if (
                    tag == "meta"
                    and self.in_head
                    and (a.get("http-equiv") or "").lower() == "content-security-policy"
                ):
                    self.csp.append(a.get("content") or "")
                if tag == "iframe":
                    self.srcdocs.append(a.get("srcdoc"))

            def handle_endtag(self, tag):
                if tag == "head":
                    self.in_head = False

        h = Head()
        h.feed(text)
        h.close()
        self.assertEqual(len(h.csp), 1, text[:400])
        csp = h.csp[0]
        self.assertIn("default-src 'none'", csp)
        self.assertNotIn("http", csp.lower())
        self.assertEqual(h.srcdocs, [svg, page])


class TestReadableResolutions(SessionCase):
    """The Brief and the report show an escaped row's resolution unescaped, as plain text; the
    ledger keeps the escaped row, and it still imports."""

    def test_brief_and_report_show_escaped_rows_as_plain_text(self):
        seeded = {
            "Q7": {
                "status": "superseded-by-plan",
                "round": 1,
                "resolution": "plan proposes: new | one; was: old; two",
                "proposal": ["new | one", "old; two"],
            }
        }
        qs = [
            question("Q1", commits=["One | writer; only", "No\tnetwork"]),
            question("Q2"),
            question("Q3"),
            question("Q4"),
            question(
                "Q5",
                commits=["Keep | it", "Drop; it"],
                archived={"why": "Off.", "at": AT},
            ),
            question(
                "Q6",
                waiting=True,
                waitsOn="a | lookup; later",
                terminal={"decision": "accept", "text": "why; not", "updatedAt": AT},
            ),
            question("Q7"),
        ]
        events = [
            event(1, "Q1", "accept", text="only for v1; revisit later"),
            event(2, "Q1", "confirm", alt="0"),
            event(3, "Q2", "alt", alt="a", text="with a note"),
            event(4, "Q3", "own", text="Use A | B; not C"),
            event(5, "Q4", "defer", text="after the pilot"),
            event(6, "Q5", "confirm", alt="0"),
        ]
        self.session(
            qs, events, meta={"title": "Readable", "seededFrom": {"rows": seeded}}
        )
        plain = [
            "accepted: Recommended answer for Q1.; note: only for v1; revisit later; "
            "confirmed: One / writer; only",
            "alt a: Alt a of Q2; note: with a note",
            "free-text: Use A / B; not C",
            "deferred: after the pilot; arbiter: USER-RESERVED",
            "archived: Off.; confirmed: Keep / it",
            "waits on: a / lookup; later; answer: accepted: Recommended answer for Q6.; "
            "note: why; not",
            "plan proposes: new / one; was: old; two",
        ]
        brief = self.export("brief").read_text(encoding="utf-8")
        constraints = brief.split("### Constraints")[1].split("###")[0]
        for n, i in (("Q2", 1), ("Q3", 2)):
            self.assertIn(f"- {n} Short {n}: {plain[i]}\n", constraints)
        self.assertNotIn("Q1", constraints)
        scope = brief.split("### Out-of-scope")[1].split("###")[0]
        self.assertIn(f"- Q5 Question Q5?: {plain[4]}\n", scope)
        self.assertIn("- One / writer; only: confirmed on Q1;", brief)
        self.assertIn("- risk: No network (unconfirmed); from Q1\n", brief)
        report = self.export("report").read_text(encoding="utf-8")
        cells = [html.unescape(c) for c in re.findall(r"<td>([^<]*)</td></tr>", report)]
        self.assertEqual(cells, plain)
        for text in (brief, html.unescape(report)):
            self.assertNotIn("commitments::", text)
            self.assertNotIn("\\|", text)
        ledger = self.export("ledger")
        rows = register_rows(ledger)
        self.assertIn(
            "answer:: accepted: Recommended answer for Q1.; note:: only", rows[0]
        )
        self.assertTrue(
            rows[0].endswith("; commitments:: +One \\| writer\\; only; -No\\tnetwork"),
            rows[0],
        )
        self.assertTrue(
            rows[4].endswith("; commitments:: +Keep \\| it; -Drop\\; it"), rows[4]
        )
        self.assertIn("hold:: claude a \\| lookup\\; later", rows[5])
        self.assertIn("proposal:: new \\| one; was:: old\\; two", rows[6])
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)


class TestReportFileVisuals(SessionCase):
    SVG = "<svg xmlns='http://www.w3.org/2000/svg'><text>filemark</text></svg>"
    PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452")

    def report(self, *visuals):
        self.session(
            [question("Q1", visuals=list(visuals))], [event(1, "Q1", "accept")]
        )
        return self.export("report").read_text(encoding="utf-8")

    def test_archived_visuals_are_left_out(self):
        gone = {"why": "old", "at": "2026-01-01T00:00:00Z"}
        text = self.report(
            {"id": "v1", "format": "markdown", "content": "kept-body"},
            {
                "id": "v2",
                "format": "markdown",
                "content": "gone-body",
                "archived": gone,
            },
        )
        self.assertIn("kept-body", text)
        self.assertNotIn("gone-body", text)

    def iframes(self, text):
        class Walk(html.parser.HTMLParser):
            def __init__(self):
                super().__init__()
                self.found = []

            def handle_starttag(self, tag, attrs):
                if tag == "iframe":
                    self.found.append(dict(attrs))

        w = Walk()
        w.feed(text)
        w.close()
        return w.found

    def test_file_svg_is_inlined_into_a_sandboxed_srcdoc(self):
        (self.dir / "diagrams").mkdir()
        (self.dir / "diagrams" / "flow.svg").write_text(self.SVG, encoding="utf-8")
        text = self.report({"id": "v1", "format": "svg", "file": "diagrams/flow.svg"})
        frames = self.iframes(text)
        self.assertEqual(len(frames), 1)
        self.assertEqual(frames[0].get("sandbox"), "")
        self.assertEqual(frames[0].get("srcdoc"), self.SVG)
        self.assertIn("diagrams/flow.svg", text)

    def test_scripted_html_names_the_missing_javascript(self):
        scripted = "<div id=m></div><SCRIPT>m.textContent = 'x'</SCRIPT>"
        text = self.report(
            {"id": "v1", "format": "html", "content": scripted},
            {"id": "v2", "format": "html", "content": "<p>static</p>"},
        )
        frames = self.iframes(text)
        self.assertEqual([f.get("sandbox") for f in frames], ["", ""])
        self.assertEqual(frames[0].get("srcdoc"), scripted)
        self.assertEqual(text.count("This visual needs JavaScript"), 1)
        self.assertLess(
            text.index("This visual needs JavaScript"), text.index("<iframe")
        )

    def test_file_image_becomes_a_data_url(self):
        (self.dir / "flow.png").write_bytes(self.PNG)
        text = self.report({"id": "v1", "format": "image", "file": "flow.png"})
        url = "data:image/png;base64," + base64.b64encode(self.PNG).decode("ascii")
        self.assertIn(f'src="{url}"', text)

    def test_file_outside_the_data_dir_keeps_the_path_line(self):
        (self.tmp / "x.svg").write_text(self.SVG, encoding="utf-8")
        text = self.report({"id": "v1", "format": "svg", "file": "../x.svg"})
        self.assertEqual(self.iframes(text), [])
        self.assertNotIn("filemark", text)
        self.assertIn("<code>../x.svg</code>", text)

    def test_missing_file_keeps_the_path_line(self):
        text = self.report({"id": "v1", "format": "svg", "file": "missing.svg"})
        self.assertEqual(self.iframes(text), [])
        self.assertIn("<code>missing.svg</code>", text)


class TestImportLedger(SessionCase):
    """AC29: import-ledger then export-ledger round-trips with no decision lost."""

    def test_round_trip(self):
        qs = [
            question("J1", commits=["Kept"]),
            question("J2"),
            question("J3"),
            question("J4"),
            question("J5", archived={"why": "Pruned.", "at": AT}),
            question("K1"),
        ]
        events = [
            event(1, "J1", "accept", text="fine"),
            event(2, "J1", "confirm", alt="0"),
            event(3, "J2", "alt", alt="b"),
            event(4, "J3", "own", text="Own | words"),
            event(5, "J4", "defer", text="later"),
        ]
        self.session(qs, events)
        first = self.export("ledger")
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
        self.assertEqual(rc, 0, out)
        second = self.export("ledger", d=fresh)
        self.assertEqual(register_rows(first), register_rows(second))
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        doc = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
        self.assertIn("seededFrom", doc["meta"])
        j1 = next(q for q in doc["questions"] if q["id"] == "J1")
        self.assertEqual(j1["terminal"]["decision"], "accept")
        self.assertEqual(j1["history"][-1]["by"], "user-terminal")
        self.assertIn("Seeded from ledger", j1["history"][-1]["text"])
        k1 = next(q for q in doc["questions"] if q["id"] == "K1")
        self.assertNotIn("terminal", k1)
        self.assertEqual(
            next(q for q in doc["questions"] if q["id"] == "J5")["archived"]["why"],
            "Pruned.",
        )

    def test_a_user_hold_reopens_an_imported_answer_even_after_it_clears(self):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | answered | round 1 | Who reads? | accepted: everyone\n"
            "- Q2 | answered | round 1 | Who writes? | accepted: admins\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        ops = self.tmp / "ops.json"
        for op in (
            {"op": "wait", "id": "Q2", "by": "user", "waitsOn": "who really writes"},
            {"op": "wait", "id": "Q2", "clear": True},
        ):
            ops.write_text(json.dumps({"ops": [op]}), encoding="utf-8")
            rc, out = self.rp("apply", "--file", str(ops))
            self.assertEqual(rc, 0, out)
            ledger = self.export("ledger")
            rows = register_rows(ledger)
            self.assertTrue(rows[1].startswith("- Q2 | open |"), rows)
            self.assertTrue(rows[0].startswith("- Q1 | answered |"), rows)
            rc, out = self.check("--ledger", ledger)
            self.assertEqual(rc, 1, out)
            self.assertIn("open=1", out)

    def apply(self, *ops, d=None):
        path = self.tmp / "ops.json"
        path.write_text(json.dumps({"ops": list(ops)}), encoding="utf-8")
        rc, out = self.rp("apply", "--file", str(path), d=d)
        self.assertEqual(rc, 0, out)

    def test_a_held_row_round_trips_with_its_hold_and_the_answer_it_keeps(self):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | answered | round 1 | Who reads? | accepted: everyone\n"
            "- Q2 | open | round 1 | Who writes? |\n"
            "- Q3 | open | round 1 | Retention? |\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        self.apply(
            {"op": "wait", "id": "Q1", "waitsOn": "the benchmark"},
            {"op": "wait", "id": "Q2", "waitsOn": "a lookup of the owners"},
            {"op": "wait", "id": "Q3", "by": "user", "waitsOn": "your call"},
        )
        first = self.export("ledger")
        rows = register_rows(first)
        self.assertEqual(
            rows,
            [
                "- Q1 | open | round 1 | Who reads? | hold:: claude the benchmark; answer:: accepted: everyone",
                "- Q2 | open | round 1 | Who writes? | hold:: claude a lookup of the owners",
                "- Q3 | open | round 1 | Retention? | hold:: user your call",
            ],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        qs = {
            q["id"]: q
            for q in json.loads((fresh / "questions.json").read_text(encoding="utf-8"))[
                "questions"
            ]
        }
        self.assertEqual(
            (qs["Q1"]["waitsOn"], qs["Q1"]["terminal"]["decision"]),
            ("the benchmark", "accept"),
        )
        self.assertEqual(qs["Q3"]["waitingBy"], "user")
        self.apply(
            {"op": "wait", "id": "Q1", "clear": True},
            {"op": "wait", "id": "Q2", "clear": True},
            d=fresh,
        )
        self.assertEqual(
            register_rows(self.export("ledger", d=fresh))[:2],
            [
                "- Q1 | answered | round 1 | Who reads? | answer:: accepted: everyone",
                "- Q2 | open | round 1 | Who writes? |",
            ],
        )

    def test_a_hold_text_with_the_row_delimiters_round_trips_escaped(self):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | answered | round 1 | Who reads? | accepted: everyone\n"
            "- Q2 | open | round 1 | Who writes? |\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        path = self.tmp / "ops.json"
        path.write_text(
            json.dumps(
                {
                    "ops": [
                        {
                            "op": "wait",
                            "id": "Q2",
                            "waitsOn": "vendor quote; answer: pending",
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        rc, out = self.rp("apply", "--file", str(path))
        self.assertEqual(rc, 0, out)
        self.apply(
            {"op": "wait", "id": "Q1", "waitsOn": "vendor quote; answer: pending"}
        )
        rows = register_rows(self.export("ledger"))
        self.assertEqual(
            rows,
            [
                "- Q1 | open | round 1 | Who reads? | hold:: claude vendor quote\\; answer: pending; answer:: accepted: everyone",
                "- Q2 | open | round 1 | Who writes? | hold:: claude vendor quote\\; answer: pending",
            ],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp(
            "import-ledger", "--ledger", str(self.export("ledger")), d=fresh
        )
        self.assertEqual(rc, 0, out)
        qs = {
            q["id"]: q
            for q in json.loads((fresh / "questions.json").read_text(encoding="utf-8"))[
                "questions"
            ]
        }
        self.assertEqual(
            [qs[i].get("waitsOn") for i in ("Q1", "Q2")],
            ["vendor quote; answer: pending"] * 2,
        )
        self.assertNotIn("terminal", qs["Q2"])
        self.apply(
            {"op": "wait", "id": "Q1", "clear": True},
            {"op": "wait", "id": "Q2", "clear": True},
            d=fresh,
        )
        self.assertEqual(
            register_rows(self.export("ledger", d=fresh)),
            [
                "- Q1 | answered | round 1 | Who reads? | answer:: accepted: everyone",
                "- Q2 | open | round 1 | Who writes? |",
            ],
        )

    def test_a_held_row_keeps_its_confirmed_commitments_apart_from_its_hold(self):
        self.session([question("Q1", commits=["One writer only", "No network"])], [])
        self.apply(
            {"op": "wait", "id": "Q1", "waitsOn": "the benchmark"},
            {
                "op": "confirm-commitments",
                "id": "Q1",
                "indices": [0],
                "reason": "said in chat",
            },
        )
        rows = register_rows(self.export("ledger"))
        self.assertEqual(
            rows,
            [
                "- Q1 | open | round 1 | Question Q1? | hold:: claude the benchmark; commitments:: +One writer only; -No network"
            ],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp(
            "import-ledger", "--ledger", str(self.export("ledger")), d=fresh
        )
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        [q] = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))[
            "questions"
        ]
        self.assertEqual(q["waitsOn"], "the benchmark")
        self.assertEqual(
            exporters.commitments(q, []), (["One writer only"], ["No network"])
        )
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        self.apply({"op": "wait", "id": "Q1", "clear": True}, d=fresh)
        self.assertEqual(
            register_rows(self.export("ledger", d=fresh)),
            [
                "- Q1 | open | round 1 | Question Q1? | "
                "commitments:: +One writer only; -No network"
            ],
        )

    def test_a_legacy_held_row_is_read_without_unescaping(self):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | open | round 1 | Where? | waits on: C:\\new\\tmp; answer: accepted: yes\n"
            "- Q2 | open | round 1 | Who? | awaiting user: a\\;b; confirmed: One; Two\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        qs = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))[
            "questions"
        ]
        self.assertEqual(qs[0]["waitsOn"], "C:\\new\\tmp")
        self.assertEqual(qs[0]["terminal"]["decision"], "accept")
        self.assertEqual((qs[1]["waitsOn"], qs[1]["waitingBy"]), ("a\\;b", "user"))
        self.assertEqual(qs[1]["commits"], ["One", "Two"])
        self.assertEqual(
            register_rows(self.export("ledger")),
            [
                "- Q1 | open | round 1 | Where? | hold:: claude C:\\\\new\\\\tmp; answer:: accepted: yes",
                "- Q2 | open | round 1 | Who? | hold:: user a\\\\\\;b; commitments:: +One; +Two",
            ],
        )

    def test_an_escaped_row_keeps_an_unknown_escape_literal(self):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | open | round 1 | Where? | waits on:: a\\qb\\;c\\u2028d\\zz; confirmed: \n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        [q] = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))[
            "questions"
        ]
        self.assertEqual(q["waitsOn"], "a\\qb;c\u2028d\\zz")
        self.assertEqual(q["commits"], [""])

    def test_a_confirmed_row_with_a_leading_separator_still_imports(self):
        rows = [
            "- Q1 | open | round 1 | Where? | ; confirmed: One",
            "- Q2 | open | round 1 | Who? | confirmed: A; C",
        ]
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            + "\n".join(rows)
            + "\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        self.assertEqual(
            register_rows(self.export("ledger")),
            [
                "- Q1 | open | round 1 | Where? | commitments:: +One",
                "- Q2 | open | round 1 | Who? | commitments:: +A; +C",
            ],
        )
        qs = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))[
            "questions"
        ]
        self.assertEqual(
            [exporters.commitments(q, []) for q in qs],
            [(["One"], []), (["A", "C"], [])],
        )

    def test_an_open_row_round_trips_its_confirmed_commitments(self):
        self.session([question("Q1", commits=["A; b", "C|d  e\\", "Unticked"])], [])
        self.apply(
            {
                "op": "confirm-commitments",
                "id": "Q1",
                "indices": [0, 1],
                "reason": "chat",
            }
        )
        rows = register_rows(self.export("ledger"))
        self.assertEqual(
            rows,
            [
                "- Q1 | open | round 1 | Question Q1? | "
                "commitments:: +A\\; b; +C\\|d  e\\\\; -Unticked"
            ],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp(
            "import-ledger", "--ledger", str(self.export("ledger")), d=fresh
        )
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        doc = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
        [q] = doc["questions"]
        self.assertEqual(
            exporters.commitments(q, []), (["A; b", "C|d  e\\"], ["Unticked"])
        )
        self.assertNotIn("Q1", doc["meta"]["seededFrom"]["rows"])
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)

    def test_an_escaped_confirmed_row_keeps_empty_commitments(self):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | open | round 1 | One? | confirmed::\n"
            "- Q2 | open | round 1 | Two? | confirmed:: A;\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        qs = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))[
            "questions"
        ]
        self.assertEqual([q["commits"] for q in qs], [[""], ["A", ""]])

    def test_an_answered_row_round_trips_its_confirmed_commitments(self):
        commits = ["A; b", "confirmed::", "confirmed:: x", "", "Unticked"]
        ticked = [{"index": i, "reason": "chat", "at": AT} for i in range(4)]
        terminals = [
            {"decision": "accept", "text": "fine; really"},
            {"decision": "alt", "alt": "a", "text": "a note"},
            {"decision": "own", "text": "mine"},
            {"decision": "defer", "text": "later"},
        ]
        qs = [
            question(
                f"Q{i}",
                commits=commits,
                commitsConfirmed=ticked,
                terminal=dict(t, updatedAt=AT),
            )
            for i, t in enumerate(terminals, 1)
        ]
        # A head that reads like the tail, with no commitment and with only an empty one.
        own = {"decision": "own", "updatedAt": AT}
        qs += [
            question("Q5", terminal=dict(own, text="mine; confirmed:: y")),
            question("Q6", terminal=dict(own, text="mine; confirmed::")),
            question(
                "Q7",
                commits=[""],
                commitsConfirmed=ticked[:1],
                terminal=dict(own, text="mine; confirmed::"),
            ),
            question("Q8", archived={"why": "Pruned.", "at": AT}, commits=["A; b"]),
        ]
        qs[-1]["commitsConfirmed"] = ticked[:1]
        self.session(qs, [])
        rows = register_rows(self.export("ledger"))
        tail = "; commitments:: +A\\; b; +confirmed::; +confirmed:: x; +; -Unticked"
        self.assertEqual(
            rows,
            [
                "- Q1 | open | round 1 | Question Q1? | answer:: accepted: Recommended "
                "answer for Q1.; note:: fine\\; really" + tail,
                "- Q2 | answered | round 1 | Question Q2? | answer:: alt a: Alt a of Q2; "
                "note:: a note" + tail,
                "- Q3 | answered | round 1 | Question Q3? | answer:: free-text: mine"
                + tail,
                "- Q4 | deferred | round 1 | Question Q4? | answer:: deferred: later"
                + tail,
                "- Q5 | answered | round 1 | Question Q5? | answer:: free-text: mine\\; "
                "confirmed:: y",
                "- Q6 | answered | round 1 | Question Q6? | answer:: free-text: mine\\; "
                "confirmed::",
                "- Q7 | answered | round 1 | Question Q7? | answer:: free-text: mine\\; "
                "confirmed::; commitments:: +",
                "- Q8 | withdrawn | round 1 | Question Q8? | answer:: archived: Pruned.; "
                "commitments:: +A\\; b",
            ],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp(
            "import-ledger", "--ledger", str(self.export("ledger")), d=fresh
        )
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        got = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
        confirmed = commits[:4]
        self.assertEqual(
            [exporters.commitments(q, [])[0] for q in got["questions"]],
            [confirmed] * 4 + [[], [], [""], ["A; b"]],
        )
        self.assertEqual(
            [q["terminal"]["text"] for q in got["questions"][4:7]],
            ["mine; confirmed:: y", "mine; confirmed::", "mine; confirmed::"],
        )

    def test_an_unheld_answer_round_trips_its_text_and_note(self):
        terminals = [
            {"decision": "accept", "text": "keep it; short"},
            {"decision": "alt", "alt": "a", "text": "a | note"},
            {"decision": "own", "text": "two  spaces\nand | a pipe"},
            {"decision": "defer", "text": "after the audit; maybe"},
            {"decision": "accept"},
            {"decision": "own", "text": "plain words"},
        ]
        qs = [
            question(f"Q{i}", terminal=dict(t, updatedAt=AT))
            for i, t in enumerate(terminals, 1)
        ]
        self.session(qs, [])
        first = self.export("ledger")
        rows = register_rows(first)
        self.assertEqual(
            rows,
            [
                "- Q1 | answered | round 1 | Question Q1? | answer:: accepted: Recommended "
                "answer for Q1.; note:: keep it\\; short",
                "- Q2 | answered | round 1 | Question Q2? | answer:: alt a: Alt a of Q2; "
                "note:: a \\| note",
                "- Q3 | answered | round 1 | Question Q3? | answer:: free-text: two  "
                "spaces\\nand \\| a pipe",
                "- Q4 | deferred | round 1 | Question Q4? | answer:: deferred: after the "
                "audit\\; maybe",
                "- Q5 | answered | round 1 | Question Q5? | answer:: accepted: Recommended "
                "answer for Q5.",
                "- Q6 | answered | round 1 | Question Q6? | answer:: free-text: plain words",
            ],
        )
        rc, out = self.check("--ledger", first)
        self.assertIn("deferred=1 blocked=0 withdrawn=0 answered=5", out)
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        self.assertEqual(load_state(fresh), load_state(self.dir))

    def test_a_hedged_answer_exports_its_condition_and_round_trips(self):
        qs = [
            question("Q1", commits=["Runs weekly"]),
            question(
                "Q2",
                terminal={
                    "decision": "hedged",
                    "text": "if a; b holds",
                    "updatedAt": AT,
                },
            ),
            question("Q3"),
        ]
        ev = [event(1, "Q1", "hedged", text="only if the lock is cheap")]
        ev.append(event(2, "Q3", "accept", text="fine"))
        self.session(qs, ev)
        first = self.export("ledger")
        rows = register_rows(first)
        self.assertEqual(
            rows,
            [
                "- Q1 | open | round 1 | Question Q1? | answer:: hedged: Recommended "
                "answer for Q1.; note:: only if the lock is cheap; commitments:: -Runs weekly",
                "- Q2 | answered | round 1 | Question Q2? | answer:: hedged: Recommended "
                "answer for Q2.; note:: if a\\; b holds",
                "- Q3 | answered | round 1 | Question Q3? | answer:: accepted: Recommended "
                "answer for Q3.; note:: fine",
            ],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        got = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
        self.assertEqual(
            [
                (q["terminal"]["decision"], q["terminal"]["text"])
                for q in got["questions"]
            ],
            [
                ("hedged", "only if the lock is cheap"),
                ("hedged", "if a; b holds"),
                ("accept", "fine"),
            ],
        )

    def test_a_hedged_row_lists_its_condition_in_the_brief(self):
        self.session(
            [question("Q1")], [event(1, "Q1", "hedged", text="only if it is cheap")]
        )
        brief = self.export("brief").read_text(encoding="utf-8")
        self.assertIn(
            "- Q1 Short Q1: hedged: Recommended answer for Q1.; note: only if it is cheap",
            brief,
        )
        self.assertIn("1 answered", brief)

    def test_a_held_hedged_answer_keeps_its_condition_and_round_trips(self):
        self.session(
            [question("Q1", waiting=True, waitsOn="the lookup")],
            [event(1, "Q1", "hedged", text="only if it is cheap")],
        )
        first = self.export("ledger")
        rows = register_rows(first)
        self.assertIn(
            "hold:: claude the lookup; answer:: hedged: Recommended answer for Q1.; "
            "note:: only if it is cheap",
            rows[0],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)

    def test_a_hedged_answer_with_no_condition_is_refused_on_import(self):
        ledger = self.tmp / "hedged.md"
        ledger.write_text(
            "## Open-question register\n\n"
            "- Q1 | answered | round 1 | T? | answer:: hedged: Do it\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertNotEqual(rc, 0)
        self.assertIn("hedged answer with no condition", out)

    def test_the_legacy_free_text_hedge_still_imports_as_own(self):
        ledger = self.tmp / "legacy.md"
        ledger.write_text(
            "## Open-question register\n\n"
            "- Q1 | answered | round 1 | T? | answer:: free-text: hedged: Do it if cheap\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        got = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))
        terminal = got["questions"][0]["terminal"]
        self.assertEqual(
            (terminal["decision"], terminal["text"]), ("own", "hedged: Do it if cheap")
        )

    def test_an_escaped_answer_that_contradicts_its_row_is_refused(self):
        for i, row in enumerate(
            [
                "answered | round 1 | Who? | answer:: deferred: later",
                "deferred | round 1 | Who? | answer:: accepted: x; arbiter: USER-RESERVED",
                "deferred | round 1 | Who? | answer:: deferred: later; note:: x",
                "answered | round 1 | Who? | answer:: free-text: x; arbiter: USER-RESERVED",
                "answered | round 1 | Who? | answer:: accepted: x; why: y",
            ]
        ):
            with self.subTest(row=row):
                d = self.tmp / f"bad-{i}"
                d.mkdir()
                ledger = self.tmp / f"bad-{i}.md"
                ledger.write_text(
                    "# Interview ledger\n\n## Open-question register\n\n"
                    f"- Q1 | {row}\n",
                    encoding="utf-8",
                )
                rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=d)
                self.assertNotEqual(rc, 0, out)
                self.assertIn("refused", out)

    def test_a_named_row_with_an_unknown_or_contradictory_field_is_refused(self):
        for i, (row, error) in enumerate(
            [
                (
                    "open | round 1 | Who? | hold:: claude x; arbiter:: y",
                    "unknown field 'arbiter'",
                ),
                (
                    "open | round 1 | Who? | hld:: claude vendor; commitments:: +One",
                    "unknown field 'hld'",
                ),
                (
                    "open | round 1 | Who? | Hold:: claude x; commitments:: +One",
                    "unknown field 'Hold'",
                ),
                (
                    "open | round 1 | Who? | hld2:: claude x; commitments:: +One",
                    "unknown field 'hld2'",
                ),
                (
                    "open | round 1 | Who? | 2fa:: claude x; commitments:: +One",
                    "unknown field '2fa'",
                ),
                (
                    "open | round 1 | Who? | _hold:: claude x; commitments:: +One",
                    "unknown field '_hold'",
                ),
                (
                    "answered | round 1 | Who? | answer:: accepted: x; aside:: accepted: y",
                    "contradictory fields 'answer' and 'aside'",
                ),
                (
                    "superseded-by-plan | round 1 | Who? | proposal:: x",
                    "contradictory fields 'proposal' and 'was'",
                ),
                (
                    "answered | round 1 | Who? | answer:: accepted: x; note:: a; note:: b",
                    "field 'note' repeated or out of order",
                ),
                (
                    "answered | round 1 | Who? | note:: a; answer:: accepted: x",
                    "field 'answer' repeated or out of order",
                ),
                (
                    "open | round 1 | Who? | commitments:: +A; B",
                    "unmarked commitment 'B' in field 'commitments'",
                ),
                (
                    "answered | round 1 | Who? | answer:: maybe",
                    "unreadable field 'answer' 'maybe'",
                ),
                (
                    "open | round 1 | Who? | hold:: someone x",
                    "unreadable field 'hold' 'someone x'",
                ),
                (
                    "answered | round 1 | Who? | hold:: claude x; answer:: accepted: y",
                    "contradictory fields 'hold' and 'status answered'",
                ),
                (
                    "open | round 1 | Who? | aside:: accepted: y",
                    "contradictory fields 'aside' and 'hold'",
                ),
                (
                    "answered | round 1 | Who? | answer:: deferred: later",
                    "contradictory fields 'answer' and 'status answered'",
                ),
                (
                    "open | round 1 | Who? | proposal:: x; was:: y",
                    "contradictory fields 'proposal' and 'status open'",
                ),
                (
                    "withdrawn | round 1 | Who? | answer:: archived: x; note:: y",
                    "contradictory fields 'answer' and 'note'",
                ),
                (
                    "open | round 1 | Who? | answer:: free-text: x; commitments:: -One",
                    "contradictory fields 'answer' and 'status open'",
                ),
            ]
        ):
            with self.subTest(row=row):
                d = self.tmp / f"named-{i}"
                d.mkdir()
                ledger = self.tmp / f"named-{i}.md"
                ledger.write_text(
                    "# Interview ledger\n\n## Open-question register\n\n"
                    f"- Q1 | {row}\n",
                    encoding="utf-8",
                )
                rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=d)
                self.assertNotEqual(rc, 0, out)
                self.assertIn(f"refused: {error}", out)

    def test_a_legacy_answered_row_keeps_its_confirmed_text(self):
        rows = [
            "- Q1 | answered | round 1 | Who? | free-text: mine; confirmed: A; b",
            "- Q2 | deferred | round 1 | When? | deferred; arbiter: USER-RESERVED; confirmed: C",
        ]
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            + "\n".join(rows)
            + "\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        qs = json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))[
            "questions"
        ]
        self.assertEqual(qs[0]["terminal"]["text"], "mine; confirmed: A; b")
        self.assertEqual([q["commits"] for q in qs], [[], []])
        self.assertEqual(
            register_rows(self.export("ledger")),
            [
                "- Q1 | answered | round 1 | Who? | answer:: free-text: mine\\; "
                "confirmed: A\\; b",
                "- Q2 | deferred | round 1 | When? | answer:: deferred; note:: "
                "deferred\\; arbiter: USER-RESERVED\\; confirmed: C",
            ],
        )

    def test_a_set_aside_answer_round_trips_as_context(self):
        self.session([question("Q1")], [])
        self.apply(
            {
                "op": "record-terminal",
                "id": "Q1",
                "decision": "accept",
                "text": "keep it; short",
            }
        )
        self.apply({"op": "wait", "id": "Q1", "by": "user", "waitsOn": "your call"})
        rows = register_rows(self.export("ledger"))
        self.assertEqual(
            rows,
            [
                "- Q1 | open | round 1 | Question Q1? | hold:: user your call; "
                "note:: keep it\\; short; aside:: accepted: Recommended answer for Q1."
            ],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp(
            "import-ledger", "--ledger", str(self.export("ledger")), d=fresh
        )
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        path = fresh / "questions.json"
        [q] = json.loads(path.read_text(encoding="utf-8"))["questions"]
        self.assertEqual(
            (q["terminal"]["decision"], q["terminal"]["text"]),
            ("accept", "keep it; short"),
        )
        self.assertIsNone(exporters.latest_decision(q, {}))
        self.apply(
            {"op": "record-terminal", "id": "Q1", "decision": "own", "text": "mine"},
            d=fresh,
        )
        [q] = json.loads(path.read_text(encoding="utf-8"))["questions"]
        self.assertEqual(exporters.latest_decision(q, {})["decision"], "own")

    def test_a_held_row_with_an_answer_and_an_aside_is_refused(self):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | open | round 1 | Where? | awaiting user:: x; answer: deferred; aside: deferred\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertNotEqual(rc, 0, out)
        self.assertIn("refused", out)

    def test_import_refuses_a_dir_with_questions(self):
        self.decided()
        ledger = self.export("ledger")
        rc, _ = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 1)


class TestSupersededByPlan(SessionCase):
    """AC10: the non-terminal superseded-by-plan status round-trips through the page."""

    RES = "plan proposes: admin only; was: any enrolled user"
    ROW = "proposal:: admin only; was:: any enrolled user"
    FIELDS = {"proposal": "admin only", "was": "any enrolled user", "note": None}
    # After the import's own stamp, so a page answer given after a re-import counts.
    AFTER = "2999-01-01T00:00:00Z"

    def seed(self, res=RES):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | answered | round 1 | Who reads? | accepted: everyone\n"
            f"- Q2 | Superseded-By-Plan | round 1 | Who writes? | {res}\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        return json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))

    def test_import_seeds_it_as_an_open_question(self):
        doc = self.seed()
        q2 = next(q for q in doc["questions"] if q["id"] == "Q2")
        self.assertNotIn("terminal", q2)
        self.assertNotIn("archived", q2)
        self.assertEqual(q2["history"][-1]["by"], "claude")
        self.assertIn(self.RES, q2["history"][-1]["text"])
        row = doc["meta"]["seededFrom"]["rows"]["Q2"]
        self.assertEqual(row["status"], "superseded-by-plan")
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)

    def test_settle_keeps_an_untouched_superseded_seed(self):
        seed = {"Q2": {"status": "superseded-by-plan", "resolution": self.RES}}
        q = question("Q2")
        self.assertEqual(
            exporters.settle(q, {}, [], seed),
            ("superseded-by-plan", self.FIELDS, "", False),
        )
        page = {"Q2": {"decision": "accept", "updatedAt": AT}}
        self.assertEqual(exporters.settle(q, page, [], seed)[0], "answered")

    def test_a_held_proposal_with_a_newline_or_was_round_trips(self):
        esc = exporters.esc_field
        for i, new in enumerate(["nl\nx", "x; was: y"]):
            with self.subTest(new=new):
                d = self.tmp / f"held-{i}"
                d.mkdir()
                head = "- Q1 | superseded-by-plan | round 1 | Which? | "
                row = (
                    f"{head}plan proposes: {esc(new)}; "
                    f"was: {esc(new + ' old')}; awaiting user:: bench"
                )
                ledger = self.tmp / f"held-{i}.md"
                ledger.write_text(
                    "# Interview ledger\n\n## Open-question register\n\n" + row + "\n",
                    encoding="utf-8",
                )
                rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=d)
                self.assertEqual(rc, 0, out)
                first = self.export("ledger", d=d)
                self.assertEqual(
                    register_rows(first),
                    [
                        f"{head}hold:: user bench; proposal:: {esc(new)}; "
                        f"was:: {esc(new + ' old')}"
                    ],
                )
                rc, out = self.check("--ledger", first)
                self.assertIn("superseded=1", out)
                [q] = json.loads((d / "questions.json").read_text(encoding="utf-8"))[
                    "questions"
                ]
                self.assertEqual(q["recommendation"], new)

    def test_a_cleared_hold_keeps_the_escaped_proposal(self):
        esc = exporters.esc_field
        for i, new in enumerate(["nl\nx", "x; was: y", "a | b", " lead", "plain"]):
            with self.subTest(new=new):
                old = new + " old"
                d, fresh = self.tmp / f"cleared-{i}", self.tmp / f"cleared-re-{i}"
                d.mkdir()
                fresh.mkdir()
                ledger = self.tmp / f"cleared-{i}.md"
                ledger.write_text(
                    "# Interview ledger\n\n## Open-question register\n\n"
                    f"- Q1 | superseded-by-plan | round 1 | Which? | plan proposes: {esc(new)}; "
                    f"was: {esc(old)}; awaiting user:: bench\n",
                    encoding="utf-8",
                )
                rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=d)
                self.assertEqual(rc, 0, out)
                ops = self.tmp / f"clear-{i}.json"
                ops.write_text(
                    json.dumps({"ops": [{"op": "wait", "id": "Q1", "clear": True}]}),
                    encoding="utf-8",
                )
                rc, out = self.rp("apply", "--file", str(ops), d=d)
                self.assertEqual(rc, 0, out)
                first = self.export("ledger", d=d)
                res = f"proposal:: {esc(new)}; was:: {esc(old)}"
                rows = [f"- Q1 | superseded-by-plan | round 1 | Which? | {res}"]
                self.assertEqual(register_rows(first), rows)
                rc, out = self.check("--ledger", first)
                self.assertIn("superseded=1", out)
                rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
                self.assertEqual(rc, 0, out)
                doc = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
                seed = doc["meta"]["seededFrom"]["rows"]["Q1"]
                self.assertEqual(exporters.seed_proposal(seed), (new, old))
                self.assertEqual(doc["questions"][0]["recommendation"], new)
                self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)

    def test_an_unreadable_escaped_proposal_is_refused(self):
        for i, res in enumerate(
            ["plan proposes:: x; y", "plan proposes:: x; was: y; z"]
        ):
            with self.subTest(res=res):
                d = self.tmp / f"bad-{i}"
                d.mkdir()
                ledger = self.tmp / f"bad-{i}.md"
                ledger.write_text(
                    "# Interview ledger\n\n## Open-question register\n\n"
                    f"- Q1 | superseded-by-plan | round 1 | Which? | {res}\n",
                    encoding="utf-8",
                )
                rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=d)
                self.assertNotEqual(rc, 0, out)
                self.assertIn("refused", out)

    def test_a_cleared_hold_keeps_the_confirmed_commitments_with_the_proposal(self):
        ledger = self.tmp / "held.md"
        ledger.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            "- Q1 | superseded-by-plan | round 1 | Which? | plan proposes: admin only; "
            "was: any enrolled user; awaiting user:: bench; confirmed: A\\; b; C\n",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        ops = self.tmp / "clear.json"
        ops.write_text(
            json.dumps({"ops": [{"op": "wait", "id": "Q1", "clear": True}]}),
            encoding="utf-8",
        )
        rc, out = self.rp("apply", "--file", str(ops))
        self.assertEqual(rc, 0, out)
        first = self.export("ledger")
        rows = [
            f"- Q1 | superseded-by-plan | round 1 | Which? | {self.ROW}; "
            "commitments:: +A\\; b; +C"
        ]
        self.assertEqual(register_rows(first), rows)
        rc, out = self.check("--ledger", first)
        self.assertIn("superseded=1", out)
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        doc = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
        [q] = doc["questions"]
        self.assertEqual(exporters.commitments(q, []), (["A; b", "C"], []))
        self.assertEqual(
            exporters.seed_proposal(doc["meta"]["seededFrom"]["rows"]["Q1"]),
            ("admin only", "any enrolled user"),
        )
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        # An accept reconfirms the proposal and keeps the commitments on the answered row.
        ops.write_text(
            json.dumps(
                {"ops": [{"op": "record-terminal", "id": "Q1", "decision": "accept"}]}
            ),
            encoding="utf-8",
        )
        rc, out = self.rp("apply", "--file", str(ops), d=fresh)
        self.assertEqual(rc, 0, out)
        second = self.export("ledger", d=fresh)
        rows = [
            f"- Q1 | answered | round 1 | Which? | {self.ROW}; "
            "answer:: accepted: admin only; commitments:: +A\\; b; +C"
        ]
        self.assertEqual(register_rows(second), rows)
        again = self.tmp / "again"
        again.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(second), d=again)
        self.assertEqual(rc, 0, out)
        [q] = json.loads((again / "questions.json").read_text(encoding="utf-8"))[
            "questions"
        ]
        self.assertEqual(exporters.commitments(q, []), (["A; b", "C"], []))
        self.assertEqual(register_rows(self.export("ledger", d=again)), rows)

    def test_ledger_leaves_it_unticked_and_the_gate_blocks(self):
        self.seed()
        ledger = self.export("ledger")
        text = ledger.read_text(encoding="utf-8")
        self.assertIn("- [x] Q1 ", text)
        self.assertIn("- [ ] Q2 ", text)
        self.assertIn(
            f"- Q2 | superseded-by-plan | round 1 | Who writes? | {self.ROW}", text
        )
        rc, out = self.check("--ledger", ledger)
        self.assertEqual(rc, 1, out)
        self.assertIn("superseded=1", out)
        self.assertIn("status=open", out)

    def test_a_cleared_user_hold_keeps_the_proposal(self):
        self.seed()
        ops = self.tmp / "ops.json"
        ops.write_text(
            json.dumps(
                {
                    "ops": [
                        {"op": "wait", "id": "Q2", "by": "user", "waitsOn": "x"},
                        {"op": "wait", "id": "Q2", "clear": True},
                    ]
                }
            ),
            encoding="utf-8",
        )
        rc, out = self.rp("apply", "--file", str(ops))
        self.assertEqual(rc, 0, out)
        text = self.export("ledger").read_text(encoding="utf-8")
        self.assertIn(
            f"- Q2 | superseded-by-plan | round 1 | Who writes? | {self.ROW}", text
        )

    def test_brief_tldr_counts_it(self):
        self.seed()
        text = self.export("brief").read_text(encoding="utf-8")
        tldr = text.split("### TLDR")[1].split("###")[0]
        self.assertIn("1 answered", tldr)
        self.assertIn(", 1 superseded-by-plan", tldr)

    def test_report_lists_it_as_a_loose_end(self):
        self.seed()
        text = self.export("report").read_text(encoding="utf-8")
        ends = text.split("<h2>Loose ends</h2>")[1].split("</ul>")[0]
        self.assertIn("Q2 (Q2) is superseded-by-plan", ends)
        self.assertNotIn("Q1 (Q1)", ends)

    def respond(self, events, d=None):
        d = d or self.dir
        responses, history = rebuild_responses(events)
        (d / "responses.json").write_text(
            json.dumps(
                {
                    "seq": len(events),
                    "events": events,
                    "responses": responses,
                    "history": history,
                }
            ),
            encoding="utf-8",
        )
        return register_rows(self.export("ledger", d=d))

    def reimport(self, events):
        """Answer the seeded page, export its ledger, and import that ledger into a fresh dir."""
        self.respond(events)
        fresh = Path(tempfile.mkdtemp(dir=self.tmp, prefix="fresh-"))
        ledger = self.export("ledger")
        rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=fresh)
        self.assertEqual(rc, 0, out)
        return fresh

    def after(self, *args, **kw):
        return dict(event(*args, **kw), at=self.AFTER)

    def test_alt_was_after_a_reimported_defer_restores_the_prior_answer(self):
        self.seed()
        fresh = self.reimport([event(1, "Q2", "defer", text="ask later")])
        rows = self.respond([self.after(1, "Q2", "alt", alt="was")], d=fresh)
        self.assertEqual(
            rows[1],
            f"- Q2 | answered | round 1 | Who writes? | {self.ROW}; "
            "answer:: alt was: any enrolled user",
        )

    def test_accept_after_a_reimported_defer_reconfirms_the_proposal(self):
        self.seed()
        fresh = self.reimport([event(1, "Q2", "defer", text="ask later")])
        rows = self.respond([self.after(1, "Q2", "accept")], d=fresh)
        self.assertEqual(
            rows[1],
            f"- Q2 | answered | round 1 | Who writes? | {self.ROW}; "
            "answer:: accepted: admin only",
        )

    def test_defers_across_a_reimport_do_not_stack(self):
        self.seed()
        fresh = self.reimport([event(1, "Q2", "defer", text="ask later")])
        rows = self.respond([self.after(1, "Q2", "defer", text="again")], d=fresh)
        self.assertEqual(
            rows[1],
            f"- Q2 | superseded-by-plan | round 1 | Who writes? | {self.ROW}; "
            "answer:: deferred: again",
        )

    def test_import_seeds_the_proposal_and_the_prior_answer(self):
        doc = self.seed()
        q2 = next(q for q in doc["questions"] if q["id"] == "Q2")
        self.assertEqual(q2["recommendation"], "admin only")
        self.assertEqual(
            q2["alternatives"], [{"key": "was", "text": "any enrolled user"}]
        )

    def test_page_accept_reconfirms_the_proposal(self):
        self.seed()
        rows = self.respond([event(1, "Q2", "accept")])
        self.assertEqual(
            rows[1],
            f"- Q2 | answered | round 1 | Who writes? | {self.ROW}; "
            "answer:: accepted: admin only",
        )

    def test_page_accept_reconfirm_keeps_the_note(self):
        self.seed()
        rows = self.respond([event(1, "Q2", "accept", text="fine")])
        self.assertTrue(
            rows[1].endswith(f"{self.ROW}; answer:: accepted: admin only; note:: fine"),
            rows[1],
        )

    def test_a_page_answer_set_aside_by_a_cleared_hold_keeps_the_proposal(self):
        self.seed()
        self.respond([event(1, "Q2", "accept")])
        ops = self.tmp / "ops.json"
        ops.write_text(
            json.dumps(
                {
                    "ops": [
                        {"op": "wait", "id": "Q2", "by": "user", "waitsOn": "x"},
                        {"op": "wait", "id": "Q2", "clear": True},
                    ]
                }
            ),
            encoding="utf-8",
        )
        rc, out = self.rp("apply", "--file", str(ops))
        self.assertEqual(rc, 0, out)
        rows = register_rows(self.export("ledger"))
        self.assertEqual(
            rows[1], f"- Q2 | superseded-by-plan | round 1 | Who writes? | {self.ROW}"
        )

    def test_page_defer_keeps_it_superseded(self):
        seed = {"Q2": {"status": "superseded-by-plan", "resolution": self.RES}}
        q = question("Q2")
        page = {"Q2": {"decision": "defer", "text": "ask later", "updatedAt": AT}}
        self.assertEqual(
            exporters.settle(q, page, [], seed),
            (
                "superseded-by-plan",
                {**self.FIELDS, "answer": "deferred: ask later"},
                "ask later",
                False,
            ),
        )
        bare = {"Q2": {"decision": "defer", "updatedAt": AT}}
        self.assertEqual(
            exporters.settle(q, bare, [], seed),
            ("superseded-by-plan", {**self.FIELDS, "answer": "deferred"}, "", False),
        )

    def test_page_defer_leaves_the_ledger_row_superseded_and_the_gate_blocks(self):
        self.seed()
        rows = self.respond([event(1, "Q2", "defer", text="ask later")])
        self.assertIn("| superseded-by-plan | ", rows[1])
        self.assertTrue(
            rows[1].endswith(f"| {self.ROW}; answer:: deferred: ask later"), rows[1]
        )
        rc, out = self.check("--ledger", self.export("ledger"))
        self.assertEqual(rc, 1, out)
        self.assertIn("superseded=1", out)

    def test_proposes_matches_any_case(self):
        doc = self.seed(res="Plan Proposes: admin only; Was: any enrolled user")
        q2 = next(q for q in doc["questions"] if q["id"] == "Q2")
        self.assertEqual(q2["recommendation"], "admin only")
        self.assertEqual(
            q2["alternatives"], [{"key": "was", "text": "any enrolled user"}]
        )

    def test_page_alt_was_keeps_the_prior_answer(self):
        self.seed()
        rows = self.respond([event(1, "Q2", "alt", alt="was")])
        self.assertRegex(rows[1], r"^- Q2 \| answered \| .*alt was: any enrolled user$")

    def test_another_shape_keeps_its_confirmed_commitments(self):
        cases = [
            (
                "moot after the plan changed",
                ["A; b", "C"],
                "note:: moot after the plan changed; commitments:: +A\\; b; +C",
            ),
            ("moot; confirmed:: kept", [], "note:: moot\\; confirmed:: kept"),
            (
                "plan proposes: x",
                ["a; was: b", "WAS: c"],
                "note:: plan proposes: x; commitments:: +a\\; was: b; +WAS: c",
            ),
        ]
        for i, (res, commits, tail) in enumerate(cases):
            with self.subTest(res=res):
                d, fresh = self.tmp / f"other-{i}", self.tmp / f"other-re-{i}"
                d.mkdir()
                fresh.mkdir()
                seed = {"status": "superseded-by-plan", "round": 1, "resolution": res}
                q = question("Q1", title="Which?", alternatives=[], commits=commits)
                q["commitsConfirmed"] = [
                    {"index": k, "reason": "chat", "at": AT}
                    for k in range(len(commits))
                ]
                doc = {
                    "meta": {"seededFrom": {"at": AT, "rows": {"Q1": seed}}},
                    "rev": 1,
                    "questions": [q],
                }
                (d / "questions.json").write_text(json.dumps(doc), encoding="utf-8")
                first = self.export("ledger", d=d)
                rows = [f"- Q1 | superseded-by-plan | round 1 | Which? | {tail}"]
                self.assertEqual(register_rows(first), rows)
                rc, out = self.check("--ledger", first)
                self.assertIn("superseded=1", out)
                rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
                self.assertEqual(rc, 0, out)
                got = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
                self.assertEqual(
                    exporters.commitments(got["questions"][0], []), (commits, [])
                )
                self.assertEqual(
                    got["meta"]["seededFrom"]["rows"]["Q1"]["resolution"], res
                )
                self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)

    def test_a_resolution_of_another_shape_still_imports(self):
        doc = self.seed(res="moot after the plan changed")
        q2 = next(q for q in doc["questions"] if q["id"] == "Q2")
        self.assertNotIn("recommendation", q2)
        self.assertEqual(q2["alternatives"], [])
        rows = register_rows(self.export("ledger"))
        self.assertIn("| superseded-by-plan | ", rows[1])

    def test_a_page_answer_settles_it(self):
        self.seed()
        events = [event(1, "Q2", "own", text="Admin only, confirmed.")]
        responses, history = rebuild_responses(events)
        (self.dir / "responses.json").write_text(
            json.dumps(
                {
                    "seq": 1,
                    "events": events,
                    "responses": responses,
                    "history": history,
                }
            ),
            encoding="utf-8",
        )
        rows = register_rows(self.export("ledger"))
        self.assertRegex(
            rows[1], r"^- Q2 \| answered \| .*free-text: Admin only, confirmed\."
        )


CORPUS_CONFIRM = {
    "op": "confirm-commitments",
    "id": "Q1",
    "indices": [0, 2],
    "reason": "chat",
}
CORPUS_ACCEPT = {"op": "record-terminal", "id": "Q1", "decision": "accept"}
CORPUS_SEED = (
    "# Interview ledger\n\n## Open-question register\n\n"
    "- Q1 | superseded-by-plan | round 1 | Which store? | plan proposes: Postgres; was: SQLite\n"
)


def corpus_add(qid="Q1", commits=("One writer", "No network", "Third"), title=None):
    return {
        "op": "add",
        "question": {
            "id": qid,
            "short": qid,
            "title": title or f"Question {qid}?",
            "recommendation": f"Rec {qid}",
            "commits": list(commits),
            "alternatives": [
                {"key": "a", "text": "Alt a"},
                {"key": "b", "text": "Alt b"},
            ],
        },
    }


def corpus_wait(waits, by="claude"):
    return {"op": "wait", "id": "Q1", "waitsOn": waits, "by": by}


def corpus_cases():
    """The merge gate's adversarial held-row corpus (corpus.py, corpus2.py, corpus3.py): name -> (ops, seed ledger)."""
    base = [corpus_add()]
    cases = {}
    for tag, waits in [
        ("nospace", "vendor;answer: x"),
        ("mixedcase", "vendor; Answer: x"),
        ("ff1b", "vendor\uff1banswer: x"),
        ("newline", "vendor;\nanswer: x"),
        ("twospace", "vendor;  answer: x"),
        ("tab-confirmed", "vendor;\tconfirmed:\tx"),
        ("exact-answer", "vendor; answer: x"),
        ("exact-confirmed", "vendor; confirmed: x"),
        ("trailing", "vendor; answer:"),
    ]:
        cases["w-" + tag] = (
            [*base, CORPUS_ACCEPT, CORPUS_CONFIRM, corpus_wait(waits)],
            None,
        )
    cases["title-delims"] = (
        [
            corpus_add(title="Pick; answer: A; confirmed: B?"),
            CORPUS_ACCEPT,
            corpus_wait("bench"),
        ],
        None,
    )
    own = {
        "op": "record-terminal",
        "id": "Q1",
        "decision": "own",
        "text": "yes; answer: no; confirmed: z",
    }
    cases["own-answer-delims"] = (
        [*base, own, CORPUS_CONFIRM, corpus_wait("bench")],
        None,
    )
    first = dict(CORPUS_CONFIRM, indices=[0])
    cases["commit-with-semicolon"] = (
        [
            corpus_add(commits=["Use Postgres; no Redis", "B"]),
            first,
            corpus_wait("bench"),
        ],
        None,
    )
    cases["commit-with-answer-delim"] = (
        [corpus_add(commits=["A; answer: B"]), first, corpus_wait("bench", "user")],
        None,
    )
    for by in ("claude", "user"):
        w = corpus_wait("bench", by)
        alt = {"op": "record-terminal", "id": "Q1", "decision": "alt", "alt": "b"}
        defer = {
            "op": "record-terminal",
            "id": "Q1",
            "decision": "defer",
            "text": "later",
        }
        cases[f"{by}-unans-noconf"] = ([*base, w], None)
        cases[f"{by}-unans-conf"] = ([*base, CORPUS_CONFIRM, w], None)
        cases[f"{by}-ans-noconf-before"] = ([*base, CORPUS_ACCEPT, w], None)
        cases[f"{by}-ans-conf-before"] = (
            [*base, CORPUS_ACCEPT, CORPUS_CONFIRM, w],
            None,
        )
        cases[f"{by}-ans-after"] = ([*base, CORPUS_CONFIRM, w, CORPUS_ACCEPT], None)
        cases[f"{by}-alt"] = ([*base, alt, w], None)
        cases[f"{by}-defer"] = ([*base, defer, w], None)
    for by in ("claude", "user"):
        w = corpus_wait("bench", by)
        cases[f"sup-{by}-hold"] = ([w], CORPUS_SEED)
        cases[f"sup-{by}-hold-accept"] = (
            [dict(CORPUS_ACCEPT), w],
            CORPUS_SEED,
        )
    for by in ("claude", "user"):
        for tag, waits in [
            ("newline", "vendor;\nanswer: pending"),
            ("tab-conf", "vendor;\tconfirmed:\tA"),
        ]:
            cases[f"unans-{by}-{tag}"] = (
                [corpus_add(commits=["C"]), corpus_wait(waits, by)],
                None,
            )
    add = corpus_add(commits=[])
    add["question"].update(waiting=True, waitsOn="vendor; answer: pending")
    cases["add-with-delim"] = ([add], None)
    return cases


def held_state(doc, resp):
    """Per question: the hold, the decision that counts, else the newest one a user hold set
    aside, the confirmed commitments and the plan proposal."""
    responses = resp.get("responses") or {}
    events = resp.get("events") or []
    seeds = ((doc.get("meta") or {}).get("seededFrom") or {}).get("rows") or {}
    out = {}
    for q in doc["questions"]:
        rec = exporters.latest_decision(q, responses) or {}
        aside = [
            x
            for x in (responses.get(q["id"]), q.get("terminal"))
            if x and x.get("updatedAt") and exporters.set_aside(q, x)
        ]
        aside = max(aside, key=lambda x: x["updatedAt"]) if aside and not rec else {}
        out[q["id"]] = {
            "waiting": bool(q.get("waiting")),
            "waitsOn": q.get("waitsOn"),
            "waitingBy": q.get("waitingBy"),
            "decision": rec.get("decision"),
            "alt": rec.get("alt") if rec.get("decision") == "alt" else None,
            "text": rec.get("text") or "",
            "said": exporters.decision_fields(q, rec)[0] if rec else None,
            "confirmed": exporters.commitments(q, events)[0],
            "aside": (
                aside.get("decision"),
                aside.get("alt") if aside.get("decision") == "alt" else None,
                aside.get("text") or "",
            )
            if aside
            else None,
            "proposal": exporters.seed_proposal(seeds.get(q["id"])),
        }
    return out


def load_state(d):
    doc = json.loads((d / "questions.json").read_text(encoding="utf-8"))
    path = d / "responses.json"
    resp = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    return held_state(doc, resp)


def resumed_state(d):
    """held_state plus what a resumed session must get back: every commitment in order with its
    confirmation, the withdrawal, the seeded text of an unheld row still unsettled, and the
    register's status, arbiter and whether the decision carries the commitments."""
    doc = json.loads((d / "questions.json").read_text(encoding="utf-8"))
    path = d / "responses.json"
    resp = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    events = resp.get("events") or []
    seeds = ((doc.get("meta") or {}).get("seededFrom") or {}).get("rows") or {}
    rows = {r["q"]["id"]: r for r in exporters.register(doc, resp)}
    state = held_state(doc, resp)
    for q in doc["questions"]:
        r = rows[q["id"]]
        # A held row shows no seed text until its hold clears, when the property test compares it.
        unsettled = (
            r["status"] in exporters.UNSETTLED
            and not q.get("waiting")
            and not (
                r["status"] == "open"
                and exporters.latest_decision(q, resp.get("responses") or {})
            )
        )
        state[q["id"]].update(
            commits=exporters.marked_commits(q, events),
            archived=(q.get("archived") or {}).get("why"),
            supersededBy=q.get("supersededBy"),
            seedText=exporters.seed_text(seeds.get(q["id"])) if unsettled else None,
            status=r["status"],
            reserved=r["reserved"],
            carries=r["carries"],
        )
    return state


class TestHeldRowCorpus(SessionCase):
    """Each corpus case: the ledger re-exports the same rows, the re-import holds the same state
    (a decision a user hold set aside counts on neither side), and clearing the hold on both
    sides still exports the same rows."""

    def apply_ops(self, ops, d):
        path = self.tmp / f"ops-{len(list(self.tmp.iterdir()))}.json"
        path.write_text(json.dumps({"ops": ops}), encoding="utf-8")
        rc, out = self.rp("apply", "--file", str(path), d=d)
        self.assertEqual(rc, 0, out)

    def roundtrip(self, ops, seed):
        if seed:
            ledger = self.tmp / "seed-ledger.md"
            ledger.write_text(seed, encoding="utf-8")
            rc, out = self.rp("import-ledger", "--ledger", str(ledger))
            self.assertEqual(rc, 0, out)
        self.apply_ops(ops, self.dir)
        first = self.export("ledger")
        rows = register_rows(first)
        self.assertEqual(len(rows), 1, rows)
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        self.assertEqual(load_state(fresh), load_state(self.dir))
        for d in (self.dir, fresh):
            self.apply_ops([{"op": "wait", "id": "Q1", "clear": True}], d)
        self.assertEqual(
            register_rows(self.export("ledger", d=fresh)),
            register_rows(self.export("ledger")),
        )


def corpus_test(ops, seed):
    def test(self):
        self.roundtrip(ops, seed)

    return test


for _name, (_ops, _seed) in corpus_cases().items():
    setattr(
        TestHeldRowCorpus,
        "test_" + _name.replace("-", "_"),
        corpus_test(_ops, _seed),
    )


class TestHeldRowProperty(SessionCase):
    """Random held rows over every hold shape, plus never-held rows (open with confirmed
    commitments, answered and deferred, superseded-by-plan with a proposal or another
    resolution): export -> import -> export is identical, the imported state equals the original
    before and after the hold is cleared, no row spans lines, and check-open-questions.sh counts
    every row."""

    PIECES = [
        ";",
        ":",
        "|",
        "\\",
        "\n",
        "\t",
        "\r",
        " ",
        "  ",
        "; ",
        "answer:",
        " answer: ",
        "confirmed:",
        "; confirmed: ",
        "confirmed::",
        "; confirmed:: ",
        "plan proposes:",
        "was:",
        "note:",
        "waits on::",
        "\\n",
        "\\;",
        "\\u0041",
        "\u00e9",
        "\u65e5\u672c",
        "\u2028",
        "\u00a0",
        "\x0b",
        "x",
        "Postgres",
        "- Q9 | open",
    ]
    SHAPES = [
        (by, decision, superseded, confirmed)
        for by in ("claude", "user")
        for decision in (None, "accept", "alt", "own", "defer")
        for superseded in (False, True)
        for confirmed in (False, True)
    ]
    EARLIER = "2026-09-23T10:00:00Z"
    LATER = "2026-09-25T10:00:00Z"

    def text(self, rnd, least=0):
        return "".join(rnd.choice(self.PIECES) for _ in range(rnd.randint(least, 6)))

    def proposal(self, rnd):
        """A proposal and prior answer: one a legacy superseded-by-plan row can carry (its
        resolution alone), or one only an escaped held row can (kept as structured fields)."""
        if rnd.random() < 0.5:
            new = self.text(rnd, 1) + rnd.choice(["\n", "; was: ", ";was:"])
            return new + self.text(rnd), self.text(rnd), True
        while True:
            new, old = (
                exporters.clean(self.text(rnd, 1)),
                exporters.clean(self.text(rnd)),
            )
            m = exporters.PROPOSES.match(f"plan proposes: {new}; was: {old}")
            if m and m.groups() == (new, old):
                return new, old, False

    def build(self, seed):
        rnd = random.Random(seed)
        qs, rows = [], {}
        expect = {"open": 0, "superseded": 0, "answered": 0, "deferred": 0}
        # Unheld superseded-by-plan rows reconfirmed by an accept or kept by a defer: the row
        # keeps the proposal, not the decision, so only their confirmed commitments are compared.
        expect["loose"] = set()
        for i, (by, decision, superseded, confirmed) in enumerate(self.SHAPES, 1):
            qid = f"Q{i}" if seed % 2 == 0 else f"H{i}"
            commits = [f"{self.text(rnd)}; {self.text(rnd)}"]
            commits += [self.text(rnd) for _ in range(rnd.randint(0, 2))]
            q = {
                "id": qid,
                "short": f"Short {qid}",
                "title": f"Question {qid}?",
                "round": 1,
                "recommendation": self.text(rnd, 1),
                "commits": commits,
                "alternatives": [
                    {"key": "a", "text": self.text(rnd)},
                    {"key": "b", "text": self.text(rnd)},
                ],
                "waiting": True,
                "waitsOn": self.text(rnd, 1),
                "history": [],
            }
            if confirmed:
                picks = rnd.sample(range(len(commits)), rnd.randint(1, len(commits)))
                q["commitsConfirmed"] = [
                    {"index": k, "reason": "chat", "at": AT} for k in sorted(picks)
                ]
            if superseded:
                new, old, structured = self.proposal(rnd)
                q["recommendation"] = new
                q["alternatives"] = [{"key": "was", "text": old}]
                rows[qid] = {
                    "status": "superseded-by-plan",
                    "round": 1,
                    "resolution": f"plan proposes: {new}; was: {old}",
                }
                if structured:
                    rows[qid]["proposal"] = [new, old]
            if decision:
                alt = (
                    rnd.choice(q["alternatives"])["key"] if decision == "alt" else None
                )
                q["terminal"] = {
                    "decision": decision,
                    "alt": alt,
                    "text": self.text(rnd),
                    "updatedAt": AT,
                }
            if by == "user":
                q["waitingBy"] = "user"
                if rnd.random() < 0.6:
                    q["setAsideAt"] = rnd.choice([self.EARLIER, self.LATER])
            expect["superseded" if superseded else "open"] += 1
            qs.append(q)
        n = len(self.SHAPES)
        # Never-held rows: an open row with confirmed commitments, superseded-by-plan rows
        # without and with confirmed commitments, answered and deferred rows with confirmed
        # commitments, and superseded-by-plan rows reconfirmed by an accept or kept by a defer.
        unheld = [
            (None, False, True),
            (None, True, False),
            (None, True, True),
            ("accept", False, True),
            ("alt", False, True),
            ("own", False, True),
            ("defer", False, True),
            ("accept", True, True),
            ("defer", True, True),
        ]
        for i, (decision, superseded, confirmed) in enumerate(unheld, n + 1):
            qid = f"Q{i}" if seed % 2 == 0 else f"H{i}"
            q = {
                "id": qid,
                "short": f"Short {qid}",
                "title": f"Question {qid}?",
                "round": 1,
                "recommendation": self.text(rnd, 1),
                "commits": [],
                "alternatives": [],
                "history": [],
            }
            if confirmed:
                q["commits"] = [f"{self.text(rnd)}; {self.text(rnd)}"]
                q["commits"] += [self.text(rnd) for _ in range(rnd.randint(0, 2))]
                picks = rnd.sample(
                    range(len(q["commits"])), rnd.randint(1, len(q["commits"]))
                )
                q["commitsConfirmed"] = [
                    {"index": k, "reason": "chat", "at": AT} for k in sorted(picks)
                ]
            if decision:
                q["alternatives"] = [
                    {"key": "a", "text": self.text(rnd)},
                    {"key": "b", "text": self.text(rnd)},
                ]
                q["terminal"] = {
                    "decision": decision,
                    "alt": "a" if decision == "alt" else None,
                    "text": self.text(rnd),
                    "updatedAt": AT,
                }
                if superseded:
                    expect["loose"].add(qid)
            if superseded:
                new, old, structured = self.proposal(rnd)
                q["recommendation"] = new
                q["alternatives"] = [{"key": "was", "text": old}]
                rows[qid] = {
                    "status": "superseded-by-plan",
                    "round": 1,
                    "resolution": f"plan proposes: {new}; was: {old}",
                }
                if structured:
                    rows[qid]["proposal"] = [new, old]
            # An accept that leaves a commitment unticked reads open.
            unticked = len(q.get("commitsConfirmed", [])) < len(q["commits"])
            if decision == "accept" and unticked:
                expect["open"] += 1
            elif decision in ("accept", "alt", "own"):
                expect["answered"] += 1
            elif decision == "defer" and not superseded:
                expect["deferred"] += 1
            else:
                expect["superseded" if superseded else "open"] += 1
            qs.append(q)
        # Never-held superseded-by-plan rows whose resolution is not a proposal, some with
        # confirmed commitments, some holding the confirmed tail's mark.
        for mark in ("", "", "; confirmed::", "; confirmed:: x"):
            qid = f"Q{len(qs) + 1}" if seed % 2 == 0 else f"H{len(qs) + 1}"
            commits = [self.text(rnd) for _ in range(rnd.randint(0, 3))]
            qs.append(
                {
                    "id": qid,
                    "short": f"Short {qid}",
                    "title": f"Question {qid}?",
                    "round": 1,
                    "commits": commits,
                    "commitsConfirmed": [
                        {"index": k, "reason": "chat", "at": AT}
                        for k in range(len(commits))
                        if rnd.random() < 0.7
                    ],
                    "alternatives": [],
                    "history": [],
                }
            )
            rows[qid] = {
                "status": "superseded-by-plan",
                "round": 1,
                "resolution": exporters.clean("moot " + self.text(rnd) + mark),
            }
            expect["superseded"] += 1
        meta = {"title": "Held rows"}
        if rows:
            meta["seededFrom"] = {"at": AT, "rows": rows}
        doc = {"meta": meta, "rev": 1, "groups": [], "questions": qs, "visuals": []}
        return doc, expect

    def ledger(self, d, name):
        path = self.tmp / name
        path.write_text(exporters.export_ledger(d), encoding="utf-8")
        return path

    def check_seed(self, seed):
        doc, expect = self.build(seed)
        orig = self.tmp / f"orig-{seed}"
        orig.mkdir()
        (orig / "questions.json").write_text(json.dumps(doc), encoding="utf-8")
        first = self.ledger(orig, f"first-{seed}.md")
        text = first.read_text(encoding="utf-8")
        for line in text.split("\n"):
            self.assertLessEqual(len(line.splitlines()), 1, f"seed {seed}: {line!r}")
        rows = register_rows(first)
        self.assertEqual(len(rows), len(doc["questions"]), f"seed {seed}")
        rc, out = self.check("--ledger", first)
        self.assertEqual(rc, 1, f"seed {seed}: {out}")
        self.assertIn(
            f"registered={len(rows)} open={expect['open']} "
            f"deferred={expect['deferred']} blocked=0 withdrawn=0 "
            f"answered={expect['answered']} superseded={expect['superseded']} ",
            out,
            f"seed {seed}",
        )
        fresh = self.tmp / f"fresh-{seed}"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(first), d=fresh)
        self.assertEqual(rc, 0, f"seed {seed}: {out}")
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, f"seed {seed}: {out}")
        self.assertEqual(
            register_rows(self.ledger(fresh, f"second-{seed}.md")), rows, f"seed {seed}"
        )
        before, after = held_state(doc, {}), load_state(fresh)
        self.assertEqual(sorted(after), sorted(before), f"seed {seed}")
        for qid, state in before.items():
            if qid in expect["loose"]:
                self.assertEqual(
                    after[qid]["confirmed"], state["confirmed"], f"seed {seed} {qid}"
                )
            else:
                self.assertEqual(after[qid], state, f"seed {seed} {qid}")
        for d in (orig, fresh):
            path = d / "questions.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            for q in data["questions"]:
                for key in ("waiting", "waitsOn", "waitingBy"):
                    q.pop(key, None)
            path.write_text(json.dumps(data), encoding="utf-8")
        cleared_ledger = self.ledger(orig, f"cleared-{seed}.md")
        cleared = register_rows(cleared_ledger)
        self.assertEqual(
            register_rows(self.ledger(fresh, f"cleared-re-{seed}.md")),
            cleared,
            f"seed {seed}",
        )
        # The cleared rows round-trip too, each with its confirmed commitments.
        again = self.tmp / f"again-{seed}"
        again.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(cleared_ledger), d=again)
        self.assertEqual(rc, 0, f"seed {seed}: {out}")
        self.assertEqual(
            register_rows(self.ledger(again, f"again-{seed}.md")),
            cleared,
            f"seed {seed}",
        )
        want = {k: v["confirmed"] for k, v in load_state(orig).items()}
        got = {k: v["confirmed"] for k, v in load_state(again).items()}
        self.assertEqual(got, want, f"seed {seed}")

    def test_every_hold_shape_round_trips_losslessly(self):
        for seed in range(10):
            with self.subTest(seed=seed):
                self.check_seed(seed)


LEGACY = HERE / "tests" / "fixtures" / "ledger-legacy"
LEGACY_SHAPES = 36


def legacy_state(doc):
    """What an import left in questions.json, from its raw fields and none of its timestamps: per
    question the commitments with their confirmation, the terminal decision (an accept's or an
    alternative's text is its note), the recommendation and alternatives (a plan proposal's
    `was` is the alternative keyed was), the archived reason, the hold, the set-aside keys and
    the seeded row with its proposal pair."""
    seeds = ((doc.get("meta") or {}).get("seededFrom") or {}).get("rows") or {}
    state = {}
    for q in doc["questions"]:
        ticked = {c["index"] for c in q.get("commitsConfirmed") or []}
        term, arch = q.get("terminal"), q.get("archived")
        state[q["id"]] = {
            "title": q["title"],
            "round": q["round"],
            "commits": [
                {"text": c, "confirmed": i in ticked}
                for i, c in enumerate(q.get("commits") or [])
            ],
            "terminal": {
                "decision": term.get("decision"),
                "alt": term.get("alt"),
                "text": term.get("text"),
                "seeded": bool(term.get("seeded")),
            }
            if term
            else None,
            "recommendation": q.get("recommendation"),
            "alternatives": q.get("alternatives"),
            "archived": {"why": arch["why"], "seeded": bool(arch.get("seeded"))}
            if arch
            else None,
            "hold": {"waitsOn": q["waitsOn"], "by": q.get("waitingBy") or "claude"}
            if q.get("waiting")
            else None,
            "setAside": sorted(k for k in q if k.startswith("setAside")),
            "seed": seeds.get(q["id"]),
        }
    return state


class TestLegacyLedgerFixtures(SessionCase):
    """Every ledger grammar that shipped still imports. Each directory under
    tests/fixtures/ledger-legacy/ holds one row shape as a ledger (ledger.md) and the state its
    import leaves in questions.json (expected.json, from legacy_state); a newer grammar keeps
    every fixture importing to the same state unless a test names the change."""

    def test_every_legacy_ledger_imports_to_its_expected_state(self):
        shapes = sorted(p for p in LEGACY.iterdir() if p.is_dir())
        self.assertEqual(len(shapes), LEGACY_SHAPES)
        for shape in shapes:
            with self.subTest(shape=shape.name):
                d = self.tmp / shape.name
                d.mkdir()
                rc, out = self.rp(
                    "import-ledger", "--ledger", str(shape / "ledger.md"), d=d
                )
                self.assertEqual(rc, 0, out)
                rc, out = self.rp("validate", d=d)
                self.assertEqual(rc, 0, out)
                got = json.loads((d / "questions.json").read_text(encoding="utf-8"))
                want = json.loads((shape / "expected.json").read_text(encoding="utf-8"))
                self.assertEqual(legacy_state(got), want)

    def round_trip(self, shape):
        """Import a fixture, export its ledger, import that into an empty data dir and export
        again: per pass the state (legacy_state without the seeded bookkeeping), the ledger's
        register rows, the Brief and the report's resolution cells."""
        ledger, passes = LEGACY / shape / "ledger.md", []
        for step in ("legacy", "named"):
            d = self.tmp / f"{shape}-{step}"
            d.mkdir()
            rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=d)
            self.assertEqual(rc, 0, out)
            rc, out = self.rp("validate", d=d)
            self.assertEqual(rc, 0, out)
            state = legacy_state(json.loads((d / "questions.json").read_text("utf-8")))
            for q in state.values():
                q.pop("seed")
                for key in ("terminal", "archived"):
                    if q[key]:
                        q[key].pop("seeded")
            ledger = self.tmp / f"{shape}-{step}-out" / "ledger.md"
            ledger.parent.mkdir()
            ledger.write_text(exporters.export_ledger(d), encoding="utf-8")
            cells = re.findall(r"<td>([^<]*)</td></tr>", exporters.export_report(d))
            passes.append(
                {
                    "state": state,
                    "rows": register_rows(ledger),
                    "brief": exporters.export_brief(d),
                    "display": [html.unescape(c) for c in cells],
                }
            )
        return passes

    def test_every_legacy_ledger_round_trips_through_the_named_grammar(self):
        for shape in sorted(p.name for p in LEGACY.iterdir() if p.is_dir()):
            with self.subTest(shape=shape):
                legacy, named = self.round_trip(shape)
                self.assertEqual(named, legacy)

    def test_a_plain_alt_answer_keeps_its_text_and_adds_no_alternative(self):
        legacy, named = self.round_trip("answered-plain")
        self.assertEqual(
            named["rows"][1].split(" | ")[-1], "answer:: alt a; note:: only admins"
        )
        q2 = named["state"]["Q2"]
        self.assertEqual(q2["alternatives"], [])
        self.assertEqual(
            q2["terminal"],
            {"decision": "alt", "alt": "a", "text": "only admins"},
        )

    def test_a_seeded_deferral_keeps_the_plan_as_its_arbiter(self):
        for shape, n in (
            ("deferred-plain", "Q1"),
            ("older-settled-confirmed-tail", "Q3"),
        ):
            with self.subTest(shape=shape):
                for p in self.round_trip(shape):
                    deferred = p["brief"].split("### Deferred questions")[1]
                    line = next(
                        x for x in deferred.splitlines() if x.startswith(f"- {n}:")
                    )
                    self.assertTrue(
                        line.endswith(
                            "defer until the user revisits it; "
                            + exporters.ARBITER_PLAN
                        ),
                        line,
                    )

    def test_a_seeded_user_reserved_deferral_names_its_arbiter_once(self):
        for p in self.round_trip("deferred-plain"):
            deferred = p["brief"].split("### Deferred questions")[1]
            self.assertIn(
                "- Q2: Who writes?, defer until the user revisits it; "
                "**arbiter: USER-RESERVED**\n",
                deferred,
            )
            self.assertEqual(p["display"][1].count("USER-RESERVED"), 1)

    def test_an_older_confirmed_open_row_writes_its_commitments_once(self):
        legacy, named = self.round_trip("older-open-confirmed")
        for p in (legacy, named):
            self.assertEqual(
                p["rows"][0], "- Q1 | open | round 1 | Where? | commitments:: +One"
            )
            self.assertEqual(p["display"][0], "confirmed: One")

    def test_an_alternative_or_a_deferral_keeps_its_confirmed_commitments_in_view(self):
        for shape, i in (
            ("answered-confirmed-tail", 2),
            ("deferred-escaped-confirmed-tail", 0),
            ("held-answer-alt", 0),
        ):
            with self.subTest(shape=shape):
                for p in self.round_trip(shape):
                    self.assertRegex(p["display"][i], r"; confirmed: [^;]")


class TestResumedState(SessionCase):
    """Export then import into an empty data dir restores the question state (resumed_state), not
    only the row text: the issue's four losses, and every combination of seed, hold, decision and
    commitment set."""

    PROPOSED = "- Q1 | superseded-by-plan | round 1 | Who? | plan proposes: Postgres; was: SQLite\n"

    def seed(self, row):
        ledger = self.tmp / "seed-ledger.md"
        ledger.write_text(
            f"# Interview ledger\n\n## Open-question register\n\n{row}",
            encoding="utf-8",
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        return json.loads((self.dir / "questions.json").read_text(encoding="utf-8"))

    def reimport(self):
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp(
            "import-ledger", "--ledger", str(self.export("ledger")), d=fresh
        )
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        return fresh

    def round_trip(self):
        """The state before export, after checking the import restored all of it."""
        before = resumed_state(self.dir)
        self.assertEqual(resumed_state(self.reimport()), before)
        return before["Q1"]

    def test_a_unconfirmed_commitments_survive(self):
        q = question("Q1", title="Who?", commits=["One writer", "No network"])
        self.session(
            [q], [event(1, "Q1", "accept"), event(2, "Q1", "confirm", alt="0")]
        )
        got = self.round_trip()
        self.assertEqual(got["commits"], [(True, "One writer"), (False, "No network")])
        self.assertEqual(got["decision"], "accept")

    def test_b_an_open_seeded_row_keeps_commitments_confirmed_later(self):
        doc = self.seed("- Q1 | open | round 1 | Who? | leaning to Postgres\n")
        doc["questions"][0]["commits"] = ["One writer", "No network"]
        self.session(
            doc["questions"], [event(1, "Q1", "confirm", alt="0")], doc["meta"]
        )
        got = self.round_trip()
        self.assertEqual(got["commits"], [(True, "One writer"), (False, "No network")])
        self.assertEqual(got["seedText"], "leaning to Postgres")
        self.assertEqual(got["status"], "open")

    def test_c_an_accept_on_a_superseded_row_keeps_its_structure(self):
        doc = self.seed(self.PROPOSED)
        self.session(
            doc["questions"], [event(1, "Q1", "accept", text="fine")], doc["meta"]
        )
        got = self.round_trip()
        self.assertEqual((got["decision"], got["text"]), ("accept", "fine"))
        self.assertEqual(got["said"], "accepted: Postgres")
        self.assertEqual(got["proposal"], ("Postgres", "SQLite"))
        self.assertEqual(got["status"], "answered")

    def test_d_a_defer_on_a_superseded_row_survives(self):
        doc = self.seed(self.PROPOSED)
        events = [event(1, "Q1", "defer", text="after the pilot")]
        self.session(doc["questions"], events, doc["meta"])
        got = self.round_trip()
        self.assertEqual((got["decision"], got["text"]), ("defer", "after the pilot"))
        self.assertEqual(got["proposal"], ("Postgres", "SQLite"))
        self.assertEqual(got["status"], "superseded-by-plan")

    def test_a_held_seeded_deferral_keeps_the_plan_as_its_arbiter_once_the_hold_clears(
        self,
    ):
        doc = self.seed("- Q1 | deferred | round 1 | Who? | ask the DBA\n")
        doc["questions"][0].update(waiting=True, waitsOn="vendor")
        self.session(doc["questions"], [], doc["meta"])
        row = register_rows(self.export("ledger"))[0]
        self.assertTrue(
            row.endswith("hold:: claude vendor; answer:: deferred; note:: ask the DBA"),
            row,
        )
        fresh = self.reimport()
        path = fresh / "questions.json"
        held = json.loads(path.read_text(encoding="utf-8"))
        for q in held["questions"]:
            for key in ("waiting", "waitsOn"):
                q.pop(key)
        path.write_text(json.dumps(held), encoding="utf-8")
        got = resumed_state(fresh)["Q1"]
        self.assertEqual((got["status"], got["reserved"]), ("deferred", False))

    def test_a_held_seeded_text_survives_the_hold_on_an_open_or_superseded_row(self):
        doc = self.seed(
            "- Q1 | open | round 1 | Who? | leaning to Postgres\n"
            "- Q2 | superseded-by-plan | round 1 | When? | moot\n"
        )
        for q in doc["questions"]:
            q.update(waiting=True, waitsOn="vendor")
        self.session(doc["questions"], [], doc["meta"])
        rows = register_rows(self.export("ledger"))
        self.assertTrue(rows[0].startswith("- Q1 | open |"), rows[0])
        self.assertTrue(rows[1].startswith("- Q2 | superseded-by-plan |"), rows[1])
        fresh = json.loads((self.reimport() / "questions.json").read_text("utf-8"))
        seeded = fresh["meta"]["seededFrom"]["rows"]
        self.assertEqual(
            (seeded["Q1"]["status"], seeded["Q1"]["resolution"]),
            ("open", "leaning to Postgres"),
        )
        self.assertEqual(
            (seeded["Q2"]["status"], seeded["Q2"]["resolution"]),
            ("superseded-by-plan", "moot"),
        )

    def test_an_untouched_resumed_session_names_its_unconfirmed_commitment_as_a_risk(
        self,
    ):
        self.seed(
            "- Q1 | answered | round 1 | Who? | answer:: accepted: Rec.; "
            "commitments:: +One writer; -No network\n"
        )
        brief = exporters.export_brief(self.dir)
        self.assertIn(
            "- 1 commitments confirmed; 1 unconfirmed, carried as named risks", brief
        )
        self.assertIn("- One writer: confirmed on Q1; revisit if Q1 changes\n", brief)
        self.assertIn("- risk: No network (unconfirmed); from Q1\n", brief)

    # Every combination: seed x hold x decision x commitment set, one question each.
    SEEDS = {
        None: None,
        "proposal": {
            "status": "superseded-by-plan",
            "resolution": "plan proposes: Post | gres; was: SQL; ite",
            "proposal": ["Post | gres", "SQL; ite"],
        },
        "superseded-text": {
            "status": "superseded-by-plan",
            "resolution": "moot; after | it",
        },
        "open-text": {"status": "open", "resolution": "leaning; to | Postgres"},
        "deferred": {"status": "deferred", "resolution": "ask; the DBA"},
        "reserved": {
            "status": "deferred",
            "resolution": "later; arbiter: USER-RESERVED",
        },
        "blocked": {"status": "blocked", "resolution": "waiting | on legal"},
    }
    HOLDS = (None, "claude", "user", "user-aside")
    DECISIONS = (
        None,
        *(
            (src, kind)
            for src in ("page", "terminal")
            for kind in ("accept", "alt", "own", "defer")
        ),
        ("terminal", "unlisted-alt"),
        ("withdraw", "archived"),
        ("withdraw", "superseded"),
    )
    COMMITS = ["One | writer; only", "No\tnetwork", "a\\;b"]
    TICKS = {"none": (), "all": (0, 1, 2), "unconfirmed": (), "mixed": (0, 2)}
    TEXTS = {
        "accept": "only v1; revisit",
        "alt": "with a | note",
        "unlisted-alt": "kept; note",
        "own": "Use A | B; not C",
        "defer": "after; the pilot",
    }
    EARLIER = "2026-09-23T10:00:00Z"
    LATER = "2026-09-25T10:00:00Z"

    def combinations(self):
        for seed, hold, decision, commits in (
            (s, h, d, c)
            for s in self.SEEDS
            for h in self.HOLDS
            for d in self.DECISIONS
            for c in self.TICKS
        ):
            # A withdrawn row carries only its withdrawal: a hold or a seeded deferral on it
            # does not export.
            if (
                decision
                and decision[0] == "withdraw"
                and (hold or seed in ("deferred", "reserved", "blocked"))
            ):
                continue
            yield seed, hold, decision, commits

    @staticmethod
    def held_loss(combo):
        """A combination whose state does not survive export and import once its hold clears,
        because the grammar has no field for it: a seeded blocked row (a held row's status reads
        open, so it comes back deferred), and the seed text of an open or superseded-by-plan row
        whose set-aside accept or alternative keeps its own note in note."""
        seed, hold, decision, _ = combo
        if seed == "blocked":
            return hold in ("claude", "user") and not decision
        return (
            seed in ("open-text", "superseded-text")
            and hold == "user-aside"
            and bool(decision)
            and decision[1] in ("accept", "alt", "unlisted-alt")
        )

    def build(self):
        qs, events, rows = [], [], {}
        for i, (seed, hold, decision, commits) in enumerate(self.combinations(), 1):
            qid = f"Q{i}"
            q = question(qid, commits=[] if commits == "none" else list(self.COMMITS))
            if seed:
                rows[qid] = dict(self.SEEDS[seed], round=1)
            if seed == "proposal":
                q["recommendation"] = "Post | gres"
                q["alternatives"] = [{"key": "was", "text": "SQL; ite"}]
            if seed in ("deferred", "reserved", "blocked"):
                text = self.SEEDS[seed]["resolution"]
                q["terminal"] = {
                    "decision": "defer",
                    "alt": None,
                    "text": text,
                    "updatedAt": self.EARLIER,
                    "seeded": True,
                }
            for k in self.TICKS[commits]:
                events.append(event(len(events) + 1, qid, "confirm", alt=str(k)))
            src, kind = decision or (None, None)
            if src == "withdraw" and kind == "archived":
                q["archived"] = {"why": "Off; the | path", "at": AT}
            elif src == "withdraw":
                q["supersededBy"] = "Q1"
            elif kind:
                alt = {"alt": q["alternatives"][0]["key"], "unlisted-alt": "z"}.get(
                    kind
                )
                if src == "page":
                    events.append(
                        event(
                            len(events) + 1, qid, kind, alt=alt, text=self.TEXTS[kind]
                        )
                    )
                else:
                    q["terminal"] = {
                        "decision": "alt" if alt else kind,
                        "alt": alt,
                        "text": self.TEXTS[kind],
                        "updatedAt": AT,
                    }
            if hold:
                q.update(waiting=True, waitsOn="vendor; answer: x | y")
            if hold in ("user", "user-aside"):
                q["waitingBy"] = "user"
            if hold == "user-aside":
                q.update(setAsideAt=self.LATER, setAsideSeq=10**6)
            qs.append(q)
        return (
            qs,
            events,
            {"title": "Every combination", "seededFrom": {"at": AT, "rows": rows}},
        )

    def test_every_combination_round_trips_its_state(self):
        qs, events, meta = self.build()
        self.session(qs, events, meta)
        before = resumed_state(self.dir)
        self.assertEqual(
            {s["status"] for s in before.values()},
            {
                "open",
                "answered",
                "deferred",
                "blocked",
                "withdrawn",
                "superseded-by-plan",
            },
        )
        rows = register_rows(self.export("ledger"))
        fresh = self.reimport()
        after = resumed_state(fresh)
        combos = list(self.combinations())
        for i, combo in enumerate(combos, 1):
            qid = f"Q{i}"
            with self.subTest(qid=qid, combo=combo):
                self.assertEqual(after[qid], before[qid], rows[i - 1])
        self.assertEqual(len(after), len(combos))
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)
        # Clearing every hold on both sides leaves the same state, except for the combinations
        # held_loss names, which the grammar has no field for and this pins as still lost.
        for d in (self.dir, fresh):
            path = d / "questions.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            for q in doc["questions"]:
                for key in ("waiting", "waitsOn", "waitingBy"):
                    q.pop(key, None)
            path.write_text(json.dumps(doc), encoding="utf-8")
        before, after = resumed_state(self.dir), resumed_state(fresh)
        for i, combo in enumerate(combos, 1):
            with self.subTest(qid=f"Q{i}", combo=combo, cleared=True):
                lost = self.held_loss(combo)
                same = after[f"Q{i}"] == before[f"Q{i}"]
                self.assertNotEqual(
                    same, lost, "shrink held_loss" if same else rows[i - 1]
                )


class TestLedgerIgnoresConfirmsAgainstAnEarlierList(SessionCase):
    """A confirm event at or below the question's commitsSinceSeq was made against an earlier
    commitment list, so the ledger leaves that commitment unconfirmed and an import restores only
    the confirm made after the list changed."""

    def test_only_a_confirm_after_the_list_changed_is_exported_and_imported(self):
        q = question("Q1", title="Who?", commits=["A", "B"], commitsSinceSeq=5)
        old, new = (
            event(3, "Q1", "confirm", alt="0"),
            event(7, "Q1", "confirm", alt="1"),
        )
        self.session([q], [old, new])
        ledger = self.export("ledger")
        self.assertEqual(
            register_rows(ledger),
            ["- Q1 | open | round 1 | Who? | commitments:: -A; +B"],
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=fresh)
        self.assertEqual(rc, 0, out)
        got = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
        self.assertEqual(exporters.commitments(got["questions"][0], []), (["B"], ["A"]))


class TestUntickedCommitmentGate(SessionCase):
    """An accepted or hedged row with an unconfirmed commitment exports open, so the `lock` gate
    does not pass until each commitment is confirmed."""

    COMMITS = ["One writer only", "No network"]

    def one(self, events):
        self.session([question("Q1", commits=self.COMMITS)], events)

    def row(self):
        (row,) = register_rows(self.export("ledger"))
        return row

    def gate(self):
        return self.check("--ledger", self.export("ledger"))[0]

    def test_an_accept_with_an_unticked_commitment_is_open_and_blocks_the_gate(self):
        self.one([event(1, "Q1", "accept"), event(2, "Q1", "confirm", alt="0")])
        self.assertEqual(
            self.row(),
            "- Q1 | open | round 1 | Question Q1? | answer:: accepted: Recommended answer "
            "for Q1.; commitments:: +One writer only; -No network",
        )
        self.assertEqual(self.gate(), 1)

    def test_an_accept_with_every_commitment_ticked_is_answered(self):
        self.one(
            [
                event(1, "Q1", "accept"),
                event(2, "Q1", "confirm", alt="0"),
                event(3, "Q1", "confirm", alt="1"),
            ]
        )
        self.assertIn("| answered |", self.row())
        self.assertEqual(self.gate(), 0)

    def test_a_hedged_answer_with_an_unticked_commitment_is_open(self):
        self.one([event(1, "Q1", "hedged", text="only if cheap")])
        self.assertEqual(
            self.row(),
            "- Q1 | open | round 1 | Question Q1? | answer:: hedged: Recommended answer "
            "for Q1.; note:: only if cheap; commitments:: -One writer only; -No network",
        )
        self.assertEqual(self.gate(), 1)

    def test_an_own_answer_and_an_alternative_do_not_open_the_row(self):
        qs = [question(f"Q{i}", commits=["Part"]) for i in (1, 2)]
        self.session(
            qs, [event(1, "Q1", "own", text="Mine."), event(2, "Q2", "alt", alt="a")]
        )
        self.assertEqual(
            [r.split(" | ")[1] for r in register_rows(self.export("ledger"))],
            ["answered", "answered"],
        )

    def test_revised_commitments_reopen_an_accept_whose_earlier_confirms_no_longer_tick(
        self,
    ):
        self.one(
            [
                event(1, "Q1", "accept"),
                event(2, "Q1", "confirm", alt="0"),
                event(3, "Q1", "confirm", alt="1"),
            ]
        )
        self.assertEqual(self.gate(), 0)
        rc, out = self.rp(
            "revise", "Q1", "--commit", "Two writers", "--commit", "Online", "--force"
        )
        self.assertEqual(rc, 0, out)
        self.assertEqual(
            self.row(),
            "- Q1 | open | round 1 | Question Q1? | answer:: accepted: Recommended answer "
            "for Q1.; commitments:: -Two writers; -Online",
        )
        self.assertEqual(self.gate(), 1)

    def test_the_open_row_round_trips_through_import_ledger(self):
        self.one(
            [
                event(1, "Q1", "hedged", text="only if cheap"),
                event(2, "Q1", "confirm", alt="1"),
            ]
        )
        ledger = self.export("ledger")
        rows = register_rows(ledger)
        self.assertIn("| open |", rows[0])
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(ledger), d=fresh)
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        got = json.loads((fresh / "questions.json").read_text(encoding="utf-8"))
        (q,) = got["questions"]
        self.assertEqual(
            (q["terminal"]["decision"], q["terminal"]["text"]),
            ("hedged", "only if cheap"),
        )
        self.assertEqual(
            exporters.commitments(q, []), (["No network"], ["One writer only"])
        )
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), rows)

    def test_an_open_row_with_an_answer_and_every_commitment_ticked_is_refused(self):
        bad = self.tmp / "bad.md"
        bad.write_text(
            "## Open-question register\n\n- Q1 | open | round 1 | Who? | answer:: "
            "accepted: Yes.; commitments:: +A\n",
            encoding="utf-8",
        )
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp("import-ledger", "--ledger", str(bad), d=fresh)
        self.assertNotEqual(rc, 0)
        self.assertIn("refused", out)

    def test_the_brief_names_the_open_row_and_keeps_its_risk(self):
        self.one([event(1, "Q1", "accept")])
        brief = self.export("brief").read_text(encoding="utf-8")
        self.assertIn("- 0 commitments confirmed; 2 unconfirmed", brief)
        self.assertIn("- Q1: decided, open until its commitments are confirmed", brief)
        self.assertIn("- risk: No network (unconfirmed); from Q1", brief)


class TestLedgerRoundCellsAndMerge(SessionCase):
    """Round cells survive import and export; export-ledger --ledger merges into a ledger's
    register, --diff prints what that would change, and sync-ledger rewrites only its rows."""

    def ledger(self, rows, prose=""):
        path = self.tmp / f"ledger-{len(list(self.tmp.iterdir()))}.md"
        path.write_text(
            "# Interview ledger\n\n## Open-question register\n\n"
            + prose
            + "\n".join(rows)
            + "\n\n### Deferred questions\n\n- none\n",
            encoding="utf-8",
        )
        return path

    def doc(self, d=None):
        return json.loads((d or self.dir).joinpath("questions.json").read_text("utf-8"))

    def test_a_labeled_round_cell_imports_as_its_round(self):
        ledger = self.ledger(
            [
                "- Q1 | open | round 5 (sweep S1 to S3) | One? |",
                "- Q2 | open | round 5 (sweep S12 to S14) | Two? |",
                "- Q3 | open | round 5 (sweep S7), resolved in step 2 | Three? |",
                "- Q4 | open | Round 5 (research) | Four? |",
                "- Q5 | open | 6 (design) | Five? |",
            ]
        )
        rc, out = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        self.assertEqual([q["round"] for q in self.doc()["questions"]], [5, 5, 5, 5, 6])
        self.assertIn("warning: Q5 round cell '6 (design)'", out)
        self.assertEqual(out.count("warning:"), 1, out)
        rc, out = self.rp("validate")
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger")), register_rows(ledger))

    def test_an_import_then_export_round_trips_byte_for_byte(self):
        self.decided()
        rows = register_rows(self.export("ledger"))
        labeled = [
            rows[0].replace("| round 1 |", "| round 1 (sweep S1 to S3) |", 1),
            rows[1].replace("| round 1 |", "| Round 1 (design) |", 1),
            *rows[2:],
        ]
        self.assertNotEqual(labeled, rows)
        fresh = self.tmp / "fresh"
        fresh.mkdir()
        rc, out = self.rp(
            "import-ledger", "--ledger", str(self.ledger(labeled)), d=fresh
        )
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("validate", d=fresh)
        self.assertEqual(rc, 0, out)
        self.assertEqual(register_rows(self.export("ledger", d=fresh)), labeled)
        # A round the page changes no longer matches the label, so the plain cell is written.
        doc = self.doc(fresh)
        doc["questions"][0]["round"] = 2
        (fresh / "questions.json").write_text(json.dumps(doc), encoding="utf-8")
        self.assertIn("| round 2 |", register_rows(self.export("ledger", d=fresh))[0])

    def three_of_four(self, accepted=("Q1", "Q2", "Q4")):
        """Page questions Q1, Q2 and Q4, the named ones accepted; Q3 lives only in the ledger."""
        self.session(
            [question("Q1"), question("Q2"), question("Q4", round=2)],
            [event(n, qid, "accept") for n, qid in enumerate(accepted, start=1)],
        )

    def test_ledger_only_rows_and_titles_survive_the_export(self):
        self.three_of_four()
        only = "- Q3 | deferred | round 1 | Never posted? | deferred: to planning"
        ledger = self.ledger(
            [
                "- Q1 | open | round 1 | Who writes the ledger? |",
                "- Q2 | open | round 1 | Question Q2? |",
                only,
                "- Q4 | open | round 2 | Question Q4? |",
            ]
        )
        out = self.tmp / "merged.md"
        rc, text = self.rp("export-ledger", "--out", str(out), "--ledger", str(ledger))
        self.assertEqual(rc, 0, text)
        rows = register_rows(out)
        self.assertEqual(
            [r.split(" | ")[0] for r in rows], ["- Q1", "- Q2", "- Q3", "- Q4"]
        )
        self.assertEqual(rows[2], only)
        self.assertIn("| Who writes the ledger? |", rows[0])
        self.assertTrue(all(" | answered | " in r for r in rows if r != only), rows)
        self.assertIn("- Q3: Never posted?", out.read_text(encoding="utf-8"))
        rc, verdict = self.check("--ledger", out)
        self.assertEqual(rc, 0, verdict)

    def test_diff_lists_the_label_the_ledger_only_row_and_the_conflict(self):
        self.three_of_four(accepted=("Q1", "Q4"))
        ledger = self.ledger(
            [
                "- Q1 | open | round 1 (design) | Question Q1? |",
                "- Q2 | answered | round 1 | Question Q2? | free-text: settled in the ledger",
                "- Q3 | deferred | round 1 | Never posted? | deferred: to planning",
                "- Q4 | open | round 2 | Question Q4? |",
            ]
        )
        before = ledger.read_text(encoding="utf-8")
        rc, out = self.rp("export-ledger", "--diff", str(ledger))
        self.assertEqual(rc, 1, out)
        self.assertIn("Q1 round: kept 'round 1 (design)' (page: 'round 1')", out)
        self.assertIn("Q3: only in the ledger; kept", out)
        self.assertIn("Q2 status: conflict, kept the ledger's 'answered'", out)
        self.assertIn("Q1 status: 'open' -> 'answered'", out)
        self.assertEqual(ledger.read_text(encoding="utf-8"), before)
        merged = self.tmp / "merged.md"
        rc, out = self.rp(
            "export-ledger", "--out", str(merged), "--ledger", str(ledger)
        )
        self.assertEqual(rc, 1, out)
        self.assertIn("conflict", out)
        rows = register_rows(merged)
        self.assertIn("| round 1 (design) |", rows[0])
        self.assertEqual(
            rows[1],
            "- Q2 | answered | round 1 | Question Q2? | free-text: settled in the ledger",
        )
        self.assertEqual(
            rows[2], "- Q3 | deferred | round 1 | Never posted? | deferred: to planning"
        )

    def test_a_page_decision_since_the_ledger_row_is_not_a_conflict(self):
        self.three_of_four()
        ledger = self.ledger(
            [
                "- Q1 | deferred | round 1 | Question Q1? | deferred: later",
                "- Q2 | open | round 1 | Question Q2? |",
                "- Q3 | deferred | round 1 | Never posted? | deferred: to planning",
                "- Q4 | open | round 2 | Question Q4? |",
            ]
        )
        rc, out = self.rp("export-ledger", "--diff", str(ledger))
        self.assertEqual(rc, 1, out)
        self.assertIn("Q1 status: 'deferred' -> 'answered'", out)
        self.assertNotIn("conflict", out)

    def test_sync_ledger_after_apply_rewrites_only_the_register_rows(self):
        self.decided()
        ledger = self.tmp / "checklist.md"
        ledger.write_text(
            self.export("ledger")
            .read_text(encoding="utf-8")
            .replace(
                "## Open-question register\n\n",
                "## Open-question register\n\nRows are written by sync-ledger.\n\n",
            ),
            encoding="utf-8",
        )
        tree = ledger.read_text(encoding="utf-8").split("## Open-question register")[0]
        ops = self.tmp / "ops.json"
        ops.write_text(
            json.dumps(
                {
                    "ops": [
                        {
                            "op": "record-terminal",
                            "id": "Q3",
                            "decision": "defer",
                            "text": "later",
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        rc, out = self.rp("apply", "--file", str(ops))
        self.assertEqual(rc, 0, out)
        rc, out = self.rp("sync-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        text = ledger.read_text(encoding="utf-8")
        self.assertEqual(register_rows(ledger), register_rows(self.export("ledger")))
        self.assertIn(" | deferred | ", register_rows(ledger)[2])
        self.assertIn("Rows are written by sync-ledger.\n\n- Q1 |", text)
        self.assertEqual(text.split("## Open-question register")[0], tree)
        rc, out = self.rp("export-ledger", "--diff", str(ledger))
        self.assertEqual(rc, 0, out)

    def test_a_ledger_answer_after_an_import_is_a_conflict_the_sync_keeps(self):
        seed = [
            "- Q1 | deferred | round 1 | Later? | deferred: to planning",
            "- Q2 | open | round 1 | Held? | hold:: user checking the tracker",
        ]
        rc, out = self.rp("import-ledger", "--ledger", str(self.ledger(seed)))
        self.assertEqual(rc, 0, out)
        answered = [
            "- Q1 | answered | round 1 | Later? | free-text: decided after all",
            "- Q2 | answered | round 1 | Held? | free-text: the tracker says yes",
        ]
        ledger = self.ledger(answered)
        rc, out = self.rp("export-ledger", "--diff", str(ledger))
        self.assertEqual(rc, 1, out)
        self.assertIn("Q1 status: conflict, kept the ledger's 'answered'", out)
        self.assertIn("Q2 status: conflict, kept the ledger's 'answered'", out)
        rc, out = self.rp("sync-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 1, out)
        self.assertEqual(register_rows(ledger), answered)

    def test_sync_ledger_keeps_crlf_line_endings(self):
        self.decided()
        ledger = self.tmp / "crlf.md"
        text = self.export("ledger").read_text(encoding="utf-8")
        ledger.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))
        rc, out = self.rp("sync-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 0, out)
        data = ledger.read_bytes()
        self.assertEqual(data, text.replace("\n", "\r\n").encode("utf-8"))

    def test_sync_ledger_refuses_two_registers(self):
        self.decided()
        ledger = self.ledger(["- Q1 | open | round 1 | Question Q1? |"])
        ledger.write_text(
            ledger.read_text(encoding="utf-8") + "\n## Open-question register\n",
            encoding="utf-8",
        )
        rc, out = self.rp("sync-ledger", "--ledger", str(ledger))
        self.assertNotEqual(rc, 0, out)
        self.assertIn("2 open-question register headings", out)


class TestNoEmojiNoSkillNames(SessionCase):
    def test_outputs_carry_no_emoji(self):
        self.decided()
        for what in ("ledger", "brief", "report"):
            text = self.export(what).read_text(encoding="utf-8")
            self.assertFalse(re.search("[\U0001f300-\U0001faff☀-➿]", text), what)


if __name__ == "__main__":
    unittest.main()
