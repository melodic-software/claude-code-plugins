# test-scope: .github/actions/resolve-config/ratification.mjs
"""The owner's ratification rule agrees across languages: resolve-issue's
start (`.github/actions/resolve-config/ratification.mjs`, run here under node)
and the pr-merge lane's gate (`babysit_merge_policy.find_ratification`).

Each case is one comments list; both sides must pick the same ratifying
comment, or none. The cases cover each rule of `findRatification`: the marker
on a line of its own, a listed human's id, no App, never edited.
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

import babysit_merge_policy as policy

RULE = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/actions/resolve-config/ratification.mjs"
)
NODE = """
import { findRatification } from %s;
const { cases, ratifiers } = JSON.parse(process.argv[1]);
const set = new Set(ratifiers);
console.log(JSON.stringify(cases.map((comments) => findRatification(comments, set)?.id ?? null)));
"""
MARKER = (
    "<!-- admission: admitted when unblocked, owner batch ratification 2026-10-16 -->"
)
OWNER, OTHER = 153232337, 99
AT = "2026-10-16T12:00:00Z"


def comment(cid: int = 1, **changes: Any) -> dict[str, Any]:
    return {
        "id": cid,
        "body": MARKER,
        "user": {"id": OWNER},
        "performed_via_github_app": None,
        "created_at": AT,
        "updated_at": AT,
    } | changes


def without(key: str) -> dict[str, Any]:
    base = comment()
    del base[key]
    return base


BODIES = [
    MARKER,
    f"text\n{MARKER}\nmore",
    f"text\r\n{MARKER}\r\nmore",
    f"text\r{MARKER}",
    f"text {MARKER} more",
    f"text\x85{MARKER}",
    f" {MARKER}",
    f"{MARKER} ",
    f"> {MARKER}",
    MARKER.replace("2026-10-16", "2026-1-16"),
    MARKER.replace("2026", "٢٠٢٦"),
    MARKER.replace("admitted", "Admitted"),
    "",
    None,
]
CASES: list[list[dict[str, Any]]] = [
    *([comment(body=body)] for body in BODIES),
    [without("body")],
    [comment(user={"id": OTHER})],
    [comment(user={"id": str(OWNER)})],
    [comment(user=None)],
    [without("user")],
    [comment(performed_via_github_app={"id": 1})],
    [comment(performed_via_github_app=False)],
    [comment(performed_via_github_app=0)],
    [without("performed_via_github_app")],
    [comment(updated_at="2026-10-16T12:05:00Z")],
    [comment(updated_at=None)],
    [comment(created_at=None, updated_at=None)],
    [without("updated_at")],
    [comment(1, body="hi"), comment(2), comment(3)],
    [comment(1, user={"id": OTHER}), comment(2, updated_at="x"), comment(3)],
    [],
]


def node_picks(cases: list[Any], ratifiers: list[int]) -> list[Any]:
    script = NODE % json.dumps(RULE.as_uri())
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            json.dumps({"cases": cases, "ratifiers": ratifiers}),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


@unittest.skipUnless(shutil.which("node"), "node is not installed")
class TheRatificationRuleAgrees(unittest.TestCase):
    def test_both_sides_pick_the_same_comment(self) -> None:
        picked = node_picks(CASES, [OWNER])
        for case, expected in zip(CASES, picked, strict=True):
            with self.subTest(case=case):
                found = policy.find_ratification(case, frozenset({OWNER}))
                self.assertEqual(found.get("id") if found else None, expected)

    def test_the_cases_cover_both_outcomes(self) -> None:
        picked = node_picks(CASES, [OWNER])
        self.assertGreater(picked.count(None), 10)
        self.assertGreater(len(picked) - picked.count(None), 4)


if __name__ == "__main__":
    unittest.main()
