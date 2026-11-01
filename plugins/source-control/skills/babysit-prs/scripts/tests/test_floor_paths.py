# test-scope: scripts/sync-hold-floor.py .github/scripts/pr-merge/merge-holds.mjs .github/workflows/pr-review-hosted.yml .github/workflows/pr-review-security-hosted.yml .github/workflows/pr-require-checks.yml docs/conventions/pr-pipeline.yaml
"""`merge.diff-check.floor-paths`: this repository's effective floor stays what
it was when its rows moved out of the plugin default, the built-in floor holds
only what every consumer shares, a row can only tighten the floor, and the
loader refuses a row it cannot trust."""

from __future__ import annotations

import dataclasses
import hashlib
import importlib.util
import json
import pathlib
import re
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_review_evidence as evidence
import babysit_risk as risk
from babysit_risk import ChangedFile, FloorRowError, LaneEvidence, floor_for, floor_rows

ROOT = pathlib.Path(__file__).resolve().parents[6]
PIPELINE = (ROOT / "docs/conventions/pr-pipeline.yaml").read_text(encoding="utf-8")
ROWS = policy.floor_paths_in(PIPELINE)
FLOOR = floor_for(ROWS)
_SPEC = importlib.util.spec_from_file_location(
    "sync_hold_floor", ROOT / "scripts/sync-hold-floor.py"
)
sync = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(sync)

BABYSIT = "plugins/source-control/skills/babysit-prs/scripts/"
SHARED = {
    "**/CODEOWNERS",
    "**/.gitmodules",
    "**/.claude/**",
    "**/.claude-lane/**",
    "**/.mcp.json",
    "**/CLAUDE.md",
    "**/CLAUDE.local.md",
    "**/AGENTS.md",
    "REVIEW.md",
    "docs/conventions/pr-pipeline.yaml",
}
REVIEW_SURFACE = (
    ".github/scripts/pr-review-main/**",
    "docs/conventions/instruction-exception-register/**",
    "docs/conventions/untrusted-content/**",
    "docs/standards/**",
)


def digest(items) -> str:
    return hashlib.sha256("\n".join(sorted(items)).encode()).hexdigest()


def table(rows) -> set[tuple[str, str]]:
    return {(g, c) for g, c, *_ in rows}


def _file(path: str) -> ChangedFile:
    return ChangedFile(path, None, "modified", 1, 0, True, "100644")


def _score(path: str, rows, reviewed: bool):
    security = LaneEvidence(
        "claude-security-review", True, None, 0, blocking_findings=0
    )
    code = LaneEvidence("claude-review", True, None, 0)
    return risk.score(
        risk.RiskInput(
            files=(_file(path),),
            files_complete=True,
            max_changed_lines=200,
            high_paths=(),
            lanes=(code, security),
            floor_rows=rows,
            author_reviewed=frozenset({path} if reviewed else ()),
        )
    )


