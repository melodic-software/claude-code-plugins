#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

for _leaked_git_var in (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_PREFIX",
    "GIT_OBJECT_DIRECTORY",
    "GIT_CONFIG",
):
    os.environ.pop(_leaked_git_var, None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
del _leaked_git_var

HERE = Path(__file__).resolve().parent
GATE = HERE / "check-vocabulary.py"
DATA = HERE / "vocabulary-senses.json"

sys.path.insert(0, str(HERE))
from vocabulary_allowlist_table import ALLOWLIST, GUIDE  # noqa: E402

HITS = {
    "lane-view-producer": "node lib/view-settings.mjs resolve --lane planning --option auto",
    "lane-placement-direction": "Flag stranded docs conventions on the promote lane.",
    "lane-code-metrics-language": "Files outside every language lane carry a line count.",
    "lane-dead-code-analyzer": "Run dead-code-scan.sh --lane grep over src.",
    "lane-coupling-step": "A second list is always a route-lane ledger entry.",
    "lane-owning-skill": "Hand the findings off to the remediation lanes.",
    "rung": "## Choosing the rung: text, diagram, page, or video",
    "default-ladder": "The shipped default ladder is page, then terminal.",
    "overlay": "Write the personal overlay to the gitignored local file.",
    "tier-precedence": "The project tier takes precedence over the user tier.",
    "surface-config": "Edit the settings surface to change it.",
    "contract-brief": "The Brief is the contract the plan builds on.",
    "lane-hunt-scope": "Run /bugs:scan --lane core-logic to hunt one slice.",
}

ALLOWED = {
    "rung": (
        "plugins/session-flow/skills/find-handoff/reference/rung-1-known-location.md",
        "Rung 1 reads the page text.",
    ),
    "default-ladder": (
        "docs/guide.md",
        "The toolchain resolution ladder's default ladder tries npm first.",
    ),
    "overlay": (
        "docs/guide.md",
        "The disk-hygiene policy overlay layers on the shipped defaults.",
    ),
    "tier-precedence": (
        "docs/guide.md",
        "The view tier overrides the page default.",
    ),
    "surface-config": (
        "docs/guide.md",
        "The interview surface reads settings.json.",
    ),
    "contract-brief": (
        "docs/guide.md",
        "The Brief cites docs/contracts/loop-lane.",
    ),
}


def run_gate(files: dict, *args: str):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "scripts").mkdir()
        shutil.copy(GATE, root / "scripts" / GATE.name)
        shutil.copy(DATA, root / "scripts" / DATA.name)
        for rel, body in files.items():
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(body + "\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "add", "-A"], cwd=root, check=True)
        result = subprocess.run(
            [sys.executable, str(root / "scripts" / GATE.name), *args],
            cwd=root,
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout, result.stderr


def rules_match(sense: str, line: str) -> bool:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    (entry,) = [s for s in data["senses"] if s["id"] == sense]
    return any(
        re.search(r["match"], line, re.I)
        and ("near" not in r or re.search(r["near"], line, re.I))
        for r in entry["rules"]
    )


class EachSense(unittest.TestCase):
    def test_the_data_file_names_every_sense(self):
        data = json.loads(DATA.read_text(encoding="utf-8"))
        self.assertEqual([s["id"] for s in data["senses"]], list(HITS))

    def test_each_allowlist_entry_has_a_reason(self):
        data = json.loads(DATA.read_text(encoding="utf-8"))
        for sense in data["senses"]:
            for entry in sense.get("allow", []):
                self.assertTrue(entry.get("reason", "").strip(), entry)

    def test_one_hit_per_sense(self):
        for sense, line in HITS.items():
            with self.subTest(sense=sense):
                code, out, err = run_gate({"docs/guide.md": line})
                self.assertEqual(code, 1, out + err)
                self.assertEqual(out, f"docs/guide.md:1: {sense}: {line}\n")

    def test_one_allowlisted_miss_per_sense(self):
        for sense, (path, line) in ALLOWED.items():
            with self.subTest(sense=sense):
                self.assertTrue(
                    rules_match(sense, line), "the rule must match the line"
                )
                code, out, err = run_gate({path: line})
                self.assertEqual(code, 0, out + err)
                self.assertEqual(out, "")

    def test_a_numbered_view_form_rung_is_reported(self):
        line = "Rung 2 renders the page; rung 1 renders a diagram."
        code, out, err = run_gate({"docs/guide.md": line})
        self.assertEqual(code, 1, out + err)
        self.assertEqual(out, f"docs/guide.md:1: rung: {line}\n")

    def test_a_line_outside_the_sense_context_is_not_reported(self):
        code, out, _ = run_gate({"docs/guide.md": "Each rung up costs more tokens."})
        self.assertEqual((code, out), (0, ""))

    def test_each_retired_lane_sense_is_reported(self):
        lines = [
            "tidy hunts a rotated lane for Beck tidyings.",
            "Copy the template into .claude/tidy-lanes/web.md.",
            "user-interface:audit reviews one concern lane at a time.",
        ]
        code, out, _ = run_gate({"docs/guide.md": "\n".join(lines)})
        self.assertEqual(code, 1, out)
        self.assertEqual(
            out,
            "".join(
                f"docs/guide.md:{n}: lane-hunt-scope: {line}\n"
                for n, line in enumerate(lines, 1)
            ),
        )

    def test_a_stage_worker_lane_is_not_reported(self):
        lines = [
            "The merge lane merges the pull request once CI Status is green.",
            "Run the pr-merge lane with --lane-merges-only.",
            "The video digest reads each artifact from its concern lane folder.",
        ]
        code, out, _ = run_gate({"docs/guide.md": "\n".join(lines)})
        self.assertEqual((code, out), (0, ""))

    def test_surface_as_a_verb_or_a_key_is_not_reported(self):
        lines = [
            "When it does not, setup surfaces the missing line in settings.json.",
            "- surface: .claude/settings.json",
            'select(.identity.sites[0].surface=="user:settings.json")',
        ]
        code, out, _ = run_gate({"docs/guide.md": "\n".join(lines)})
        self.assertEqual((code, out), (0, ""))

    def test_a_sense_ending_its_line_ignores_the_next_line(self):
        lines = ["Edit the settings.json surface", "the next line starts with an article"]
        code, out, err = run_gate({"docs/guide.md": "\n".join(lines)})
        self.assertEqual(code, 1, out + err)
        self.assertEqual(out, f"docs/guide.md:1: surface-config: {lines[0]}\n")

    def test_a_tree_scanned_in_parallel_reports_in_path_order(self):
        files = {f"docs/clean-{n:04}.md": "Nothing retired here." for n in range(1100)}
        files["docs/clean-0007.md"] = HITS["rung"]
        files["docs/clean-1099.md"] = HITS["overlay"]
        code, out, err = run_gate(files)
        self.assertEqual(code, 1, out + err)
        self.assertEqual(
            out,
            f"docs/clean-0007.md:1: rung: {HITS['rung']}\n"
            f"docs/clean-1099.md:1: overlay: {HITS['overlay']}\n",
        )


class EachAllowlistEntry(unittest.TestCase):
    def test_the_table_names_every_allowlist_entry(self):
        data = json.loads(DATA.read_text(encoding="utf-8"))
        shipped = sorted(
            (sense["id"], kind, entry[kind])
            for sense in data["senses"]
            for entry in sense.get("allow", [])
            for kind in ("path", "phrase")
            if kind in entry
        )
        tabled = sorted((sense, kind, value) for sense, kind, value, _, _ in ALLOWLIST)
        self.assertEqual(tabled, shipped)

    def test_each_entry_keeps_its_line(self):
        for sense, kind, value, file, line in ALLOWLIST:
            with self.subTest(sense=sense, entry=value):
                self.assertTrue(
                    rules_match(sense, line), "the rule must match the line"
                )
                if kind == "phrase":
                    self.assertTrue(
                        re.search(value, line, re.I), "the phrase must match the line"
                    )
                else:
                    code, out, err = run_gate({GUIDE: line}, "--sense", sense)
                    self.assertEqual(
                        code, 1, "the line must be reported outside the path"
                    )
                code, out, err = run_gate({file: line})
                self.assertEqual((code, out), (0, ""), err)


class Paths(unittest.TestCase):
    EXCLUDED = (
        "docs/adr/0001-record.md",
        "docs/upstream/source.md",
        "docs/standards/rule.md",
        "CHANGELOG.md",
        "plugins/x/CHANGELOG.md",
    )

    def test_always_excluded_paths_are_skipped(self):
        files = {p: HITS["rung"] for p in self.EXCLUDED}
        code, out, err = run_gate(files)
        self.assertEqual((code, out), (0, ""), err)

    def test_authored_eval_text_is_checked(self):
        authored = (
            "plugins/x/skills/y/evals/evals.json",
            "plugins/x/evals/case/case.yaml",
            "plugins/x/evals/case/prompt.md",
        )
        code, out, err = run_gate({p: HITS["rung"] for p in authored})
        self.assertEqual(code, 1, err)
        self.assertEqual(
            sorted(line.split(":")[0] for line in out.splitlines()), sorted(authored)
        )

    def test_an_excluded_path_named_as_an_argument_is_still_skipped(self):
        files = {p: HITS["rung"] for p in self.EXCLUDED}
        code, out, err = run_gate(files, *self.EXCLUDED)
        self.assertEqual((code, out), (0, ""), err)

    def test_the_checkers_own_files_are_skipped(self):
        code, out, err = run_gate({"docs/clean.md": "Nothing retired here."})
        self.assertEqual((code, out), (0, ""), err)

    def test_no_path_checks_the_whole_repository(self):
        files = {"a/one.md": HITS["rung"], "b/two.md": HITS["overlay"]}
        code, out, _ = run_gate(files)
        self.assertEqual(code, 1)
        self.assertIn("a/one.md:1: rung:", out)
        self.assertIn("b/two.md:1: overlay:", out)

    def test_a_file_argument_checks_only_that_file(self):
        files = {"a/one.md": HITS["rung"], "b/two.md": HITS["overlay"]}
        code, out, _ = run_gate(files, "b/two.md")
        self.assertEqual(code, 1)
        self.assertEqual(out, f"b/two.md:1: overlay: {HITS['overlay']}\n")

    def test_a_directory_argument_checks_the_files_under_it(self):
        files = {
            "a/one.md": HITS["rung"],
            "a/deep/three.md": HITS["tier-precedence"],
            "b/two.md": HITS["overlay"],
        }
        code, out, _ = run_gate(files, "a")
        self.assertEqual(code, 1)
        self.assertIn("a/one.md:1: rung:", out)
        self.assertIn("a/deep/three.md:1: tier-precedence:", out)
        self.assertNotIn("b/two.md", out)

    def test_a_clean_path_argument_exits_0(self):
        files = {"a/one.md": HITS["rung"], "b/clean.md": "Nothing retired here."}
        self.assertEqual(run_gate(files, "b")[:2], (0, ""))

    def test_a_missing_path_exits_2(self):
        self.assertEqual(run_gate({}, "no/such/path")[0], 2)


class Senses(unittest.TestCase):
    FILES = {
        "docs/guide.md": "\n".join(
            [HITS["rung"], HITS["overlay"], HITS["contract-brief"]]
        )
    }

    def test_sense_selects_one(self):
        code, out, _ = run_gate(self.FILES, "--sense", "overlay")
        self.assertEqual(code, 1)
        self.assertEqual(out, f"docs/guide.md:2: overlay: {HITS['overlay']}\n")

    def test_sense_repeats(self):
        code, out, _ = run_gate(
            self.FILES, "--sense", "rung", "--sense", "contract-brief"
        )
        self.assertEqual(code, 1)
        self.assertIn("docs/guide.md:1: rung:", out)
        self.assertIn("docs/guide.md:3: contract-brief:", out)
        self.assertNotIn("overlay", out)

    def test_a_sense_with_no_match_exits_0(self):
        self.assertEqual(run_gate(self.FILES, "--sense", "default-ladder")[:2], (0, ""))

    def test_no_sense_checks_all(self):
        code, out, _ = run_gate(self.FILES)
        self.assertEqual(code, 1)
        self.assertEqual(len(out.splitlines()), 3)

    def test_an_unknown_sense_exits_2(self):
        code, _, err = run_gate(self.FILES, "--sense", "bogus")
        self.assertEqual(code, 2)
        self.assertIn("unknown sense bogus", err)


if __name__ == "__main__":
    unittest.main()
