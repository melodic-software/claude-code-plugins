#!/usr/bin/env python3
"""Black-box tests for change-shape.py.

Runs the script as a subprocess so the exit-code contract a shell gate relies
on is what gets asserted, not an internal function. Grammar-dependent cases
skip VISIBLY when tree-sitter or a grammar is absent; the degradation case
always runs, because a suite that can be entirely skipped proves nothing.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("change-shape.py")


def run(before: str, after: str, ext: str, *extra: str) -> tuple[int, str, str]:
    with tempfile.TemporaryDirectory() as tmp:
        b = Path(tmp, f"before{ext}")
        a = Path(tmp, f"after{ext}")
        b.write_text(before)
        a.write_text(after)
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), *extra, str(b), str(a)],
            capture_output=True,
            text=True,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr


def grammar_available(ext: str) -> bool:
    code, _, _ = run("x = 1\n", "x = 1\n", ext)
    return code != 3


def powershell_available() -> bool:
    # Not `!= 3`: a missing PowerShell host is exit 2, the same code a mapped
    # extension never returns when the backend works.
    code, _, _ = run("$x = 1\n", "$x = 1\n", ".ps1")
    return code == 0


TS_BASE = """// leading comment
export function helper(x: number): number {
  // increment x
  return x + 1;
}
"""

SH_BASE = """#!/usr/bin/env bash
# explain the retry
retry_count=3
run() { echo "$retry_count"; }
"""


@unittest.skipUnless(
    grammar_available(".ts"), "tree-sitter typescript grammar not installed"
)
class TypeScriptVerdicts(unittest.TestCase):
    def test_comment_deletion_is_comment_only(self):
        after = TS_BASE.replace("// leading comment\n", "").replace(
            "  // increment x\n", ""
        )
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 0, out)
        self.assertTrue(out.startswith("COMMENT-ONLY"), out)

    def test_reindent_is_comment_only(self):
        after = TS_BASE.replace("  return", "      return").replace("  //", "      //")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 0, out)

    def test_consistent_rename_is_rename_only_with_mapping(self):
        after = TS_BASE.replace("helper", "incrementByOne")
        code, out, _ = run(TS_BASE, after, ".ts", "--json")
        self.assertEqual(code, 10, out)
        self.assertIn('"mapping": {"helper": "incrementByOne"}', out)

    def test_two_identifiers_collapsing_to_one_name_is_code_changed(self):
        after = (
            TS_BASE.replace("helper", "same")
            .replace("(x: number)", "(same: number)")
            .replace("x + 1", "same + 1")
        )
        code, out, _ = run(TS_BASE, after, ".ts", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("collapse", out)

    def test_literal_change_is_code_changed(self):
        after = TS_BASE.replace("x + 1", "x + 2")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 20, out)
        self.assertIn("number", out)

    def test_comment_deletion_plus_literal_change_is_not_masked(self):
        after = TS_BASE.replace("// leading comment\n", "").replace("x + 1", "x + 2")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 20, out)

    def test_unparsable_after_is_unprovable(self):
        after = TS_BASE.replace("return x + 1;", "return x + ;")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 21, out)
        self.assertTrue(out.startswith("UNPROVABLE"), out)


@unittest.skipUnless(grammar_available(".sh"), "tree-sitter bash grammar not installed")
class BashVerdicts(unittest.TestCase):
    def test_comment_deletion_is_comment_only(self):
        after = SH_BASE.replace("# explain the retry\n", "")
        code, out, _ = run(SH_BASE, after, ".sh")
        self.assertEqual(code, 0, out)

    def test_shebang_deletion_is_not_comment_only(self):
        after = SH_BASE.replace("#!/usr/bin/env bash\n", "")
        code, out, _ = run(SH_BASE, after, ".sh")
        self.assertEqual(code, 20, out)

    def test_heredoc_body_edit_is_code_changed(self):
        before = SH_BASE + "cat >f <<'EOF'\n# looks like a comment\nEOF\n"
        after = SH_BASE + "cat >f <<'EOF'\n# looks different\nEOF\n"
        code, out, _ = run(before, after, ".sh")
        self.assertEqual(code, 20, out)

    def test_value_change_that_orphans_the_comment_is_code_changed(self):
        after = SH_BASE.replace("retry_count=3", "retry_count=5")
        code, out, _ = run(SH_BASE, after, ".sh")
        self.assertEqual(code, 20, out)


PY_BASE = '''"""Module docstring stays: it is a doc comment, not a code token."""
# explain the budget
retry_budget = 3


def run():
    # narrate
    return retry_budget
'''

CS_BASE = """/// <summary>Public doc.</summary>
public class Widget {
    // internal note
    private int Count = 3;
    public int Get() { return Count; }
}
"""

JS_BASE = """// leading
function helper(x) {
  // increment
  return x + 1;
}
module.exports = { helper };
"""

YML_BASE = """# top comment
name: ci
on: [push]  # trailing comment
jobs:
  build:
    runs-on: ubuntu-latest