class TheEffectiveFloorDidNotMove(unittest.TestCase):
    """Computed from babysit_risk.py on main before the rows moved. A floor
    change updates these pins in the pull request that makes it."""

    def test_each_glob_keeps_its_class(self):
        self.assertEqual(len(FLOOR.classes), 119)
        self.assertEqual(
            digest(f"{g}\t{c}" for g, c in FLOOR.classes),
            "d63163a9ea3f37986303e4c2dedb189890829837654eda379c077f38cf2146e5",
        )

    def test_each_clearing_route_keeps_its_globs(self):
        pins = {
            FLOOR.high: "945769a8559834120719353db1e06df5c0af6d7689a21fc99e189d2042f6e256",
            FLOOR.review: "dfed007b8fe690d7c2d368b9d3a3f2a984aff096b4214fe00274bdcd8342b560",
            FLOOR.author_review: "10af3daeaaeaaa01c77eafd040b831be3f147fdf3fa850b636b87a8e64094399",
        }
        self.assertEqual(
            (len(FLOOR.high), len(FLOOR.review), len(FLOOR.author_review)),
            (69, 50, 15),
        )
        for globs, pin in pins.items():
            self.assertEqual(digest(globs), pin)

    def test_each_generated_copy_holds_that_set(self):
        hold_paths = re.compile(
            r"BEGIN hold-floor hold-paths.*?\n(.*?)\n\s*# END", re.S
        )
        wanted = (
            {g for g, _ in FLOOR.classes}
            | {sync.TRUSTED_ACTORS}
            | set(sync.SCRUTINY_ONLY)
        )
        for name in ("pr-review-hosted.yml", "pr-review-security-hosted.yml"):
            with self.subTest(name):
                text = (ROOT / ".github/workflows" / name).read_text(encoding="utf-8")
                block = hold_paths.search(text)[1].splitlines()[1:]
                self.assertEqual({line.strip() for line in block}, wanted)
        merge_holds = (ROOT / sync.MERGE_HOLDS).read_text(encoding="utf-8")
        rows = re.search(
            r"BEGIN hold-floor HOLD_PATH_CLASSES.*?\n(.*?)\n\s*// END",
            merge_holds,
            re.S,
        )
        self.assertEqual(
            {
                tuple(json.loads(line.strip().rstrip(",")))
                for line in rows[1].splitlines()
            },
            set(FLOOR.classes),
        )
        patterns = (ROOT / ".github/workflows/pr-require-checks.yml").read_text(
            encoding="utf-8"
        )
        quoted = re.search(r"hold_patterns=\((.*?)\)\n", patterns)[1]
        self.assertEqual(
            set(re.findall(r"'([^']+)'", quoted)),
            {
                p
                for g in (sync.TRUSTED_ACTORS, *(g for g, _ in FLOOR.classes))
                for p in sync.bash_patterns(g)
            },
        )

    def test_row_order_decides_nothing(self):
        reordered = floor_for(tuple(reversed(ROWS)))
        path = ".github/scripts/pr-merge/who.mjs"
        for floor in (FLOOR, reordered):
            self.assertTrue(any(risk.glob_match(g, path) for g in floor.author_review))
        self.assertEqual(set(reordered.classes), set(FLOOR.classes))
        self.assertEqual(set(reordered.high), set(FLOOR.high))
        self.assertEqual(set(reordered.author_review), set(FLOOR.author_review))


class TheBuiltInFloorIsShared(unittest.TestCase):
    def test_it_holds_only_what_every_consumer_shares(self):
        moved = [
            g
            for g, _ in risk.FLOOR_CLASSES
            if g not in SHARED and not g.startswith(BABYSIT)
        ]
        self.assertEqual(moved, [])
        self.assertEqual(len(risk.FLOOR_CLASSES), 28)

    def test_every_other_row_sits_in_the_config(self):
        self.assertEqual(len(ROWS), 119 - 28)
        self.assertFalse(table(ROWS) & set(risk.FLOOR_CLASSES))

    def test_the_config_every_consumer_reads_is_held_by_a_built_in_row(self):
        self.assertEqual(
            dict(risk.FLOOR_CLASSES).get(policy.CONFIG_PATH), "trust"
        )
        self.assertIn(policy.CONFIG_PATH, floor_for().high)
        self.assertNotIn(policy.CONFIG_PATH, floor_for().author_review)

    def test_no_author_lift_names_no_path_of_this_repository(self):
        self.assertLessEqual(risk._NO_AUTHOR_LIFT, SHARED)

    def test_a_consumer_with_no_rows_gets_the_built_in_floor_alone(self):
        self.assertEqual(floor_for().classes, risk.FLOOR_CLASSES)
        self.assertFalse(
            any(risk.glob_match(g, ".github/scripts/x.mjs") for g in floor_for().all)
        )


