#!/usr/bin/env python3
"""Self-test for the retired-sense vocabulary checker.

Each case builds a throwaway git repository holding a copy of the checker and
its shipped data file plus the files the case names, so the suite proves the
shipped rules and allowlist rather than the current state of this checkout.
"""

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

# FIXTURE ISOLATION: `git init` and `git add` below must never reach the
# caller's repository through an inherited git environment. The variable list
# mirrors scripts/test-git-helpers.sh; scripts/check-fixture-git-isolation.sh
# keeps it true.
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
del _leaked_git_var

HERE = Path(__file__).resolve().parent
GATE = HERE / "check-vocabulary.py"
DATA = HERE / "vocabulary-senses.json"

# One line per sense that the sense's rules report.
HITS = {
    "rung": "## Choosing the rung: text, diagram, page, or video",
    "default-ladder": "The shipped default ladder is page, then terminal.",
    "overlay": "Write the personal overlay to the gitignored local file.",
    "tier-precedence": "The project tier takes precedence over the user tier.",
    "surface-config": "Edit the settings surface to change it.",
    "contract-brief": "The Brief is the contract the plan builds on.",
}

# One line per sense that a rule matches but an allowlist entry keeps, with
# the path it is written to.
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

GUIDE = "docs/guide.md"
RUNG_LINE = "Rung 2 opens the page."
OVERLAY_LINE = "The overlay layers on the shipped defaults."
TIER_LINE = "The tier overrides the default."
SURFACE_LINE = "The surface reads settings.json."


def phrase(sense: str, regex: str, line: str):
    return (sense, "phrase", regex, GUIDE, line)


def path(sense: str, glob: str, file: str, line: str):
    return (sense, "path", glob, file, line)


