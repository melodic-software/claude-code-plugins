"""Tests for schema.py, the stdlib JSON Schema subset round.py validates with."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import schema  # noqa: E402

FIXTURES = HERE / "tests" / "fixtures"


class TestKeywords(unittest.TestCase):
    def err(self, inst, s):
        return schema.first_error(inst, s)

    def test_type(self):
        self.assertIsNone(self.err(1, {"type": "integer"}))
        self.assertIn("expected integer", self.err(True, {"type": "integer"}))
        self.assertIsNone(self.err(None, {"type": ["string", "null"]}))

    def test_required_and_properties(self):
        s = {
            "type": "object",
            "required": ["a"],
            "properties": {"a": {"type": "string"}},
        }
        self.assertIn("missing required 'a'", self.err({}, s))
        self.assertIn("$.a", self.err({"a": 1}, s))

    def test_enum(self):
        self.assertIsNone(self.err("x", {"enum": ["x", None]}))
        self.assertIn("not one of", self.err("y", {"enum": ["x"]}))

    def test_additional_properties(self):
        self.assertIn(
            "unexpected property 'b'",
            self.err({"b": 1}, {"additionalProperties": False}),
        )
        s = {"additionalProperties": {"type": "string"}}
        self.assertIn("$.b", self.err({"b": 1}, s))

    def test_items_and_min_items(self):
        s = {"type": "array", "minItems": 1, "items": {"type": "string"}}
        self.assertIn("at least 1", self.err([], s))
        self.assertIn("$[1]", self.err(["a", 2], s))

    def test_max_items(self):
        s = {"type": "array", "maxItems": 2}
        self.assertIsNone(self.err(["a", "b"], s))
        self.assertIn("at most 2", self.err(["a", "b", "c"], s))

    def test_one_any_all_of(self):
        one = {"oneOf": [{"required": ["a"]}, {"required": ["b"]}]}
        self.assertIsNone(self.err({"a": 1}, one))
        self.assertIn("2 branches match", self.err({"a": 1, "b": 2}, one))
        self.assertIn("oneOf", self.err({}, one))
        self.assertIn("anyOf", self.err(1, {"anyOf": [{"type": "string"}]}))
        self.assertIsNotNone(
            self.err(1, {"allOf": [{"type": "integer"}, {"enum": [2]}]})
        )

    def test_ref_by_id_and_defs(self):
        self.assertIsNone(
            self.err(
                {"id": "v", "format": "svg", "content": "x"},
                {"$ref": schema.load("visual")["$id"]},
            )
        )
        self.assertIsNotNone(
            self.err({"id": "v", "content": "x"}, schema.load("visual"))
        )


class TestShippedSchemas(unittest.TestCase):
    def test_v21_sample_files_without_schema_version_validate(self):
        for name in ("questions", "responses"):
            doc = json.loads((FIXTURES / f"{name}.json").read_text(encoding="utf-8"))
            self.assertNotIn("schemaVersion", doc)
            self.assertIsNone(schema.first_error(doc, schema.load(name)))

    def test_seeded_row_status_accepts_superseded_by_plan(self):
        doc = json.loads((FIXTURES / "questions.json").read_text(encoding="utf-8"))
        rows = {"Q1": {"status": "superseded-by-plan", "round": 1, "resolution": "r"}}
        doc["meta"]["seededFrom"] = {"at": "t", "rows": rows}
        self.assertIsNone(schema.first_error(doc, schema.load("questions")))
        rows["Q1"]["status"] = "pending"
        self.assertIsNotNone(schema.first_error(doc, schema.load("questions")))

    def test_activity_is_capped_at_200_entries(self):
        doc = json.loads((FIXTURES / "questions.json").read_text(encoding="utf-8"))
        doc["status"] = {"text": "Researching", "at": "t"}
        doc["activity"] = [{"at": "t", "text": "Replied on Q1", "ids": ["Q1"]}] * 200
        self.assertIsNone(schema.first_error(doc, schema.load("questions")))
        doc["activity"].append({"at": "t", "text": "One more"})
        self.assertIn("at most 200", schema.first_error(doc, schema.load("questions")))

    def test_event_kinds_include_confirm(self):
        e = {"seq": 1, "id": "Q1", "kind": "confirm", "alt": "0", "at": "t"}
        self.assertIsNone(schema.first_error(e, schema.load("event")))

    def test_event_kinds_include_confirm_understanding(self):
        e = {
            "seq": 1,
            "id": None,
            "kind": "confirm-understanding",
            "alt": "off",
            "text": "Goal is wrong",
            "at": "t",
            "contentRev": 2,
        }
        self.assertIsNone(schema.first_error(e, schema.load("event")))

    def test_question_holds_and_restatement_fields(self):
        doc = json.loads((FIXTURES / "questions.json").read_text(encoding="utf-8"))
        q = doc["questions"][0]
        q.update(waiting=True, waitsOn="x", waitingBy="user", setAsideAt="t")
        q["commitsConfirmed"] = [{"index": 0, "reason": "r", "at": "t"}]
        doc["restatement"] = {"rev": 1, "at": "t", "sections": {"goal": "g"}}
        self.assertIsNone(schema.first_error(doc, schema.load("questions")))
        doc["restatement"]["sections"]["other"] = "o"
        self.assertIn("other", schema.first_error(doc, schema.load("questions")))


if __name__ == "__main__":
    unittest.main()
