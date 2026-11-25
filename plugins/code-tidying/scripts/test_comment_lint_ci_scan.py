#!/usr/bin/env python3
"""Black-box tests for comment-lint-ci-scan.py: each case writes a repository
layout to a temporary directory, runs the script, and reads its JSON."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("comment-lint-ci-scan.py")


def scan(files: dict[str, str]) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        for name, text in files.items():
            path = Path(tmp, name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "--repo", tmp], capture_output=True, text=True, check=False
        )
        if proc.returncode != 0:
            raise AssertionError(proc.stderr)
        return json.loads(proc.stdout)


def kinds(result: dict) -> list[str]:
    return [d["kind"] for d in result["decisions"]]


CALL = "bash .githooks/code-tidying/comment-lint-ci.sh"


class Systems(unittest.TestCase):
    def test_no_ci_files_is_no_system(self) -> None:
        result = scan({"src/app.py": "x = 1\n"})
        self.assertEqual(result["systems"], [])
        self.assertEqual(kinds(result), ["no-ci-system"])

    def test_each_vendor_is_found_by_its_own_file(self) -> None:
        layout = {
            ".github/workflows/ci.yml": "github-actions",
            "azure-pipelines.yml": "azure-pipelines",
            ".gitlab-ci.yml": "gitlab-ci",
            "Jenkinsfile": "jenkins",
            ".circleci/config.yml": "circleci",
            "bitbucket-pipelines.yml": "bitbucket-pipelines",
        }
        for file, system in layout.items():
            with self.subTest(system=system):
                result = scan({file: "steps: []\n"})
                self.assertEqual(result["systems"], [{"system": system, "files": [file]}])

    def test_two_systems_ask_which(self) -> None:
        result = scan({".gitlab-ci.yml": "x\n", "Jenkinsfile": "x\n"})
        self.assertIn("several-systems", kinds(result))

    def test_a_task_runner_is_reported_beside_no_system(self) -> None:
        result = scan({"Makefile": "lint:\n\ttrue\n"})
        self.assertEqual(result["runners"], [{"runner": "make", "files": ["Makefile"]}])
        self.assertEqual(result["decisions"], [{"kind": "no-ci-system", "runners": ["make"]}])

    def test_a_system_with_no_caller_says_so(self) -> None:
        self.assertEqual(kinds(scan({".gitlab-ci.yml": "lint:\n  script: make\n"})), ["no-caller"])


class Callers(unittest.TestCase):
    def test_a_matching_call_has_no_decision_but_the_tools(self) -> None:
        text = f"lint:\n  script:\n    - pip install pygments\n    - python3 -V\n    - {CALL} \"$CI_COMMIT_SHA\" origin/main\n"
        result = scan({".gitlab-ci.yml": text})
        self.assertEqual(result["callers"][0]["args"], ["$CI_COMMIT_SHA", "origin/main"])
        self.assertEqual(result["decisions"], [])

    def test_a_template_expression_counts_as_one_argument(self) -> None:
        text = f"      - run: {CALL} ${{{{ github.event.pull_request.head.sha }}}} \"origin/${{{{ github.base_ref }}}}\"\n"
        result = scan({".github/workflows/ci.yml": text})
        self.assertEqual(len(result["callers"][0]["args"]), 2)
        self.assertNotIn("drift", kinds(result))

    def test_a_continued_line_is_read_whole(self) -> None:
        text = f"    script: |\n      {CALL} \\\n        \"$(Build.SourceVersion)\" \\\n        origin/main\n"
        result = scan({"azure-pipelines.yml": text})
        self.assertEqual(result["callers"][0]["line"], 2)
        self.assertNotIn("drift", kinds(result))

    def test_a_quoted_groovy_step_is_parsed(self) -> None:
        text = f"sh \"{CALL} ${{env.GIT_COMMIT}} origin/${{env.CHANGE_TARGET}}\"\n"
        result = scan({"Jenkinsfile": text})
        self.assertEqual(result["callers"][0]["args"], ["${env.GIT_COMMIT}", "origin/${env.CHANGE_TARGET}"])
        self.assertNotIn("drift", kinds(result))

    def test_a_call_stops_at_a_shell_operator(self) -> None:
        result = scan({".gitlab-ci.yml": f"  - {CALL} \"$A\" \"$B\" && echo done\n"})
        self.assertEqual(result["callers"][0]["args"], ["$A", "$B"])

    def test_one_argument_is_drift(self) -> None:
        result = scan({".gitlab-ci.yml": f"  - {CALL} \"$CI_COMMIT_SHA\"\n"})
        drift = [d for d in result["decisions"] if d["kind"] == "drift"]
        self.assertEqual(drift[0]["args"], ["$CI_COMMIT_SHA"])
        self.assertEqual(drift[0]["interface"], "comment-lint-ci.sh <head> <base>")

    def test_an_option_is_drift(self) -> None:
        result = scan({".gitlab-ci.yml": f"  - {CALL} --base origin/main\n"})
        self.assertIn("drift", kinds(result))

    def test_the_older_recipe_is_found(self) -> None:
        text = "      - run: sh plugins/code-tidying/git-hooks/comment-lint.sh\n      - run: scripts/check-comment-lint.sh\n"
        result = scan({".github/workflows/ci.yml": text})
        self.assertEqual([c["form"] for c in result["callers"]], ["recipe", "recipe"])
        self.assertEqual(kinds(result).count("recipe-caller"), 2)

    def test_a_hook_shim_is_no_caller(self) -> None:
        result = scan({"Makefile": "x:\n\tsh .lefthook/pre-commit/code-tidying-comment-lint.sh\n", ".gitlab-ci.yml": "x\n"})
        self.assertEqual(result["callers"], [])

    def test_a_caller_file_that_never_names_pygments_is_flagged(self) -> None:
        result = scan({".gitlab-ci.yml": f"  - python3 -V\n  - {CALL} \"$A\" \"$B\"\n"})
        self.assertEqual(
            [d for d in result["decisions"] if d["kind"] == "missing-tool"],
            [{"kind": "missing-tool", "tool": "pygments", "files": [".gitlab-ci.yml"]}],
        )


class Reach(unittest.TestCase):
    MAKEFILE = f"test:\n\tpytest\n\ncomment-lint:\n\t{CALL} \"$HEAD\" origin/main\n"

    def test_a_commented_out_call_is_no_caller(self) -> None:
        text = f"lint:\n  script:\n    # - {CALL} \"$A\" \"$B\"\n    - make test\n"
        result = scan({".gitlab-ci.yml": text})
        self.assertEqual(result["callers"], [])
        self.assertEqual(kinds(result), ["no-caller"])

    def test_a_commented_out_groovy_call_is_no_caller(self) -> None:
        self.assertEqual(scan({"Jenkinsfile": f"// sh '{CALL} $A $B'\n"})["callers"], [])

    def test_a_make_target_ci_never_runs_is_not_installed(self) -> None:
        result = scan({".gitlab-ci.yml": "test:\n  script:\n    - make test\n", "Makefile": self.MAKEFILE})
        unreached = [d for d in result["decisions"] if d["kind"] == "unreached-caller"]
        self.assertEqual(
            unreached,
            [
                {
                    "kind": "unreached-caller",
                    "file": "Makefile",
                    "line": 5,
                    "runner": "make",
                    "target": "comment-lint",
                    "ci_files": [".gitlab-ci.yml"],
                }
            ],
        )

    def test_a_make_target_a_commented_ci_line_names_is_not_installed(self) -> None:
        ci = "lint:\n  script:\n    # - make comment-lint\n    - make test\n"
        self.assertIn("unreached-caller", kinds(scan({".gitlab-ci.yml": ci, "Makefile": self.MAKEFILE})))

    def test_a_make_target_ci_runs_is_reached(self) -> None:
        result = scan({".gitlab-ci.yml": "lint:\n  script:\n    - make comment-lint\n", "Makefile": self.MAKEFILE})
        self.assertNotIn("unreached-caller", kinds(result))
        self.assertEqual(result["callers"][0]["reached_by"], [".gitlab-ci.yml"])

    def test_a_just_recipe_ci_runs_is_reached(self) -> None:
        justfile = f"comment-lint head base:\n    {CALL} {{{{head}}}} {{{{base}}}}\n"
        ci = "      - run: just comment-lint \"$SHA\" origin/main\n"
        result = scan({".github/workflows/ci.yml": ci, "justfile": justfile})
        self.assertNotIn("unreached-caller", kinds(result))

    def test_a_task_ci_runs_is_reached_and_another_is_not(self) -> None:
        taskfile = f"version: '3'\ntasks:\n  lint-comments:\n    cmds:\n      - {CALL} \"$A\" \"$B\"\n"
        reached = scan({"Jenkinsfile": "sh 'task lint-comments'\n", "Taskfile.yml": taskfile})
        unreached = scan({"Jenkinsfile": "sh 'task build'\n", "Taskfile.yml": taskfile})
        self.assertNotIn("unreached-caller", kinds(reached))
        self.assertIn("unreached-caller", kinds(unreached))

    def test_a_runner_caller_with_no_ci_system_is_unreached(self) -> None:
        result = scan({"Makefile": self.MAKEFILE})
        self.assertEqual(kinds(result)[:2], ["no-ci-system", "unreached-caller"])


class Usage(unittest.TestCase):
    def test_a_missing_repo_is_a_usage_error(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "--repo", "/nonexistent/repo"], capture_output=True, check=False
        )
        self.assertEqual(proc.returncode, 2)

    def test_an_unknown_option_is_a_usage_error(self) -> None:
        proc = subprocess.run([sys.executable, str(SCRIPT), "--nope"], capture_output=True, check=False)
        self.assertEqual(proc.returncode, 2)


if __name__ == "__main__":
    unittest.main()