class ReviewSurfaceRowsNeverTakeTheLift(unittest.TestCase):
    """Owner decision Q11 (A): a person clears these whatever the author did."""

    def test_they_stay_gate_rows_marked_no_lift(self):
        for glob in REVIEW_SURFACE:
            with self.subTest(glob):
                self.assertIn((glob, "gate", False), ROWS)
                self.assertNotIn(glob, FLOOR.author_review)

    def test_only_those_rows_refuse_the_lift(self):
        self.assertEqual({g for g, _, lift in ROWS if not lift}, set(REVIEW_SURFACE))

    def test_an_author_reviewed_path_on_one_still_holds_for_a_person(self):
        for glob, sample in zip(
            REVIEW_SURFACE,
            (
                ".github/scripts/pr-review-main/record.mjs",
                "docs/conventions/instruction-exception-register/README.md",
                "docs/conventions/untrusted-content/README.md",
                "docs/standards/REVIEW.md",
            ),
            strict=True,
        ):
            with self.subTest(glob):
                result = _score(sample, ROWS, reviewed=True)
                self.assertIn(f"high-path:{glob}", [r.code for r in result.reasons])
                self.assertTrue(risk.holds(result))

    def test_dropping_the_marker_is_what_grants_the_lift(self):
        # The control: the same path, the row without `author-lift: false`.
        path = "docs/standards/REVIEW.md"
        loosened = tuple(
            (g, c, True) if g == "docs/standards/**" else (g, c, lift)
            for g, c, lift in ROWS
        )
        self.assertNotIn(
            "high-path:docs/standards/**",
            [r.code for r in _score(path, loosened, reviewed=True).reasons],
        )


class ARowOnlyTightens(unittest.TestCase):
    def test_a_row_cannot_downgrade_a_built_in_trust_glob(self):
        floor = floor_for((("**/CODEOWNERS", "enforcement", True),))
        self.assertIn("**/CODEOWNERS", floor.high)
        floor = floor_for((("**/CODEOWNERS", "gate", True),))
        self.assertNotIn("**/CODEOWNERS", floor.author_review)

    def test_a_row_cannot_grant_a_lift_a_built_in_refuses(self):
        floor = floor_for((("REVIEW.md", "gate", True),))
        self.assertNotIn("REVIEW.md", floor.author_review)

    def test_refusing_the_lift_wins_over_a_row_that_allows_it(self):
        floor = floor_for((("a/**", "gate", True), ("a/**", "gate", False)))
        self.assertIn("a/**", floor.high)
        self.assertNotIn("a/**", floor.author_review)

    def test_a_workflow_row_never_takes_the_lift(self):
        floor = floor_for(((".github/workflows/x.yml", "gate", True),))
        self.assertIn(".github/workflows/x.yml", floor.high)
        self.assertNotIn(".github/workflows/x.yml", floor.author_review)


class TheLoaderRefusesARowItCannotTrust(unittest.TestCase):
    def test_a_good_row_of_each_shape_reads(self):
        self.assertEqual(
            floor_rows(
                {
                    "0.glob": "a/**",
                    "0.class": "trust",
                    "1.glob": "b/**",
                    "1.class": "gate",
                    "1.author-lift": "false",
                    "2.glob": "c/**",
                    "2.class": "gate",
                    "2.author-lift": "true",
                    "3.glob": "d/**",
                    "3.class": "enforcement",
                }
            ),
            (
                ("a/**", "trust", True),
                ("b/**", "gate", False),
                ("c/**", "gate", True),
                ("d/**", "enforcement", True),
            ),
        )

    def test_a_row_it_cannot_trust_raises(self):
        gate = {"0.glob": "a", "0.class": "gate"}
        cases = {
            "author-lift on a trust row": {
                "0.glob": "a",
                "0.class": "trust",
                "0.author-lift": "false",
            },
            "author-lift on an enforcement row": {
                "0.glob": "a",
                "0.class": "enforcement",
                "0.author-lift": "true",
            },
            "a misspelled field": {**gate, "0.author_lift": "false"},
            "a value that is not a boolean": {**gate, "0.author-lift": "no"},
            "a capitalized boolean": {**gate, "0.author-lift": "False"},
            "an unknown class": {"0.glob": "a", "0.class": "gate-review-surface"},
            "no class": {"0.glob": "a"},
            "no glob": {"0.class": "gate"},
            "the plain-string form": {"0": "docs/adr/**"},
            "a scalar key": {"": "docs/adr/**"},
            "a mapping, not a list": {"glob": "a", "class": "gate"},
            "a row with no field": {"0.glob": "a", "0.class": "gate", "2.glob": "b"},
        }
        for name, records in cases.items():
            with self.subTest(name), self.assertRaises(FloorRowError):
                floor_rows(records)

    def config_at(self, rows: str) -> policy.PipelineConfig:
        text = "merge:\n  rung: C3\n  diff-check:\n    floor-paths:\n" + rows

        def file_at(path: str, _sha: str) -> str | None:
            return text if path == policy.CONFIG_PATH else None

        return policy.read_config_at("o/r", "a" * 40, file_at)

    def test_a_config_row_it_cannot_trust_turns_the_rung_off(self):
        config = self.config_at(
            '      - glob: "a/**"\n        class: trust\n        author-lift: false\n'
        )
        self.assertEqual(config.rung, "off")
        self.assertEqual(config.floor_paths, ())
        self.assertIn("author-lift on a trust row", config.notes[0])

    def test_the_plain_string_form_turns_the_rung_off(self):
        config = self.config_at('      - "docs/adr/**"\n')
        self.assertEqual(config.rung, "off")

    def test_a_config_row_it_trusts_keeps_the_rung(self):
        config = self.config_at(
            '      - glob: "a/**"\n        class: gate\n        author-lift: false\n'
        )
        self.assertEqual(config.rung, "C3")
        self.assertEqual(config.floor_paths, (("a/**", "gate", False),))