# Every allowlist entry in the data file, each with one line that a rule of
# its sense matches and that the entry keeps: (sense, kind, value, path, line).
# Deleting or renaming an entry fails test_the_table_names_every_allowlist_entry,
# and a new entry needs a row here.
ALLOWLIST = [
    phrase("rung", r"\bautonomy (ladder|rungs?)\b", "The autonomy ladder rung for a page stays."),
    path("rung", "plugins/autonomy/**", "plugins/autonomy/README.md", RUNG_LINE),
    phrase("rung", r"\benforcement[- ]ladder\b", "The enforcement ladder's rung for a page stays."),
    path("rung", "docs/contracts/enforcement-ladder/**", "docs/contracts/enforcement-ladder/v1.md", RUNG_LINE),
    path("rung", "docs/conventions/enforcement-ladder/**", "docs/conventions/enforcement-ladder/README.md", RUNG_LINE),
    path("rung", "**/enforcement-ladder.md", "docs/enforcement-ladder.md", RUNG_LINE),
    phrase("rung", r"\bresolution ladder\b", "The resolution ladder's rung for a page stays."),
    path("rung", "plugins/toolchain/**", "plugins/toolchain/README.md", RUNG_LINE),
    phrase("rung", r"\bmethod[- ]ladder\b", "The method ladder's rung for a page stays."),
    path("rung", "plugins/github/reference/method-ladder.md", "plugins/github/reference/method-ladder.md", RUNG_LINE),
    phrase("rung", r"\b(loop[- ]lane|pr[- ]pipeline)\b.*\brungs?\b", "The loop-lane rung for a page stays."),
    path("rung", "docs/contracts/loop-lane/**", "docs/contracts/loop-lane/v1.md", RUNG_LINE),
    path("rung", "docs/conventions/loop-lane/**", "docs/conventions/loop-lane/README.md", RUNG_LINE),
    path("rung", "docs/conventions/pr-pipeline/**", "docs/conventions/pr-pipeline/README.md", RUNG_LINE),
    path("rung", "plugins/session-flow/skills/find-handoff/**", "plugins/session-flow/skills/find-handoff/SKILL.md", RUNG_LINE),
    phrase("rung", r"\b(explanation rungs?|rungs? of explanation)\b", "The explanation rung sits above the page."),
    phrase("rung", r"\bcandidate ladder\b", "The candidate ladder's rung for a page stays."),
    path("rung", "plugins/session-flow/skills/recommend-skills/**", "plugins/session-flow/skills/recommend-skills/SKILL.md", RUNG_LINE),
    phrase("default-ladder", r"\bautonomy\b", "The autonomy default ladder starts at observe."),
    phrase("default-ladder", r"\benforcement[- ]ladder\b", "The enforcement ladder is the default ladder here."),
    phrase("default-ladder", r"\bresolution ladder\b", "The resolution ladder's default ladder tries npm first."),
    phrase("default-ladder", r"\bmethod[- ]ladder\b", "The method ladder's default ladder tries gh first."),
    phrase("default-ladder", r"\bcandidate ladder\b", "The candidate ladder's default ladder ranks skills first."),
    phrase("overlay", r"\bpolicy[- ]overlays?\b", "The policy overlay layers on the shipped defaults."),
    phrase("overlay", r"\bcatalog[- ]?overlays?\b", "The catalog overlay layers on the shipped catalog."),
    path("overlay", "plugins/machine-health/skills/**", "plugins/machine-health/skills/check/SKILL.md", OVERLAY_LINE),
    path("overlay", "plugins/machine-health/README.md", "plugins/machine-health/README.md", OVERLAY_LINE),
    path("overlay", "plugins/user-interface/skills/**", "plugins/user-interface/skills/x/SKILL.md", OVERLAY_LINE),
    path("overlay", "plugins/user-interface/reference/**", "plugins/user-interface/reference/x.md", OVERLAY_LINE),
    path("overlay", "plugins/user-interface/evals/**", "plugins/user-interface/evals/x.md", OVERLAY_LINE),
    path("overlay", "plugins/planning/shared/web/**", "plugins/planning/shared/web/page.css", OVERLAY_LINE),
    path("overlay", "plugins/planning/evals/st-plan-4/graders/**", "plugins/planning/evals/st-plan-4/graders/defect-c.md", OVERLAY_LINE),
    path("overlay", "plugins/playwright/skills/**", "plugins/playwright/skills/x/SKILL.md", OVERLAY_LINE),
    path("overlay", "plugins/animation/skills/**", "plugins/animation/skills/x/SKILL.md", OVERLAY_LINE),
    path("overlay", "plugins/pixel-art/reference/**", "plugins/pixel-art/reference/x.md", OVERLAY_LINE),
    path("overlay", "plugins/pixel-art/skills/**", "plugins/pixel-art/skills/x/SKILL.md", OVERLAY_LINE),
    phrase("overlay", r"\bbrand[- ]overlays?\b", "The brand overlay layers on the slide."),
    path("overlay", "plugins/ai-briefing/skills/generate/output/**", "plugins/ai-briefing/skills/generate/output/brief.md", OVERLAY_LINE),
    path("overlay", "plugins/gaming/**", "plugins/gaming/README.md", OVERLAY_LINE),
    path("overlay", "plugins/songwriting/skills/**", "plugins/songwriting/skills/x/SKILL.md", OVERLAY_LINE),
    phrase("overlay", r"\bagentic[- ]overlays?\b", "The agentic overlay layers on the harness."),
    path("overlay", "plugins/testing/skills/audit/evals/judge-calibration/**", "plugins/testing/skills/audit/evals/judge-calibration/case.md", OVERLAY_LINE),
    phrase("overlay", r"\b(css|ui|video|image|visual|modal)[- ]overlays?\b", "The modal overlay layers on the page."),
    phrase("overlay", r"\badr/[0-9]{4}-[a-z0-9-]*overlay[a-z0-9-]*\.md\b", "Read [ADR 0015](../../adr/0015-bind-the-tracker-with-a-personal-overlay.md) on the layer."),
    phrase("tier-precedence", r"\bview tiers?\b", "The view tier overrides the page default."),
    phrase("tier-precedence", r"\b(static|client-interactive|animated|claude-interactive) tiers?\b", "The static tier overrides the page default."),
    phrase("tier-precedence", r"\benforcement[- ]ladder\b", "The enforcement ladder tier overrides the default."),
    path("tier-precedence", "docs/contracts/enforcement-ladder/**", "docs/contracts/enforcement-ladder/v1.md", TIER_LINE),
    path("tier-precedence", "docs/conventions/enforcement-ladder/**", "docs/conventions/enforcement-ladder/README.md", TIER_LINE),
    path("tier-precedence", "**/enforcement-ladder.md", "docs/enforcement-ladder.md", TIER_LINE),
    phrase("tier-precedence", r"\bmemory[- ]tiers?\b", "The memory tier overrides the default."),
    phrase("tier-precedence", r"\b(model|strong|frontier|capability|cheap|fast)[- ]tiers?\b", "The model tier overrides the default."),
    phrase("surface-config", r"\binterview surfaces?\b", "The interview surface reads settings.json."),
    phrase("surface-config", r"\b(terminal|shared session)\b", "The terminal surface reads settings.json."),
    path("surface-config", "plugins/planning/surface/**", "plugins/planning/surface/README.md", SURFACE_LINE),
    phrase("surface-config", r"\bplanning/surface\b", "The planning/surface code reads settings.json."),
    phrase(
        "surface-config",
        r"\b(skills?|commands?)\b.*\bsurfaces?\b|\bsurfaces?\b.*\b(skills?|commands?)\b",
        "Each surface reads its skills from settings.json.",
    ),
    phrase("surface-config", r"\bemitting surfaces?\b", "The emitting surface reads settings.json."),
    phrase(
        "contract-brief",
        r"\bdocs/contracts\b|\bcontracts/[\w-]+|\bversioned contracts?\b",
        "The Brief cites docs/contracts/loop-lane.",
    ),
    phrase("contract-brief", r"\binterface contracts?\b", "The Brief names an interface contract."),
    phrase(
        "contract-brief",
        r"\b(pr|api|feed|payload|behavioral|presentation|execution|detection)[- ]contracts?\b",
        "The dispatch brief carries the PR contract forward.",
    ),
    phrase("contract-brief", r"\bname[- ]by[- ]contract\b", "The brief follows the name-by-contract rule."),
    phrase("contract-brief", r"\bcontract case\b", "Contract case for the hand-off once the Brief is locked."),
]


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
    def test_the_data_file_names_the_six_senses(self):
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
                self.assertTrue(rules_match(sense, line), "the rule must match the line")
                code, out, err = run_gate({path: line})
                self.assertEqual(code, 0, out + err)
                self.assertEqual(out, "")

    def test_a_line_outside_the_sense_context_is_not_reported(self):
        code, out, _ = run_gate({"docs/guide.md": "Each rung up costs more tokens."})
        self.assertEqual((code, out), (0, ""))


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
                self.assertTrue(rules_match(sense, line), "the rule must match the line")
                if kind == "phrase":
                    self.assertTrue(re.search(value, line, re.I), "the phrase must match the line")
                else:
                    code, out, err = run_gate({GUIDE: line}, "--sense", sense)
                    self.assertEqual(code, 1, "the line must be reported outside the path")
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
    FILES = {"docs/guide.md": "\n".join([HITS["rung"], HITS["overlay"], HITS["contract-brief"]])}

    def test_sense_selects_one(self):
        code, out, _ = run_gate(self.FILES, "--sense", "overlay")
        self.assertEqual(code, 1)
        self.assertEqual(out, f"docs/guide.md:2: overlay: {HITS['overlay']}\n")

    def test_sense_repeats(self):
        code, out, _ = run_gate(self.FILES, "--sense", "rung", "--sense", "contract-brief")
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
