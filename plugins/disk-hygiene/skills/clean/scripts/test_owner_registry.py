#!/usr/bin/env python3
"""Tests for the bundled managed-state owner registry."""

from __future__ import annotations

import fnmatch
import json
import unittest
from pathlib import Path
from typing import Any

REFERENCE = Path(__file__).resolve().parents[1] / "reference"
REGISTRY = json.loads((REFERENCE / "owner-registry.json").read_text(encoding="utf-8"))
SCHEMA = json.loads(
    (REFERENCE / "owner-registry.schema.json").read_text(encoding="utf-8")
)
POLICY = json.loads((REFERENCE / "baseline-policy.json").read_text(encoding="utf-8"))

EXPECTED_IDS = {
    "docker-desktop",
    "nvidia-shader-cache",
    "cursor",
    "openai-codex-cli",
    "chezmoi",
    "pulumi",
}
JSON_TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "null": type(None),
}


def validate(value: Any, schema: dict[str, Any], where: str = "$") -> list[str]:
    """Check the JSON Schema keywords the registry schema uses; return errors."""
    errors: list[str] = []
    if "const" in schema and value != schema["const"]:
        errors.append(f"{where}: expected {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{where}: {value!r} not in {schema['enum']}")
    if "type" in schema:
        names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(isinstance(value, JSON_TYPES[name]) for name in names):
            return [*errors, f"{where}: expected type {names}"]
    if isinstance(value, str) and len(value) < schema.get("minLength", 0):
        errors.append(f"{where}: shorter than {schema['minLength']}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{where}: fewer than {schema['minItems']} items")
        if schema.get("uniqueItems") and len({json.dumps(v) for v in value}) != len(
            value
        ):
            errors.append(f"{where}: items not unique")
        for index, item in enumerate(value):
            errors += validate(item, schema.get("items", {}), f"{where}[{index}]")
    if isinstance(value, dict):
        if len(value) < schema.get("minProperties", 0):
            errors.append(f"{where}: fewer than {schema['minProperties']} properties")
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{where}: missing {key!r}")
        properties = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for key, item in value.items():
            if "propertyNames" in schema:
                errors += validate(key, schema["propertyNames"], f"{where}.<{key}>")
            if key in properties:
                errors += validate(item, properties[key], f"{where}.{key}")
            elif extra is False:
                errors.append(f"{where}: unexpected {key!r}")
            elif isinstance(extra, dict):
                errors += validate(item, extra, f"{where}.{key}")
    return errors


def pattern_segments(entry: dict[str, Any]) -> list[str]:
    return [
        segment
        for patterns in entry["path_patterns"].values()
        for pattern in patterns
        for segment in pattern.replace("\\", "/").split("/")
    ]


class OwnerRegistryTest(unittest.TestCase):
    def test_registry_validates_against_schema(self) -> None:
        self.assertEqual(validate(REGISTRY, SCHEMA), [])

    def test_validator_rejects_a_malformed_entry(self) -> None:
        bad = json.loads(json.dumps(REGISTRY))
        del bad["entries"][0]["tool"]
        bad["entries"][1]["platforms"] = ["beos"]
        self.assertEqual(len(validate(bad, SCHEMA)), 2)

    def test_seeds_the_six_owners(self) -> None:
        ids = [entry["id"] for entry in REGISTRY["entries"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), EXPECTED_IDS)

    def test_note_states_hint_is_not_authorization(self) -> None:
        self.assertIn("never authorization", REGISTRY["note"])

    def test_path_patterns_cover_only_declared_platforms(self) -> None:
        for entry in REGISTRY["entries"]:
            self.assertLessEqual(
                set(entry["path_patterns"]), set(entry["platforms"]), entry["id"]
            )

    def test_no_path_pattern_touches_a_protected_name(self) -> None:
        exact = {name.casefold() for name in POLICY["protected_exact_names"]}
        globs = POLICY["protected_name_globs"]
        for entry in REGISTRY["entries"]:
            for segment in pattern_segments(entry):
                self.assertNotIn(segment.casefold(), exact, entry["id"])
                for glob in globs:
                    self.assertFalse(fnmatch.fnmatchcase(segment, glob), entry["id"])


if __name__ == "__main__":
    unittest.main()
