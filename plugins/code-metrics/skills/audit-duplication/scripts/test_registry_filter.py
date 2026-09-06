#!/usr/bin/env python3
"""Output-based tests for registry-filter.py at its command line.

The filter is a pure function from a document plus registries to a document,
so every case drives the script through subprocess with a small document on
stdin (design T13, the one seam per script). The committed fixture
scripts/fixtures/registry/cluster.txt covers the shape a consuming repository
ships; these cases cover the rule itself.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "registry-filter.py"
FIXTURE_REGISTRY = (
    Path(__file__).resolve().parents[3]
    / "scripts"
    / "fixtures"
    / "registry"
    / "cluster.txt"
)


def document(*instance_sets: list[str]) -> dict:
    return {
        "schema": "code-metrics/v1",
        "skill": "audit-duplication",
        "measures": [
            {
                "file": None,
                "function": None,
                "lane": "bash",
                "instances": [
                    {"file": path, "start_line": 1, "end_line": 41} for path in paths
                ],
                "values": {"lines": 41, "tokens": 110},
                "collector": "jscpd",
            }
            for paths in instance_sets
        ],
        "excluded": [],
    }


def run(doc: dict, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        input=json.dumps(doc),
        capture_output=True,
        text=True,
        check=False,
    )


class RegistryFilterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.registry = Path(self.tmp.name) / "cluster.txt"
        self.registry.write_text(
            "# a comment line\n\nshared/shared-utils.sh\nhooks/hook-utils.sh\n",
            encoding="utf-8",
        )
        self.addCleanup(self.tmp.cleanup)

    def test_a_declared_cluster_is_dropped_and_recorded(self) -> None:
        doc = document(["alpha/shared/shared-utils.sh", "beta/shared/shared-utils.sh"])
        result = run(doc, "--root", ".", "--registry", str(self.registry))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual(out["measures"], [])
        self.assertEqual(len(out["excluded"]), 1)
        entry = out["excluded"][0]
        self.assertEqual(entry["path"], "shared/shared-utils.sh")
        self.assertEqual(entry["line"], 3)
        self.assertEqual(entry["registry"], str(self.registry).replace("\\", "/"))
        self.assertEqual(len(entry["instances"]), 2)

    def test_a_second_registry_line_carries_its_own_line_number(self) -> None:
        doc = document(
            ["plugins/one/hooks/hook-utils.sh", "plugins/two/hooks/hook-utils.sh"]
        )
        result = run(doc, "--root", ".", "--registry", str(self.registry))
        self.assertEqual(result.returncode, 0, result.stderr)
        entry = json.loads(result.stdout)["excluded"][0]
        self.assertEqual((entry["path"], entry["line"]), ("hooks/hook-utils.sh", 4))

    def test_an_instance_outside_the_declared_path_keeps_the_group(self) -> None:
        doc = document(["alpha/shared/shared-utils.sh", "beta/lib/other-utils.sh"])
        result = run(doc, "--root", ".", "--registry", str(self.registry))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual(len(out["measures"]), 1)
        self.assertEqual(out["excluded"], [])

    def test_two_instances_under_one_prefix_keep_the_group(self) -> None:
        doc = document(["alpha/shared/shared-utils.sh", "alpha/shared/shared-utils.sh"])
        result = run(doc, "--root", ".", "--registry", str(self.registry))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual(len(out["measures"]), 1)
        self.assertEqual(out["excluded"], [])

    def test_rows_without_instances_pass_through_untouched(self) -> None:
        doc = document(["alpha/shared/shared-utils.sh", "beta/shared/shared-utils.sh"])
        doc["measures"].append({"file": "src/a.ts", "function": "parse", "values": {}})
        result = run(doc, "--root", ".", "--registry", str(self.registry))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual([r["file"] for r in out["measures"]], ["src/a.ts"])

    def test_no_registry_leaves_the_document_alone(self) -> None:
        doc = document(["alpha/shared/shared-utils.sh", "beta/shared/shared-utils.sh"])
        result = run(doc, "--root", ".")
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual(len(out["measures"]), 1)
        self.assertEqual(out["excluded"], [])

    def test_absolute_instance_paths_are_read_relative_to_the_root(self) -> None:
        root = Path(self.tmp.name)
        doc = document(
            [
                str(root / "alpha" / "shared" / "shared-utils.sh"),
                str(root / "beta" / "shared" / "shared-utils.sh"),
            ]
        )
        result = run(doc, "--root", str(root), "--registry", str(self.registry))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)["excluded"]), 1)

    def test_the_committed_cluster_registry_declares_the_fixture_path(self) -> None:
        doc = document(
            [
                "plugins/code-metrics/scripts/fixtures/sources/cluster/alpha/shared/shared-utils.sh",
                "plugins/code-metrics/scripts/fixtures/sources/cluster/beta/shared/shared-utils.sh",
            ]
        )
        result = run(doc, "--root", ".", "--registry", str(FIXTURE_REGISTRY))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual(out["measures"], [])
        self.assertEqual(out["excluded"][0]["path"], "shared/shared-utils.sh")

    def test_the_zero_floor_states_zero_once_a_collector_ran(self) -> None:
        doc = document()
        doc["run"] = [{"lane": "bash", "measure": "duplication", "status": "ok"}]
        doc["summary"] = {"files": 0, "functions": 0, "over_reference": {}}
        result = run(doc, "--root", ".", "--zero-floor")
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)["summary"]
        self.assertEqual((summary["duplicated_lines"], summary["clone_groups"]), (0, 0))

    def test_the_zero_floor_leaves_a_run_that_measured_nothing_alone(self) -> None:
        doc = document()
        doc["run"] = [
            {
                "lane": "bash",
                "measure": "duplication",
                "status": "unavailable",
                "reason": "jscpd: not found",
            }
        ]
        doc["summary"] = {"files": 0, "functions": 0, "over_reference": {}}
        result = run(doc, "--root", ".", "--zero-floor")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("duplicated_lines", json.loads(result.stdout)["summary"])

    def test_a_missing_registry_is_a_usage_error(self) -> None:
        result = run(
            document(), "--root", ".", "--registry", "/nonexistent/registry.txt"
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("registry not found", result.stderr)

    def test_a_non_json_document_is_a_usage_error(self) -> None:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--root", "."],
            input="not json",
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("not a JSON document", result.stderr)


if __name__ == "__main__":
    unittest.main()
