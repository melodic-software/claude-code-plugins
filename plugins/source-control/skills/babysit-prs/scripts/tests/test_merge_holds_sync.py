# test-scope: .github/scripts/pr-merge/merge-holds.mjs
"""The native auto-merge holds (`.github/scripts/pr-merge/merge-holds.mjs`,
run here under node) cover the merge gate's cost paths and manifests, so a
lane pull request native auto-merge merges cannot skip them. The gate's other
cost reasons (Pulumi project files, workflow and pipeline lines) are not
mirrored; workflows and the pipeline config are hold paths already.

- The cost paths: the same globs as `babysit_risk.COST_PATHS`, and the same
  paths matched (`glob_match` folds case and covers what sits under a glob).
- The manifests: every path `babysit_risk.is_manifest_path` takes is a hold
  path (`pathHold`).
"""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import unittest
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_risk as risk

MODULE = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/merge-holds.mjs"
)
NODE = """
import { COST_PATHS, costHold, pathHold } from %s;
const paths = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  costPaths: COST_PATHS,
  cost: paths.map((path) => costHold([path], null) !== null),
  held: paths.map((path) => pathHold([path], []) !== null),
}));
"""
PATHS = [
    "plugins/multi-agent/reference/defaults.yaml",
    "Plugins/Multi-Agent/Reference/Defaults.YAML",
    "plugins/multi-agent/reference/defaults.yml",
    "Pulumi.yaml",
    "infra/Pulumi.yaml",
    "infra/pulumi.PROD.yaml",
    "infra/Pulumi.md",
    "main.tf",
    ".infra/net/main.TF",
    "a.tf/inside.txt",
    ".tf",
    "infra/.tf",
    "x/.tfvars",
    ".bicep",
    "a/.bicepparam",
    "infra/.x.tf",
    "infra/.terraform/x.tf",
    "vars.tfvars",
    "deploy/main.bicep",
    "deploy/main.bicepparam",
    "deploy/main.bicep.md",
    "docs/a.md",
    ".claude-plugin/marketplace.json",
    "plugins/foo/.claude-plugin/plugin.json",
    "plugins/foo/.claude-plugin/other.json",
]


def module(paths: list[str]) -> dict[str, Any]:
    script = NODE % json.dumps(MODULE.as_uri())
    proc = subprocess.run(
        ["node", "--input-type=module", "-e", script, json.dumps(paths)],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheNativeHoldsCoverTheGate(unittest.TestCase):
    def test_the_cost_paths_are_the_same(self) -> None:
        answer = module(PATHS)
        self.assertEqual(answer["costPaths"], list(risk.COST_PATHS))
        for path, held in zip(PATHS, answer["cost"], strict=True):
            with self.subTest(path):
                self.assertEqual(
                    held, any(risk.glob_match(g, path) for g in risk.COST_PATHS)
                )
        self.assertIn(True, answer["cost"])
        self.assertIn(False, answer["cost"])

    def test_every_manifest_the_gate_reads_is_a_hold_path(self) -> None:
        answer = module(PATHS)
        manifests = [p for p in PATHS if risk.is_manifest_path(p)]
        self.assertEqual(
            manifests,
            [
                ".claude-plugin/marketplace.json",
                "plugins/foo/.claude-plugin/plugin.json",
            ],
        )
        for path, held in zip(PATHS, answer["held"], strict=True):
            if path in manifests:
                with self.subTest(path):
                    self.assertTrue(held)


if __name__ == "__main__":
    unittest.main()
