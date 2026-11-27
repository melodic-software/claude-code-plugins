#!/usr/bin/env python3
# test-scope: plugins/evals/skills/plugin-eval/scripts/select-cases.py plugins/evals/skills/plugin-eval/scripts/select_mapping.py plugins/evals/skills/plugin-eval/scripts/suite_refs.py plugins/evals/skills/plugin-eval/scripts/eval_visibility.py plugins/evals/skills/plugin-eval/scripts/no_run_text.py
"""Tests for which eval-file comment deletions select-cases proves the agent under test cannot
see: trailing comments, self-naming print lines, literal heredocs, quoted copy tails, the
suite's own `plugins` entry, path bindings, and skill `evals/` folders.
"""

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

SCAFFOLD = "plugins/alpha/evals/one-basic/scaffold.sh"
SETUP = "plugins/alpha/evals/fixtures/setup.sh"
CASE = "plugins/alpha/evals/one-basic/case.yaml"
RUN_SETUP = 'bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/setup.sh"\n'


class SelectCasesHiddenTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        _build_fixture_repo(self.repo)

    def tearDown(self):
        self._tmp.cleanup()

    def _base(self, scaffold=RUN_SETUP, setup="echo fixture\n", case_extra=""):
        _write(
            self.repo,
            CASE,
            'schema_version: "1.1"\nname: one-basic\ndescription: "Basic case for alpha:one"\n'
            "tags: [alpha:one]\ncontext:\n  scaffold_script: scaffold.sh\n" + case_extra,
        )
        _write(self.repo, SCAFFOLD, "#!/usr/bin/env bash\n" + scaffold)
        _write(self.repo, SETUP, "#!/usr/bin/env bash\n# Prints the fixture.\n" + setup)
        _commit_all(self.repo, "add eval files")
        _git(self.repo, "branch", "-f", "base", "HEAD")

    def _select(self, rel, old, new):
        path = self.repo / rel
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
        _commit_all(self.repo, "edit eval file")
        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        return _parse_blocks(res.stdout)["plugins/alpha"]

    def assert_runs(self, block, why):
        self.assertEqual("one-basic", block.get("cases"), why)

    def assert_free(self, block, why):
        self.assertNotIn("cases", block, why)
        self.assertIn("one-basic", block.get("affected-no-run", "").split(), why)

    def test_trailing_scaffold_comment_deletion_is_no_run(self):
        self._base(scaffold=RUN_SETUP + "mkdir -p out # the report goes here\n")
        block = self._select(SCAFFOLD, " # the report goes here", "")
        self.assert_free(block, "only the comment after the code went")

    def test_trailing_helper_comment_deletion_is_no_run(self):
        self._base(setup="case $1 in\n  *) ;; # nothing else to seed\nesac\n")
        block = self._select(SETUP, " # nothing else to seed", "")
        self.assert_free(block, "the helper the scaffold runs stays hidden")

    def test_trailing_comment_with_a_code_change_still_runs(self):
        self._base(scaffold=RUN_SETUP + "mkdir -p out # the report goes here\n")
        block = self._select(SCAFFOLD, "out # the report goes here", "outs")
        self.assert_runs(block, "the code before the comment changed")

    def test_hash_inside_double_quotes_is_not_a_trailing_comment(self):
        self._base(scaffold=RUN_SETUP + 'echo "a # b" >notes.txt\n')
        block = self._select(SCAFFOLD, ' # b" >notes.txt', '"')
        self.assert_runs(block, "the # sat in a quoted string the workspace gets")

    def test_trailing_comment_in_a_heredoc_still_runs(self):
        self._base(scaffold=RUN_SETUP + "cat >notes.md <<'MD'\nkeep this # the agent reads\nMD\n")
        block = self._select(SCAFFOLD, " # the agent reads", "")
        self.assert_runs(block, "a heredoc line lands in the workspace")

    def test_trailing_case_yaml_comment_deletion_is_no_run(self):
        self._base(case_extra="runs: 2 # two are enough\n")
        block = self._select(CASE, " # two are enough", "")
        self.assertNotIn("cases", block, "a case.yaml comment after a value is hidden")

    def test_trailing_case_yaml_hash_in_a_quoted_value_still_runs(self):
        self._base(case_extra='expected_outcome: "a # b"\n')
        block = self._select(CASE, ' # b"', '"')
        self.assert_runs(block, "the # was part of the quoted value")

    def test_trailing_case_yaml_comment_on_a_copied_case_still_runs(self):
        self._base(scaffold=RUN_SETUP + 'cp -r "$(dirname "$0")/.." ws/\n', case_extra="runs: 2 # two\n")
        block = self._select(CASE, " # two", "")
        self.assert_runs(block, "the copy puts case.yaml in the workspace")

    def test_trailing_case_yaml_comment_a_script_reads_still_runs(self):
        _write(
            self.repo,
            "plugins/alpha/evals/check-runs.sh",
            "#!/usr/bin/env bash\ngrep -q 'runs: 2 # two$' \"$1/case.yaml\"\n",
        )
        self._base(case_extra="runs: 2 # two\n")
        block = self._select(CASE, " # two", "")
        self.assert_runs(block, "check-runs.sh matches the whole line")

    def test_usage_line_naming_the_helper_is_no_run(self):
        self._base(setup="printf 'usage: setup.sh a|b\\n' >&2\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "printing its own name prints no comment")

    def test_unset_message_naming_the_helper_is_no_run(self):
        self._base(setup='n="${1:?setup.sh needs a count}"\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "the :? message prints only the name")

    def test_helper_that_cats_itself_still_runs(self):
        self._base(setup='cat "$0" >copy.txt\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the helper writes its own source")

    def test_helper_reading_itself_by_name_still_runs(self):
        self._base(setup="cat 'setup.sh' >copy.txt\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "a single-quoted name is still a path")

    def test_awk_record_in_single_quotes_is_not_a_self_read(self):
        self._base(setup="awk '\n  length($0) > 3 { print }\n' data.txt\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "awk's $0 is the record, not the script")

    def test_dollar_zero_in_an_evaluated_string_still_runs(self):
        self._base(setup="eval 'cat \"$0\" >copy.txt'\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "eval runs the string with the script as $0")

    def test_literal_heredoc_naming_the_case_folder_is_no_run(self):
        self._base(
            scaffold=RUN_SETUP + "cat >bench.sh <<'EOF'\ncd \"$(dirname \"${BASH_SOURCE[0]}\")\"\nEOF\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "the heredoc writes text into the workspace and runs none of it")

    def test_unquoted_heredoc_copying_the_helper_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + 'cat >copy.sh <<EOF\n$(cat "$(dirname "$0")/../fixtures/setup.sh")\nEOF\n'
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "an unquoted heredoc runs its command substitution")

    def test_heredoc_fed_to_bash_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + "bash <<'EOF'\ncp \"$(dirname \"$0\")/../fixtures/setup.sh\" ws/\nEOF\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "bash runs the heredoc")

    def _copy_base(self, copy_line):
        self._base(
            scaffold='fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"\n'
            'bash "$fixtures/setup.sh"\n' + copy_line
        )

    def test_quoted_copy_with_another_suffix_is_no_run(self):
        self._copy_base('cp "$fixtures/$1.txt" ws/\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "the copy names only .txt files")

    def test_quoted_copy_with_no_suffix_still_runs(self):
        self._copy_base('cp "$fixtures/$1" ws/\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "$1 may name setup.sh")

    def test_quoted_copy_with_a_matching_suffix_still_runs(self):
        self._copy_base('cp "$fixtures/$1.sh" ws/\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "setup.sh ends with .sh")

    def test_unquoted_copy_with_a_suffix_still_runs(self):
        self._copy_base("cp $fixtures/$1.txt ws/\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "word splitting can make $1 a second path")

    def test_quoted_copy_continuing_past_its_quote_still_runs(self):
        self._copy_base('cp "$fixtures/$1".txt* ws/\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the word goes on past the closing quote")

    def test_plugins_entry_naming_the_own_plugin_is_no_run(self):
        self._base(case_extra='plugins: ["../.."]\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "../.. is the plugin under test, loaded anyway")

    def test_plugins_entry_above_the_plugin_still_runs(self):
        self._base(case_extra='plugins: ["../../.."]\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the plugins folder holds the suite and is not the plugin")

    def test_plugins_entry_inside_a_case_copy_of_the_helper_runs(self):
        self._base(case_extra='plugins: ["../fixtures"]\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the loaded folder holds the helper")

    def _binding_base(self, extra=""):
        self._base(
            scaffold='fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd -P)/setup.sh"\n'
            '(cd ws && bash "${fixture}" scan)\n' + extra
        )

    def test_path_binding_then_run_is_no_run(self):
        self._binding_base()
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "the variable is only ever run")

    def test_exported_path_binding_still_runs(self):
        self._binding_base("export fixture\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "a child process may use it")

    def test_path_binding_then_copy_still_runs(self):
        self._binding_base('cp "$fixture" ws/\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the variable is copied")

    def test_path_binding_with_an_operator_still_runs(self):
        self._binding_base('cp -r "${fixture%/*}" ws/\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "${fixture%/*} names the fixtures folder")

    def test_cd_pwd_variable_outside_the_suite_is_no_run(self):
        self._base(
            scaffold=RUN_SETUP + 'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
            'plugin="$(cd "$here/../.." && pwd)"\nbash "$plugin/scripts/util.sh"\n'
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "$plugin/scripts is outside the evals folder")

    def test_cd_pwd_variable_copied_whole_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + 'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
            'plugin="$(cd "$here/../.." && pwd)"\ncp -r "$plugin" ws/\n'
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the plugin root holds the evals folder")

    def test_path_binding_with_a_copy_on_its_line_still_runs(self):
        self._base(
            scaffold='fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd -P)/setup.sh"'
            ' && cp "$fixture" copy.sh\nbash "$fixture"\n'
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the copy after the binding writes the helper")

    def test_dirname_binding_with_a_folder_copy_on_its_line_still_runs(self):
        self._base(scaffold=RUN_SETUP + 'dir="$(dirname "$0")"; cp -r "$dir/.." all/\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the copy takes the whole evals folder")

    def test_cd_prefix_then_a_relative_copy_still_runs(self):
        self._copy_base('(cd "$fixtures" && bash "$fixtures/setup.sh" && cp -r . ../ws/)\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "cp -r . copies the fixtures folder")

    def test_cd_into_the_suite_then_a_bare_name_still_runs(self):
        self._base(scaffold=RUN_SETUP + 'cd "$(dirname "${BASH_SOURCE[0]}")"\ncd ..\ntar c fixtures | tar x -C ws\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "after the cd, fixtures names the helper's folder")

    def test_unresolved_self_path_in_the_scaffold_still_runs(self):
        self._base(scaffold=RUN_SETUP + 'cp -r "${0%/*}"/.. ws/\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "${0%/*} is the case folder")

    def test_unset_check_on_dollar_zero_still_runs(self):
        self._base(setup='cat "${0:?}" >copy.txt\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "only the message of ${0:?} is printed text")

    def test_dollar_zero_in_a_trap_string_still_runs(self):
        self._base(setup="trap 'cp \"$0\" ./copy.sh' EXIT\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the trap runs the string with the script as $0")

    def test_dollar_zero_in_a_sourced_here_string_still_runs(self):
        self._base(setup="source /dev/stdin <<<'cp \"$0\" ./copy.sh'\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "source runs the string with the script as $0")

    def test_literal_heredoc_in_a_file_that_pipes_to_bash_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + "body() {\n  cat <<'EOF'\ncp \"$(dirname \"$0\")\"/../fixtures/setup.sh ws/\nEOF\n}\n"
            "body | bash\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the heredoc body runs once piped to bash")

    def test_quoted_copy_whose_tail_matches_a_holding_folder_still_runs(self):
        _write(self.repo, "plugins/alpha/evals/fixtures/hooks.d/setup.sh", "#!/usr/bin/env bash\n# Hook.\n")
        self._copy_base('bash "$fixtures/hooks.d/setup.sh"\ncp -r "$fixtures/$1.d" ws/\n')
        block = self._select("plugins/alpha/evals/fixtures/hooks.d/setup.sh", "# Hook.\n", "")
        self.assert_runs(block, "$1.d can name hooks.d, which holds the helper")

    def test_trailing_comment_after_an_escaped_blank_still_runs(self):
        self._base(scaffold=RUN_SETUP + "echo a\\  # c\nmkdir out\n")
        block = self._select(SCAFFOLD, "echo a\\  # c", "echo a\\")
        self.assert_runs(block, "the cut leaves a line continuation")

    def test_case_yaml_comments_a_case_script_greps_still_run(self):
        self._base(
            scaffold=RUN_SETUP + 'grep "#" "$(dirname "${BASH_SOURCE[0]}")/case.yaml" >notes.txt\n',
            case_extra="runs: 2 # two are enough\n",
        )
        block = self._select(CASE, " # two are enough", "")
        self.assert_runs(block, "the scaffold writes case.yaml's comments into the workspace")

    def test_ansi_c_string_reads_and_keeps_the_exemption(self):
        self._base(setup="printf $'a\\tb\\'c\\n' >data.txt\n")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "an ANSI-C string reads cleanly")

    def test_skill_evals_folder_yaml_comment_still_runs_the_skill(self):
        _write(self.repo, "plugins/alpha/skills/one/evals/notes.yaml", "# Calibration notes.\nk: v\n")
        _commit_all(self.repo, "add skill evals file")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._select("plugins/alpha/skills/one/evals/notes.yaml", "# Calibration notes.\n", "")
        self.assertIn("one-basic", block.get("cases", "").split(), "the agent can read a skill folder")


class ShellCommentStartTest(unittest.TestCase):
    def setUp(self):
        import no_run_text

        self.start = no_run_text.shell_comment_start

    def test_comment_after_code(self):
        self.assertEqual(9, self.start("mkdir -p # x"))

    def test_hash_cases_that_are_not_comments(self):
        for line in (
            'echo "a # b"',
            "echo 'a # b'",
            'echo "$(printf "%s" x) # in" ',
            "echo ${x#y}",
            "echo a\\ #b",
            "(( n # 2 ))",
            "x=$(echo a # b",
            "echo `a # b`",
            "echo $'a\\' # b'",
            'echo "open # b',
            "echo $[1 #2]",
            "[[ a =~ b #c ]]",
        ):
            self.assertIsNone(self.start(line), line)

    def test_case_pattern_paren_does_not_hide_the_comment(self):
        self.assertEqual(8, self.start("  *) ;; # rest"))


if __name__ == "__main__":
    unittest.main()
