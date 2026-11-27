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


    def test_literal_heredoc_written_then_run_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + "cat >runner.sh <<'EOF'\ncp -r \"$(dirname \"$0\")/../fixtures\" ./copy\nEOF\n"
            "bash runner.sh\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the scaffold runs the script the heredoc wrote")

    def test_literal_heredoc_made_executable_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + "cat >runner.sh <<'EOF'\ncp -r \"$(dirname \"$0\")/../fixtures\" ./copy\nEOF\n"
            "chmod +x runner.sh\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "a file made executable may be run")

    def test_running_one_written_file_leaves_other_heredocs_inert(self):
        self._base(
            scaffold=RUN_SETUP + "cat >tool <<'EOF'\necho ok\nEOF\nchmod +x tool\n"
            "cat >notes.sh <<'EOF'\ncd \"$(dirname \"${BASH_SOURCE[0]}\")\"\nEOF\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "only tool runs; notes.sh stays text")

    def test_a_written_file_run_by_another_written_file_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + "cat >a.sh <<'EOF'\nbash b.sh\nEOF\n"
            "cat >b.sh <<'EOF'\ncp -r \"$(dirname \"$0\")/../fixtures\" ./copy\nEOF\nbash a.sh\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "a.sh runs b.sh")

    def _written_runner(self, run_lines, body='cp -r "$(dirname "$0")/../fixtures" ./copy'):
        self._base(scaffold=RUN_SETUP + "cat >gen.sh <<'EOF'\n" + body + "\nEOF\n" + run_lines)
        return self._select(SETUP, "# Prints the fixture.\n", "")

    def test_written_file_run_through_a_wrapper_or_variable_still_runs(self):
        for run in (
            "nice bash gen.sh\n", "timeout 60 bash gen.sh\n", "env -i bash gen.sh\n",
            "f=gen.sh\nbash \"$f\"\n", "\"$SHELL\" gen.sh\n", "cd sub && ./gen.sh\n",
        ):
            with self.subTest(run=run):
                self.assert_runs(self._written_runner(run), "the scaffold may run gen.sh")

    def test_written_file_renamed_or_linked_still_runs(self):
        for run in ("mv gen.sh run.sh\nbash run.sh\n", "ln -s gen.sh run.sh\n", "cp gen.sh x.sh\n"):
            with self.subTest(run=run):
                self.assert_runs(self._written_runner(run), "gen.sh moves to a name that runs")

    def test_written_file_only_committed_read_or_appended_is_no_run(self):
        for run in ("git add gen.sh\n", "printf 'x\\n' >>gen.sh\n", "git -c user.name=x commit -qm x\n",
                    "git init -q --bare .git/origin.git\n"):
            with self.subTest(run=run):
                self.assert_free(self._written_runner(run), "nothing runs gen.sh")

    def test_written_file_named_in_unquoted_heredoc_text(self):
        free = self._written_runner("cat >notes.txt <<EOF\nrun: bash gen.sh in $PWD\nEOF\n")
        self.assert_free(free, "the unquoted heredoc only writes the text")
        runs = self._written_runner("cat >notes.txt <<EOF\n$(bash gen.sh)\nEOF\n")
        self.assert_runs(runs, "the command substitution runs gen.sh")
        chained = self._written_runner("cat >run.sh <<EOF\nbash gen.sh\nEOF\nbash run.sh\n")
        self.assert_runs(chained, "run.sh, which an unquoted heredoc writes, runs gen.sh")

    def test_written_file_reached_by_a_built_name_or_odd_form_still_runs(self):
        for run in (
            'n=gen\nbash "$n.sh"\n', "bash ./g*.sh\n", 'for f in ./*.sh; do bash "$f"; done\n',
            'v=f\nf=gen.sh\nbash "${!v}"\n', "bash <>gen.sh\n", 'bash <<<"$(cat gen.sh)"\n',
            'echo "$(cat gen.sh)" >run.sh\nbash run.sh\n',
            "git init -q\ngit add gen.sh\ngit -c 'diff.external=bash<gen.sh' diff\n",
            'x="\ncat <<EOF\n"\nbash gen.sh\n', "cat >notes.txt <<EOF\n$\\\n(bash gen.sh)\nEOF\n",
            '"make"\n', "${MAKE:-make}\n", "cmake -S . -B build\n",
            "mkdir -p .git/hooks\ncp gen.sh .git/hooks/pre-commit\n", "cd .git/hooks\n",
        ):
            with self.subTest(run=run):
                self.assert_runs(self._written_runner(run), "the scaffold may run gen.sh")

    def test_written_file_named_by_a_non_shell_case_file_still_runs(self):
        _write(self.repo, "plugins/alpha/evals/fixtures/helper.py", 'import subprocess\nsubprocess.run(["bash", "gen.sh"])\n')
        block = self._written_runner('python3 "$(dirname "$0")/../fixtures/helper.py"\n')
        self.assert_runs(block, "helper.py runs gen.sh")

    def test_shadowed_cat_or_path_change_still_runs(self):
        for prefix in ("cat() { bash -s; }\n", 'PATH="$PWD/bin:$PATH"\n', "alias cat=bash\n"):
            with self.subTest(prefix=prefix):
                self._base(
                    scaffold=RUN_SETUP + prefix + "cat >out.txt <<'EOF'\n"
                    'cp -r "$(dirname "$0")/../fixtures" ./copy\nEOF\n'
                )
                block = self._select(SETUP, "# Prints the fixture.\n", "")
                self.assert_runs(block, "cat no longer just writes text")

    def test_heredoc_in_a_file_that_sources_a_library_still_runs(self):
        _write(self.repo, "plugins/alpha/evals/fixtures/lib.sh", "cat() { bash -s; }\n")
        self._base(
            scaffold=RUN_SETUP + 'source "$(dirname "$0")/../fixtures/lib.sh"\n'
            "cat >out.txt <<'EOF'\ncp -r \"$(dirname \"$0\")/../fixtures\" ./copy\nEOF\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the sourced library may redefine cat")

    def test_git_hooks_path_or_hooks_heredoc_still_runs(self):
        for extra in ("git config core.hooksPath hooks\n", "cat >.git/hooks/pre-commit <<'H'\nx\nH\n"):
            with self.subTest(extra=extra):
                self.assert_runs(self._written_runner(extra), "git runs hooks it finds")

    def test_hooks_path_dev_null_keeps_heredocs_inert(self):
        self.assert_free(
            self._written_runner("git -c core.hooksPath=/dev/null commit -q -m x\n"),
            "hooks are switched off",
        )

    def test_heredoc_with_a_variable_target_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + 'f=x.sh\ncat >"$f" <<\'EOF\'\ncp -r "$(dirname "$0")/../fixtures" ./copy\nEOF\n'
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the written name is not literal")

    def test_pushd_into_the_suite_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + 'pushd "$(dirname "${BASH_SOURCE[0]}")"\npushd ..\ntar c fixtures | tar x -C ws\n'
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "after the pushd, fixtures names the helper's folder")

    def test_literal_heredoc_in_a_case_that_runs_make_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + "cat >Makefile <<'EOF'\nall:\n\tcp -r \"$(dirname \"$0\")/../fixtures\" copy\nEOF\nmake\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "make runs the Makefile the heredoc wrote")

    def test_if_source_of_a_written_file_still_runs(self):
        self._base(
            scaffold=RUN_SETUP + "cat >env.sh <<'EOF'\ncp \"$(dirname \"$0\")/../fixtures/setup.sh\" ws/\nEOF\n"
            "if source ./env.sh; then :; fi\n"
        )
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the sourced file runs with the scaffold as $0")

    def _positional_base(self, calls):
        _write(
            self.repo,
            "plugins/alpha/evals/fixtures/seed.sh",
            '#!/usr/bin/env bash\nfixtures="$(dirname "${BASH_SOURCE[0]}")"\n'
            'while [[ $# -ge 2 ]]; do\n  src="$1" dest="$2"\n  shift 2\n  cp "$fixtures/$src" "$dest"\ndone\n',
        )
        self._base(scaffold=RUN_SETUP + calls)

    def test_positional_copy_with_literal_arguments_is_no_run(self):
        self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" \\\n  a.txt out/a \\\n  b.txt out/b\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "every call copies a.txt or b.txt")

    def test_positional_copy_in_a_helper_setting_shell_options_is_no_run(self):
        self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" a.txt out/a\n')
        seed = self.repo / "plugins/alpha/evals/fixtures/seed.sh"
        seed.write_text(seed.read_text(encoding="utf-8").replace("while", "set -euo pipefail\nwhile", 1))
        _commit_all(self.repo, "strict mode")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_free(block, "set -euo pipefail sets options, not arguments")

    def test_positional_copy_naming_the_helper_still_runs(self):
        self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" setup.sh out/s\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "a call copies setup.sh")

    def test_positional_copy_with_a_variable_argument_still_runs(self):
        self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" "$1" out/s\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "$1 may name setup.sh")

    def test_positional_copy_with_a_glob_argument_still_runs(self):
        self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" se*.sh out/s\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the glob can match setup.sh")

    def test_positional_copy_with_rebound_arguments_still_runs(self):
        for extra in (
            'set -e -- "set""up.sh"\n', "set -u setup.sh\n", 'src+=".sh"\n', "src[0]=setup.sh\n",
            'printf -v "src" setup.sh\n', 'copy() { src="$1"; }\n', '\\set -- "set""up.sh" "$2"\n',
            '"set" -- "set""up.sh" "$2"\n', 'fixtures="$(dirname "$fixtures")"\n',
            '[ -n "${src:-}" ] || src="$1"\n',
        ):
            with self.subTest(extra=extra):
                self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" a.txt out/a\n')
                seed = self.repo / "plugins/alpha/evals/fixtures/seed.sh"
                text = seed.read_text(encoding="utf-8").replace("while", extra + "while", 1)
                seed.write_text(text, encoding="utf-8")
                _commit_all(self.repo, "rebind")
                _git(self.repo, "branch", "-f", "base", "HEAD")
                block = self._select(SETUP, "# Prints the fixture.\n", "")
                self.assert_runs(block, "the copied name is not only the call's argument")

    def test_positional_copy_named_by_a_non_shell_script_still_runs(self):
        _write(self.repo, "plugins/alpha/scripts/call.py", 'run(["bash", "seed.sh", "setup.sh"])\n')
        self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" a.txt out/a\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "a Python caller's arguments are not read")

    def test_positional_copy_called_from_a_makefile_or_extensionless_script_still_runs(self):
        for caller in ("plugins/alpha/evals/one-basic/Makefile", "plugins/alpha/evals/one-basic/more"):
            with self.subTest(caller=caller):
                _write(self.repo, caller, "\tbash ../fixtures/seed.sh setup.sh out/s\n")
                self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" a.txt out/a\n')
                block = self._select(SETUP, "# Prints the fixture.\n", "")
                self.assert_runs(block, "the caller passes setup.sh")
                (self.repo / caller).unlink()

    def test_positional_copy_called_from_another_plugin_still_runs(self):
        _write(
            self.repo,
            "plugins/beta/evals/fixtures/use.sh",
            'bash "$(dirname "$0")/../../../alpha/evals/fixtures/seed.sh" "$1" out\n',
        )
        self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" a.txt out/a\n')
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "the other plugin passes a variable")

    def test_positional_copy_reassigned_still_runs(self):
        self._positional_base('bash "$(dirname "$0")/../fixtures/seed.sh" a.txt out/a\n')
        seed = self.repo / "plugins/alpha/evals/fixtures/seed.sh"
        seed.write_text(seed.read_text(encoding="utf-8") + "src=setup.sh\n", encoding="utf-8")
        _commit_all(self.repo, "reassign")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._select(SETUP, "# Prints the fixture.\n", "")
        self.assert_runs(block, "src is not only a positional argument")

    def test_quoted_hash_in_a_description_edit_stays_description_only(self):
        _write(
            self.repo,
            CASE,
            'schema_version: "1.1"\nname: one-basic\ndescription: "Covers issue #12"\n'
            "tags: [alpha:one]\ncontext:\n  scaffold_script: scaffold.sh\n",
        )
        _commit_all(self.repo, "set description")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        block = self._select(CASE, '"Covers issue #12"', '"Covers issue #12 and #13"')
        self.assertNotIn("cases", block, "the # sits inside the quoted description")

    def test_dropping_a_comment_after_an_apostrophe_is_not_description_only(self):
        for line in ('description: "Don\'t break alpha" # keep tabs', "description: Don't panic # keep tabs"):
            with self.subTest(line=line):
                _write(
                    self.repo,
                    CASE,
                    'schema_version: "1.1"\nname: one-basic\n' + line + "\n"
                    "tags: [alpha:one]\ncontext:\n  scaffold_script: scaffold.sh\n",
                )
                _write(
                    self.repo,
                    SCAFFOLD,
                    "#!/usr/bin/env bash\n" + RUN_SETUP + 'grep "#" "$(dirname "$0")/case.yaml" >notes.txt\n',
                )
                _commit_all(self.repo, "comment after apostrophe")
                _git(self.repo, "branch", "-f", "base", "HEAD")
                block = self._select(CASE, " # keep tabs", "")
                self.assert_runs(block, "the scaffold writes the comment into the workspace")

    def _editorconfig_select(self, rel, old, new):
        _write(self.repo, rel, "root = true\n# Tabs for fixtures.\n; Kept as is.\n[*]\nindent_style = tab # x\n")
        _commit_all(self.repo, "add editorconfig")
        _git(self.repo, "branch", "-f", "base", "HEAD")
        return self._select(rel, old, new)

    def test_editorconfig_hash_and_semicolon_comment_lines_are_no_run(self):
        for old in ("# Tabs for fixtures.\n", "; Kept as is.\n"):
            with self.subTest(old=old):
                block = self._editorconfig_select("plugins/alpha/skills/one/.editorconfig", old, "")
                self.assertNotIn("cases", block, "an .editorconfig comment line changes no setting")
                self.assertIn("one-basic", block.get("affected-no-run", "").split())

    def test_editorconfig_hash_after_a_value_is_not_a_comment(self):
        block = self._editorconfig_select(
            "plugins/alpha/skills/one/.editorconfig", "indent_style = tab # x", "indent_style = tab"
        )
        self.assertIn("one-basic", block.get("cases", "").split(), "the # is part of the value")

    def test_editorconfig_comment_in_an_evals_folder_is_no_run(self):
        for rel in ("plugins/alpha/skills/one/evals/.editorconfig", "plugins/alpha/evals/one-basic/.editorconfig"):
            with self.subTest(rel=rel):
                block = self._editorconfig_select(rel, "# Tabs for fixtures.\n", "")
                self.assertNotIn("cases", block, "an editor-settings comment changes nothing the agent does")

    def test_editorconfig_key_change_in_an_evals_folder_still_runs(self):
        for old, new in (("root = true", "root = false"), ("indent_style = tab # x", "indent_style = tab")):
            with self.subTest(old=old):
                block = self._editorconfig_select("plugins/alpha/skills/one/evals/.editorconfig", old, new)
                self.assertIn("one-basic", block.get("cases", "").split(), "a setting changed")


