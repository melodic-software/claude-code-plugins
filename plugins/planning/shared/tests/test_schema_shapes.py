# test-scope: plugins/planning/shared/schema/*.schema.json
# test-scope: plugins/planning/shared/tests/fixtures/*.json
"""The shared session schemas accept the sample files and refuse the shapes the contract forbids."""

from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHARED = HERE.parent
SCHEMA_DIR = SHARED / "schema"
FIXTURES = HERE / "fixtures"
SURFACE = SHARED.parent / "surface"
# Appended, as session.py does: prepended, surface/test_server.py would shadow ours at discovery.
if str(SURFACE) not in sys.path:
    sys.path.append(str(SURFACE))

import schema  # noqa: E402

STATE = schema.load("state", SCHEMA_DIR)
OPS = schema.load("ops", SCHEMA_DIR)
EVENT = schema.load("event", SCHEMA_DIR)
SHAPE = schema.load("question-shape", SCHEMA_DIR)


def fixture(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def question_error(question):
    return schema.first_error(question, STATE["$defs"]["question"], "$", STATE)


class TestSchemaDirectory(unittest.TestCase):
    def test_each_directory_loads_its_own_schema_of_one_name(self):
        self.assertTrue(schema.load("ops")["$id"].endswith("/planning/surface/ops"))
        self.assertTrue(OPS["$id"].endswith("/planning/shared/ops"))


class TestValidSamples(unittest.TestCase):
    def test_full_session_file_is_valid(self):
        self.assertIsNone(schema.first_error(fixture("state-v1.json"), STATE))

    def test_every_event_kind_is_valid(self):
        events = fixture("state-v1.json")["log"]["events"] + fixture("events-v1.json")
        for event in events:
            self.assertIsNone(schema.first_error(event, EVENT), event["kind"])
        kinds = {e["kind"] for e in events}
        self.assertEqual(
            kinds,
            {
                "round-sent",
                "round-cancelled",
                "request-run",
                "request-cancelled",
                "session-ended",
                "upload-received",
            },
        )

    def test_ops_samples_are_valid(self):
        for name in ("ops-open-round.json", "ops-result.json", "ops-handle.json"):
            self.assertIsNone(schema.first_error(fixture(name), OPS), name)

    def test_question_shape_fields_of_a_question_are_a_valid_shape(self):
        q = fixture("state-v1.json")["questions"][0]
        shape = {k: v for k, v in q.items() if k in SHAPE["properties"]}
        self.assertIsNone(schema.first_error(shape, SHAPE))


class TestRefusedShapes(unittest.TestCase):
    def test_recommendation_on_a_choice_question(self):
        q = fixture("invalid-recommendation-on-choice.json")
        self.assertIn("$.recommendation", question_error(q))
        del q["recommendation"]
        self.assertIsNone(question_error(q))

    def test_recommendation_on_a_host_question(self):
        q = fixture("state-v1.json")["questions"][0]
        self.assertIsNone(question_error(q))
        q["origin"] = {"kind": "host", "proposal": "P2", "by": "host"}
        self.assertIn("$.recommendation", question_error(q))

    def test_device_scope_on_a_prototype_question(self):
        q = fixture("invalid-device-scope-on-prototype.json")
        self.assertIn("$.answerScope", question_error(q))
        q["answerScope"] = "person"
        self.assertIsNone(question_error(q))

    def test_old_reaction_value_agree(self):
        state = fixture("state-v1.json")
        state["reactions"] = fixture("invalid-reaction-agree.json")
        self.assertIn(
            "'agree' is not one of ['thumbs', 'heart', 'idea']",
            schema.first_error(state, STATE),
        )
        state["reactions"]["Q5"]["p:aB3dE5fG7hJ9:computer"]["kL1mN3pQ5rS7"] = "thumbs"
        self.assertIsNone(schema.first_error(state, STATE))

    def test_result_needs_published(self):
        state = fixture("state-v1.json")
        del state["results"]["Q1"][0]["published"]
        self.assertIn("missing required 'published'", schema.first_error(state, STATE))

    def test_op_with_an_unknown_tag(self):
        ops = copy.deepcopy(fixture("ops-handle.json"))
        ops["ops"].append({"op": "drop-session"})
        self.assertIn("$.ops[2]", schema.first_error(ops, OPS))

    def test_question_input_keeps_the_question_rules(self):
        ops = fixture("ops-open-round.json")
        ops["ops"][0]["questions"][1]["recommendation"] = "Standard."
        self.assertIn("$.ops[0]", schema.first_error(ops, OPS))


if __name__ == "__main__":
    unittest.main()