"""


@unittest.skipUnless(
    grammar_available(".py"), "tree-sitter python grammar not installed"
)
class PythonVerdicts(unittest.TestCase):
    def test_comment_deletion_is_comment_only(self):
        after = PY_BASE.replace("# explain the budget\n", "").replace(
            "    # narrate\n", ""
        )
        code, out, _ = run(PY_BASE, after, ".py")
        self.assertEqual(code, 0, out)

    def test_docstring_deletion_is_code_changed(self):
        # A docstring is a string expression statement, not a comment node; removing
        # it must never pass as COMMENT-ONLY.
        after = PY_BASE.replace(
            '"""Module docstring stays: it is a doc comment, not a code token."""\n', ""
        )
        code, out, _ = run(PY_BASE, after, ".py")
        self.assertEqual(code, 20, out)

    def test_rename_is_rename_only(self):
        after = PY_BASE.replace("retry_budget", "max_attempts")
        code, out, _ = run(PY_BASE, after, ".py", "--json")
        self.assertEqual(code, 10, out)
        self.assertIn('"retry_budget": "max_attempts"', out)

    def test_rename_that_misses_a_reference_is_code_changed(self):
        # Only the declaration is renamed; the read in run() still says retry_budget.
        after = PY_BASE.replace("retry_budget = 3", "max_attempts = 3")
        code, out, _ = run(PY_BASE, after, ".py", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("incomplete rename", out)

    def test_rename_onto_an_existing_identifier_is_code_changed(self):
        before = "def f(x, y):\n    return x + y\n"
        after = "def f(y, y):\n    return y + y\n"
        code, out, _ = run(before, after, ".py", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("collides", out)


@unittest.skipUnless(
    grammar_available(".cs"), "tree-sitter c-sharp grammar not installed"
)
class CSharpVerdicts(unittest.TestCase):
    def test_line_comment_deletion_is_comment_only(self):
        after = CS_BASE.replace("    // internal note\n", "")
        code, out, _ = run(CS_BASE, after, ".cs")
        self.assertEqual(code, 0, out)

    def test_xml_doc_deletion_is_comment_only_by_token_proof(self):
        # The proof is about code tokens; exempting public XML docs is the
        # skill's job (never touched), not the classifier's.
        after = CS_BASE.replace("/// <summary>Public doc.</summary>\n", "")
        code, out, _ = run(CS_BASE, after, ".cs")
        self.assertEqual(code, 0, out)

    def test_rename_is_rename_only(self):
        after = CS_BASE.replace("Count", "Total")
        code, out, _ = run(CS_BASE, after, ".cs", "--json")
        self.assertEqual(code, 10, out)
        self.assertIn('"Count": "Total"', out)


@unittest.skipUnless(
    grammar_available(".js"), "tree-sitter javascript grammar not installed"
)
class JavaScriptVerdicts(unittest.TestCase):
    def test_comment_deletion_is_comment_only(self):
        after = JS_BASE.replace("// leading\n", "").replace("  // increment\n", "")
        code, out, _ = run(JS_BASE, after, ".js")
        self.assertEqual(code, 0, out)

    def test_rename_is_rename_only(self):
        after = JS_BASE.replace("helper", "incrementByOne")
        code, out, _ = run(JS_BASE, after, ".js", "--json")
        self.assertEqual(code, 10, out)
        self.assertIn('"helper": "incrementByOne"', out)


@unittest.skipUnless(
    grammar_available(".yml"), "tree-sitter yaml grammar not installed"
)
class YamlVerdicts(unittest.TestCase):
    def test_comment_deletion_is_comment_only(self):
        after = YML_BASE.replace("# top comment\n", "").replace(
            "  # trailing comment", ""
        )
        code, out, _ = run(YML_BASE, after, ".yml")
        self.assertEqual(code, 0, out)

    def test_value_change_is_code_changed(self):
        after = YML_BASE.replace("ubuntu-latest", "ubuntu-22.04")
        code, out, _ = run(YML_BASE, after, ".yml")
        self.assertEqual(code, 20, out)


PS_BASE = '''#Requires -Version 7.4
<#
.SYNOPSIS
    Emits a banner.
#>
# leading comment
function Get-Thing {
    param([string]$oldName)
    <# block comment #>
    $banner = @"
# not a comment
"@
    Write-Output $oldName  # trailing comment
    Write-Output $banner
}
'''


@unittest.skipUnless(powershell_available(), "no PowerShell host (pwsh) on PATH")
class PowerShellVerdicts(unittest.TestCase):
    def test_full_line_comment_deletion_is_comment_only(self):
        after = PS_BASE.replace("# leading comment\n", "")
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 0, out)
        self.assertTrue(out.startswith("COMMENT-ONLY"), out)

    def test_end_of_line_comment_deletion_is_comment_only(self):
        after = PS_BASE.replace("  # trailing comment", "")
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 0, out)

    def test_block_comment_deletion_is_comment_only(self):
        after = PS_BASE.replace("    <# block comment #>\n", "")
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 0, out)

    def test_help_block_deletion_is_comment_only(self):
        # The proof is honest: comment-based help is an ordinary comment token.
        # Protecting it is the skill's exempt-surfaces job, not the proof's.
        after = PS_BASE.replace("<#\n.SYNOPSIS\n    Emits a banner.\n#>\n", "")
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 0, out)

    def test_here_string_hash_line_survives_a_comment_deletion(self):
        after = PS_BASE.replace("# leading comment\n", "")
        self.assertIn("# not a comment", after)
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 0, out)

    def test_here_string_hash_line_deletion_is_code_changed(self):
        after = PS_BASE.replace('@"\n# not a comment\n"@', '@"\n"@')
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 20, out)

    def test_requires_deletion_is_code_changed(self):
        after = PS_BASE.replace("#Requires -Version 7.4\n", "")
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 20, out)

    def test_consistent_variable_rename_is_rename_only(self):
        after = PS_BASE.replace("$oldName", "$newName")
        code, out, _ = run(PS_BASE, after, ".ps1", "--json")
        self.assertEqual(code, 10, out)
        self.assertIn('"$oldName": "$newName"', out)

    def test_incomplete_variable_rename_is_code_changed(self):
        after = PS_BASE.replace("param([string]$oldName)", "param([string]$newName)")
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 20, out)

    def test_function_rename_is_code_changed(self):
        # A command name is `Generic`, a cross-file contract, never a rename.
        after = PS_BASE.replace("Get-Thing", "Get-Other")
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 20, out)

    def test_unbalanced_brace_is_unprovable(self):
        after = PS_BASE.replace("    Write-Output $banner\n}\n", "    Write-Output $banner\n")
        code, out, _ = run(PS_BASE, after, ".ps1")
        self.assertEqual(code, 21, out)
        self.assertTrue(out.startswith("UNPROVABLE"), out)

    def test_psm1_uses_the_same_backend(self):
        after = PS_BASE.replace("# leading comment\n", "")
        code, out, _ = run(PS_BASE, after, ".psm1")
        self.assertEqual(code, 0, out)

    def test_shebang_deletion_is_not_comment_only(self):
        before = "#!/usr/bin/env pwsh\n$x = 1\n"
        code, out, _ = run(before, "$x = 1\n", ".ps1")
        self.assertEqual(code, 20, out)

    def test_statements_merging_behind_a_comment_deletion_is_code_changed(self):
        # Deleting the comment also deletes the newline that separated two
        # commands, so `Write-Output $a` swallows `$b` as an argument.
        before = "$a = 1\n$b = 2\nWrite-Output $a # c\n$b\n"
        after = "$a = 1\n$b = 2\nWrite-Output $a $b\n"
        code, out, _ = run(before, after, ".ps1")
        self.assertEqual(code, 20, out)

    def test_blank_line_change_is_still_comment_only(self):
        before = "$a = 1\n\n# c\n\n$b = 2\n"
        after = "$a = 1\n$b = 2\n"
        code, out, _ = run(before, after, ".ps1")
        self.assertEqual(code, 0, out)


PS_INTERPOLATION = """$old = 1
Write-Output "$old"
Write-Output "${old}"
Write-Output @"
$old
"@
Write-Output $old
"""


@unittest.skipUnless(powershell_available(), "no PowerShell host (pwsh) on PATH")
class PowerShellRenames(unittest.TestCase):
    """A variable inside an expandable string is a reference the rename must reach."""

    def bare_only(self, src: str) -> str:
        """Rename only the occurrences that are not inside a string."""
        return src.replace("$old = 1", "$new = 1").replace(
            "Write-Output $old", "Write-Output $new"
        )

    def test_rename_missing_an_interpolated_reference_is_code_changed(self):
        code, out, _ = run(PS_INTERPOLATION, self.bare_only(PS_INTERPOLATION), ".ps1")
        self.assertEqual(code, 20, out)

    def test_rename_missing_a_braced_reference_is_code_changed(self):
        src = '$old = 1\nWrite-Output "${old}"\nWrite-Output $old\n'
        code, out, _ = run(src, self.bare_only(src), ".ps1")
        self.assertEqual(code, 20, out)

    def test_rename_missing_a_here_string_reference_is_code_changed(self):
        src = '$old = 1\nWrite-Output @"\n$old\n"@\nWrite-Output $old\n'
        code, out, _ = run(src, self.bare_only(src), ".ps1")
        self.assertEqual(code, 20, out)

    def test_rename_onto_a_name_only_seen_inside_a_string_is_code_changed(self):
        # `$new` appears nowhere but inside the string, so the collision is
        # visible only because interpolated references are read out.
        src = '$old = 1\nWrite-Output "$new"\nWrite-Output $old\n'
        code, out, _ = run(src, self.bare_only(src), ".ps1")
        self.assertEqual(code, 20, out)

    def test_rename_to_a_scoped_name_is_code_changed(self):
        src = "$old = 1\nWrite-Output $old\n"
        after = src.replace("$old", "$global:old")
        code, out, _ = run(src, after, ".ps1", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("scope prefix", out)

    def test_rename_to_an_environment_variable_is_code_changed(self):
        src = "$old = 1\nWrite-Output $old\n"
        after = src.replace("$old", "$env:OLD")
        code, out, _ = run(src, after, ".ps1", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("scope prefix", out)

    def test_rename_to_an_automatic_variable_is_code_changed(self):
        src = "$old = 1\nWrite-Output $old\n"
        after = src.replace("$old", "$_")
        code, out, _ = run(src, after, ".ps1", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("reserved variable", out)

    def test_case_only_respelling_is_not_a_rename(self):
        # PowerShell variable names are case-insensitive, so nothing moved.
        src = "$Old = 1\nWrite-Output $Old\n"
        after = src.replace("$Old", "$old")
        code, out, _ = run(src, after, ".ps1", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("respelled", out)

    def test_rename_colliding_case_insensitively_is_code_changed(self):
        src = "$new = 0\n$old = 1\nWrite-Output $old\n"
        after = src.replace("$old", "$New")
        code, out, _ = run(src, after, ".ps1", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("collides", out)

    def test_incomplete_rename_is_caught_across_case(self):
        src = "$old = 1\nWrite-Output $Old\nWrite-Output $old\n"
        after = src.replace("$old = 1", "$new = 1").replace(
            "Write-Output $old", "Write-Output $new"
        )
        code, out, _ = run(src, after, ".ps1", "--json")
        self.assertEqual(code, 20, out)
        self.assertIn("incomplete rename", out)

    def test_rename_to_a_reserved_variable_is_code_changed(self):
        for target in ("$null", "$HOME", "$true", "$PID"):
            with self.subTest(target=target):
                src = "$old = 1\nWrite-Output $old\n"
                code, out, _ = run(src, src.replace("$old", target), ".ps1", "--json")
                self.assertEqual(code, 20, out)
                self.assertIn("reserved variable", out)

    def test_same_scope_rename_is_still_rename_only(self):
        src = "$script:old = 1\nWrite-Output $script:old\n"
        after = src.replace("$script:old", "$script:new")
        code, out, _ = run(src, after, ".ps1", "--json")
        self.assertEqual(code, 10, out)


class Degradation(unittest.TestCase):
    """Always runs: proves the unavailable path is loud and distinct."""

    def test_missing_tree_sitter_exits_3_with_reason(self):
        with tempfile.TemporaryDirectory() as tmp:
            b = Path(tmp, "a.py")
            a = Path(tmp, "b.py")
            b.write_text("x = 1\n")
            a.write_text("x = 1\n")
            # -S drops site-packages, so `import tree_sitter` cannot resolve.
            proc = subprocess.run(
                [sys.executable, "-S", str(SCRIPT), str(b), str(a)],
                capture_output=True,
                text=True,
                check=False,
                env={**os.environ, "PYTHONPATH": tmp},
            )
        self.assertEqual(proc.returncode, 3, proc.stderr)
        self.assertIn("UNAVAILABLE", proc.stderr)
        self.assertIn("tree-sitter", proc.stderr)

    def test_unknown_extension_is_usage_error(self):
        code, _, err = run("x", "x", ".unknownext")
        self.assertEqual(code, 2, err)
        self.assertIn("--lang", err)

    def test_missing_powershell_host_is_exit_2_not_a_tacit_pass(self):
        # Exit 2, the "unproven edit" code, never exit 3: exit 3 lets a coarser
        # reading layer apply the deletion anyway.
        with tempfile.TemporaryDirectory() as tmp:
            b = Path(tmp, "a.ps1")
            a = Path(tmp, "b.ps1")
            b.write_text("$x = 1\n")
            a.write_text("$x = 1\n")
            proc = subprocess.run(
                [sys.executable, str(SCRIPT), str(b), str(a)],
                capture_output=True,
                text=True,
                check=False,
                cwd=tmp,
                env={**os.environ, "PATH": ""},
            )
        self.assertEqual(proc.returncode, 2, proc.stderr)
        self.assertIn("pwsh", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
