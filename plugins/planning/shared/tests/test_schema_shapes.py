# test-scope: plugins/planning/shared/schema/*.schema.json
# test-scope: plugins/planning/shared/tests/fixtures/*.json
# test-scope: plugins/planning/shared/session.py plugins/planning/skills/interview/context/question-shape.md
"""The shared session schemas accept the sample files and refuse the shapes the contract forbids."""

from __future__ import annotations

import copy
import json
import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHARED = HERE.parent
SCHEMA_DIR = SHARED / "schema"
FIXTURES = HERE / "fixtures"
SURFACE = SHARED.parent / "surface"
QUESTION_SHAPE_DOC = SHARED.parent / "skills" / "interview" / "context" / "question-shape.md"
# Appended, as session.py does: prepended, surface/test_server.py would shadow ours at discovery.
if str(SURFACE) not in sys.path:
    sys.path.append(str(SURFACE))

import schema  # noqa: E402

if str(SHARED) not in sys.path:
    sys.path.insert(0, str(SHARED))
import session  # noqa: E402

STATE = schema.load("state", SCHEMA_DIR)
OPS = schema.load("ops", SCHEMA_DIR)
EVENT = schema.load("event", SCHEMA_DIR)
SHAPE = schema.load("question-shape", SCHEMA_DIR)
WIRE = schema.load("wire", SCHEMA_DIR)


