"""The tracker binding reader: the `tracker` mapping of
docs/conventions/work-items.yaml binds first, the legacy root
.work-item-tracker.json binds a repository that has not moved it, and with
neither the caller's default applies.

Expected values come from the work-items seam's binding discovery
(plugins/work-items/tools/work-item-tracker/lib/binding.sh `wit_find_binding`):
a YAML file with no `tracker` key falls through to the legacy file, and a YAML
file that does not parse is an error, never a fallback.
"""

from __future__ import annotations

import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_merge_skip as skip
import babysit_tracker_binding as binding

YAML = "docs/conventions/work-items.yaml"
LEGACY = ".work-item-tracker.json"
ROLE = "human-gated"
DEFAULT = "needs-human"


def legacy(label: object) -> str:
    config = {"role_labels": {ROLE: label}}
    return json.dumps({"schema_version": "1.0", "config": config})


class RoleLabel(unittest.TestCase):
    def label(self, files: dict[str, str]) -> str:
        self.reads: list[str] = []

        def read(path: str) -> str | None:
            self.reads.append(path)
            return files.get(path)

        return binding.role_label(read, policy.yaml_records, ROLE, DEFAULT)

    def test_the_paths_are_the_ones_the_seam_reads(self) -> None:
        self.assertEqual(binding.PATHS, (YAML, LEGACY))

    def test_the_yaml_binding_maps_the_role(self) -> None:
        text = (
            "tracker:\n"
            "  schema_version: '1.0'\n"
            "  provider: github\n"
            "  config:\n"
            "    role_labels:\n"
            f"      {ROLE}: ' human-review '\n"
        )
        files = {YAML: text, LEGACY: legacy("from-json")}
        self.assertEqual(self.label(files), "human-review")
        self.assertEqual(self.reads, [YAML])

    def test_a_yaml_binding_that_maps_no_role_is_the_default(self) -> None:
        # It binds, so the legacy file is never read.
        files = {YAML: "tracker:\n  provider: github\n", LEGACY: legacy("from-json")}
        self.assertEqual(self.label(files), DEFAULT)
        self.assertEqual(self.reads, [YAML])

    def test_a_yaml_file_with_no_tracker_key_falls_back(self) -> None:
        other = "work_priority_order:\n  - 'priority: high'\n"
        files = {YAML: other, LEGACY: legacy("from-json")}
        self.assertEqual(self.label(files), "from-json")
        self.assertEqual(self.reads, [YAML, LEGACY])

    def test_with_no_yaml_file_the_legacy_file_binds(self) -> None:
        self.assertEqual(self.label({LEGACY: legacy(" from-json ")}), "from-json")

    def test_a_blank_or_non_string_label_is_the_default(self) -> None:
        for value in ("", "  ", 7, None):
            with self.subTest(value=value):
                self.assertEqual(self.label({LEGACY: legacy(value)}), DEFAULT)

    def test_with_neither_file_the_default_applies(self) -> None:
        self.assertEqual(self.label({}), DEFAULT)
        self.assertEqual(self.reads, [YAML, LEGACY])

    def test_a_yaml_file_that_does_not_parse_raises(self) -> None:
        files = {YAML: "tracker: {provider: github}\n", LEGACY: legacy("from-json")}
        with self.assertRaises(policy.PolicyReadError):
            self.label(files)

    def test_a_scalar_tracker_key_raises(self) -> None:
        # The seam counts it as a binding and rejects it; it never falls back.
        files = {YAML: "tracker: github\n", LEGACY: legacy("from-json")}
        with self.assertRaises(binding.BindingError):
            self.label(files)

    def test_an_empty_legacy_file_is_the_default(self) -> None:
        self.assertEqual(self.label({LEGACY: " \n"}), DEFAULT)

    def test_a_legacy_file_that_is_not_json_raises(self) -> None:
        with self.assertRaises(binding.BindingError):
            self.label({LEGACY: "{ not json"})

    def test_a_failed_read_passes_through(self) -> None:
        def read(path: str) -> str | None:
            raise RuntimeError(f"{path}: HTTP 502")

        with self.assertRaisesRegex(RuntimeError, "HTTP 502"):
            binding.role_label(read, policy.yaml_records, ROLE, DEFAULT)


class SkipKeysOnTheBinding(unittest.TestCase):
    def test_the_skip_key_covers_both_binding_files(self) -> None:
        self.assertLessEqual(set(binding.PATHS), set(skip.MAIN_PATHS))


if __name__ == "__main__":
    unittest.main()
