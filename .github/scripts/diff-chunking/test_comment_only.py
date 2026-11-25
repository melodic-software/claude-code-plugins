"""Black-box tests for comment_only.py, which classifies through
plugins/code-tidying/scripts/change-shape.py.

Each case is a file changed between two commits of a throwaway repository;
the expected verdict for each is the rule the helper's contract states.
Without tree-sitter and its grammars the suite skips visibly, and fails when
CODE_TIDYING_REQUIRE_TREE_SITTER is set, as CI's Test Python job sets it.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

SCRIPT = Path(__file__).with_name("comment_only.py")
REQUIREMENTS = Path(__file__).with_name("requirements-comment-only.txt")
GRAMMARS = (
    "tree_sitter",
    "tree_sitter_python",
    "tree_sitter_javascript",
    "tree_sitter_bash",
)
MISSING = [m for m in GRAMMARS if importlib.util.find_spec(m) is None]
if MISSING:
    notice = f"tree-sitter tooling unavailable ({', '.join(MISSING)}); pip install -r {REQUIREMENTS}"
    if os.environ.get("CODE_TIDYING_REQUIRE_TREE_SITTER"):
        raise RuntimeError(notice)
    pytest.skip(notice, allow_module_level=True)

ENV = {
    **os.environ,
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
}

PY_BASE = (
    "import os\n\n\n# explain the root\ndef root():\n    return os.getcwd()  # cwd\n"
)
PY_STRIPPED = "import os\n\n\ndef root():\n    return os.getcwd()\n"
JS_BASE = (
    "// say hello\nexport function hi(name) {\n  return `hi ${name}`; // greet\n}\n"
)
JS_STRIPPED = "export function hi(name) {\n  return `hi ${name}`;\n}\n"
SH_BASE = '#!/usr/bin/env bash\n# count the files\nn=$(ls | wc -l)\necho "$n"\n'
SH_STRIPPED = '#!/usr/bin/env bash\nn=$(ls | wc -l)\necho "$n"\n'

CASES = {
    "comment.py": (PY_BASE, PY_STRIPPED, True),
    "comment.js": (JS_BASE, JS_STRIPPED, True),
    "comment.sh": (SH_BASE, SH_STRIPPED, True),
    "docstring.py": (
        'def area(r):\n    """Area of a circle."""\n    return 3.14 * r * r\n',
        "def area(r):\n    return 3.14 * r * r\n",
        True,
    ),
    "code.py": (PY_BASE, PY_BASE.replace("getcwd", "getcwdb"), False),
    "shellcheck.sh": (
        "#!/usr/bin/env bash\n# shellcheck disable=SC2086\necho $1\n",
        "#!/usr/bin/env bash\necho $1\n",
        False,
    ),
    "eslint.js": (
        "// eslint-disable-next-line no-console\nconsole.log(1);\n",
        "console.log(1);\n",
        False,
    ),
    "moved-directive.sh": (
        "#!/usr/bin/env bash\n# shellcheck disable=SC2086\necho $1\necho $2\n",
        "#!/usr/bin/env bash\necho $1\n# shellcheck disable=SC2086\necho $2\n",
        False,
    ),
    "next-line.js": (
        "// eslint-disable-next-line no-console\nconsole.log(1);\n",
        "// eslint-disable-next-line no-console\n\nconsole.log(1);\n",
        False,
    ),
    "block-next-line.js": (
        "/* eslint-disable-next-line\n   no-console\n*/\nconsole.log(1);\n",
        "/* eslint-disable-next-line\n   no-console\n*/\n\nconsole.log(1);\n",
        False,
    ),
    "reference.ts": (
        '/// <reference path="./globals.d.ts" />\nexport const x = 1;\n',
        "export const x = 1;\n",
        False,
    ),
    "pure.js": (
        "export const x =\n  /* @__PURE__ */\n  make();\n",
        "export const x =\n  make();\n",
        False,
    ),
    "flow.js": ("// @flow\nexport const x = 1;\n", "export const x = 1;\n", False),
    "spdx.js": (
        "// SPDX-License-Identifier: MIT\nexport const x = 1;\n",
        "export const x = 1;\n",
        False,
    ),
    "moved-comment.sh": (
        "#!/usr/bin/env bash\n# note\necho a\n",
        "#!/usr/bin/env bash\necho a\n# note\n",
        False,
    ),
    "added.py": (None, PY_STRIPPED, False),
    "deleted.py": (PY_BASE, None, False),
    "notes.md": ("# Title\n\n<!-- a comment -->\nText.\n", "# Title\n\nText.\n", False),
    "script.ps1": ("# say it\nWrite-Output 1\n", "Write-Output 1\n", False),
    "unchanged.py": (PY_BASE, PY_BASE, False),
}
RENAMED_FROM, RENAMED_TO = "old-name.py", "new-name.py"
MODE_CHANGED = "mode.sh"
EXECUTABLE = "executable.sh"


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=True,
        env=ENV,
    ).stdout.strip()


def commit_tree(
    repo: Path, files: dict[str, str | None], modes: dict[str, bool]
) -> str:
    for path, content in files.items():
        target = repo / path
        if content is None:
            target.unlink(missing_ok=True)
            continue
        target.write_text(content)
    for path, executable in modes.items():
        (repo / path).chmod(0o755 if executable else 0o644)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "--allow-empty", "-m", "snapshot")
    return git(repo, "rev-parse", "HEAD")


def run(
    repo: Path, base: str, head: str, paths: list[str]
) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), base, head],
        input="".join(f"{p}\n" for p in paths),
        capture_output=True,
        text=True,
        cwd=repo,
        env=ENV,
        check=False,
    )


@pytest.fixture(scope="module")
def outcome(tmp_path_factory):
    repo = tmp_path_factory.mktemp("repo")
    git(repo, "init", "-q")
    base_files = {p: b for p, (b, _, _) in CASES.items()}
    base_files[RENAMED_FROM] = PY_BASE
    base_files[MODE_CHANGED] = SH_BASE
    base_files[EXECUTABLE] = SH_BASE
    base = commit_tree(repo, base_files, {MODE_CHANGED: False, EXECUTABLE: True})
    head_files = {p: h for p, (_, h, _) in CASES.items()}
    head_files[RENAMED_FROM] = None
    head_files[RENAMED_TO] = PY_STRIPPED
    head_files[MODE_CHANGED] = SH_STRIPPED
    head_files[EXECUTABLE] = SH_STRIPPED
    head = commit_tree(repo, head_files, {MODE_CHANGED: True, EXECUTABLE: True})
    paths = [*CASES, RENAMED_FROM, RENAMED_TO, MODE_CHANGED, EXECUTABLE]
    return run(repo, base, head, paths)


@pytest.mark.parametrize("path", list(CASES))
def test_each_case_gets_the_verdict_its_rule_states(outcome, path):
    assert outcome.returncode == 0, outcome.stderr
    printed = outcome.stdout.splitlines()
    assert (path in printed) is CASES[path][2], f"{path}: printed={printed}"


@pytest.mark.parametrize("path", [RENAMED_FROM, RENAMED_TO, MODE_CHANGED])
def test_renames_and_mode_changes_never_qualify(outcome, path):
    assert outcome.returncode == 0, outcome.stderr
    assert path not in outcome.stdout.splitlines()


def test_an_executable_that_keeps_its_mode_qualifies(outcome):
    assert outcome.returncode == 0, outcome.stderr
    assert EXECUTABLE in outcome.stdout.splitlines()


def test_prints_only_qualifying_paths_in_input_order(outcome):
    assert outcome.stdout.splitlines() == [
        "comment.py",
        "comment.js",
        "comment.sh",
        "docstring.py",
        EXECUTABLE,
    ]


def test_batch_of_200_files_finishes_within_the_bound(tmp_path):
    git(tmp_path, "init", "-q")
    names = [f"m{i:03}.py" for i in range(200)]
    base = commit_tree(tmp_path, dict.fromkeys(names, PY_BASE), {})
    head = commit_tree(tmp_path, dict.fromkeys(names, PY_STRIPPED), {})
    started = time.monotonic()
    proc = run(tmp_path, base, head, names)
    elapsed = time.monotonic() - started
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.splitlines() == names
    assert elapsed < 20, f"200 files took {elapsed:.1f}s, over the 20s bound"


def test_an_unknown_commit_prints_nothing_and_fails(tmp_path):
    git(tmp_path, "init", "-q")
    head = commit_tree(tmp_path, {"a.py": PY_BASE}, {})
    proc = run(tmp_path, "0" * 40, head, ["a.py"])
    assert proc.returncode == 1
    assert proc.stdout == ""


def test_missing_arguments_is_a_usage_error(tmp_path):
    usage = subprocess.run(
        [sys.executable, str(SCRIPT), "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert usage.returncode == 2
    assert usage.stdout == ""


def test_requirements_pin_every_package_the_grammars_need():
    shape = (
        Path(__file__).resolve().parents[3]
        / "plugins/code-tidying/scripts/change-shape.py"
    )
    spec = importlib.util.spec_from_file_location("change_shape", shape)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    needed = {"tree-sitter"} | {
        entry[1].replace("_", "-") for entry in module.EXT_LANG.values() if entry[1]
    }
    pinned = {}
    for line in REQUIREMENTS.read_text().splitlines():
        if line and not line.startswith((" ", "#")):
            name = line.split("==")[0]
            pinned[name] = 0
        elif line.lstrip().startswith("--hash=sha256:"):
            pinned[name] += 1
    assert set(pinned) == needed
    assert all(pinned.values()), f"a pin without a hash: {pinned}"