class CommandStartTest(unittest.TestCase):
    def setUp(self):
        import suite_refs

        self.runs, self.cd = suite_refs.RUNS_STRING_RE, suite_refs.CD_WORD_RE

    def test_every_command_position_is_seen(self):
        for prefix in (
            "", "  ", "a; ", "a && ", "a || ", "a | ", "a & ", "( ", "{ ", "$( ", "`", "! ",
            "if ", "elif ", "then ", "else ", "do ", "while ", "until ", "x) ", "time ", "nohup ",
            "env ", "env A=1 ", "A=1 ", "exec ", "command ", "builtin ", "sudo ", "xargs ",
            "time -p ", "env -i ", "env -u X ", "command -p ", "sudo -E ", "exec -a name ", "nice ",
            "timeout 60 ", "stdbuf -oL ", "setsid ", "coproc ", "<( ", 'A="x y" ', "f() { ",
        ):
            with self.subTest(prefix=prefix):
                self.assertTrue(self.runs.search(prefix + "eval \"$x\""), prefix)
                self.assertTrue(self.runs.search(prefix + "source /dev/stdin <<<'x'"), prefix)
                self.assertTrue(self.runs.search(prefix + ". <(cat x)"), prefix)
                self.assertTrue(self.cd.search(prefix + "cd dir"), prefix)

    def test_words_that_only_look_like_commands(self):
        for line in (
            "git config user.name eval", "echo resource", "cp -r . ws", "abcd x",
            '. "$here/lib.sh"', 'value="\\"bash x.sh"',
        ):
            with self.subTest(line=line):
                self.assertIsNone(self.runs.search(line), line)
                self.assertIsNone(self.cd.search(line), line)


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
