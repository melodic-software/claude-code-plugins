#!/usr/bin/env python3
# test-scope: plugins/evals/skills/plugin-eval/scripts/select-cases.py plugins/evals/skills/plugin-eval/scripts/select_mapping.py plugins/evals/skills/plugin-eval/scripts/no_run_text.py
"""Tests for the edits select-cases.py runs no eval case for: Next, Related and See also edits,
routing-only description edits, decided-term swaps and comment-line deletions.
"""

import json
import os
import tempfile
import unittest
from pathlib import Path

from select_test_helpers import (
    _build_fixture_repo,
    _commit_all,
    _git,
    _parse_blocks,
    _run_select,
    _write,
)

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"


class SelectCasesNoRunTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        _build_fixture_repo(self.repo)

    def tearDown(self):
        self._tmp.cleanup()

    def _base_with_next_section(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8") + (
            "\n## Next\n\n- Done, when available: /alpha:two\n- Stuck: /alpha:three\n"
            "\n## Gotchas\n\n- Keep it short.\n"
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "add Next section")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return path

    def test_next_section_edit_is_no_run(self):
        path = self._base_with_next_section()
        text = path.read_text(encoding="utf-8").replace(
            "- Done, when available: /alpha:two\n", "- Done: /alpha:two.\n"
        )
        path.write_text(text.replace("- Stuck: /alpha:three\n", ""), encoding="utf-8")
        _commit_all(self.repo, "trim Next")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual("0", blocks["plugins/alpha"]["agent-runs"])

    def test_edit_outside_next_section_still_cuts(self):
        path = self._base_with_next_section()
        text = path.read_text(encoding="utf-8").replace("- Keep it short.\n", "- Keep it long.\n")
        path.write_text(text.replace("- Stuck: /alpha:three\n", ""), encoding="utf-8")
        _commit_all(self.repo, "trim Next and reword a gotcha")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            blocks["plugins/alpha"]["cases"],
        )

    def _base_with_sections(self, headings):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        extra = "".join("\n## %s\n\n- Sibling: /alpha:two\n" % h for h in headings)
        path.write_text(
            path.read_text(encoding="utf-8") + extra + "\n## Gotchas\n\n- Keep it short.\n",
            encoding="utf-8",
        )
        _commit_all(self.repo, "add sections")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return path

    def _edit_and_select(self, path, old, new):
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding="utf-8")
        _commit_all(self.repo, "edit skill")
        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        return _parse_blocks(res.stdout)["plugins/alpha"]

    def test_related_and_see_also_section_edits_are_no_run(self):
        path = self._base_with_sections(["Related", "See also"])
        block = self._edit_and_select(
            path, "- Sibling: /alpha:two\n", "- Sibling, for audits: /alpha:three\n"
        )
        self.assertNotIn("cases", block, "Related and See also edits must run no case")
        self.assertEqual("0", block["agent-runs"])

    def test_routing_heading_renamed_to_related_is_no_run(self):
        path = self._base_with_sections(["Boundaries", "What this skill does not do"])
        block = self._edit_and_select(path, "## Boundaries\n", "## Related\n")
        self.assertNotIn("cases", block, "a Boundaries-to-Related rename must run no case")
        block = self._edit_and_select(
            path, "## What this skill does not do\n", "## Scope boundary\n"
        )
        self.assertNotIn("cases", block, "a rename between routing headings must run no case")

    def test_non_routing_heading_renamed_to_related_still_cuts(self):
        path = self._base_with_sections([])
        block = self._edit_and_select(path, "## Gotchas\n", "## Related\n")
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "renaming Gotchas is a cut: only routing headings are exempt",
        )

    def _set_base_description(self, description):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            'description: "Run alpha one checks. Use when checking alpha items."',
            'description: "%s"' % description,
        )
        path.write_text(text, encoding="utf-8")
        _commit_all(self.repo, "set base description")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return path

    def _write_glossary(self):
        _write(
            self.repo,
            "docs/glossary.md",
            """
            # Glossary

            ## Rejected terms

            | Rejected | Owned by |
            |---|---|
            | lane *(the slice a hunt rotates through)* | focus area, the word hunts use |
            | lane *(one concern an audit judges)* | concern, the word audits use |
            | stage runner | **lane** above |
            """,
        )

    def _assert_exempt(self, block):
        self.assertNotIn("cases", block, "an exempt description edit must run no case")
        self.assertNotIn("run-after-merge", block, "an exempt edit schedules no later run")
        self.assertEqual(
            "control-no-fire one-trigger opt-case",
            block.get("affected-no-run"),
            "the triggering and no-fire cases are listed as affected but not run",
        )
        exempt, _, reason = block.get("no-run-exempt", "").partition(";")
        self.assertEqual("alpha:one", exempt)
        self.assertIn("routing clauses", reason, "the line states why nothing runs")
        self.assertEqual("0", block["agent-runs"])

    def test_added_not_for_clause_is_exempt(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        self._assert_exempt(
            self._edit_and_select(
                path,
                "Use when checking alpha items.",
                "Use when checking alpha items. Not for beta sweeps: /beta:runner.",
            )
        )

    def test_reworded_skip_clause_is_exempt(self):
        path = self._set_base_description(
            "Run alpha one checks. Use when checking alpha items. Skip when sweeping (beta:runner)."
        )
        self._assert_exempt(
            self._edit_and_select(
                path,
                "Skip when sweeping (beta:runner).",
                "Skip when a sweep is asked for: /beta:runner.",
            )
        )

    def test_removed_prefer_clause_is_exempt(self):
        path = self._set_base_description(
            "Run alpha one checks; prefer /beta:runner. Use when checking alpha items."
        )
        self._assert_exempt(
            self._edit_and_select(
                path,
                "Run alpha one checks; prefer /beta:runner.",
                "Run alpha one checks.",
            )
        )

    def test_trigger_words_after_a_routed_skill_are_cut(self):
        path = self._set_base_description(
            "Run alpha one checks."
            " Prefer this skill over /beta:runner when the user asks for deploys."
        )
        block = self._edit_and_select(path, "asks for deploys", "asks for rollbacks")
        self.assertNotIn("no-run-exempt", block, "deploys is trigger wording after the skill")

    def test_numeric_colon_value_change_is_cut(self):
        path = self._set_base_description(
            "Run alpha one checks at 10:30. Use when checking alpha items."
        )
        block = self._edit_and_select(path, "at 10:30", "at 11:45")
        self.assertNotIn("no-run-exempt", block, "10:30 is a time, not a skill token")

    def test_skill_token_form_change_is_exempt(self):
        path = self._set_base_description(
            "Run alpha one checks after beta:runner. Use when checking alpha items."
        )
        self._assert_exempt(
            self._edit_and_select(path, "after beta:runner.", "after /beta:runner.")
        )

    def test_swapping_in_another_skill_outside_a_routing_clause_is_cut(self):
        path = self._set_base_description(
            "Run alpha one checks after /beta:runner. Use when checking alpha items."
        )
        block = self._edit_and_select(path, "after /beta:runner.", "after /beta:sweeper.")
        self.assertNotIn("no-run-exempt", block, "only a token's form is exempt, not its skill")

    def test_capitalized_token_ending_a_routing_segment_is_not_routing(self):
        import no_run_text

        old = "Run checks. Not for Python:Django, use alpha."
        self.assertFalse(no_run_text.is_routing_only_change(old, "Run checks.", ()))

    def test_non_skill_colon_value_change_is_cut(self):
        path = self._set_base_description(
            "Run alpha one checks in mode:fast. Use when checking alpha items."
        )
        block = self._edit_and_select(path, "in mode:fast.", "in mode:slow.")
        self.assertNotIn("no-run-exempt", block, "mode is no plugin, so mode:fast is a value")

    def test_glossary_decided_term_swap_is_exempt(self):
        self._write_glossary()
        path = self._set_base_description(
            "Run alpha one checks over a rotated lane, one concern lane at a time."
            " Use when checking alpha lanes."
        )
        self._assert_exempt(
            self._edit_and_select(
                path,
                "over a rotated lane, one concern lane at a time. Use when checking alpha lanes.",
                "over a rotated focus area, one concern at a time."
                " Use when checking alpha focus areas.",
            )
        )

    def test_swap_to_an_undecided_term_is_cut(self):
        self._write_glossary()
        path = self._set_base_description(
            "Run alpha one checks over a rotated lane. Use when checking alpha items."
        )
        block = self._edit_and_select(path, "rotated lane.", "rotated track.")
        self.assertNotIn("no-run-exempt", block, "track is not the glossary's decided word")
        self.assertEqual("control-no-fire one-basic one-trigger opt-case", block.get("cases"))

    def test_rewording_beside_a_routing_clause_is_cut(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        block = self._edit_and_select(
            path,
            'description: "Run alpha one checks. Use when checking alpha items."',
            'description: "Run alpha one audits. Use when checking alpha items.'
            ' Not for beta sweeps: /beta:runner."',
        )
        self.assertNotIn("no-run-exempt", block, "checks to audits is a real rewording")
        self.assertEqual("control-no-fire one-basic one-trigger opt-case", block.get("cases"))
        self.assertEqual("20", block["agent-runs"])

    def test_trigger_rewording_in_a_prefer_sentence_is_cut(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                'alpha items."', 'alpha items, and prefer /beta:runner for sweeps."'
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "add a prefer clause")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(path, "checking alpha items,", "deploying services,")
        self.assertNotIn("no-run-exempt", block, "the Use when trigger was rewritten")
        self.assertEqual("control-no-fire one-basic one-trigger opt-case", block.get("cases"))

    def test_trigger_word_beside_a_later_routing_clause_is_cut(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                'alpha items."', 'alpha items, prefer speed, not for sweeps: /beta:runner."'
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "add a routing clause after a trigger word")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(path, "prefer speed", "prefer depth")
        self.assertNotIn("no-run-exempt", block, "prefer speed is trigger wording")

    def test_glossary_row_added_on_the_branch_exempts_nothing(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "Follow these steps carefully.\n",
                "Follow these steps carefully.\nHunt one rotated lane at a time.\n",
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "add lane wording")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        self._write_glossary()
        block = self._edit_and_select(path, "rotated lane at", "rotated focus area at")
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "a row the branch adds cannot exempt the branch's own swap",
        )

    def _base_with_lane_text(self):
        self._write_glossary()
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            'alpha items."\n', 'alpha items."\nargument-hint: "[--lane <lane>]"\n'
        )
        path.write_text(
            text.replace(
                "Follow these steps carefully.\n",
                "Follow these steps carefully.\nHunt one rotated lane at a time.\n",
            ),
            encoding="utf-8",
        )
        _write(self.repo, "plugins/alpha/evals/one-basic/prompt.md", "/alpha:one check this lane\n")
        _commit_all(self.repo, "add lane wording")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return path

    def test_decided_term_swap_in_body_hunk_is_no_run(self):
        path = self._base_with_lane_text()
        block = self._edit_and_select(path, "rotated lane at", "rotated focus area at")
        self.assertNotIn("cases", block, "a body hunk that only swaps a decided term runs nothing")
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_decided_term_flag_rename_in_argument_hint_is_no_run(self):
        path = self._base_with_lane_text()
        block = self._edit_and_select(path, "[--lane <lane>]", "[--area <area>]")
        self.assertNotIn(
            "cases", block, "--lane to --area takes the last word of the decided focus area"
        )
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_decided_term_swap_in_eval_prompt_is_no_run(self):
        self._base_with_lane_text()
        prompt = self.repo / "plugins/alpha/evals/one-basic/prompt.md"
        block = self._edit_and_select(prompt, "this lane", "this focus area")
        self.assertNotIn("cases", block, "a prompt that only swaps a decided term runs nothing")
        self.assertEqual("one-basic", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_hunk_with_a_swap_and_another_change_still_runs(self):
        path = self._base_with_lane_text()
        block = self._edit_and_select(
            path, "Hunt one rotated lane at a time.", "Hunt two rotated focus areas at a time."
        )
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "one to two is a real change beside the swap, so the hunk is a cut",
        )

    def _base_with_comments(self):
        _write(
            self.repo,
            "plugins/alpha/skills/one/config.yaml",
            "# Defaults for alpha one.\n# Reviewed yearly.\nlimit: 3\n",
        )
        scaffold = self.repo / "plugins/alpha/evals/one-basic/scaffold.sh"
        scaffold.write_text(
            scaffold.read_text(encoding="utf-8").replace(
                "#!/usr/bin/env bash\n", "#!/usr/bin/env bash\n# Seeds the shared fixture.\n"
            ),
            encoding="utf-8",
        )
        details = self.repo / "plugins/alpha/skills/one/reference/details.md"
        details.write_text(
            details.read_text(encoding="utf-8")
            + "<!-- Validate the schema before anything else. -->\n",
            encoding="utf-8",
        )
        _commit_all(self.repo, "add comments")
        _git(self.repo, "branch", "-f", "base", "HEAD")

    def test_yaml_comment_line_deletion_is_no_run(self):
        self._base_with_comments()
        config = self.repo / "plugins/alpha/skills/one/config.yaml"
        block = self._edit_and_select(config, "# Defaults for alpha one.\n# Reviewed yearly.\n", "")
        self.assertNotIn("cases", block, "deleting YAML comment lines changes no behavior")
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("affected-no-run"))
        self.assertEqual("0", block["agent-runs"])

    def test_scaffold_comment_deletion_runs_its_case(self):
        self._base_with_comments()
        scaffold = self.repo / "plugins/alpha/evals/one-basic/scaffold.sh"
        block = self._edit_and_select(scaffold, "# Seeds the shared fixture.\n", "")
        self.assertEqual(
            "one-basic", block.get("cases"), "the model running a case may read its comments"
        )

    def _deletion_is_no_run(self, name, text, deleted):
        """Whether deleting the consecutive `deleted` lines from `text` in a skill file counts as
        a comment-only deletion."""
        import no_run_text

        lines = text.splitlines()
        old = deleted.splitlines()
        start = next(i for i in range(len(lines)) if lines[i : i + len(old)] == old) + 1
        style = no_run_text.comment_style("plugins/alpha/skills/one/" + name, text)
        return no_run_text._hunk_is_no_run(old, [], (), style, start)

    def test_comment_shaped_line_in_a_heredoc_is_content(self):
        text = "cat > status.md <<'MD'\n# Project status\nMD\n"
        self.assertFalse(self._deletion_is_no_run("seed.sh", text, "# Project status"))

    def _base_with_block_scalar(self):
        self._base_with_comments()
        config = self.repo / "plugins/alpha/skills/one/config.yaml"
        config.write_text(
            config.read_text(encoding="utf-8") + "prompt: |\n  # Heading the model reads\n  body\n",
            encoding="utf-8",
        )
        _commit_all(self.repo, "add a block scalar")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return config

    def test_comment_deletion_outside_a_block_scalar_is_no_run(self):
        config = self._base_with_block_scalar()
        block = self._edit_and_select(config, "# Reviewed yearly.\n", "")
        self.assertNotIn("cases", block, "only lines inside the block scalar are content")

    def test_comment_shaped_line_inside_a_block_scalar_still_runs(self):
        config = self._base_with_block_scalar()
        block = self._edit_and_select(config, "  # Heading the model reads\n", "")
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("cases"))

    def _assert_string_line_runs(self, rel, base_text, line):
        path = self.repo / rel
        _write(self.repo, rel, base_text)
        _commit_all(self.repo, "seed a multi-line string")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(path, line, "")
        self.assertEqual("control-no-fire one-basic one-trigger", block.get("cases"))

    def test_comment_shaped_line_in_a_toml_string_still_runs(self):
        self._assert_string_line_runs(
            "plugins/alpha/skills/one/config.toml",
            'prompt = """\n# Heading the model reads\nbody\n"""\n',
            "# Heading the model reads\n",
        )

    def test_powershell_here_string_lines_are_content(self):
        import no_run_text

        text = '# Seeds it.\n$text = @"\n# Heading the model reads\nbody\n"@\n'
        self.assertEqual(("hash", frozenset({3, 4, 5})), no_run_text.comment_style("a.ps1", text))

    def test_directive_comment_deletion_is_not_a_comment_deletion(self):
        text = "# shellcheck disable=SC2086\necho hi\n"
        self.assertFalse(self._deletion_is_no_run("seed.sh", text, "# shellcheck disable=SC2086"))

    def test_markdown_html_comment_deletion_still_runs(self):
        self._base_with_comments()
        details = self.repo / "plugins/alpha/skills/one/reference/details.md"
        block = self._edit_and_select(
            details, "<!-- Validate the schema before anything else. -->\n", ""
        )
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "a markdown HTML comment can carry instructions a model reads",
        )

    def test_comment_deletion_beside_a_code_change_still_runs(self):
        self._base_with_comments()
        config = self.repo / "plugins/alpha/skills/one/config.yaml"
        block = self._edit_and_select(config, "# Reviewed yearly.\nlimit: 3\n", "limit: 4\n")
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "the hunk also changes limit, so it is a cut",
        )

    def test_whitespace_change_in_scaffold_still_runs(self):
        self._write_glossary()
        scaffold = self.repo / "plugins/alpha/evals/one-basic/scaffold.sh"
        scaffold.write_text(
            scaffold.read_text(encoding="utf-8") + 'printf "a b" # lane\n', encoding="utf-8"
        )
        _commit_all(self.repo, "add printf")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(
            scaffold, 'printf "a b" # lane\n', 'printf "a  b" # focus area\n'
        )
        self.assertEqual(
            "one-basic", block.get("cases"), "a whitespace change beside a swap is not swap-only"
        )

    def test_block_comment_with_trailing_code_is_not_a_comment_deletion(self):
        text = '/* setup */ console.log("seed");\n// plain comment\n'
        self.assertFalse(
            self._deletion_is_no_run("seed.js", text, '/* setup */ console.log("seed");')
        )

    def test_js_comment_lines_and_closed_block_deletion_is_a_comment_deletion(self):
        text = '/* one-line */\n/*\n * block\n */\n// plain\nconsole.log("seed");\n'
        self.assertTrue(
            self._deletion_is_no_run(
                "seed.js", text, "/* one-line */\n/*\n * block\n */\n// plain"
            )
        )

    def test_decided_term_swap_in_a_skill_name_still_runs(self):
        self._write_glossary()
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "---\ndescription", "---\nname: one-lane\ndescription"
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "name the skill")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(path, "name: one-lane", "name: one-area")
        self.assertEqual(
            "control-no-fire one-basic one-trigger",
            block.get("cases"),
            "a skill's name is what people invoke, so a swap there is a cut",
        )

    def test_swap_only_rename_of_a_skill_directory_is_not_no_run(self):
        import select_mapping

        self._write_glossary()
        _write(self.repo, "plugins/alpha/skills/lane-check/SKILL.md", "# Check one lane\n")
        _commit_all(self.repo, "add skill")
        base = _git(self.repo, "rev-parse", "HEAD").strip()
        _git(
            self.repo, "mv", "plugins/alpha/skills/lane-check", "plugins/alpha/skills/area-check"
        )
        _write(self.repo, "plugins/alpha/skills/area-check/SKILL.md", "# Check one focus area\n")
        _commit_all(self.repo, "rename skill")
        self.assertFalse(
            select_mapping.is_no_run_file_change(
                str(self.repo),
                base,
                "plugins/alpha/skills/lane-check/SKILL.md",
                "plugins/alpha/skills/area-check/SKILL.md",
            ),
            "renaming a skill directory renames the skill",
        )

    def test_powershell_block_comment_closer_is_not_a_comment(self):
        text = "<#\nWrite-Output seed\n#>\nWrite-Output done\n"
        self.assertFalse(self._deletion_is_no_run("seed.ps1", text, "#>"))

    def test_comment_shaped_line_in_a_sequence_block_scalar_still_runs(self):
        self._assert_string_line_runs(
            "plugins/alpha/skills/one/steps.yaml",
            "steps:\n  - |\n    # Heading the model reads\n    body\n",
            "    # Heading the model reads\n",
        )

    def test_triple_slash_directive_is_not_a_comment(self):
        text = '/// <reference types="node" />\nconsole.log("seed");\n'
        self.assertFalse(
            self._deletion_is_no_run("seed.ts", text, '/// <reference types="node" />')
        )

    def test_deleting_only_a_block_comment_opener_is_not_a_comment_deletion(self):
        text = '/*\nconsole.log("seed");\n//*/\n'
        self.assertFalse(self._deletion_is_no_run("seed.js", text, "/*"))

    def test_comment_shaped_line_in_a_js_backtick_string_is_content(self):
        text = "const prompt = `\n// Heading the model reads\nbody\n`;\n"
        self.assertFalse(self._deletion_is_no_run("seed.js", text, "// Heading the model reads"))

    def test_comment_shaped_line_in_a_python_triple_quoted_string_is_content(self):
        text = 'PROMPT = """\n# Heading the model reads\nbody\n"""\n'
        self.assertFalse(self._deletion_is_no_run("seed.py", text, "# Heading the model reads"))

    def test_decided_term_swap_in_a_script_still_runs(self):
        self._write_glossary()
        scaffold = self.repo / "plugins/alpha/evals/one-basic/scaffold.sh"
        scaffold.write_text(
            scaffold.read_text(encoding="utf-8") + 'echo "check one lane"\n', encoding="utf-8"
        )
        _commit_all(self.repo, "add echo")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._edit_and_select(scaffold, "one lane", "one focus area")
        self.assertEqual("one-basic", block.get("cases"), "a script gets no swap exemption")

    def test_swap_only_rename_with_identical_content_still_runs(self):
        self._write_glossary()
        _write(self.repo, "plugins/alpha/evals/one-basic/lane-notes.md", "Seed notes.\n")
        _commit_all(self.repo, "add notes")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        _git(
            self.repo,
            "mv",
            "plugins/alpha/evals/one-basic/lane-notes.md",
            "plugins/alpha/evals/one-basic/area-notes.md",
        )
        _commit_all(self.repo, "rename notes")
        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        self.assertEqual(
            "one-basic",
            _parse_blocks(res.stdout)["plugins/alpha"].get("cases"),
            "a change with no hunks is never exempt",
        )

    def test_comment_deletion_in_a_plugin_wide_file_is_still_listed(self):
        _write(
            self.repo, "plugins/alpha/hooks/guard.sh", "#!/usr/bin/env bash\n# Guards.\nexit 0\n"
        )
        _commit_all(self.repo, "add hook")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        hook = self.repo / "plugins/alpha/hooks/guard.sh"
        block = self._edit_and_select(hook, "# Guards.\n", "")
        self.assertEqual("plugins/alpha/hooks/guard.sh", block.get("plugin-wide"))

    def test_exempt_skill_is_listed_in_json(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "alpha items.", "alpha items. Not for beta sweeps: /beta:runner."
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "add routing clause")
        res = _run_select(self.repo, as_json=True)
        self.assertEqual(0, res.returncode, res.stderr)
        data = json.loads(res.stdout)["plugins/alpha"]
        self.assertEqual(["alpha:one"], data["no-run-exempt"])
        self.assertEqual([], data["cases"])


if __name__ == "__main__":
    unittest.main()
