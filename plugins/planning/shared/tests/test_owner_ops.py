# test-scope: plugins/planning/shared/session.py plugins/planning/shared/schema/ops.schema.json plugins/planning/shared/schema/state.schema.json
"""Claude's resolve-report, share-result and take-down-result ops act as the owner's page does, and a prototype
question an op writes keeps the prototype rules.

Expected values come from the owner routes' contract (act_on_report, share_result, the takedown
action): their status codes, error codes and the notices the reporter or asker reads.
"""

from __future__ import annotations

import test_session as ts

HOST = ts.HOST


class OwnerOpsCase(ts.SessionCase):
    def setUp(self):
        super().setUp()
        self.s.update_settings(HOST, {"reviewAnswers": True})
        self.ann, self.bo = self.people("Ann", "Bo")
        self.open_round(ts.text_q("Q1"))

    def report(self, pid):
        self.clock.tick(ts.session.REPORT_INTERVAL)
        return self.s.report(pid, {"text": "Send does nothing", "ctx": ts.CTX})["id"]

    def held_result(self):
        """Ann's research request, run by the owner and answered by Claude: held for the owner's Share."""
        rid = self.act(
            "request",
            self.ann,
            {"qid": "Q1", "kind": "research", "text": "How do other shops do it?"},
        )["id"]
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        op = {
            "op": "result",
            "qid": "Q1",
            "request": rid,
            "kind": "research",
            "used": [{"name": "discovery:research", "type": "skill"}],
            "why": "Outside comparison.",
            "summary": "Most shops pin it right.",
            "sources": [{"title": "Patterns", "url": "https://example.com/p"}],
            "report": "Seven of ten.",
        }
        return self.apply(op)["results"][0]["id"]

    def result(self, xid):
        return next(
            r for lst in self.s.state["results"].values() for r in lst if r["id"] == xid
        )

    def refused_at(self, code, http, *ops):
        exc = self.refused_ops(code, *ops)
        self.assertEqual(exc.http, http)
        return exc


class TestResolveReportOp(OwnerOpsCase):
    def test_seen_then_resolved_tell_the_reporter_as_the_owner_route_does(self):
        fid = self.report(self.ann)
        self.assertEqual(
            self.apply({"op": "resolve-report", "id": fid, "action": "seen"}),
            {"results": [{"id": fid, "status": "seen"}]},
        )
        self.assertEqual(
            [n["title"] for n in self.notes(self.ann, "report")],
            ["The host saw your problem report."],
        )
        self.apply({"op": "resolve-report", "id": fid, "action": "resolved"})
        self.assertEqual(self.disk()["reports"][fid]["status"], "resolved")
        self.assertEqual(
            self.notes(self.ann, "report")[-1]["title"],
            "The host marked your problem report resolved.",
        )
        self.refused_at(
            "wrong-status", 409, {"op": "resolve-report", "id": fid, "action": "seen"}
        )

    def test_an_unknown_report_is_not_found_and_nothing_else_in_the_apply_lands(self):
        fid = self.report(self.ann)
        exc = self.refused_at(
            "not-found",
            404,
            {"op": "resolve-report", "id": fid, "action": "resolved"},
            {"op": "resolve-report", "id": "F9", "action": "resolved"},
        )
        self.assertEqual(exc.details["op"], 1)
        self.assertEqual(
            (
                self.s.state["reports"][fid]["status"],
                self.disk()["reports"][fid]["status"],
            ),
            ("open", "open"),
        )
        self.assertEqual(self.notes(self.ann, "report"), [])

    def test_ask_and_any_other_action_are_refused_by_the_schema(self):
        fid = self.report(self.ann)
        for action in ("ask", "open", "Resolved"):
            with self.subTest(action=action):
                self.refused_at(
                    "bad-field",
                    400,
                    {"op": "resolve-report", "id": fid, "action": action},
                )
        self.refused_at("bad-field", 400, {"op": "resolve-report", "id": fid})
        self.assertEqual(
            (self.s.state["reports"][fid]["status"], self.events("report-filed")),
            ("open", []),
        )


