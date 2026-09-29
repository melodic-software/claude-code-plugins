#!/usr/bin/env python3
"""Tests for overlap.py.

`unittest` from the standard library, not pytest: pytest is not provisioned on
this repo's CI runners, and the sibling extractor's suite is stdlib too.

Run directly (`python3 test_overlap.py`) or through the `overlap.test.sh`
wrapper, which is what `run-plugin-tests.sh` discovers.
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import discover  # noqa: E402  - path shim above must run first
import overlap  # noqa: E402  - path shim above must run first

FIXTURE_CLI_VERSION = "2.1.232"

BASE_ROW = {
    "native": {"name": "doctor", "class": "bundled-skill", "markers": ["gated"]},
    "component": {"plugin": "demo", "skill": "demo-audit", "kind": "skill"},
    "verdict": "complementary",
    "reason": "different depths of the same question",
    "evidence": ["present in the extraction as bundled-skill"],
    "observation": {
        "class": "extraction",
        "detail": f"binary v{FIXTURE_CLI_VERSION}",
        "date": "2026-08-23",
    },
    "recheck": {
        "trigger": "a Claude Code release adds, removes, or renames a bundled skill in this lane",
        "verified": "2026-08-23",
    },
    "integration": "route",
    "baked": {
        "description_phrase": False,
        "boundary_section": True,
        "native_step": False,
        "suggest_sentence": False,
    },
    "budget_caveat": False,
}

# A verdict lands with its Boundary section, so the default component carries
# one; the description phrase is the separately gated half and stays absent. The
# surface is named as a code span, which is what ties the section to the row.
BOUNDARY_EXTRA = "\n## Boundary, the bundled `doctor` skill\n\nDetail.\n"


def deep_copy(value):
    return json.loads(json.dumps(value))


def make_store(rows):
    return {"schema": 1, "rows": deep_copy(rows)}


SKILL_TEMPLATE = """---
description: "{description}"
{frontmatter_extra}---

## Purpose

Demo body.
{extra}
"""

SKILL_RAW_TEMPLATE = """---
{frontmatter}
---

## Purpose

Demo body.

## Boundary, the bundled `doctor` skill

