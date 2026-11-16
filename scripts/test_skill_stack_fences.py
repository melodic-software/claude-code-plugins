#!/usr/bin/env python3
"""Tests for skill-stack-fences.py, the counter behind the skill-stack-fences ratchet.

Each case builds a throwaway git repository and runs the counter at its command
line, so every expected value below comes from the fixture and the rules in the
counter's docstring, not from running the counter.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG", "GIT_INDEX_FILE"):
    os.environ.pop(_leaked_git_var, None)

SCRIPT = Path(__file__).resolve().parent / "skill-stack-fences.py"

SKILL = "plugins/demo/skills/run/SKILL.md"


class SkillStackFencesTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name) / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, rel: str, text: str) -> None:
        path = self.repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def stage(self) -> None:
        subprocess.run(["git", "-C", str(self.repo), "add", "-A"], check=True)

    def run_counter(self, cwd: Path | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT)],
            cwd=cwd or self.repo,
            capture_output=True,
            text=True,
            check=False,
        )

    def counts(self) -> dict[str, int]:
        result = self.run_counter()
        self.assertEqual(result.returncode, 0, result.stderr)
        out: dict[str, int] = {}
        for line in result.stdout.splitlines():
            path, token = line.rsplit(" ", 1)
            field, value = token.split("=")
            self.assertEqual(field, "fences")
            out[path] = int(value)
        return out

    def test_counts_stack_tags_and_skips_shell_data_and_untagged(self) -> None:
        self.write(
            SKILL,
            "```csharp\nvar x = 1;\n```\n"
            "```ts\nconst x = 1;\n```\n"
            "```rust\nlet x = 1;\n```\n"
            "```bash\nls\n```\n"
            "```powershell\nGet-Item .\n```\n"
            "```json\n{}\n```\n"
            "```yaml\na: 1\n```\n"
            "```text\nplain\n```\n"
            "```markdown\n# h\n```\n"
            "```sql\nselect 1;\n```\n"
            "```regex\na+\n```\n"
            "```!\ngit status\n```\n"
            "```\nuntagged\n```\n",
        )
        self.stage()
        self.assertEqual(self.counts(), {SKILL: 3})

    def test_tag_is_first_word_case_insensitive_with_attributes(self) -> None:
        self.write(
            SKILL,
            "```Python title=x.py\nx = 1\n```\n"
            "``` js\nx\n```\n"
            "```{.go}\nx\n```\n"
            "```Bash\nls\n```\n",
        )
        self.stage()
        self.assertEqual(self.counts(), {SKILL: 3})

    def test_list_indented_and_tilde_fences_count(self) -> None:
        self.write(
            SKILL,
            "1. Step\n\n      ```java\n      class A {}\n      ```\n\n"
            "~~~kotlin\nval a = 1\n~~~\n",
        )
        self.stage()
        self.assertEqual(self.counts(), {SKILL: 2})

    def test_blockquote_fences_count(self) -> None:
        self.write(
            SKILL,
            "> ```python\n> x = 1\n> ```\n"
            ">> ```ts\n>> x\n>> ```\n"
            "> - ```go\n>   x\n>   ```\n",
        )
        self.stage()
        self.assertEqual(self.counts(), {SKILL: 3})

    def test_fences_right_after_a_list_marker_count(self) -> None:
        self.write(
            SKILL,
            "- ```python\n  x = 1\n  ```\n"
            "* ```java\n  x\n  ```\n"
            "1. ```csharp\n   x\n   ```\n"
            "2) ```ruby\n   x\n   ```\n"
            "- ```bash\n  ls\n  ```\n",
        )
        self.stage()
        self.assertEqual(self.counts(), {SKILL: 4})

    def test_list_item_opener_does_not_hide_the_next_block(self) -> None:
        self.write(
            SKILL,
            "- ```python\n  x = 1\n  ```\n\n```csharp\nvar x;\n```\n",
        )
        self.stage()
        self.assertEqual(self.counts(), {SKILL: 2})

    def test_fences_inside_another_fence_are_content(self) -> None:
        self.write(
            SKILL,
            "````markdown\n```python\nx = 1\n```\n````\n"
            "~~~text\n```csharp\nvar x;\n```\n~~~\n"
            "```python\nprint()\n```\n",
        )
        self.stage()
        self.assertEqual(self.counts(), {SKILL: 1})

    def test_closing_fence_needs_same_char_and_at_least_opening_length(self) -> None:
        self.write(
            SKILL,
            "````text\n```\n~~~~\n```csharp\n````\n```python\nx\n```\n",
        )
        self.stage()
        self.assertEqual(self.counts(), {SKILL: 1})

    def test_scope_is_tracked_skill_and_agent_markdown_outside_test_and_vendor_dirs(
        self,
    ) -> None:
        fence = "```python\nx = 1\n```\n"
        agent = "plugins/demo/agents/worker.md"
        nested = "plugins/demo/skills/run/reference/deep/notes.md"
        self.write(SKILL, fence)
        self.write(agent, fence + fence)
        self.write(nested, fence)
        for rel in (
            "plugins/demo/skills/run/evals/case/prompt.md",
            "plugins/demo/skills/run/tests/fixtures/a.md",
            "plugins/demo/skills/run/vendor/SKILL.md",
            "plugins/demo/skills/run/scripts/notes.txt",
            "plugins/demo/reference/shared.md",
            "plugins/demo/README.md",
            "docs/guide.md",
        ):
            self.write(rel, fence)
        self.stage()
        self.write("plugins/demo/skills/run/untracked.md", fence)
        self.assertEqual(self.counts(), {SKILL: 1, agent: 2, nested: 1})

    def test_output_is_sorted_and_omits_files_at_zero(self) -> None:
        fence = "```go\nx\n```\n"
        self.write("plugins/b/skills/s/SKILL.md", fence)
        self.write("plugins/a/skills/s/SKILL.md", fence)
        self.write("plugins/c/skills/s/SKILL.md", "```bash\nls\n```\n")
        self.stage()
        result = self.run_counter()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "plugins/a/skills/s/SKILL.md fences=1",
                "plugins/b/skills/s/SKILL.md fences=1",
            ],
        )

    def test_exit_2_when_no_file_is_in_scope(self) -> None:
        self.write("docs/guide.md", "```python\nx\n```\n")
        self.stage()
        result = self.run_counter()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_exit_2_outside_a_git_repository(self) -> None:
        outside = Path(self._tmp.name) / "plain"
        outside.mkdir()
        result = self.run_counter(cwd=outside)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
