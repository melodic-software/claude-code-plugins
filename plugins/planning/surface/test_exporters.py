"""Tests for the exporters and import-ledger (AC27 to AC29), driven through round.py's CLI.

Sessions are built in temporary data dirs: questions.json written directly, responses.json
derived from a hand-written event log with the server's own rebuild function. The ledger and
Brief outputs are graded by the plugin's `scripts/check-open-questions.sh`.
"""

from __future__ import annotations

import base64
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
        self.assertNotIn("superseded-by-plan", text)

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


class TestReportFileVisuals(SessionCase):
    SVG = "<svg xmlns='http://www.w3.org/2000/svg'><text>filemark</text></svg>"
    PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452")

    def report(self, *visuals):
        self.session(
            [question("Q1", visuals=list(visuals))], [event(1, "Q1", "accept")]
        )
        return self.export("report").read_text(encoding="utf-8")

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

    def test_import_refuses_a_dir_with_questions(self):
        self.decided()
        ledger = self.export("ledger")
        rc, _ = self.rp("import-ledger", "--ledger", str(ledger))
        self.assertEqual(rc, 1)


class TestSupersededByPlan(SessionCase):
    """AC10: the non-terminal superseded-by-plan status round-trips through the page."""

    RES = "plan proposes: admin only; was: any enrolled user"

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
            ("superseded-by-plan", self.RES, "", False),
        )
        page = {"Q2": {"decision": "accept", "updatedAt": AT}}
        self.assertEqual(exporters.settle(q, page, [], seed)[0], "answered")

    def test_ledger_leaves_it_unticked_and_the_gate_blocks(self):
        self.seed()
        ledger = self.export("ledger")
        text = ledger.read_text(encoding="utf-8")
        self.assertIn("- [x] Q1 ", text)
        self.assertIn("- [ ] Q2 ", text)
        self.assertIn(
            f"- Q2 | superseded-by-plan | round 1 | Who writes? | {self.RES}", text
        )
        rc, out = self.check("--ledger", ledger)
        self.assertEqual(rc, 1, out)
        self.assertIn("superseded=1", out)
        self.assertIn("status=open", out)

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

    def respond(self, events):
        responses, history = rebuild_responses(events)
        (self.dir / "responses.json").write_text(
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
        return register_rows(self.export("ledger"))

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
        self.assertRegex(
            rows[1],
            r"^- Q2 \| answered \| .*"
            r"reconfirmed at plan approval: admin only; was: any enrolled user$",
        )

    def test_page_accept_reconfirm_keeps_the_note(self):
        self.seed()
        rows = self.respond([event(1, "Q2", "accept", text="fine")])
        self.assertRegex(
            rows[1],
            r"reconfirmed at plan approval: admin only; was: any enrolled user; note: fine$",
        )

    def test_page_defer_keeps_it_superseded(self):
        seed = {"Q2": {"status": "superseded-by-plan", "resolution": self.RES}}
        q = question("Q2")
        page = {"Q2": {"decision": "defer", "text": "ask later", "updatedAt": AT}}
        self.assertEqual(
            exporters.settle(q, page, [], seed),
            (
                "superseded-by-plan",
                f"{self.RES}; deferred on page: ask later",
                "ask later",
                False,
            ),
        )
        bare = {"Q2": {"decision": "defer", "updatedAt": AT}}
        self.assertEqual(
            exporters.settle(q, bare, [], seed),
            ("superseded-by-plan", self.RES, "", False),
        )

    def test_page_defer_leaves_the_ledger_row_superseded_and_the_gate_blocks(self):
        self.seed()
        rows = self.respond([event(1, "Q2", "defer", text="ask later")])
        self.assertIn("| superseded-by-plan | ", rows[1])
        self.assertIn(f"{self.RES}; deferred on page: ask later", rows[1])
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


class TestNoEmojiNoSkillNames(SessionCase):
    def test_outputs_carry_no_emoji(self):
        self.decided()
        for what in ("ledger", "brief", "report"):
            text = self.export(what).read_text(encoding="utf-8")
            self.assertFalse(re.search("[\U0001f300-\U0001faff☀-➿]", text), what)


if __name__ == "__main__":
    unittest.main()