Detail.
"""


class TempRepo:
    """A throwaway repo tree with a store, a view, and plugin components."""

    def __init__(self, rows=None):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.store_path = self.root / "docs" / "native-surfaces" / "records.json"
        self.view_path = self.root / "docs" / "native-surfaces.md"
        self.store_path.parent.mkdir(parents=True, exist_ok=True)
        self.write_store(make_store(rows if rows is not None else [BASE_ROW]))
        # BASE_ROW claims a Boundary section, so the component it names exists
        # from the start; tests that want a different component rewrite it.
        self.write_skill("demo", "demo-audit", extra=BOUNDARY_EXTRA)

    def write_store(self, store):
        self.store_path.write_text(json.dumps(store, indent=2), encoding="utf-8")

    def write_skill(
        self,
        plugin,
        skill,
        description="Plain description.",
        extra="",
        frontmatter_extra="",
    ):
        path = self.root / "plugins" / plugin / "skills" / skill / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            SKILL_TEMPLATE.format(
                description=description,
                extra=extra,
                frontmatter_extra=frontmatter_extra,
            ),
            encoding="utf-8",
        )
        return path

    def write_skill_raw(self, plugin, skill, frontmatter):
        """Write a skill whose frontmatter block is given verbatim.

        Needed for the scalar styles the quoted-description template cannot
        express (block scalars, sibling keys carrying the gate token).
        """
        path = self.root / "plugins" / plugin / "skills" / skill / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            SKILL_RAW_TEMPLATE.format(frontmatter=frontmatter), encoding="utf-8"
        )
        return path

    def generate(self, extra_args=()):
        return overlap.main(
            [
                "generate",
                "--repo",
                str(self.root),
                "--store",
                str(self.store_path),
                "--view",
                str(self.view_path),
                *extra_args,
            ]
        )

    def self_check(self, cli_version=FIXTURE_CLI_VERSION, upstream_sha=None):
        args = [
            "self-check",
            "--repo",
            str(self.root),
            "--store",
            str(self.store_path),
            "--view",
            str(self.view_path),
        ]
        if cli_version is not None:
            args += ["--cli-version", cli_version]
        if upstream_sha is not None:
            shas = (
                [upstream_sha] if isinstance(upstream_sha, str) else list(upstream_sha)
            )
            for sha in shas:
                args += ["--upstream-sha", sha]
        return overlap.main(args)

    def cleanup(self):
        self._tmp.cleanup()


class StoreValidationTests(unittest.TestCase):
    def test_valid_row_has_no_problems(self):
        self.assertEqual(overlap.validate_store(make_store([BASE_ROW])), [])

    def test_wrong_schema_is_a_problem(self):
        store = make_store([BASE_ROW])
        store["schema"] = 2
        self.assertTrue(any("schema" in p for p in overlap.validate_store(store)))

    def test_missing_trigger_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        del row["recheck"]["trigger"]
        problems = overlap.validate_store(make_store([row]))
        self.assertTrue(any("trigger" in p for p in problems), problems)

    def test_bare_date_trigger_fails_the_observability_bar(self):
        for trigger in ("2027-01-01", "by 2027", "  2026-12  "):
            row = deep_copy(BASE_ROW)
            row["recheck"]["trigger"] = trigger
            problems = overlap.validate_store(make_store([row]))
            self.assertTrue(
                any("bare date" in p for p in problems), f"{trigger!r} -> {problems}"
            )

    def test_event_trigger_passes(self):
        row = deep_copy(BASE_ROW)
        row["recheck"]["trigger"] = (
            "the /skills roster stops listing this surface in 2027"
        )
        self.assertEqual(overlap.validate_store(make_store([row])), [])

    def test_unknown_verdict_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        row["verdict"] = "prefer-something"
        self.assertTrue(
            any("verdict" in p for p in overlap.validate_store(make_store([row])))
        )

    def test_observation_class_is_required(self):
        row = deep_copy(BASE_ROW)
        row["observation"]["class"] = "available"
        problems = overlap.validate_store(make_store([row]))
        self.assertTrue(any("observation.class" in p for p in problems), problems)

    def test_missing_reason_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        row["reason"] = "   "
        self.assertTrue(
            any("reason" in p for p in overlap.validate_store(make_store([row])))
        )

    def test_live_roster_row_may_not_be_baked(self):
        row = deep_copy(BASE_ROW)
        row["observation"] = {
            "class": "live-roster",
            "detail": "observed in a cloud session",
            "date": "2026-08-23",
        }
        row["baked"]["description_phrase"] = True
        problems = overlap.validate_store(make_store([row]))
        self.assertTrue(any("never baked" in p for p in problems), problems)

    def test_duplicate_rows_are_a_problem(self):
        problems = overlap.validate_store(make_store([BASE_ROW, BASE_ROW]))
        self.assertTrue(any("duplicate" in p for p in problems), problems)

    def test_unknown_native_class_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        row["native"]["class"] = "bundled"
        self.assertTrue(
            any("native.class" in p for p in overlap.validate_store(make_store([row])))
        )

    def test_same_name_skill_and_agent_rows_are_not_duplicates(self):
        # Distinct components resolving to distinct paths: skills/<name>/SKILL.md
        # vs agents/<name>.md. Identity keys on kind, so both rows stand.
        skill_row = deep_copy(BASE_ROW)
        agent_row = deep_copy(BASE_ROW)
        agent_row["component"]["kind"] = "agent"
        self.assertEqual(overlap.validate_store(make_store([skill_row, agent_row])), [])

    def test_duplicate_rows_of_the_same_kind_name_that_kind(self):
        problems = overlap.validate_store(make_store([BASE_ROW, BASE_ROW]))
        duplicates = [p for p in problems if "duplicate" in p]
        self.assertTrue(duplicates, problems)
        self.assertIn("(skill)", duplicates[0])

    def test_duplicate_agent_rows_are_still_a_problem(self):
        row = deep_copy(BASE_ROW)
        row["component"]["kind"] = "agent"
        problems = overlap.validate_store(make_store([row, row]))
        self.assertTrue(any("duplicate" in p for p in problems), problems)


class DescriptionExtractionTests(unittest.TestCase):
    """The parity check reads one field, so the extractor is tested as one."""

    def extract(self, frontmatter):
        return overlap.frontmatter_description(frontmatter)

    def test_quoted_single_line(self):
        self.assertEqual(self.extract('\ndescription: "Do a thing."\n'), "Do a thing.")

    def test_plain_single_line(self):
        self.assertEqual(self.extract("\ndescription: Do a thing.\n"), "Do a thing.")

    def test_folded_block_scalar_reads_as_one_line(self):
        frontmatter = "\ndescription: >-\n  Do a thing that\n  wraps a line.\n"
        self.assertEqual(self.extract(frontmatter), "Do a thing that wraps a line.")

    def test_literal_block_scalar_reads_as_one_line(self):
        frontmatter = "\ndescription: |\n  Do a thing that\n  wraps a line.\n"
        self.assertEqual(self.extract(frontmatter), "Do a thing that wraps a line.")

    def test_a_phrase_wrapped_across_a_block_scalar_is_still_found(self):
        frontmatter = (
            "\ndescription: >\n  When the bundled skill resolves in\n"
            "  this session, prefer it.\n"
        )
        self.assertIn(overlap.GATE_TOKEN, self.extract(frontmatter))

    def test_nested_description_is_not_read(self):
        frontmatter = "\nname: demo\nmetadata:\n  description: Nested value.\n"
        self.assertEqual(self.extract(frontmatter), "")

    def test_a_later_key_does_not_leak_into_the_value(self):
        frontmatter = '\ndescription: "Do a thing."\nargument-hint: "[target]"\n'
        self.assertEqual(self.extract(frontmatter), "Do a thing.")

    def test_absent_description_is_empty(self):
        self.assertEqual(self.extract("\nname: demo\n"), "")


class GenerateTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def test_generate_creates_a_marker_fenced_view(self):
        self.assertEqual(self.repo.generate(), 0)
        text = self.repo.view_path.read_text(encoding="utf-8")
        self.assertIn(overlap.START_MARKER, text)
        self.assertIn(overlap.END_MARKER, text)
        self.assertIn("`doctor`", text)
        self.assertIn("Never hand-edit", text)

    def test_generate_is_idempotent(self):
        self.repo.generate()
        first = self.repo.view_path.read_text(encoding="utf-8")
        self.repo.generate()
        self.assertEqual(first, self.repo.view_path.read_text(encoding="utf-8"))

    def test_check_passes_when_in_sync(self):
        self.repo.generate()
        self.assertEqual(self.repo.generate(["--check"]), 0)

    def test_check_fails_on_drift(self):
        self.repo.generate()
        rows = [deep_copy(BASE_ROW)]
        rows[0]["verdict"] = "prefer-native"
        self.repo.write_store(make_store(rows))
        self.assertEqual(self.repo.generate(["--check"]), 1)

    def test_check_fails_when_the_view_is_absent(self):
        self.assertEqual(self.repo.generate(["--check"]), 1)

    def test_hand_edited_body_is_restored_but_the_header_is_kept(self):
        self.repo.generate()
        text = self.repo.view_path.read_text(encoding="utf-8")
        head, _, rest = text.partition(overlap.START_MARKER)
        _, _, tail = rest.partition(overlap.END_MARKER)
        self.repo.view_path.write_text(
            head
            + "MY HEADER NOTE\n"
            + overlap.START_MARKER
            + "\nvandalised\n"
            + overlap.END_MARKER
            + tail,
            encoding="utf-8",
        )
        self.assertEqual(self.repo.generate(["--check"]), 1)
        self.assertEqual(self.repo.generate(), 0)
        restored = self.repo.view_path.read_text(encoding="utf-8")
        self.assertIn("MY HEADER NOTE", restored)
        self.assertNotIn("vandalized", restored)

    def test_missing_markers_fail_rather_than_overwrite(self):
        self.repo.view_path.parent.mkdir(parents=True, exist_ok=True)
        self.repo.view_path.write_text("# hand written\n", encoding="utf-8")
        self.assertEqual(self.repo.generate(), 1)
        self.assertEqual(
            self.repo.view_path.read_text(encoding="utf-8"), "# hand written\n"
        )


class SelfCheckTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def test_clean_store_and_view_exit_zero(self):
        self.repo.generate()
        self.assertEqual(self.repo.self_check(), 0)

    def test_missing_store_degrades_rather_than_breaking(self):
        self.repo.store_path.unlink()
        self.assertEqual(self.repo.self_check(), 3)

    def test_version_drift_degrades(self):
        self.repo.generate()
        self.assertEqual(self.repo.self_check(cli_version="2.1.999"), 3)

    def test_view_drift_breaks(self):
        self.repo.generate()
        rows = [deep_copy(BASE_ROW)]
        rows[0]["reason"] = "changed after generation"
        self.repo.write_store(make_store(rows))
        self.assertEqual(self.repo.self_check(), 1)

    def test_trigger_less_row_breaks(self):
        row = deep_copy(BASE_ROW)
        row["recheck"]["trigger"] = ""
        self.repo.write_store(make_store([row]))
        self.assertEqual(self.repo.self_check(), 1)

    def test_forward_parity_break_when_the_phrase_is_missing(self):
        row = deep_copy(BASE_ROW)
        row["baked"]["description_phrase"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill("demo", "demo-audit", description="No gate here.")
        self.assertEqual(self.repo.self_check(), 1)

    def test_forward_parity_holds_when_the_phrase_is_present(self):
        row = deep_copy(BASE_ROW)
        row["baked"]["description_phrase"] = True
        row["baked"]["boundary_section"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            description=(
                "When the bundled doctor skill "
                f"{overlap.GATE_TOKEN}, prefer it for the quick pass; this skill for the "
                "deep one."
            ),
            extra=BOUNDARY_EXTRA,
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_forward_parity_breaks_when_the_token_sits_outside_the_description(self):
        # The token in `argument-hint` is not routing-effective; a baked claim
        # is only satisfied by the description field itself.
        row = deep_copy(BASE_ROW)
        row["baked"]["description_phrase"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            description="No gate here.",
            frontmatter_extra=f'argument-hint: "when doctor {overlap.GATE_TOKEN}"\n',
        )
        self.assertEqual(self.repo.self_check(), 1)

    def test_forward_parity_holds_for_a_folded_description(self):
        row = deep_copy(BASE_ROW)
        row["baked"]["description_phrase"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill_raw(
            "demo",
            "demo-audit",
            "description: >-\n"
            "  When the bundled doctor skill resolves in\n"
            "  this session, prefer it for the quick pass.",
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_reverse_parity_ignores_a_token_outside_the_description(self):
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "unrelated",
            description="Plain description.",
            frontmatter_extra=f'argument-hint: "when the thing {overlap.GATE_TOKEN}"\n',
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_reverse_parity_breaks_on_a_folded_description_with_no_row(self):
        self.repo.generate()
        self.repo.write_skill_raw(
            "demo",
            "orphan",
            "description: |\n  When the bundled thing resolves in\n  this session, prefer it.",
        )
        self.assertEqual(self.repo.self_check(), 1)

    def test_reverse_parity_break_when_no_row_claims_the_baked_line(self):
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "orphan",
            description=f"When the bundled thing {overlap.GATE_TOKEN}, prefer it.",
        )
        self.assertEqual(self.repo.self_check(), 1)

    def test_row_without_a_description_phrase_is_legal_pending_sweep_state(self):
        # The phrase is the budget-priced, routing-affecting half and earns its
        # own gate; a row carrying only its Boundary section is complete.
        self.repo.generate()
        self.repo.write_skill("demo", "demo-audit", extra=BOUNDARY_EXTRA)
        self.assertEqual(self.repo.self_check(), 0)

    def test_row_without_a_boundary_section_breaks(self):
        # The verdict is recorded but the model never reads it. Broken, not
        # degraded: a consumer gate passes degraded runs because they report a
        # condition this repository cannot fix by editing its own files, and a
        # missing section is fixable in the change that adds the row.
        row = deep_copy(BASE_ROW)
        row["baked"]["boundary_section"] = False
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill("demo", "demo-audit")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            exit_code = self.repo.self_check()
        self.assertEqual(exit_code, 1)
        self.assertIn("carry no Boundary section", err.getvalue())
        self.assertIn("demo:demo-audit", err.getvalue())

    def test_boundary_section_for_another_surface_does_not_satisfy_a_row(self):
        # `boundary_section` true plus any `## Boundary` heading would pass a
        # presence-only check while the row's own surface goes unmentioned.
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            extra="\n## Boundary, the bundled `simplify` skill\n\nDetail.\n",
        )
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            exit_code = self.repo.self_check()
        self.assertEqual(exit_code, 1)
        self.assertIn("names `doctor`", err.getvalue())

    def test_a_generic_boundary_heading_naming_the_surface_satisfies_a_row(self):
        # The preferred heading names the surface, but a component covering
        # several surfaces under one generic heading is legal as long as the
        # section text names each row's surface.
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            extra=(
                "\n## Boundary\n\nThe bundled `doctor` skill offers to fix; this "
                "skill only reports.\n"
            ),
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_one_boundary_section_can_carry_several_rows(self):
        # The visualize shape: two rows, two native surfaces, one section.
        second = deep_copy(BASE_ROW)
        second["native"] = {
            "name": "simplify",
            "class": "bundled-skill",
            "markers": [],
        }
        self.repo.write_store(make_store([BASE_ROW, second]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            extra=(
                "\n## Boundary\n\nThe bundled `doctor` skill fixes; the bundled "
                "`simplify` skill refines a diff; this skill only reports.\n"
            ),
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_a_surface_named_only_in_prose_does_not_satisfy_a_row(self):
        # A native name that is also an ordinary English word must not be
        # satisfied by prose that happens to use it.
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "run", "class": "bundled-skill", "markers": []}
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            extra="\n## Boundary\n\nThis skill does not run the application.\n",
        )
        self.assertEqual(self.repo.self_check(), 1)

    def test_defer_rows_owe_no_boundary_section(self):
        row = deep_copy(BASE_ROW)
        row["verdict"] = "defer"
        row["baked"]["boundary_section"] = False
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.assertEqual(self.repo.self_check(), 0)

    def test_agent_rows_owe_no_boundary_section(self):
        # Agents are registry-rows-only: a role prompt loads after dispatch, too
        # late to route, so no agent row is ever baked and the advisory that
        # names skills without a Boundary section must not count them.
        row = deep_copy(BASE_ROW)
        row["component"] = {"plugin": "demo", "skill": "some-agent", "kind": "agent"}
        row["baked"]["boundary_section"] = False
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            exit_code = self.repo.self_check()
        self.assertEqual(exit_code, 0)
        self.assertNotIn("carry no Boundary section", out.getvalue())

    def test_boundary_heading_alone_is_not_a_reverse_parity_break(self):
        # `## Boundary` predates this registry across the fleet; only the
        # frontmatter gate token is a baked-line marker.
        self.repo.generate()
        self.repo.write_skill(
            "demo", "unrelated", extra="\n## Boundary — unrelated surfaces\n\nDetail.\n"
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_missing_integration_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        del row["integration"]
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("integration" in problem for problem in problems))

    def test_builtin_command_rejects_wrap(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "export", "class": "builtin-command", "markers": []}
        row["integration"] = "wrap"
        row["baked"]["boundary_section"] = False
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("never `wrap`" in problem for problem in problems))

    def test_bundled_workflow_rejects_wrap(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {
            "name": "deep-research",
            "class": "bundled-workflow",
            "markers": [],
        }
        row["integration"] = "wrap"
        row["baked"]["boundary_section"] = False
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("never `wrap`" in problem for problem in problems))

    def test_builtin_command_allows_suggest_with_invocation_evidence(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "export", "class": "builtin-command", "markers": []}
        row["integration"] = "suggest"
        row["baked"]["boundary_section"] = False
        row["evidence"] = ["invocation mode: local-jsx command type, not a prompt"]
        self.assertEqual(overlap.validate_row(row, 0), [])

    def test_session_skill_rejects_suggest(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "morning", "class": "session-skill", "markers": []}
        row["integration"] = "suggest"
        row["observation"]["class"] = "live-roster"
        row["baked"]["boundary_section"] = False
        row["evidence"] = [
            "invocation mode: session roster, not a bundled registration"
        ]
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("session-skill" in problem for problem in problems))

    def test_session_skill_route_is_legal(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "morning", "class": "session-skill", "markers": []}
        row["integration"] = "route"
        row["observation"]["class"] = "live-roster"
        row["baked"]["boundary_section"] = False
        self.assertEqual(overlap.validate_row(row, 0), [])

    def test_model_disabled_bundled_skill_takes_suggest_only(self):
        row = deep_copy(BASE_ROW)
        row["native"]["markers"] = ["gated", "model-invocation-disabled"]
        row["integration"] = "route"
        row["baked"]["boundary_section"] = False
        problems = overlap.validate_row(row, 0)
        self.assertTrue(
            any("model-invocation-disabled" in problem for problem in problems)
        )
        row["integration"] = "suggest"
        row["evidence"] = [
            "invocation mode: model-invocation-disabled (disableModelInvocation)"
        ]
        self.assertEqual(overlap.validate_row(row, 0), [])

    def test_model_disabled_suggest_row_rejects_description_phrase(self):
        row = deep_copy(BASE_ROW)
        row["native"]["markers"] = ["gated", "model-invocation-disabled"]
        row["integration"] = "suggest"
        row["baked"]["boundary_section"] = False
        row["evidence"] = [
            "invocation mode: model-invocation-disabled (disableModelInvocation)"
        ]
        row["baked"]["description_phrase"] = False
        self.assertEqual(overlap.validate_row(row, 0), [])
        row["baked"]["description_phrase"] = True
        problems = overlap.validate_row(row, 0)
        self.assertTrue(
            any("never bakes a description phrase" in problem for problem in problems)
        )

    def test_defer_overrides_model_disabled_and_takes_route(self):
        # design-sync is both defer and model-invocation-disabled. The
        # confirmed verdict table records route; defer wins because nothing
        # is baked from a defer row.
        row = deep_copy(BASE_ROW)
        row["native"]["name"] = "design-sync"
        row["native"]["markers"] = ["hidden", "gated", "model-invocation-disabled"]
        row["verdict"] = "defer"
        row["integration"] = "route"
        row["baked"]["boundary_section"] = False
        self.assertEqual(overlap.validate_row(row, 0), [])
        row["integration"] = "suggest"
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("`defer`" in problem for problem in problems))

    def test_marketplace_plugin_rejects_suggest(self):
        row = deep_copy(MARKETPLACE_ROW)
        row["integration"] = "suggest"
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("route` or `wrap`" in problem for problem in problems))

    def test_plugin_backed_builtin_allows_wrap_with_evidence(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {
            "name": "security-review",
            "class": "plugin-backed-builtin",
            "markers": [],
        }
        row["integration"] = "wrap"
        row["evidence"] = ["invocation mode: Skill-tool reachable prompt command"]
        self.assertEqual(overlap.validate_row(row, 0), [])

    def test_wrap_without_invocation_evidence_is_a_problem(self):
        row = deep_copy(BASE_ROW)
        row["integration"] = "wrap"
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("invocation mode" in problem for problem in problems))

    def test_native_step_requires_wrap(self):
        row = deep_copy(BASE_ROW)
        row["baked"]["native_step"] = True
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("native_step" in problem for problem in problems))

    def test_suggest_sentence_requires_suggest(self):
        row = deep_copy(BASE_ROW)
        row["baked"]["suggest_sentence"] = True
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("suggest_sentence" in problem for problem in problems))

    def test_agent_rows_are_never_baked(self):
        row = deep_copy(BASE_ROW)
        row["component"] = {"plugin": "demo", "skill": "some-agent", "kind": "agent"}
        row["baked"]["description_phrase"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.assertEqual(self.repo.self_check(), 1)


FIXTURE_UPSTREAM_SHA = "ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12"

MARKETPLACE_ROW = {
    "native": {"name": "demo-upstream", "class": "marketplace-plugin", "markers": []},
    "component": {"plugin": "demo", "skill": "demo-route", "kind": "skill"},
    "verdict": "complementary",
    "reason": "the wrapper routes to the first-party plugin instead of rebuilding it",
    "evidence": ["upstream SKILL.md read at the pinned commit"],
    "observation": {
        "class": "upstream-source",
        "detail": f"upstream repo at commit {FIXTURE_UPSTREAM_SHA}",
        "date": "2026-09-01",
    },
    "recheck": {
        "trigger": "the upstream repository's default branch moves past the pinned commit",
        "verified": "2026-09-01",
    },
    "integration": "route",
    "baked": {
        "description_phrase": False,
        "boundary_section": False,
        "native_step": False,
        "suggest_sentence": False,
    },
    "budget_caveat": False,
}


class MarketplaceLaneTests(unittest.TestCase):
    """The marketplace-plugin class: lanes, validation, parity, freshness."""

    def test_every_native_class_has_a_lane(self):
        # A class without a lane validates and then renders nowhere - the
        # silent-vanish failure this invariant exists to prevent.
        lane_classes = {lane for lane, _heading, _noun in overlap.LANES}
        self.assertEqual(set(overlap.NATIVE_CLASSES), lane_classes)

    def test_every_lane_has_a_native_class(self):
        native = set(overlap.NATIVE_CLASSES)
        for lane, _heading, _noun in overlap.LANES:
            self.assertIn(lane, native)

    def test_valid_marketplace_row_has_no_problems(self):
        self.assertEqual(overlap.validate_row(deep_copy(MARKETPLACE_ROW), 0), [])

    def test_upstream_source_detail_must_name_a_commit(self):
        row = deep_copy(MARKETPLACE_ROW)
        row["observation"]["detail"] = "read from the upstream repo on 2026-09-01"
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("upstream-source" in problem for problem in problems))

    def test_a_bare_numeric_run_is_not_a_commit(self):
        row = deep_copy(MARKETPLACE_ROW)
        row["observation"]["detail"] = "snapshot 20260901 of the upstream repo"
        problems = overlap.validate_row(row, 0)
        self.assertTrue(any("upstream-source" in problem for problem in problems))

    def test_marketplace_row_renders_into_its_lane(self):
        block = overlap.render_block([deep_copy(MARKETPLACE_ROW)])
        self.assertIn("First-party marketplace plugins", block)
        self.assertIn("demo-upstream", block)

    def test_marketplace_forward_parity_wants_the_marketplace_token(self):
        repo = TempRepo(rows=[])
        self.addCleanup(repo.cleanup)
        row = deep_copy(MARKETPLACE_ROW)
        row["baked"]["description_phrase"] = True
        # BASE_ROW rides along so the extraction-version advisory (a store with
        # no extraction row degrades) does not mask the parity verdict.
        repo.write_store(make_store([BASE_ROW, row]))
        repo.generate()
        # The native gate token does not satisfy a marketplace-plugin row.
        repo.write_skill(
            "demo",
            "demo-route",
            description=f"When the upstream thing {overlap.GATE_TOKEN}, route there.",
        )
        self.assertEqual(repo.self_check(upstream_sha=FIXTURE_UPSTREAM_SHA), 1)
        repo.write_skill(
            "demo",
            "demo-route",
            description=(
                "When the upstream plugin is "
                f"{overlap.MARKETPLACE_GATE_TOKEN}, route there."
            ),
        )
        repo.generate()
        self.assertEqual(repo.self_check(upstream_sha=FIXTURE_UPSTREAM_SHA), 0)

    def test_marketplace_token_without_a_row_is_an_orphan(self):
        repo = TempRepo(rows=[])
        self.addCleanup(repo.cleanup)
        repo.generate()
        repo.write_skill(
            "demo",
            "orphan",
            description=(
                f"When the upstream plugin is {overlap.MARKETPLACE_GATE_TOKEN}, "
                "route there."
            ),
        )
        self.assertEqual(repo.self_check(), 1)

    def test_self_check_without_upstream_sha_degrades(self):
        repo = TempRepo(rows=[BASE_ROW, MARKETPLACE_ROW])
        self.addCleanup(repo.cleanup)
        repo.generate()
        self.assertEqual(repo.self_check(), 3)

    def test_self_check_with_matching_upstream_sha_is_ok(self):
        repo = TempRepo(rows=[BASE_ROW, MARKETPLACE_ROW])
        self.addCleanup(repo.cleanup)
        repo.generate()
        self.assertEqual(repo.self_check(upstream_sha=FIXTURE_UPSTREAM_SHA), 0)

    def test_self_check_accepts_one_sha_per_upstream_repository(self):
        # Two upstream-source rows citing two repositories: a recorded commit
        # matches when ANY provided value matches it, so neither drifts.
        other = deep_copy(MARKETPLACE_ROW)
        other["component"]["skill"] = "other-skill"
        other["observation"]["detail"] = (
            "anthropics/claude-code at commit d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b"
        )
        repo = TempRepo([BASE_ROW, MARKETPLACE_ROW, other])
        self.addCleanup(repo.cleanup)
        repo.generate()
        self.assertEqual(
            repo.self_check(
                upstream_sha=[
                    FIXTURE_UPSTREAM_SHA,
                    "d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b",
                ]
            ),
            0,
        )
        self.assertEqual(repo.self_check(upstream_sha=[FIXTURE_UPSTREAM_SHA]), 3)

    def test_self_check_with_short_prefix_sha_still_matches(self):
        repo = TempRepo(rows=[BASE_ROW, MARKETPLACE_ROW])
        self.addCleanup(repo.cleanup)
        repo.generate()
        self.assertEqual(
            repo.self_check(upstream_sha=FIXTURE_UPSTREAM_SHA[:8]),
            0,
        )

    def test_self_check_with_drifted_upstream_sha_degrades(self):
        repo = TempRepo(rows=[BASE_ROW, MARKETPLACE_ROW])
        self.addCleanup(repo.cleanup)
        repo.generate()
        self.assertEqual(
            repo.self_check(upstream_sha="ffffffffffffffffffffffffffffffffffffffff"),
            3,
        )

    def test_self_check_with_whitespace_upstream_sha_degrades_not_passes(self):
        # A value that strips to "" would otherwise match every recorded SHA
        # via startswith and silently suppress the drift advisory.
        repo = TempRepo(rows=[BASE_ROW, MARKETPLACE_ROW])
        self.addCleanup(repo.cleanup)
        repo.generate()
        self.assertEqual(repo.self_check(upstream_sha="   "), 3)

    def test_self_check_with_short_malformed_upstream_sha_degrades(self):
        repo = TempRepo(rows=[BASE_ROW, MARKETPLACE_ROW])
        self.addCleanup(repo.cleanup)
        repo.generate()
        self.assertEqual(repo.self_check(upstream_sha=FIXTURE_UPSTREAM_SHA[:4]), 3)


class DetectTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)
        self.inventory_path = self.repo.root / "inventory.json"
        self.pairs_path = self.repo.root / "pairs.json"
        self.pairs_path.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "pairs": [
                        {
                            "native": {"name": "doctor", "class": "bundled-skill"},
                            "component": {
                                "plugin": "demo",
                                "skill": "demo-audit",
                                "kind": "skill",
                            },
                            "why": "seeded",
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.repo.write_skill("demo", "demo-audit")

    def write_inventory(self, **overrides):
        payload = {
            "schema": 1,
            "builtin_commands": {"help": {"name": "help"}},
            "bundled_skills": {
                "doctor": {
                    "name": "doctor",
                    "gated": True,
                    "hidden": False,
                    "aliases": ["checkup"],
                    "description": "Health-check your setup",
                }
            },
            "plugin_backed": {"security-review": "security-review"},
            "integrity": {
                "status": "ok",
                "cli_version": FIXTURE_CLI_VERSION,
                "validated_against": FIXTURE_CLI_VERSION,
            },
        }
        payload.update(overrides)
        self.inventory_path.write_text(json.dumps(payload), encoding="utf-8")

    def detect(self, out=None):
        args = [
            "detect",
            "--repo",
            str(self.repo.root),
            "--inventory",
            str(self.inventory_path),
            "--pairs",
            str(self.pairs_path),
        ]
        if out is not None:
            args += ["--out", str(out)]
        return overlap.main(args)

    def test_detect_emits_candidates_without_verdicts(self):
        self.write_inventory()
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(len(report["candidates"]), 1)
        candidate = report["candidates"][0]
        self.assertIsNone(candidate["verdict"])
        self.assertTrue(candidate["native"]["observed"])
        self.assertTrue(candidate["component_present"])
        self.assertTrue(any("gated" in item for item in candidate["evidence"]))

    def test_missing_consumed_key_is_broken(self):
        self.write_inventory()
        payload = json.loads(self.inventory_path.read_text(encoding="utf-8"))
        del payload["plugin_backed"]
        self.inventory_path.write_text(json.dumps(payload), encoding="utf-8")
        self.assertEqual(self.detect(), 1)

    def test_wrong_inventory_schema_is_broken(self):
        self.write_inventory(schema=2)
        self.assertEqual(self.detect(), 1)

    def test_degraded_integrity_propagates_as_exit_three(self):
        self.write_inventory(
            integrity={
                "status": "degraded",
                "cli_version": FIXTURE_CLI_VERSION,
                "validated_against": "2.1.228",
            }
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 3)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(report["integrity"]["counts_are"], "floors")

    def test_broken_integrity_is_exit_one(self):
        self.write_inventory(integrity={"status": "broken", "cli_version": None})
        self.assertEqual(self.detect(), 1)

    def test_plugin_backed_lane_is_not_read_as_a_builtin(self):
        self.write_inventory()
        self.pairs_path.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "pairs": [
                        {
                            "native": {
                                "name": "security-review",
                                "class": "plugin-backed-builtin",
                            },
                            "component": {
                                "plugin": "demo",
                                "skill": "demo-audit",
                                "kind": "skill",
                            },
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        candidate = json.loads(out.read_text(encoding="utf-8"))["candidates"][0]
        self.assertEqual(candidate["native"]["class"], "plugin-backed-builtin")

    def write_pairs(self, payload):
        self.pairs_path.write_text(json.dumps(payload), encoding="utf-8")

    def detect_stderr(self):
        """Run detect, returning (exit code, stderr) - never a traceback."""
        buffer = io.StringIO()
        with contextlib.redirect_stderr(buffer):
            code = self.detect()
        return code, buffer.getvalue()

    def test_null_pairs_is_broken_not_a_traceback(self):
        self.write_inventory()
        self.write_pairs({"schema": 1, "pairs": None})
        code, stderr = self.detect_stderr()
        self.assertEqual(code, 1)
        self.assertIn("`pairs` must be a list", stderr)

    def test_non_list_pairs_is_broken(self):
        self.write_inventory()
        self.write_pairs({"schema": 1, "pairs": {"doctor": "demo:demo-audit"}})
        code, stderr = self.detect_stderr()
        self.assertEqual(code, 1)
        self.assertIn("`pairs` must be a list", stderr)

    def test_missing_pairs_key_is_broken(self):
        self.write_inventory()
        self.write_pairs({"schema": 1})
        self.assertEqual(self.detect_stderr()[0], 1)

    def test_non_object_pair_entry_names_its_index(self):
        self.write_inventory()
        self.write_pairs(
            {
                "schema": 1,
                "pairs": [
                    {
                        "native": {"name": "doctor", "class": "bundled-skill"},
                        "component": {
                            "plugin": "demo",
                            "skill": "demo-audit",
                            "kind": "skill",
                        },
                    },
                    "doctor -> demo:demo-audit",
                ],
            }
        )
        code, stderr = self.detect_stderr()
        self.assertEqual(code, 1)
        self.assertIn("pair 1: not an object", stderr)

    def test_pair_with_malformed_native_is_broken(self):
        self.write_inventory()
        self.write_pairs(
            {
                "schema": 1,
                "pairs": [
                    {
                        "native": None,
                        "component": {"plugin": "demo", "skill": "demo-audit"},
                    }
                ],
            }
        )
        code, stderr = self.detect_stderr()
        self.assertEqual(code, 1)
        self.assertIn("pair 0: missing or malformed `native`", stderr)

    def test_pair_with_unknown_native_class_is_broken(self):
        self.write_inventory()
        self.write_pairs(
            {
                "schema": 1,
                "pairs": [
                    {
                        "native": {"name": "doctor", "class": "bundled"},
                        "component": {"plugin": "demo", "skill": "demo-audit"},
                    }
                ],
            }
        )
        code, stderr = self.detect_stderr()
        self.assertEqual(code, 1)
        self.assertIn("pair 0: `native.class`", stderr)

    def test_pair_with_malformed_component_is_broken(self):
        self.write_inventory()
        self.write_pairs(
            {
                "schema": 1,
                "pairs": [
                    {
                        "native": {"name": "doctor", "class": "bundled-skill"},
                        "component": {"plugin": "demo", "skill": 7},
                    }
                ],
            }
        )
        code, stderr = self.detect_stderr()
        self.assertEqual(code, 1)
        self.assertIn("pair 0: `component.skill`", stderr)

    def test_pair_with_unknown_component_kind_is_broken(self):
        self.write_inventory()
        self.write_pairs(
            {
                "schema": 1,
                "pairs": [
                    {
                        "native": {"name": "doctor", "class": "bundled-skill"},
                        "component": {
                            "plugin": "demo",
                            "skill": "demo-audit",
                            "kind": "command",
                        },
                    }
                ],
            }
        )
        code, stderr = self.detect_stderr()
        self.assertEqual(code, 1)
        self.assertIn("pair 0: `component.kind`", stderr)

    def test_pair_without_a_kind_is_accepted_and_defaults_to_skill(self):
        self.write_inventory()
        self.write_pairs(
            {
                "schema": 1,
                "pairs": [
                    {
                        "native": {"name": "doctor", "class": "bundled-skill"},
                        "component": {"plugin": "demo", "skill": "demo-audit"},
                    }
                ],
            }
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        candidate = json.loads(out.read_text(encoding="utf-8"))["candidates"][0]
        self.assertTrue(candidate["component_present"])

    def test_shipped_canonical_pairs_file_validates(self):
        shipped = (
            Path(overlap.__file__).resolve().parent.parent
            / "reference"
            / "canonical-pairs.json"
        )
        payload = json.loads(shipped.read_text(encoding="utf-8"))
        self.assertEqual(overlap.validate_pairs(payload), [])

    def lanes(self, **statuses):
        lanes = {}
        for lane in overlap.LANE_ORDER:
            status = statuses.get(lane, "ok")
            lanes[lane] = {
                "status": status,
                "problems": [f"{lane} failed"] if status == "broken" else [],
                "advisories": [],
            }
        return lanes

    def test_a_broken_lane_marks_its_candidates_not_re_derivable(self):
        # Seeded bundled-skill `doctor`, absent from a broken bundled lane:
        # the seeded class decides the lane, and its absence proves nothing.
        self.write_inventory(
            bundled_skills={},
            integrity={
                "status": "degraded",
                "cli_version": FIXTURE_CLI_VERSION,
                "validated_against": FIXTURE_CLI_VERSION,
                "lanes": self.lanes(bundled_skills="broken"),
            },
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 3)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(
            report["integrity"]["lanes"]["bundled_skills"]["counts_are"],
            "not reportable",
        )
        self.assertEqual(
            report["integrity"]["lanes"]["builtin_commands"]["counts_are"], "totals"
        )
        candidate = report["candidates"][0]
        self.assertFalse(candidate["re_derivable"])
        self.assertTrue(
            any(
                "lane of this extraction is broken" in item
                for item in candidate["evidence"]
            )
        )

    def test_a_healthy_lane_keeps_its_candidates_re_derivable(self):
        self.write_inventory(
            integrity={
                "status": "degraded",
                "cli_version": FIXTURE_CLI_VERSION,
                "validated_against": FIXTURE_CLI_VERSION,
                "lanes": self.lanes(builtin_commands="broken"),
            }
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 3)
        candidate = json.loads(out.read_text(encoding="utf-8"))["candidates"][0]
        self.assertTrue(candidate["re_derivable"])

    def test_a_class_collision_is_marked_in_both_directions(self):
        # Seeded as a bundled skill, observed as a built-in command: a broken
        # lane on EITHER side marks the candidate.
        collided = {
            "builtin_commands": {
                "help": {"name": "help"},
                "doctor": {"name": "doctor"},
            },
            "bundled_skills": {},
        }
        for broken in ("builtin_commands", "bundled_skills"):
            self.write_inventory(
                **collided,
                integrity={
                    "status": "degraded",
                    "cli_version": FIXTURE_CLI_VERSION,
                    "validated_against": FIXTURE_CLI_VERSION,
                    "lanes": self.lanes(**{broken: "broken"}),
                },
            )
            out = self.repo.root / "candidates.json"
            self.assertEqual(self.detect(out), 3)
            candidate = json.loads(out.read_text(encoding="utf-8"))["candidates"][0]
            self.assertEqual(candidate["native"]["class"], "builtin-command")
            self.assertEqual(candidate["native"]["seeded_class"], "bundled-skill")
            self.assertFalse(candidate["re_derivable"], broken)

    def test_top_level_drift_makes_every_ok_lane_report_floors(self):
        # An unvalidated CLI version degrades the run, not a lane; the lane
        # labels must agree with the top-level `counts_are`.
        self.write_inventory(
            integrity={
                "status": "degraded",
                "cli_version": FIXTURE_CLI_VERSION,
                "validated_against": "2.1.228",
                "advisories": [
                    f"cli {FIXTURE_CLI_VERSION} differs from the last validated build "
                    "2.1.228; counts are believed, not verified"
                ],
                "lanes": self.lanes(),
            }
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 3)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(report["integrity"]["counts_are"], "floors")
        for lane in overlap.LANE_ORDER:
            self.assertEqual(report["integrity"]["lanes"][lane]["status"], "ok")
            self.assertEqual(report["integrity"]["lanes"][lane]["counts_are"], "floors")

    def test_a_lane_attributed_advisory_degrades_only_its_lane(self):
        lanes = self.lanes()
        lanes["bundled_skills"]["status"] = "degraded"
        lanes["bundled_skills"]["advisories"] = [
            "1 registration(s) register a dynamic roster"
        ]
        self.write_inventory(
            integrity={
                "status": "degraded",
                "cli_version": FIXTURE_CLI_VERSION,
                "validated_against": FIXTURE_CLI_VERSION,
                "advisories": [
                    "bundled_skills: 1 registration(s) register a dynamic roster"
                ],
                "lanes": lanes,
            }
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 3)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(
            report["integrity"]["lanes"]["bundled_skills"]["counts_are"], "floors"
        )
        self.assertEqual(
            report["integrity"]["lanes"]["builtin_commands"]["counts_are"], "totals"
        )

    def test_an_inventory_without_lanes_keeps_the_old_behavior(
        self,
    ):  # identifier, not prose # spellchecker:disable-line
        self.write_inventory()
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertNotIn("lanes", report["integrity"])
        self.assertTrue(report["candidates"][0]["re_derivable"])

    def test_a_session_skill_candidate_has_no_lane(self):
        self.write_inventory()
        self.write_pairs(
            {
                "schema": 1,
                "pairs": [
                    {
                        "native": {"name": "morning", "class": "session-skill"},
                        "component": {"plugin": "demo", "skill": "demo-audit"},
                    }
                ],
            }
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        self.assertIsNone(
            json.loads(out.read_text(encoding="utf-8"))["candidates"][0]["re_derivable"]
        )

    def test_a_name_collision_lists_every_registration(self):
        self.write_inventory(
            bundled_skills={
                "doctor": [
                    {
                        "name": "doctor",
                        "description": "Hub",
                        "disable_model_invocation": True,
                        "collision": True,
                    },
                    {
                        "name": "doctor",
                        "description": "Canvas",
                        "gated": True,
                        "user_invocable": True,
                        "collision": True,
                    },
                ]
            }
        )
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        evidence = json.loads(out.read_text(encoding="utf-8"))["candidates"][0][
            "evidence"
        ]
        self.assertTrue(any(item.startswith("name collision: 2") for item in evidence))
        self.assertIn("[1] model invocation: disabled", evidence)
        self.assertIn("[2] markers: gated", evidence)
        self.assertIn("[2] native description: Canvas", evidence)

    def test_absent_native_is_reported_as_an_extraction_statement(self):
        self.write_inventory(bundled_skills={})
        out = self.repo.root / "candidates.json"
        self.assertEqual(self.detect(out), 0)
        candidate = json.loads(out.read_text(encoding="utf-8"))["candidates"][0]
        self.assertFalse(candidate["native"]["observed"])
        self.assertTrue(
            any(
                "statement about the extraction" in item
                for item in candidate["evidence"]
            )
        )


class PresenceMentionTests(unittest.TestCase):
    """A presence-gated native mention without the gate token is an advisory."""

    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)
        self.repo.generate()

    def check(self):
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = self.repo.self_check()
        return code, buffer.getvalue()

    def test_presence_clause_without_the_token_is_an_advisory(self):
        self.repo.write_skill(
            "viz",
            "visualize",
            description=(
                "Picks a form (a mermaid diagram, or, where the bundled design skill is "
                "available, a hand-editable design canvas)."
            ),
        )
        code, out = self.check()
        self.assertEqual(code, 3)
        self.assertIn(
            "viz:visualize names a native surface behind a presence condition", out
        )

    def test_presence_clause_in_a_plugin_manifest_is_an_advisory(self):
        manifest = self.repo.root / "plugins" / "viz" / ".claude-plugin" / "plugin.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(
            json.dumps(
                {
                    "name": "viz",
                    "description": "Picks a form, or, where the bundled design skill is available, a canvas.",
                }
            ),
            encoding="utf-8",
        )
        code, out = self.check()
        self.assertEqual(code, 3)
        self.assertIn(
            "viz (plugin.json) names a native surface behind a presence condition", out
        )

    def test_a_description_carrying_the_token_is_left_to_parity(self):
        row = deep_copy(BASE_ROW)
        row["baked"]["description_phrase"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            description=(
                "When the bundled doctor skill resolves in this session, prefer it for the "
                "quick pass."
            ),
            extra=BOUNDARY_EXTRA,
        )
        code, out = self.check()
        self.assertEqual(code, 0)
        self.assertNotIn("presence condition", out)

    def test_the_token_is_judged_per_clause_not_per_description(self):
        # A gated marketplace clause does not excuse an ungated native clause
        # elsewhere in the same description.
        claimed = deep_copy(MARKETPLACE_ROW)
        claimed["component"]["skill"] = "mixed"
        claimed["baked"]["description_phrase"] = True
        self.repo.write_store(make_store([BASE_ROW, claimed]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "mixed",
            description=(
                "Builds mockups (or, where the bundled design skill is available, a canvas). "
                "Not for an explorer: that is the playground skill, routed via /playgrounds:use "
                "where the upstream playground plugin is installed from its marketplace."
            ),
        )
        code, out = self.check()
        self.assertEqual(code, 3)
        self.assertIn("demo:mixed names a native surface", out)

    def test_seam_phrasing_plugin_clause_is_not_flagged(self):
        self.repo.write_skill(
            "demo",
            "seam",
            description="Routes chart craft to the dataviz plugin if that plugin is installed.",
        )
        code, out = self.check()
        self.assertEqual(code, 0)
        self.assertNotIn("presence condition", out)

    def test_not_for_clause_without_a_presence_condition_is_not_flagged(self):
        self.repo.write_skill(
            "demo",
            "notfor",
            description="Audits an install directory. Not for: the bundled doctor skill's fix pass.",
        )
        code, out = self.check()
        self.assertEqual(code, 0)
        self.assertNotIn("presence condition", out)

    def test_a_plain_mention_in_a_when_clause_is_not_flagged(self):
        # "when the user asks about a built-in command" states no presence
        # condition; only an availability word makes one.
        self.repo.write_skill(
            "demo",
            "plain",
            description="Use when the user asks whether a built-in command is a real command.",
        )
        code, out = self.check()
        self.assertEqual(code, 0)
        self.assertNotIn("presence condition", out)


class SuggestAndNativeStepParityTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def _export_suggest_row(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "export", "class": "builtin-command", "markers": []}
        row["integration"] = "suggest"
        row["evidence"] = ["invocation mode: local-jsx command type"]
        row["baked"]["suggest_sentence"] = True
        return row

    def test_suggest_sentence_forward_parity_wants_the_shape(self):
        self.repo.write_store(make_store([self._export_suggest_row()]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            extra="\n## Boundary, the built-in `export` command\n\nDetail.\n",
        )
        self.assertEqual(self.repo.self_check(), 1)

    def test_suggest_sentence_forward_parity_holds_on_the_shape(self):
        self.repo.write_store(make_store([self._export_suggest_row()]))
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "demo-audit",
            extra=(
                "\n## Boundary, the built-in `export` command\n\nDetail.\n\n"
                "If /export is available in your session (gate basis: recorded here), "
                "run it for a durable copy.\n"
            ),
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_suggest_shape_without_a_row_is_an_orphan(self):
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "orphan",
            extra=(
                "\nIf /export is available in your session (basis), run it for a copy.\n"
            ),
        )
        self.assertEqual(self.repo.self_check(), 1)

    def test_bare_available_phrase_is_not_a_suggest_orphan(self):
        # claude-ops:changelog carries this phrase in unrelated prose.
        self.repo.generate()
        self.repo.write_skill(
            "demo",
            "changelog",
            extra=(
                "\nUpdate first or changes may reference features not yet "
                "available in your session.\n"
            ),
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_native_step_forward_parity_wants_the_heading(self):
        row = deep_copy(BASE_ROW)
        row["integration"] = "wrap"
        row["evidence"] = [
            "invocation mode: model-invocable, no disableModelInvocation"
        ]
        row["baked"]["native_step"] = True
        self.repo.write_store(make_store([row]))
        self.repo.generate()
        self.assertEqual(self.repo.self_check(), 1)
        self.repo.write_skill(
            "demo",
            "demo-audit",
            extra="\n## Boundary, the bundled `doctor` skill\n\nDetail.\n\n"
            "## Native step: doctor (bundled skill)\n\n"
            "When it resolves in this session, invoke it.\n",
        )
        self.assertEqual(self.repo.self_check(), 0)

    def test_generate_renders_the_integration_column(self):
        self.repo.generate()
        text = self.repo.view_path.read_text(encoding="utf-8")
        self.assertIn("| Lane | Rows | Baked | Integration | Verdicts |", text)
        self.assertIn("- **Integration:** `route`", text)


class ScanTests(unittest.TestCase):
    def test_repo_tree_scan_finds_skills_and_agents(self):
        repo = TempRepo()
        self.addCleanup(repo.cleanup)
        repo.write_skill("alpha", "one")
        repo.write_skill("beta", "two")
        agents = repo.root / "plugins" / "alpha" / "agents"
        agents.mkdir(parents=True, exist_ok=True)
        (agents / "helper.md").write_text("---\nname: helper\n---\n", encoding="utf-8")
        found = overlap.scan_components(repo.root)
        # TempRepo seeds demo:demo-audit for BASE_ROW; the scan reports it too.
        self.assertEqual(found["skills"], ["alpha:one", "beta:two", "demo:demo-audit"])
        self.assertEqual(found["agents"], ["alpha:helper"])

    def test_scan_of_a_tree_without_plugins_is_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = overlap.scan_components(Path(tmp))
            self.assertEqual(found, {"skills": [], "agents": []})


def surface(name, klass="bundled-skill", **fields):
    lane = overlap.LANE_OF_CLASS[klass]
    return discover.Surface.build(name, klass, lane, [{"name": name, **fields}])


class DiscoveryScoringTests(unittest.TestCase):
    def test_tokenize_stems_expands_and_stoplists(self):
        self.assertEqual(discover.tokenize("verify"), discover.tokenize("verification"))
        self.assertEqual(discover.tokenize("pr"), ["pr", "pull", "request"])
        self.assertIn("agent", discover.tokenize("subagents"))
        self.assertEqual(discover.tokenize("the skill for Claude Code"), [])
        self.assertNotEqual(discover.tokenize("states"), discover.tokenize("stats"))

    def test_a_name_match_outscores_an_unrelated_component(self):
        native = surface("commit", description="Create a git commit")
        ours = discover.Component.build(
            "source-control", "commit", "skill", "Create a git commit with a trailer."
        )
        other = discover.Component.build(
            "songwriting", "rhyme", "skill", "Find rhymes for a lyric line."
        )
        found = discover.discover([native], [ours, other], threshold=0.0, top_k=5)
        ranked = [(c.plugin, c.name) for _s, c, _score, _m in found]
        self.assertEqual(ranked[0], ("source-control", "commit"))
        self.assertNotIn(("songwriting", "rhyme"), ranked)  # no shared token at all
        self.assertIn("commit", found[0][3])

    def test_threshold_and_top_k_bound_the_result(self):
        native = surface("pr", description="Create a pull request")
        corpus = [
            discover.Component.build(
                "vcs", f"pull-request-{n}", "skill", "Open a pull request."
            )
            for n in range(5)
        ]
        self.assertEqual(len(discover.discover([native], corpus, top_k=2)), 2)
        self.assertEqual(
            discover.discover([native], corpus, threshold=1.01, top_k=5), []
        )

    def test_invocability_maps_every_combination(self):
        cases = [
            ({"model_invocable": True, "user_invocable": True}, "model+user"),
            ({"model_invocable": False, "user_invocable": True}, "user-only"),
            ({"model_invocable": True, "user_invocable": False}, "model-only"),
            ({"user_invocable": True}, "unknown"),
            ({}, "unknown"),
            ({"disable_model_invocation": True, "user_invocable": True}, "user-only"),
        ]
        for fields, expected in cases:
            with self.subTest(fields=fields):
                self.assertEqual(
                    discover.invocability([fields])["invocable_by"], expected
                )

    def test_disagreeing_registrations_are_unknown(self):
        who = discover.invocability(
            [
                {"model_invocable": True, "user_invocable": True},
                {"model_invocable": False, "user_invocable": True},
            ]
        )
        self.assertIsNone(who["model_invocable"])
        self.assertEqual(who["invocable_by"], "unknown")

    def test_recommended_integration_is_a_label_per_invocability(self):
        rec = discover.recommended_integration
        self.assertEqual(rec("bundled-skill", "user-only"), "suggest")
        self.assertEqual(rec("bundled-skill", "model+user"), "route-or-wrap")
        self.assertEqual(rec("builtin-command", "model+user"), "route")
        self.assertEqual(rec("bundled-workflow", "model+user"), "route")
        self.assertIsNone(rec("bundled-skill", "unknown"))


class DiscoveryDetectTests(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)
        self.repo.write_skill(
            "source-control",
            "commit",
            description="Create a git commit with a trailer.",
        )
        self.repo.write_skill(
            "songwriting", "rhyme", description="Find rhymes for a lyric."
        )
        self.pairs_path = self.repo.root / "pairs.json"
        self.pairs_path.write_text(
            json.dumps({"schema": 1, "pairs": []}), encoding="utf-8"
        )
        self.inventory_path = self.repo.root / "inventory.json"
        self.out = self.repo.root / "candidates.json"

    def write_inventory(self, **overrides):
        payload = {
            "schema": 1,
            "builtin_commands": {},
            "bundled_skills": {
                "commit": {"name": "commit", "description": "Create a git commit"}
            },
            "plugin_backed": {},
            "integrity": {"status": "ok"},
        }
        payload.update(overrides)
        self.inventory_path.write_text(json.dumps(payload), encoding="utf-8")

    def detect(self, *extra):
        code = overlap.main(
            [
                "detect",
                "--repo",
                str(self.repo.root),
                "--inventory",
                str(self.inventory_path),
                "--pairs",
                str(self.pairs_path),
                "--out",
                str(self.out),
                *extra,
            ]
        )
        return code, json.loads(self.out.read_text(encoding="utf-8"))

    def discovered(self, report):
        return [c for c in report["candidates"] if c["origin"] == "discovered"]

    def test_a_discovered_candidate_carries_score_tokens_and_no_verdict(self):
        self.write_inventory()
        code, report = self.detect()
        self.assertEqual(code, 0)
        [candidate] = self.discovered(report)
        self.assertEqual(candidate["component"]["skill"], "commit")
        self.assertGreater(candidate["score"], 0.3)
        self.assertIn("commit", candidate["matched_tokens"])
        self.assertIsNone(candidate["verdict"])
        self.assertIsNone(candidate["store_verdict"])
        self.assertEqual(report["discovery"]["discovered"], 1)

    def test_a_high_threshold_or_zero_top_k_discovers_nothing(self):
        self.write_inventory()
        self.assertEqual(self.discovered(self.detect("--threshold", "1.01")[1]), [])
        self.assertEqual(self.discovered(self.detect("--top-k", "0")[1]), [])

    def test_a_seeded_pair_is_not_repeated_as_discovered(self):
        self.write_inventory()
        pair = {
            "native": {"name": "commit", "class": "bundled-skill"},
            "component": {
                "plugin": "source-control",
                "skill": "commit",
                "kind": "skill",
            },
        }
        self.pairs_path.write_text(
            json.dumps({"schema": 1, "pairs": [pair]}), encoding="utf-8"
        )
        _code, report = self.detect()
        self.assertEqual(self.discovered(report), [])
        [seeded] = report["candidates"]
        self.assertEqual(seeded["origin"], "seeded")
        self.assertIsNotNone(seeded["score"])

    def test_a_pair_already_in_the_store_is_reported_as_existing(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "commit", "class": "bundled-skill", "markers": []}
        row["component"] = {
            "plugin": "source-control",
            "skill": "commit",
            "kind": "skill",
        }
        self.repo.write_store(make_store([row]))
        self.write_inventory()
        _code, report = self.detect()
        self.assertEqual(self.discovered(report), [])
        [existing] = report["discovery"]["existing"]
        self.assertEqual(existing["store_verdict"], "complementary")

    def test_internal_commands_are_never_scored(self):
        self.write_inventory(
            bundled_skills={},
            builtin_commands={
                "commit": {"name": "commit", "description": "Commit", "internal": True}
            },
        )
        _code, report = self.detect()
        self.assertEqual(report["discovery"]["surfaces_scored"], 0)
        self.assertEqual(self.discovered(report), [])

    def test_the_workflow_lane_is_optional(self):
        self.write_inventory()
        code, report = self.detect()
        self.assertEqual(code, 0)
        self.assertNotIn("bundled_workflows", report["discovery"]["lanes_scored"])
        self.repo.write_skill(
            "discovery", "research-deep", description="Dispatch deep external research."
        )
        self.write_inventory(
            bundled_workflows={
                "deep-research": {
                    "name": "deep-research",
                    "description": "Deep research",
                }
            }
        )
        code, report = self.detect()
        self.assertEqual(code, 0)
        self.assertIn("bundled_workflows", report["discovery"]["lanes_scored"])
        classes = {
            c["native"]["name"]: c["native"]["class"] for c in self.discovered(report)
        }
        self.assertEqual(classes.get("deep-research"), "bundled-workflow")

    def test_missing_invocability_fields_degrade_to_unknown(self):
        self.write_inventory()
        _code, report = self.detect()
        [candidate] = self.discovered(report)
        self.assertEqual(candidate["native"]["invocable_by"], "unknown")
        self.assertIsNone(candidate["native"]["model_invocable"])
        self.assertIsNone(candidate["native"]["argument_hint"])
        self.assertIsNone(candidate["recommended_integration"])

    def test_a_user_only_surface_recommends_suggest_and_carries_the_marker(self):
        self.write_inventory(
            bundled_skills={
                "commit": {
                    "name": "commit",
                    "description": "Create a git commit",
                    "model_invocable": False,
                    "user_invocable": True,
                    "argument_hint": "[message]",
                }
            }
        )
        _code, report = self.detect()
        [candidate] = self.discovered(report)
        self.assertEqual(candidate["native"]["invocable_by"], "user-only")
        self.assertEqual(candidate["native"]["argument_hint"], "[message]")
        self.assertIn("model-invocation-disabled", candidate["native"]["markers"])
        self.assertEqual(candidate["recommended_integration"], "suggest")
        self.assertIn("model invocation: disabled", candidate["evidence"])

    def test_a_model_invocable_skill_recommends_route_or_wrap(self):
        self.write_inventory(
            bundled_skills={
                "commit": {
                    "name": "commit",
                    "description": "Create a git commit",
                    "model_invocable": True,
                    "user_invocable": True,
                }
            }
        )
        _code, report = self.detect()
        [candidate] = self.discovered(report)
        self.assertEqual(candidate["native"]["invocable_by"], "model+user")
        self.assertEqual(candidate["native"]["markers"], [])
        self.assertEqual(candidate["recommended_integration"], "route-or-wrap")


class PluginBackedSurfaceTests(unittest.TestCase):
    def test_an_enriched_command_is_one_plugin_backed_surface(self) -> None:
        payloads = {
            "builtin_commands": {
                "scan": {
                    "name": "scan",
                    "description": "Scan the branch for vulnerabilities",
                    "plugin_name": "scanner",
                }
            },
            "plugin_backed": {"scan": "scanner"},
        }
        surfaces = overlap.native_surfaces(payloads)
        self.assertEqual([s.name for s in surfaces], ["scan"])
        self.assertEqual(surfaces[0].klass, overlap.CLASS_OF_LANE["plugin_backed"])
        self.assertTrue(surfaces[0].described)

    def test_a_bare_plugin_backed_name_still_scores(self) -> None:
        surfaces = overlap.native_surfaces({"plugin_backed": {"scan": "scanner"}})
        self.assertEqual([s.name for s in surfaces], ["scan"])


def make_dismissal(**overrides):
    entry = {
        "native": {"name": "commit", "class": "bundled-skill"},
        "component": {"plugin": "source-control", "skill": "commit", "kind": "skill"},
        "reason": "shared word only",
        "as_of": "2.1.284",
        "date": "2026-09-29",
        "fingerprint": {"native": "0" * 32, "component": "1" * 32},
    }
    entry.update(overrides)
    return entry


class DismissalValidationTests(unittest.TestCase):
    def store(self, dismissals, rows=()):
        store = make_store(list(rows))
        store["dismissals"] = dismissals
        return store

    def test_a_well_formed_dismissal_has_no_problems(self):
        self.assertEqual(overlap.validate_store(self.store([make_dismissal()])), [])

    def test_a_store_without_dismissals_stays_valid(self):
        self.assertEqual(overlap.validate_store(make_store([BASE_ROW])), [])

    def test_each_required_field_is_checked(self):
        for field, bad in (
            ("reason", " "),
            ("as_of", "latest"),
            ("date", "yesterday"),
            ("fingerprint", {"native": "abc"}),
        ):
            with self.subTest(field=field):
                problems = overlap.validate_store(
                    self.store([make_dismissal(**{field: bad})])
                )
                self.assertTrue(any(f"`{field}`" in p for p in problems), problems)

    def test_dismissals_must_be_a_list(self):
        store = make_store([])
        store["dismissals"] = {}
        self.assertIn(
            "store `dismissals` must be a list when present",
            overlap.validate_store(store),
        )

    def test_a_duplicate_dismissal_is_a_problem(self):
        problems = overlap.validate_store(self.store([make_dismissal()] * 2))
        self.assertTrue(any("duplicate dismissal" in p for p in problems))

    def test_a_dismissal_never_coexists_with_a_verdict_row(self):
        row = deep_copy(BASE_ROW)
        dismissal = make_dismissal(
            native={"name": "doctor", "class": "bundled-skill"},
            component=deep_copy(BASE_ROW["component"]),
        )
        problems = overlap.validate_store(self.store([dismissal], rows=[row]))
        self.assertTrue(any("coexists with a verdict row" in p for p in problems))

    def test_self_check_breaks_on_a_dismissal_beside_its_verdict_row(self):
        repo = TempRepo()
        self.addCleanup(repo.cleanup)
        store = make_store([BASE_ROW])
        store["dismissals"] = [
            make_dismissal(
                native={"name": "doctor", "class": "bundled-skill"},
                component=deep_copy(BASE_ROW["component"]),
            )
        ]
        repo.write_store(store)
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(repo.self_check(), 1)


class DismissalRenderTests(unittest.TestCase):
    def test_an_empty_store_renders_an_empty_dismissed_section(self):
        block = overlap.render_block([deep_copy(BASE_ROW)])
        self.assertIn("## Dismissed", block)
        self.assertIn("No dismissals recorded.", block)

    def test_a_dismissal_renders_as_a_table_row(self):
        block = overlap.render_block(
            [deep_copy(BASE_ROW)],
            [make_dismissal(reason="shared | word")],
        )
        self.assertIn("| Native surface | Class | Component |", block)
        self.assertIn(
            "| `commit` | bundled-skill | `source-control:commit` | shared \\| word "
            "| 2.1.284 | 2026-09-29 |",
            block,
        )

    def test_generate_check_tracks_dismissals(self):
        repo = TempRepo()
        self.addCleanup(repo.cleanup)
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(repo.generate(), 0)
            store = make_store([BASE_ROW])
            store["dismissals"] = [make_dismissal()]
            repo.write_store(store)
            self.assertEqual(repo.generate(["--check"]), 1)
            self.assertEqual(repo.generate(), 0)
            self.assertEqual(repo.generate(["--check"]), 0)
        self.assertIn("`source-control:commit`", repo.view_path.read_text("utf-8"))


class DismissalDetectTests(unittest.TestCase):
    """Dismiss, then detect: suppression and resurfacing."""

    # The discovery harness, borrowed without inheriting its tests.
    setUp = DiscoveryDetectTests.setUp
    write_inventory = DiscoveryDetectTests.write_inventory
    detect = DiscoveryDetectTests.detect
    discovered = DiscoveryDetectTests.discovered

    def dismiss(self, *extra, native="commit", component="source-control:commit"):
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            return overlap.main(
                [
                    "dismiss",
                    "--repo",
                    str(self.repo.root),
                    "--store",
                    str(self.repo.store_path),
                    "--inventory",
                    str(self.inventory_path),
                    "--native",
                    native,
                    "--component",
                    component,
                    "--reason",
                    "shared word only",
                    "--date",
                    "2026-09-29",
                    *extra,
                ]
            )

    def stored_dismissals(self):
        return json.loads(self.repo.store_path.read_text("utf-8"))["dismissals"]

    def test_dismiss_records_both_fingerprints_and_the_version(self):
        self.write_inventory(integrity={"status": "ok", "cli_version": "2.1.284"})
        self.assertEqual(self.dismiss(), 0)
        [entry] = self.stored_dismissals()
        self.assertEqual(entry["as_of"], "2.1.284")
        self.assertEqual(entry["native"], {"name": "commit", "class": "bundled-skill"})
        self.assertEqual(
            entry["fingerprint"]["native"], overlap.fingerprint("Create a git commit")
        )
        self.assertEqual(
            entry["fingerprint"]["component"],
            overlap.fingerprint("Create a git commit with a trailer."),
        )

    def test_dismiss_refreshes_rather_than_duplicates(self):
        self.write_inventory()
        self.assertEqual(self.dismiss("--as-of", "2.1.284"), 0)
        self.assertEqual(self.dismiss("--as-of", "2.1.285"), 0)
        [entry] = self.stored_dismissals()
        self.assertEqual(entry["as_of"], "2.1.285")

    def test_dismiss_refuses_a_pair_with_a_verdict_row(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "commit", "class": "bundled-skill", "markers": []}
        row["component"] = {
            "plugin": "source-control",
            "skill": "commit",
            "kind": "skill",
        }
        self.repo.write_store(make_store([row]))
        self.write_inventory()
        self.assertEqual(self.dismiss("--as-of", "2.1.284"), 1)

    def test_dismiss_refuses_a_surface_absent_from_the_extraction(self):
        self.write_inventory()
        self.assertEqual(self.dismiss("--as-of", "2.1.284", native="nope"), 1)

    def test_dismiss_refuses_without_a_version(self):
        self.write_inventory()
        self.assertEqual(self.dismiss(), 1)

    def test_a_dismissed_pair_is_suppressed_and_counted(self):
        self.write_inventory()
        self.assertEqual(self.dismiss("--as-of", "2.1.284"), 0)
        code, report = self.detect()
        self.assertEqual(code, 0)
        self.assertEqual(self.discovered(report), [])
        [suppressed] = report["discovery"]["suppressed"]
        self.assertEqual(suppressed["native"], "commit")
        self.assertEqual(suppressed["reason"], "shared word only")
        self.assertEqual(report["discovery"]["resurfaced"], 0)

    def test_a_native_description_change_resurfaces_the_pair(self):
        self.write_inventory()
        self.assertEqual(self.dismiss("--as-of", "2.1.284"), 0)
        self.write_inventory(
            bundled_skills={
                "commit": {
                    "name": "commit",
                    "description": "Create a signed git commit",
                }
            }
        )
        _code, report = self.detect()
        [candidate] = self.discovered(report)
        self.assertEqual(candidate["resurfaced"]["flag"], overlap.RESURFACED)
        self.assertEqual(candidate["resurfaced"]["sides"], ["native"])
        self.assertTrue(
            any(e.startswith(overlap.RESURFACED) for e in candidate["evidence"])
        )
        self.assertEqual(report["discovery"]["suppressed"], [])
        self.assertEqual(report["discovery"]["resurfaced"], 1)

    def test_a_component_description_change_resurfaces_the_pair(self):
        self.write_inventory()
        self.assertEqual(self.dismiss("--as-of", "2.1.284"), 0)
        self.repo.write_skill(
            "source-control", "commit", description="Create a git commit and push it."
        )
        _code, report = self.detect()
        [candidate] = self.discovered(report)
        self.assertEqual(candidate["resurfaced"]["sides"], ["component"])

    def test_whitespace_reflow_does_not_resurface(self):
        self.write_inventory()
        self.assertEqual(self.dismiss("--as-of", "2.1.284"), 0)
        self.write_inventory(
            bundled_skills={
                "commit": {"name": "commit", "description": "Create  a git\ncommit"}
            }
        )
        _code, report = self.detect()
        self.assertEqual(self.discovered(report), [])

    def test_a_dismissed_seed_is_suppressed_too(self):
        self.write_inventory()
        self.assertEqual(self.dismiss("--as-of", "2.1.284"), 0)
        pair = {
            "native": {"name": "commit", "class": "bundled-skill"},
            "component": {"plugin": "source-control", "skill": "commit"},
        }
        self.pairs_path.write_text(
            json.dumps({"schema": 1, "pairs": [pair]}), encoding="utf-8"
        )
        _code, report = self.detect()
        self.assertEqual(report["candidates"], [])
        self.assertEqual(len(report["discovery"]["suppressed"]), 1)

    def test_a_verdict_row_never_resurfaces(self):
        row = deep_copy(BASE_ROW)
        row["native"] = {"name": "commit", "class": "bundled-skill", "markers": []}
        row["component"] = {
            "plugin": "source-control",
            "skill": "commit",
            "kind": "skill",
        }
        store = make_store([row])
        # Even beside a (malformed-by-policy) dismissal whose fingerprints no
        # longer match, the verdict row wins: the pair stays under `existing`.
        store["dismissals"] = [make_dismissal()]
        self.repo.write_store(store)
        self.write_inventory()
        _code, report = self.detect()
        self.assertEqual(self.discovered(report), [])
        self.assertEqual(report["discovery"]["suppressed"], [])
        [existing] = report["discovery"]["existing"]
        self.assertEqual(existing["store_verdict"], "complementary")

    def test_every_candidate_carries_fingerprints(self):
        self.write_inventory()
        _code, report = self.detect()
        [candidate] = self.discovered(report)
        self.assertEqual(
            candidate["fingerprints"],
            {
                "native": overlap.fingerprint("Create a git commit"),
                "component": overlap.fingerprint("Create a git commit with a trailer."),
            },
        )
        self.assertIsNone(candidate["resurfaced"])


if __name__ == "__main__":
    unittest.main()
