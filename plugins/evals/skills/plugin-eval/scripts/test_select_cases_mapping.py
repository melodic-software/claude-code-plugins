#!/usr/bin/env python3
# test-scope: plugins/evals/skills/plugin-eval/scripts/select-cases.py plugins/evals/skills/plugin-eval/scripts/select_mapping.py plugins/evals/scripts/case_skills.py plugins/evals/skills/validate/scripts/validate-cases.py
"""Mapping and regression unit tests for plugins/evals/skills/plugin-eval/scripts/select-cases.py."""

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


class SelectCasesMappingTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        _build_fixture_repo(self.repo)

    def tearDown(self):
        self._tmp.cleanup()

    def test_finding_02_cut_description_includes_skill_linked_cases(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                'description: "Run alpha one checks. Use when checking alpha items."',
                'description: "Run alpha one checks only."',
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "shorten description")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "control-no-fire one-basic one-trigger opt-case",
            blocks["plugins/alpha"]["cases"],
        )
        self.assertEqual("20", blocks["plugins/alpha"]["agent-runs"])

    def test_finding_03_description_addition_with_repeated_tokens_is_additive(self):
        _write(
            self.repo,
            "plugins/alpha/skills/logs/SKILL.md",
            """
            ---
            description: check check logs
            ---

            # Logs

            Read the logs.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/logs-case/prompt.md",
            """
            /alpha:logs inspect
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/logs-case/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add logs skill")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/skills/logs/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "description: check check logs",
                "description: check logs and check logs",
            ),
            encoding="utf-8",
        )
        _commit_all(self.repo, "additive repeated tokens")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual(
            "control-no-fire one-trigger opt-case",
            blocks["plugins/alpha"]["run-after-merge"],
        )

    def test_case_owned_scaffold_selects_the_cases_that_call_it(self):
        for name, scaffold in (
            ("posture-necessary", 'mkdir -p out\necho "$1" > out/mode\n'),
            ("posture-none", 'bash "$(dirname "${BASH_SOURCE[0]}")/../posture-necessary/scaffold.sh" none\n'),
        ):
            _write(
                self.repo,
                "plugins/alpha/evals/%s/case.yaml" % name,
                'schema_version: "1.1"\nname: %s\ncontext:\n  scaffold_script: scaffold.sh\n' % name,
            )
            _write(self.repo, "plugins/alpha/evals/%s/prompt.md" % name, "/alpha:one check\n")
            _write(
                self.repo,
                "plugins/alpha/evals/%s/scaffold.sh" % name,
                "#!/usr/bin/env bash\n" + scaffold,
            )
            _write(
                self.repo,
                "plugins/alpha/evals/%s/graders/ok.md" % name,
                '---\ntype: regex\npattern: "ok"\n---\n',
            )
        _commit_all(self.repo, "add a scaffold another case calls")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/posture-necessary/scaffold.sh"
        path.write_text(path.read_text(encoding="utf-8") + "touch out/ready\n", encoding="utf-8")
        _commit_all(self.repo, "edit the shared scaffold")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("posture-necessary posture-none", blocks["plugins/alpha"]["cases"])

    def test_finding_04_transitive_fixture_dependency_through_helper(self):
        _write(
            self.repo,
            "plugins/alpha/evals/fixtures/checkout-service/src/pricing.js",
            """
            export const price = 10;
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/fixtures/seed-checkout-service.sh",
            """
            #!/usr/bin/env bash
            src="$(dirname "${BASH_SOURCE[0]}")/checkout-service"
            mkdir -p src
            cp "$src/src/pricing.js" src/pricing.js
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/find-unattended-run-cap-from-config/case.yaml",
            """
            schema_version: "1.1"
            name: find-unattended-run-cap-from-config
            context:
              scaffold_script: scaffold.sh
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/find-unattended-run-cap-from-config/prompt.md",
            """
            /alpha:one check checkout
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/find-unattended-run-cap-from-config/scaffold.sh",
            """
            #!/usr/bin/env bash
            bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/find-unattended-run-cap-from-config/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add transitive fixture")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/fixtures/checkout-service/src/pricing.js"
        path.write_text("export const price = 20;\n", encoding="utf-8")
        _commit_all(self.repo, "edit nested fixture file")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(
            "find-unattended-run-cap-from-config",
            blocks["plugins/alpha"]["cases"],
        )
        self.assertNotIn("unmapped", blocks["plugins/alpha"])

    def test_finding_05_fixture_path_resolved_not_substring(self):
        _write(
            self.repo,
            "plugins/alpha/evals/fixtures/data.json",
            """
            {"source": "suite"}
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group/local-fix/fixtures/data.json",
            """
            {"source": "case"}
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group/local-fix/prompt.md",
            """
            /alpha:one read local fixture
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group/local-fix/scaffold.sh",
            """
            #!/usr/bin/env bash
            cp ./fixtures/data.json data.json
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group/local-fix/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add local and suite fixtures")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/fixtures/data.json"
        path.write_text('{"source": "suite-updated"}\n', encoding="utf-8")
        _commit_all(self.repo, "edit suite fixture")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual(
            "plugins/alpha/evals/fixtures/data.json",
            blocks["plugins/alpha"]["unmapped"],
        )

    def test_finding_06_cross_plugin_reference_consumer(self):
        _write(
            self.repo,
            "plugins/alpha/reference/rules.md",
            """
            # Rules

            Keep rules exact.
            """,
        )
        _write(
            self.repo,
            "plugins/beta/skills/check/SKILL.md",
            """
            ---
            description: "Check beta rules."
            ---

            # Check

            Follow [rules](../../../alpha/reference/rules.md).
            """,
        )
        _write(
            self.repo,
            "plugins/beta/evals/check/prompt.md",
            """
            /beta:check verify
            """,
        )
        _write(
            self.repo,
            "plugins/beta/evals/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add cross-plugin reference")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/reference/rules.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("exact", "strict"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "reword alpha rules")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual(["plugins/beta"], list(blocks))
        self.assertEqual("check", blocks["plugins/beta"]["cases"])

    def test_finding_07_relative_reference_path_with_spaces(self):
        _write(
            self.repo,
            "plugins/alpha/context/shared rules.md",
            """
            # Shared Rules

            Always report errors.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/skills/check/SKILL.md",
            """
            ---
            description: "Check with spaced context."
            ---

            # Check

            Read [rules](<../../context/shared rules.md>).
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:check verify rules
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add spaced context reference")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/context/shared rules.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("errors", "warnings"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "reword spaced context")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("check", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("unmapped", blocks["plugins/alpha"])

    def test_finding_08_relative_workflow_link_for_agent_cut(self):
        _write(
            self.repo,
            "plugins/alpha/agents/rel-helper.md",
            """
            ---
            name: rel-helper
            ---

            Inspect targets carefully.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/workflows/check.js",
            """
            const AGENT = 'alpha:rel-helper'
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/skills/check/SKILL.md",
            """
            ---
            description: "Run relative workflow."
            ---

            # Check

            Run `../../workflows/check.js`.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:check run now
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add relative workflow link")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/agents/rel-helper.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("carefully", "strictly"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "reword rel-helper")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("check", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("uncovered", blocks["plugins/alpha"])

    def test_finding_09_grader_prefix_covers_matching_skill(self):
        _write(
            self.repo,
            "plugins/alpha/skills/check-files/SKILL.md",
            """
            ---
            description: "Check files in workspace."
            ---

            # Check Files

            Inspect all files.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/prefix-case/prompt.md",
            """
            Please check the files in this repo.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/prefix-case/graders/fired.md",
            """
            ---
            type: tool_used
            tool: Skill
            input_match: 'alpha:check'
            ---
            """,
        )
        _commit_all(self.repo, "add prefix grader case")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/skills/check-files/SKILL.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("all files", "staged files"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "cut check-files")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("prefix-case", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("uncovered", blocks["plugins/alpha"])

    def test_finding_10_agent_rename_preserves_cut_classification(self):
        _write(
            self.repo,
            "plugins/alpha/agents/rename-helper.md",
            """
            ---
            name: rename-helper
            description: "Helper for check workflow"
            ---

            Inspect the target file and report every finding clearly.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/workflows/check.js",
            """
            const AGENT = 'alpha:rename-helper'
            export const meta = { name: 'check' }
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/skills/check/SKILL.md",
            """
            ---
            description: "Run check workflow."
            ---

            # Check

            Launch `alpha:check`.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:check run
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add renameable agent")
        _git(self.repo, "branch", "-f", "base")

        (self.repo / "plugins/alpha/agents/rename-helper.md").unlink()
        _write(
            self.repo,
            "plugins/alpha/agents/rename-worker.md",
            """
            ---
            name: rename-worker
            description: "Helper for check workflow"
            ---

            Inspect the source file and report every finding strictly.
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/workflows/check.js",
            """
            const AGENT = 'alpha:rename-worker'
            export const meta = { name: 'check' }
            """,
        )
        _commit_all(self.repo, "rename and reword agent")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("check", blocks["plugins/alpha"]["cases"])
        self.assertNotIn("uncovered", blocks["plugins/alpha"])
        self.assertNotIn("affected-no-run", blocks["plugins/alpha"])

    def test_finding_11_case_name_uses_case_yaml_not_prompt_frontmatter(self):
        _write(
            self.repo,
            "plugins/alpha/evals/nested/dir-name/case.yaml",
            """
            schema_version: "1.1"
            name: registered
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/nested/dir-name/prompt.md",
            """
            ---
            name: display
            ---

            /alpha:one check
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/nested/dir-name/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add case with prompt frontmatter name")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/nested/dir-name/graders/ok.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("ok", "done"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "edit grader")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertEqual("registered", blocks["plugins/alpha"]["cases"])

    def test_finding_12_markdown_grader_body_paid_marker_classified_judged(self):
        _write(
            self.repo,
            "plugins/alpha/evals/check/prompt.md",
            """
            /alpha:one verify output
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/check/graders/rule.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---

            Example note documenting type: llm in prose.
            """,
        )
        _commit_all(self.repo, "add grader with paid marker in body")
        _git(self.repo, "branch", "-f", "base")

        path = self.repo / "plugins/alpha/evals/check/prompt.md"
        path.write_text("/alpha:one verify updated output\n", encoding="utf-8")
        _commit_all(self.repo, "edit prompt")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        blocks = _parse_blocks(res.stdout)
        self.assertNotIn("cases", blocks["plugins/alpha"])
        self.assertEqual("check", blocks["plugins/alpha"]["judged"])

    def test_finding_13_duplicate_case_names_counted_in_agent_runs(self):
        _write(
            self.repo,
            "plugins/alpha/evals/group-a/check/case.yaml",
            """
            schema_version: "1.1"
            runs: 2
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-a/check/prompt.md",
            """
            /alpha:one check A
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-a/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-b/check/case.yaml",
            """
            schema_version: "1.1"
            runs: 4
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-b/check/prompt.md",
            """
            /alpha:one check B
            """,
        )
        _write(
            self.repo,
            "plugins/alpha/evals/group-b/check/graders/ok.md",
            """
            ---
            type: regex
            pattern: "ok"
            ---
            """,
        )
        _commit_all(self.repo, "add duplicate case names")
        _git(self.repo, "branch", "-f", "base")

        path_a = self.repo / "plugins/alpha/evals/group-a/check/prompt.md"
        path_a.write_text("/alpha:one check A updated\n", encoding="utf-8")
        _commit_all(self.repo, "edit only group-a check")

        res_one = _run_select(self.repo)
        self.assertEqual(0, res_one.returncode, res_one.stderr)
        blocks_one = _parse_blocks(res_one.stdout)
        self.assertEqual("check", blocks_one["plugins/alpha"]["cases"])
        self.assertEqual("12", blocks_one["plugins/alpha"]["agent-runs"])

        path_b = self.repo / "plugins/alpha/evals/group-b/check/prompt.md"
        path_b.write_text("/alpha:one check B updated\n", encoding="utf-8")
        _commit_all(self.repo, "edit group-b check too")

        res_both = _run_select(self.repo)
        self.assertEqual(0, res_both.returncode, res_both.stderr)
        blocks_both = _parse_blocks(res_both.stdout)
        self.assertEqual("check", blocks_both["plugins/alpha"]["cases"])
        self.assertEqual("12", blocks_both["plugins/alpha"]["agent-runs"])

    def test_finding_14_uncommitted_plugin_changes_exit_2(self):
        path = self.repo / "plugins/alpha/evals/one-basic/graders/check.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("ok", "passed"),
            encoding="utf-8",
        )
        _commit_all(self.repo, "edit grader")

        case_yaml = self.repo / "plugins/alpha/evals/one-basic/case.yaml"
        original_yaml = case_yaml.read_text(encoding="utf-8")
        case_yaml.write_text(
            original_yaml.replace("name: one-basic", "name: draft"),
            encoding="utf-8",
        )

        res = _run_select(self.repo)
        self.assertEqual(2, res.returncode)
        self.assertIn("committed", res.stderr.lower())

        case_yaml.write_text(original_yaml, encoding="utf-8")
        (self.repo / "docs/guide.md").write_text("# Uncommitted outside plugins\n", encoding="utf-8")
        res_outside = _run_select(self.repo)
        self.assertEqual(0, res_outside.returncode, res_outside.stderr)
        blocks = _parse_blocks(res_outside.stdout)
        self.assertEqual("one-basic", blocks["plugins/alpha"]["cases"])

    def test_finding_15_quoted_and_trailing_space_paths_from_git(self):
        quoted = self.repo / 'plugins/alpha/evals/one-basic/fixtures/input "quoted".txt'
        quoted.parent.mkdir(parents=True, exist_ok=True)
        quoted.write_text("v1\n", encoding="utf-8")
        trailing = self.repo / "plugins/alpha/evals/one-basic/fixtures/trailing "
        trailing.write_text("t1\n", encoding="utf-8")
        _commit_all(self.repo, "add special-char fixtures")
        _git(self.repo, "branch", "-f", "base")

        quoted.write_text("v2\n", encoding="utf-8")
        _commit_all(self.repo, "edit quoted fixture")

        res_quoted = _run_select(self.repo)
        self.assertEqual(0, res_quoted.returncode, res_quoted.stderr)
        blocks_quoted = _parse_blocks(res_quoted.stdout)
        self.assertEqual("one-basic", blocks_quoted["plugins/alpha"]["cases"])

        _git(self.repo, "branch", "-f", "base")
        trailing.write_text("t2\n", encoding="utf-8")
        _commit_all(self.repo, "edit trailing-space fixture")

        res_trailing = _run_select(self.repo)
        self.assertEqual(0, res_trailing.returncode, res_trailing.stderr)
        blocks_trailing = _parse_blocks(res_trailing.stdout)
        self.assertEqual("one-basic", blocks_trailing["plugins/alpha"]["cases"])


if __name__ == "__main__":
    unittest.main()
