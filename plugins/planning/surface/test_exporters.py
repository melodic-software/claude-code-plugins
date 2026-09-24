"""Tests for the exporters and import-ledger (AC27 to AC29), driven through round.py's CLI.

Sessions are built in temporary data dirs: questions.json written directly, responses.json
derived from a hand-written event log with the server's own rebuild function. The ledger and
Brief outputs are graded by the plugin's `scripts/check-open-questions.sh`.
"""

from __future__ import annotations

import html.parser
import json
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

    def session(self, questions, events, meta=None):
        doc = {
            "meta": meta or {"title": "Export test", "eyebrow": "surface eyebrow text"},
            "rev": 1,
            "groups": [],
            "questions": questions,
            "visuals": [],
        }
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
        """Q1 accepted with a confirmed commitment, Q2 alt, Q3 own, Q4 archived."""
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
            rows[0], r"^- Q1 \| answered \| round 1 \| Question Q1\? \| accepted: "
        )
        self.assertIn("confirmed: One writer only", rows[0])
        self.assertNotIn("No network", rows[0])
        self.assertIn("alt a: Alt a of Q2", rows[1])
        self.assertIn("free-text: My own words.", rows[2])
        self.assertRegex(rows[3], r"^- Q4 \| withdrawn \| .*Off the chosen path\.")
        self.assertIn("**Decision tree:**", text)
        self.assertLess(
            text.index("**Decision tree:**"), text.index("## Open-question register")
        )
        self.assertIn("### Deferred questions", text)
        self.assertNotIn("surface eyebrow text", text)

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
            event(1, "Q1", "accept"),
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

    def test_confirmed_commitment_is_an_assumption_and_archived_is_out_of_scope(self):
        self.decided()
        text = self.export("brief").read_text(encoding="utf-8")
        assumptions = text.split("### Captured assumptions")[1].split("###")[0]
        self.assertIn("One writer only", assumptions)
        self.assertIn("risk: No network (unconfirmed)", assumptions)
        scope = text.split("### Out-of-scope")[1].split("###")[0]
        self.assertIn("Off the chosen path.", scope)


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

    def test_import_refuses_a_dir_with_questions(self):
        self.decided()
        ledger = self.export("ledger")
        rc, _ = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 1)


class TestNoEmojiNoSkillNames(SessionCase):
    def test_outputs_carry_no_emoji(self):
        self.decided()
        for what in ("ledger", "brief", "report"):
            text = self.export(what).read_text(encoding="utf-8")
            self.assertFalse(re.search("[\U0001f300-\U0001faff☀-➿]", text), what)


if __name__ == "__main__":
    unittest.main()