def fixture(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def question_error(question):
    return schema.first_error(question, STATE["$defs"]["question"], "$", STATE)


def wire_error(body, shape):
    return schema.first_error(body, WIRE["$defs"][shape], "$", WIRE)


def question(qid):
    return copy.deepcopy(next(q for q in fixture("state-full.json")["questions"] if q["id"] == qid))


class TestSchemaDirectory(unittest.TestCase):
    def test_each_directory_loads_its_own_schema_of_one_name(self):
        self.assertTrue(schema.load("ops")["$id"].endswith("/planning/surface/ops"))
        self.assertTrue(OPS["$id"].endswith("/planning/shared/ops"))


class TestValidSamples(unittest.TestCase):
    def test_full_session_file_is_valid(self):
        self.assertIsNone(schema.first_error(fixture("state-full.json"), STATE))

    def test_every_event_kind_is_valid(self):
        events = fixture("state-full.json")["log"]["events"] + fixture("events-v1.json")
        for event in events:
            self.assertIsNone(schema.first_error(event, EVENT), event["kind"])
        kinds = {e["kind"] for e in events}
        self.assertEqual(
            kinds,
            {
                "round-sent",
                "round-cancelled",
                "round-reset",
                "request-run",
                "request-cancelled",
                "session-ended",
                "upload-received",
                "upload-removed",
                "report-filed",
                "person-joined",
            },
        )

    def test_ops_samples_are_valid(self):
        for name in ("ops-open-round.json", "ops-result.json", "ops-handle.json"):
            self.assertIsNone(schema.first_error(fixture(name), OPS), name)

    def test_question_shape_fields_of_a_question_are_a_valid_shape(self):
        q = fixture("state-full.json")["questions"][0]
        shape = {k: v for k, v in q.items() if k in SHAPE["properties"]}
        self.assertIsNone(schema.first_error(shape, SHAPE))


class TestOptionCounts(unittest.TestCase):
    """question-shape.md's format table, session.py OPTION_COUNTS, the ops input bounds and the
    stored bounds state one option count per format: stored adds Something else, and on a multi
    question None of these."""

    WORDS = {"two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8}

    def doc_counts(self):
        rows = {}
        for kind, least, most in re.findall(
            r"^\| `(choice|multi|rank)` \|.*?\b(\w+) to (\w+) options",
            QUESTION_SHAPE_DOC.read_text(encoding="utf-8"),
            re.MULTILINE,
        ):
            rows[kind] = (self.WORDS[least], self.WORDS[most])
        return rows

    def bounds(self, fmt):
        return {
            b["properties"]["kind"]["enum"][0]: (b["properties"]["options"]["minItems"], b["properties"]["options"]["maxItems"])
            for b in fmt["oneOf"]
            if "options" in b.get("properties", {})
        }

    def test_the_doc_table_is_option_counts_and_the_ops_input_bounds(self):
        self.assertEqual(self.doc_counts(), session.OPTION_COUNTS)
        self.assertEqual(self.bounds(OPS["$defs"]["format"]), session.OPTION_COUNTS)

    def test_stored_bounds_add_the_server_options(self):
        added = {kind: 1 + (kind == "multi") for kind in session.OPTION_COUNTS}
        self.assertEqual(
            self.bounds(STATE["$defs"]["format"]),
            {kind: (least + 1, most + added[kind]) for kind, (least, most) in session.OPTION_COUNTS.items()},
        )


class TestRefusedShapes(unittest.TestCase):
    def test_recommendation_on_a_choice_question(self):
        q = fixture("invalid-recommendation-on-choice.json")
        self.assertIn("$.recommendation", question_error(q))
        del q["recommendation"]
        self.assertIsNone(question_error(q))

    def test_recommendation_on_a_host_question(self):
        q = fixture("state-full.json")["questions"][0]
        self.assertIsNone(question_error(q))
        q["origin"] = {"kind": "host", "proposal": "P2", "by": "host"}
        self.assertIn("$.recommendation", question_error(q))

    def test_device_scope_on_a_prototype_question(self):
        q = fixture("invalid-device-scope-on-prototype.json")
        self.assertIn("$.answerScope", question_error(q))
        q["answerScope"] = "person"
        self.assertIsNone(question_error(q))

    def test_old_reaction_value_agree(self):
        state = fixture("state-full.json")
        state["reactions"] = fixture("invalid-reaction-agree.json")
        self.assertIn(
            "'agree' is not one of ['thumbs', 'down', 'heart', 'idea']",
            schema.first_error(state, STATE),
        )
        state["reactions"]["Q5"]["p:aB3dE5fG7hJ9:computer"]["kL1mN3pQ5rS7"] = ["heart", "thumbs"]
        self.assertIsNone(schema.first_error(state, STATE))

    def test_a_reaction_held_as_one_value_not_a_list(self):
        state = fixture("state-full.json")
        state["reactions"]["Q5"]["p:aB3dE5fG7hJ9:computer"]["kL1mN3pQ5rS7"] = "thumbs"  # one value, as an earlier build held it
        self.assertIn("kL1mN3pQ5rS7", schema.first_error(state, STATE))
        state["reactions"]["Q5"]["p:aB3dE5fG7hJ9:computer"]["kL1mN3pQ5rS7"] = []
        self.assertIn("needs at least 1 items", schema.first_error(state, STATE))

    def test_result_needs_published(self):
        state = fixture("state-full.json")
        del state["results"]["Q1"][0]["published"]
        self.assertIn("missing required 'published'", schema.first_error(state, STATE))

    def test_op_with_an_unknown_tag(self):
        ops = copy.deepcopy(fixture("ops-handle.json"))
        ops["ops"].append({"op": "drop-session"})
        self.assertIn("$.ops[2]", schema.first_error(ops, OPS))

    def test_set_repo_op_and_the_sessions_repo_fields(self):
        sha = "0123456789abcdef0123456789abcdef01234567"
        self.assertIsNone(schema.first_error({"ops": [{"op": "set-repo", "repo": "octo-org/demo", "commit": sha}]}, OPS))
        self.assertIsNone(schema.first_error({"ops": [{"op": "set-repo", "repo": ""}]}, OPS))
        self.assertIn("$.ops[0]", schema.first_error({"ops": [{"op": "set-repo", "commit": sha}]}, OPS))
        self.assertIn("$.ops[0]", schema.first_error({"ops": [{"op": "set-repo", "repo": "a/b", "branch": "main"}]}, OPS))
        state = fixture("state-full.json")
        self.assertNotIn("repo", state["session"])  # a state without the fields stays valid
        state["session"].update(repo="octo-org/demo", commit=sha)
        self.assertIsNone(schema.first_error(state, STATE))
        state["session"]["branch"] = "main"
        self.assertIn("unexpected property 'branch'", schema.first_error(state, STATE))

    def test_question_input_keeps_the_question_rules(self):
        ops = fixture("ops-open-round.json")
        ops["ops"][0]["questions"][1]["recommendation"] = "Standard."
        self.assertIn("$.ops[0]", schema.first_error(ops, OPS))


class TestFormatsReactionsPresence(unittest.TestCase):
    """The amendment's shapes (Reactions and formats; Presence), each with a sample and a refusal."""

    def test_down_is_a_reaction_and_the_digest_counts_all_four(self):
        state = fixture("state-full.json")
        self.assertEqual(state["reactions"]["Q5"]["p:kL1mN3pQ5rS7:phone"]["host"], ["down"])
        counts = {"thumbs": 0, "heart": 0, "idea": 0}
        self.assertIn("missing required 'down'", schema.first_error(counts, EVENT["$defs"]["reactionCounts"], "$", EVENT))
        self.assertIsNone(schema.first_error({**counts, "down": 1}, EVENT["$defs"]["reactionCounts"], "$", EVENT))

    def test_a_multi_question_takes_two_or_more_options(self):
        q = question("Q6")
        self.assertIsNone(question_error(q))
        q["format"]["options"] = q["format"]["options"][:1]
        self.assertIn("$.format", question_error(q))

    def test_a_scale_runs_from_1_to_between_3_and_10_with_end_labels(self):
        q = question("Q7")
        self.assertIsNone(question_error(q))
        for bad in ({"max": 2}, {"max": 11}, {"min": 0}, {"labels": {"min": "Never"}}):
            with self.subTest(bad=bad):
                self.assertIn("$.format", question_error({**q, "format": {**q["format"], **bad}}))

    def test_a_rank_takes_three_or_more_options(self):
        q = question("Q8")
        self.assertIsNone(question_error(q))
        q["format"]["options"] = q["format"]["options"][:2]
        self.assertIn("$.format", question_error(q))

    def test_the_something_else_option_is_flagged_true_or_not_at_all(self):
        q = question("Q2")
        self.assertEqual(q["format"]["options"][-1], {"id": "other", "label": "Something else…", "other": True})
        q["format"]["options"][-1]["other"] = False
        self.assertIn("$.format", question_error(q))

    def test_a_diagram_reference_needs_alt_text(self):
        q = question("Q8")
        self.assertEqual(q["references"][0]["kind"], "diagram")
        del q["references"][0]["alt"]
        self.assertIn("$.references[0]", question_error(q))

    def test_multi_scale_and_rank_take_one_answer_per_person_not_per_device(self):
        for qid in ("Q6", "Q7", "Q8"):
            with self.subTest(qid=qid):
                self.assertIn("$.answerScope", question_error({**question(qid), "answerScope": "device"}))

    def test_a_disagreement_needs_a_reason_of_at_most_200_characters(self):
        state = fixture("state-full.json")
        self.assertIsNone(schema.first_error(state, STATE))
        d = state["disagreements"]["Q8"][0]
        d["reason"] = "x" * 201
        self.assertIn("allows at most 200 characters", schema.first_error(state, STATE))
        del d["reason"]
        self.assertIn("missing required 'reason'", schema.first_error(state, STATE))

    def test_prototype_tiers_is_an_optional_list_of_the_three_views(self):
        state = fixture("state-full.json")
        self.assertNotIn("prototypeTiers", state["session"]["settings"])  # a file from before it stays valid
        self.assertIsNone(schema.first_error(state, STATE))
        for ok in ([], ["screenshot"], ["screenshot", "snapshot", "live"]):
            state["session"]["settings"]["prototypeTiers"] = ok
            self.assertIsNone(schema.first_error(state, STATE), ok)
        for bad in (["video"], "live", ["screenshot", "snapshot", "live", "live"]):
            state["session"]["settings"]["prototypeTiers"] = bad
            self.assertIsNotNone(schema.first_error(state, STATE), bad)

    def test_a_variant_shows_shots_a_snapshot_or_an_earlier_asset_and_a_prototype_may_say_where_to_look(self):
        q = question("Q4")
        self.assertNotIn("lookAt", q["format"])  # a question from before the look-at line stays valid
        self.assertIsNone(question_error(q))
        v = {"id": "v-1", "label": "Flow"}
        for ok in ({"shots": ["0123456789abcdef.png"]}, {"shots": ["0123456789abcdef.png"] * 4, "snapshot": "fedcba9876543210.html"},
                   {"live": {"id": "L1", "path": "/?variant=A"}}, {"shots": ["0123456789abcdef.png"], "live": {"id": "L2", "path": "/"}},
                   {"snapshot": "fedcba9876543210.html", "lookAt": "Step two."}, {"asset": "fedcba9876543210.html"}):
            q["format"] = {"kind": "prototype", "lookAt": "The basket.", "variants": [{**v, **ok}, {**v, "id": "v-2", "asset": "0123456789abcdef.png"}]}
            self.assertIsNone(question_error(q), ok)
        for bad in ({}, {"asset": "0123456789abcdef.png", "shots": ["0123456789abcdef.png"]}, {"shots": []}, {"shots": ["0123456789abcdef.png"] * 5},
                    {"asset": "0123456789abcdef.png", "live": {"id": "L1", "path": "/"}}, {"live": {"id": "L1"}}, {"live": {"id": "L1", "path": "/", "url": "https://a.example"}},
                    {"snapshot": "fedcba9876543210.html", "lookAt": "x" * 201}):
            q["format"] = {"kind": "prototype", "variants": [{**v, **bad}, {**v, "id": "v-2", "asset": "0123456789abcdef.png"}]}
            self.assertIn("$.format", question_error(q), bad)
        q["format"] = {"kind": "prototype", "lookAt": "x" * 201, "variants": [{**v, "asset": "0123456789abcdef.png"}, {**v, "id": "v-2", "asset": "0123456789abcdef.png"}]}
        self.assertIn("$.format", question_error(q))

    def test_lives_is_an_optional_list_of_live_entries(self):
        state = fixture("state-full.json")
        self.assertNotIn("lives", state)  # a file from before it stays valid
        self.assertIsNone(schema.first_error(state, STATE))
        folder, port = {"kind": "folder", "folder": "staging/r1/live"}, {"kind": "port", "port": 5173}
        entry = {"id": "L1", "label": "Checkout app", "target": folder, "at": 1.0, "status": {"kind": "pending"}}
        oks = [
            entry,
            {**entry, "id": "L2", "target": port, "note": "Sample data only.", "status": {"kind": "starting", "approvedAt": 2.0, "attested": True}},
            {**entry, "id": "L3", "status": {"kind": "running", "approvedAt": 2.0, "startedAt": 3.0, "url": "https://quiet-fox.trycloudflare.com"}},
            {**entry, "id": "L4", "status": {"kind": "ended", "endedAt": 4.0, "reason": "session-ended", "approvedAt": 2.0}},
            {**entry, "id": "L5", "status": {"kind": "ended", "endedAt": 4.0, "reason": "failed", "approvedAt": 2.0}},
        ]
        state["lives"] = oks
        self.assertIsNone(schema.first_error(state, STATE))
        bads = [
            {**entry, "status": {"kind": "running", "approvedAt": 2.0, "startedAt": 3.0}},  # running needs its url
            {**entry, "status": {"kind": "pending", "url": "https://a.example"}},  # only a running entry holds a url
            {**entry, "status": {"kind": "ended", "endedAt": 4.0, "reason": "stopped", "url": "https://a.example"}},
            {**entry, "status": {"kind": "ended", "endedAt": 4.0, "reason": "crashed"}},
            {**entry, "target": {"kind": "port", "port": 70000}},
            {**entry, "target": {"kind": "url", "url": "https://hosted.example"}},  # no external links
            {**entry, "url": "https://a.example"},
            {k: v for k, v in entry.items() if k != "target"},
        ]
        for bad in bads:
            state["lives"] = [bad]
            self.assertIsNotNone(schema.first_error(state, STATE), bad)

    def test_add_live_takes_a_folder_or_a_port_and_never_a_url(self):
        for ok in ({"op": "add-live", "label": "App", "folder": "/data/staging/r1/live"}, {"op": "add-live", "label": "App", "port": 5173, "note": "Vite."}):
            self.assertIsNone(schema.first_error({"ops": [ok]}, OPS), ok)
        for bad in ({"op": "add-live", "label": "App"}, {"op": "add-live", "label": "App", "folder": "/x", "port": 5173},
                    {"op": "add-live", "label": "App", "url": "https://hosted.example"}, {"op": "add-live", "folder": "/x"},
                    {"op": "add-live", "label": "App", "port": 0}):
            self.assertIsNotNone(schema.first_error({"ops": [bad]}, OPS), bad)

    def test_a_guests_live_entry_carries_a_url_only_while_it_runs(self):
        for ok in ({"id": "L1", "label": "App", "status": {"kind": "pending"}}, {"id": "L1", "label": "App", "status": {"kind": "ended"}},
                   {"id": "L1", "label": "App", "status": {"kind": "running"}, "url": "https://quiet-fox.trycloudflare.com"}):
            self.assertIsNone(wire_error(ok, "live"), ok)
        for bad in ({"id": "L1", "label": "App", "status": {"kind": "pending"}, "url": "https://a.example"},
                    {"id": "L1", "label": "App", "status": {"kind": "running"}},
                    {"id": "L1", "label": "App", "status": {"kind": "pending"}, "target": {"kind": "port", "port": 5173}}):
            self.assertIsNotNone(wire_error(bad, "live"), bad)

    def test_a_file_from_before_disagreements_is_still_valid(self):
        state = fixture("state-full.json")
        del state["disagreements"]
        self.assertIsNone(schema.first_error(state, STATE))

    def test_a_report_holds_text_its_page_context_and_a_status_of_open_seen_or_resolved(self):
        state = fixture("state-full.json")
        ctx = {"view": "focus", "device": "phone", "browser": "safari", "viewport": {"w": 390, "h": 844}, "errors": []}
        state["reports"] = {"F1": {"by": "host", "text": "Send does nothing", "ctx": ctx, "image": "reports/F1.png", "status": "open", "ts": 1.0}}
        state["session"]["seq"]["F"] = 1
        self.assertIsNone(schema.first_error(state, STATE))
        more = copy.deepcopy(state)  # four pictures sent with it: the first at image, the rest at moreImages
        more["reports"]["F1"]["moreImages"] = ["reports/F1-p2.png", "reports/F1-p3.jpg", "reports/F1-p4.webp"]
        self.assertIsNone(schema.first_error(more, STATE))
        for bad, want in ((lambda r: r.update(status="closed"), "'closed' is not one of"), (lambda r: r["ctx"].update(answer="x"), "'answer'"),
                          (lambda r: r.pop("text"), "missing required 'text'"), (lambda r: r["ctx"].update(errors=["e"] * 6), "at most 5"),
                          (lambda r: r.update(moreImages=[f"reports/F1-p{n}.png" for n in range(2, 6)]), "at most 3")):
            with self.subTest(want=want):
                broken = copy.deepcopy(state)
                bad(broken["reports"]["F1"])
                self.assertIn(want, schema.first_error(broken, STATE) or "")

    def test_heartbeat_samples_are_valid_and_their_fields_typed(self):
        for body in fixture("wire-heartbeat.json"):
            self.assertIsNone(wire_error(body, "heartbeat"), body)
        for bad in ({"visible": "yes"}, {"lastInput": -1}, {"away": 1}, {"pid": "host"}):
            with self.subTest(bad=bad):
                self.assertIsNotNone(wire_error(bad, "heartbeat"))

    def test_presence_samples_are_valid_and_the_state_is_active_or_away(self):
        for entry in fixture("wire-presence.json"):
            self.assertIsNone(wire_error(entry, "presence"), entry)
        entry = fixture("wire-presence.json")[0]
        self.assertIn("'offline' is not one of ['active', 'away']", wire_error({**entry, "state": "offline"}, "presence"))


if __name__ == "__main__":
    unittest.main()