class TestShareResultOp(OwnerOpsCase):
    def test_a_held_answer_is_shared_with_everyone_and_its_asker_is_told(self):
        xid = self.held_result()
        self.assertFalse(self.result(xid)["published"])
        self.assertEqual(
            self.apply({"op": "share-result", "id": xid}),
            {"results": [{"id": xid, "published": True}]},
        )
        self.assertTrue(self.result(xid)["published"])
        self.assertIn("Most shops pin it right.", str(self.s.snapshot(self.bo)))
        self.assertIn(
            "Your request on question Q1 is done.",
            [n["title"] for n in self.notes(self.ann, "request")],
        )

    def test_an_unknown_result_is_not_found_and_a_shared_one_is_already_shared(self):
        self.refused_at("not-found", 404, {"op": "share-result", "id": "X99"})
        xid = self.held_result()
        self.apply({"op": "share-result", "id": xid})
        self.refused_at("wrong-status", 409, {"op": "share-result", "id": xid})

    def test_a_malformed_op_is_refused_by_the_schema(self):
        xid = self.held_result()
        self.refused_at("bad-field", 400, {"op": "share-result"})
        self.refused_at(
            "bad-field", 400, {"op": "share-result", "id": xid, "action": "publish"}
        )
        self.assertFalse(self.result(xid)["published"])


class TestTakeDownResultOp(OwnerOpsCase):
    def test_a_shared_answer_is_taken_down_to_its_asker_and_the_owner(self):
        xid = self.held_result()
        self.apply({"op": "share-result", "id": xid})
        self.assertEqual(
            self.apply({"op": "take-down-result", "id": xid}),
            {"results": [{"id": xid, "published": False}]},
        )
        res = self.result(xid)
        self.assertEqual(
            (res["published"], res["private"], "takenDown" in res), (False, True, True)
        )
        self.assertNotIn("Most shops pin it right.", str(self.s.snapshot(self.bo)))
        self.assertIn("Most shops pin it right.", str(self.s.snapshot(self.ann)))
        self.assertIn(
            "The answer to your request on question Q1 was taken down.",
            [n["title"] for n in self.notes(self.ann, "request")],
        )

    def test_an_unknown_result_is_not_found_and_an_unshared_one_cannot_be_taken_down(
        self,
    ):
        self.refused_at("not-found", 404, {"op": "take-down-result", "id": "X99"})
        xid = self.held_result()
        self.refused_at("wrong-status", 409, {"op": "take-down-result", "id": xid})

    def test_a_malformed_op_is_refused_by_the_schema(self):
        xid = self.held_result()
        self.apply({"op": "share-result", "id": xid})
        self.refused_at("bad-field", 400, {"op": "take-down-result"})
        self.refused_at(
            "bad-field",
            400,
            {"op": "take-down-result", "id": xid, "action": "takedown"},
        )
        self.assertTrue(self.result(xid)["published"])


class TestPrototypeQuestionOps(OwnerOpsCase):
    """A prototype question an op writes (open-round, make-question-from) says where to look (`format.lookAt`) and
    gives every variant at least one view (`shots`, `snapshot`, or the earlier `asset`); a refusal lands no op of the
    apply."""

    VIEWS = ({"id": "v-1", "label": "One page", "shots": [ts.PNG]}, {"id": "v-2", "label": "Two steps", "snapshot": ts.HTML})

    def proto(self, qid, *variants, look=ts.LOOK):
        fmt = {"kind": "prototype", **({"lookAt": look} if look else {}), "variants": list(variants or self.VIEWS)}
        return {**ts.text_q(qid, rec=False), "format": fmt}

    def test_open_round_refuses_no_look_at_line_or_a_variant_with_no_view_and_lands_nothing(self):
        self.send()
        self.ack(1)
        before = self.disk()
        rename = {"op": "set-title", "title": "Renamed"}
        for why, q in (("no look-at line", self.proto("Q2", look=None)), ("a variant with no view", self.proto("Q2", {"id": "v-1", "label": "One page"}, self.VIEWS[1]))):
            with self.subTest(why):
                self.refused_at("bad-field", 400, rename, {"op": "open-round", "questions": [q]})
        self.assertEqual(self.disk(), before)
        self.apply({"op": "open-round", "questions": [self.proto("Q2")]})
        fmt = self.question("Q2")["format"]
        self.assertEqual((fmt["lookAt"], fmt["variants"]), (ts.LOOK, [{"id": "v-1", "label": "One page", "asset": ts.PNG}, {"id": "v-2", "label": "Two steps", "asset": ts.HTML}]))

    def test_make_question_from_refuses_a_prototype_with_no_look_at_line(self):
        prop = self.act("propose", self.bo, {"text": "Show the one-page checkout"})["id"]
        self.refused_at("bad-field", 400, {"op": "make-question-from", "proposal": prop, "question": self.proto("Q20", look=None)})
        self.apply({"op": "make-question-from", "proposal": prop, "question": self.proto("Q20")})
        self.assertEqual(self.question("Q20")["format"]["lookAt"], ts.LOOK)