class TheEffectiveFloorReachesEveryReader(unittest.TestCase):
    def test_the_stricter_config_keeps_both_sides_rows(self):
        base = policy.PipelineConfig(
            "a" * 40,
            "C3",
            None,
            None,
            None,
            (),
            None,
            floor_paths=(("a", "gate", True),),
        )
        main = dataclasses.replace(base, floor_paths=(("a", "gate", False),))
        joined = policy.stricter_config(base, main)
        self.assertEqual(
            joined.floor_paths, (("a", "gate", True), ("a", "gate", False))
        )
        self.assertNotIn("a", joined.floor.author_review)

    def test_a_saved_config_round_trips_and_an_older_one_is_a_miss(self):
        config = policy.PipelineConfig(
            "a" * 40, "C3", None, None, None, (), None, floor_paths=ROWS
        )
        saved = json.loads(json.dumps(dataclasses.asdict(config)))
        self.assertEqual(policy._cached_config(saved), config)
        del saved["floor_paths"]
        self.assertIsNone(policy._cached_config(saved))

    def test_a_gated_workflow_is_never_a_read_only_candidate(self):
        path = ".github/workflows/pr-merge.yml"
        self.assertFalse(evidence._readonly_candidate(path, FLOOR))
        self.assertTrue(evidence.needs_main_review([path], None, None, FLOOR))

    def test_own_lines_on_a_config_row_stay_held(self):
        original = policy.foreign_paths
        policy.foreign_paths = lambda *_: frozenset()
        self.addCleanup(setattr, policy, "foreign_paths", original)
        path = ".github/scripts/pr-merge/who.mjs"
        self.assertEqual(
            policy.own_paths("o/r", {}, frozenset({path}), floor=FLOOR), frozenset()
        )
        self.assertEqual(
            policy.own_paths("o/r", {}, frozenset({path}), floor=floor_for()),
            frozenset({path}),
        )

    def test_the_author_lift_reads_config_rows(self):
        original = policy.foreign_paths
        policy.foreign_paths = lambda *_: frozenset()
        self.addCleanup(setattr, policy, "foreign_paths", original)
        pr = {"user": {"id": 7, "type": "User"}}
        lifted = ".github/scripts/pr-merge/who.mjs"
        held = "docs/standards/REVIEW.md"
        self.assertEqual(
            policy.author_reviewed_paths("o/r", pr, {lifted, held}, {7}, True, FLOOR),
            frozenset({lifted}),
        )

    def test_a_floor_row_it_cannot_read_scores_high(self):
        result = _score("a.md", ("not a row",), reviewed=False)
        self.assertEqual(result.score, risk.Risk.HIGH)


if __name__ == "__main__":
    unittest.main()
