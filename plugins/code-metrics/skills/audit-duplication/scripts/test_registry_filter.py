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

    def write_registry(self, text: str) -> Path:
        path = Path(self.tmp.name) / "clusters.txt"
        path.write_text(text, encoding="utf-8")
        return path

    def test_a_cluster_line_excludes_the_canonical_plus_its_copies(self) -> None:
        registry = self.write_registry(
            "# canonical and copies\nlib/hook-utils.sh -> plugins/*/hooks/hook-utils.sh\n"
        )
        doc = document(
            [
                "lib/hook-utils.sh",
                "plugins/one/hooks/hook-utils.sh",
                "plugins/two/hooks/hook-utils.sh",
            ]
        )
        result = run(doc, "--root", ".", "--registry", str(registry))
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual(out["measures"], [])
        entry = out["excluded"][0]
        self.assertEqual(
            entry["path"], "lib/hook-utils.sh -> plugins/*/hooks/hook-utils.sh"
        )
        self.assertEqual(entry["line"], 2)
        self.assertEqual(len(entry["instances"]), 3)

    def test_a_glob_member_matches_and_a_stranger_keeps_the_group(self) -> None:
        registry = self.write_registry(
            "lib/parse.sh -> plugins/*/skills/*/scripts/parse.sh "
            "plugins/*/skills/*/scripts/lib/parse.sh\n"
        )
        sanctioned = document(
            [
                "lib/parse.sh",
                "plugins/a/skills/x/scripts/parse.sh",
                "plugins/b/skills/y/scripts/lib/parse.sh",
            ]
        )
        result = run(sanctioned, "--root", ".", "--registry", str(registry))
        self.assertEqual(json.loads(result.stdout)["measures"], [])
        stranger = document(["lib/parse.sh", "plugins/a/hooks/parse.sh"])
        result = run(stranger, "--root", ".", "--registry", str(registry))
        out = json.loads(result.stdout)
        self.assertEqual(len(out["measures"]), 1)
        self.assertEqual(out["excluded"], [])

    def test_two_cluster_instances_in_one_directory_keep_the_group(self) -> None:
        registry = self.write_registry("lib/a.sh -> plugins/*/hooks/*.sh\n")
        doc = document(["lib/a.sh", "plugins/one/hooks/a.sh", "plugins/one/hooks/b.sh"])
        result = run(doc, "--root", ".", "--registry", str(registry))
        out = json.loads(result.stdout)
        self.assertEqual(len(out["measures"]), 1)
        self.assertEqual(out["excluded"], [])

    def test_a_plain_line_with_a_space_is_one_path(self) -> None:
        registry = self.write_registry("hooks/shared file.sh\n")
        doc = document(
            ["plugins/one/hooks/shared file.sh", "plugins/two/hooks/shared file.sh"]
        )
        result = run(doc, "--root", ".", "--registry", str(registry))
        out = json.loads(result.stdout)
        self.assertEqual(out["measures"], [])
        self.assertEqual(out["excluded"][0]["path"], "hooks/shared file.sh")

    def test_the_first_matching_line_in_file_order_wins(self) -> None:
        registry = self.write_registry("lib/x.sh -> plugins/*/hooks/x.sh\nhooks/x.sh\n")
        doc = document(["plugins/one/hooks/x.sh", "plugins/two/hooks/x.sh"])
        result = run(doc, "--root", ".", "--registry", str(registry))
        entry = json.loads(result.stdout)["excluded"][0]
        self.assertEqual(
            (entry["path"], entry["line"]), ("lib/x.sh -> plugins/*/hooks/x.sh", 1)
        )
        reversed_registry = self.write_registry(
            "hooks/x.sh\nlib/x.sh -> plugins/*/hooks/x.sh\n"
        )
        result = run(doc, "--root", ".", "--registry", str(reversed_registry))
        entry = json.loads(result.stdout)["excluded"][0]
        self.assertEqual((entry["path"], entry["line"]), ("hooks/x.sh", 1))

    def test_cwd_relative_instances_from_a_subdirectory_still_match(self) -> None:
        root = Path(self.tmp.name)
        sub = root / "plugins" / "code-metrics"
        sub.mkdir(parents=True)
        registry = self.write_registry(
            "lib/hook-utils.sh -> plugins/*/hooks/hook-utils.sh\n"
        )
        doc = document(["../../lib/hook-utils.sh", "../one/hooks/hook-utils.sh"])
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--root",
                str(root),
                "--registry",
                str(registry),
            ],
            input=json.dumps(doc),
            capture_output=True,
            text=True,
            cwd=sub,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertEqual(out["measures"], [])
        self.assertEqual(len(out["excluded"]), 1)

    def test_the_zero_floor_states_zero_once_a_collector_ran(self) -> None:
        doc = document()
        doc["run"] = [{"lane": "bash", "measure": "duplication", "status": "ok"}]
        doc["summary"] = {"files": 0, "functions": 0, "over_reference": {}}
        result = run(doc, "--root", ".", "--zero-floor")
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)["summary"]
        self.assertEqual((summary["duplicated_lines"], summary["clone_groups"]), (0, 0))

    def test_the_zero_floor_counts_a_partial_lane_as_measured(self) -> None:
        doc = document()
        doc["run"] = [
            {
                "lane": "bash",
                "measure": "duplication",
                "status": "partial",
                "reason": "1 of 3 files skipped by duplication.max_size 1mb / max_lines none",
            }
        ]
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
