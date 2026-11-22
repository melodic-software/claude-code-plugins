# test-scope: plugins/code-tidying/git-hooks/fixtures/*.sh.txt
from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "comment-lint.py"
_spec = importlib.util.spec_from_file_location("comment_lint", SCRIPT)
lint = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lint)
lint._CENSUS._ShellComments.STRICT = True

MESSAGE = (
    "comment outside the {} posture: delete it, move the reason into the code or the commit "
    "message, or link the outside constraint; /code-tidying:remove-comments fixes it"
)
SHA = "3d3c42e5aac5ba805825da76410c181273ba90b1"


def flagged(path, text, posture="necessary", added=None, allow=()):
    lines = text.count("\n") + 1
    got = lint.findings(path, text, added or [(1, lines)], posture, list(allow))
    return [int(f.split(":")[1]) for f in got]


class FindingLine(unittest.TestCase):
    def test_necessary_line_is_the_design_text(self):
        got = lint.findings("src/a.sh", "x=1\n# a note\n", [(1, 2)], "necessary", [])
        self.assertEqual(got, ["src/a.sh:2: " + MESSAGE.format("necessary")])

    def test_none_line_names_none(self):
        got = lint.findings("a.py", "x = 1  # a note\n", [(1, 1)], "none", [])
        self.assertEqual(got, ["a.py:1: " + MESSAGE.format("none")])

    def test_no_lexer_returns_none(self):
        self.assertIsNone(
            lint.findings("a.zzzunknown", "# x\n", [(1, 1)], "necessary", [])
        )


class AddedLinesOnly(unittest.TestCase):
    def test_comment_on_unchanged_line_never_fails(self):
        self.assertEqual(flagged("a.sh", "# old note\nx=1\n", added=[(2, 2)]), [])

    def test_comment_on_added_line_fails(self):
        self.assertEqual(
            flagged("a.sh", "# old note\n# new note\n", added=[(2, 2)]), [2]
        )


class RenameOnlyEdit(unittest.TestCase):
    NEW = "x=1\n# reads `diff_risk` from the summary\ndiff_risk=2\n"

    def judged(self, removed, text=NEW, start=2, added_count=2):
        added = text.split("\n")[start - 1 : start - 1 + added_count]
        hunks = [(start, removed, added)]
        got = lint.findings("a.sh", text, [(start, start + added_count - 1)], "necessary", [], hunks=hunks)
        return [int(f.split(":")[1]) for f in got]

    def test_comment_whose_only_change_is_a_renamed_identifier_passes(self):
        removed = ["# reads `babysit_risk` from the summary", "babysit_risk=2"]
        self.assertEqual(self.judged(removed), [])

    def test_renamed_identifier_with_changed_prose_is_still_judged(self):
        removed = ["# takes `babysit_risk` from the summary", "babysit_risk=2"]
        self.assertEqual(self.judged(removed), [2])

    def test_plain_word_swap_is_still_judged(self):
        text = "x=1\n# reads the risk from the summary\n"
        removed = ["# reads the danger from the summary"]
        self.assertEqual(self.judged(removed, text, added_count=1), [2])

    def test_unrelated_new_comment_is_still_judged(self):
        text = "x=1\n# a new note\ndiff_risk=2\n"
        self.assertEqual(self.judged(["babysit_risk=2"], text, start=2, added_count=2), [2])

    def test_inconsistent_rename_across_the_hunk_is_still_judged(self):
        text = "x=1\n# uses diff_risk\n# uses merge_risk\n"
        removed = ["# uses babysit_risk", "# uses babysit_risk"]
        self.assertEqual(self.judged(removed, text, added_count=2), [2, 3])

    def test_changed_adr_number_is_still_judged(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            (repo / "docs" / "adr").mkdir(parents=True)
            (repo / "docs" / "adr" / "0042-x.md").write_text("x\n", encoding="utf-8")
            text = "x=1\n# ADR-0999\n"
            hunks = [(2, ["# ADR-0042"], ["# ADR-0999"])]
            got = lint.findings("a.sh", text, [(2, 2)], "necessary", [], repo, hunks=hunks)
            self.assertEqual([int(f.split(":")[1]) for f in got], [2])

    def test_hunks_read_from_a_unified_diff(self):
        diff = (
            "diff --git a/a.sh b/a.sh\n--- a/a.sh\n+++ b/a.sh\n"
            "@@ -2,2 +2,2 @@\n-# reads `babysit_risk` from the summary\n-babysit_risk=2\n"
            "+# reads `diff_risk` from the summary\n+diff_risk=2\n"
        )
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "diff"
            p.write_text(diff, encoding="utf-8")
            self.assertEqual(
                lint._hunks(p),
                {"a.sh": [(2, ["# reads `babysit_risk` from the summary", "babysit_risk=2"],
                           ["# reads `diff_risk` from the summary", "diff_risk=2"])]},
            )


class Shape1ShebangAndCookie(unittest.TestCase):
    def test_shebang_passes(self):
        self.assertEqual(flagged("a.sh", "#!/bin/sh\nx=1\n"), [])

    def test_shebang_shaped_comment_past_line_one_fails(self):
        self.assertEqual(flagged("a.sh", "x=1\ny=2\n#!/bin/sh\n"), [3])

    def test_encoding_cookie_passes(self):
        self.assertEqual(
            flagged("a.py", "#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\nx = 1\n"),
            [],
        )

    def test_cookie_shape_past_line_two_fails(self):
        self.assertEqual(flagged("a.py", "x = 1\ny = 2\n# coding: utf-8\n"), [3])


class Shape2ToolDirective(unittest.TestCase):
    def test_directives_pass(self):
        cases = {
            "a.py": "x = 1  # noqa: E501\ny = 2  # type: ignore[attr-defined]\nz = 3  # pragma: no cover\n",
            "a.sh": "# shellcheck disable=SC2086\nx=$y\n",
            "a.js": "// eslint-disable-next-line no-console\nconsole.log(1);\n// @ts-expect-error\nf();\n",
            "b.py": "# vim: set ts=4 sw=4:\nx = 1\n",
            "a.cs": "// region Helpers\nint x;\n// endregion\n",
            "a.go": "//go:build linux\npackage a\n",
            "c.py": "# fmt: off\nx = 1\n# fmt: on\n",
        }
        for path, text in cases.items():
            with self.subTest(path=path):
                self.assertEqual(flagged(path, text), [])

    def test_plain_comment_fails(self):
        self.assertEqual(flagged("a.sh", "# set up the cache\nx=1\n"), [1])


class Shape3License(unittest.TestCase):
    def test_license_run_passes_whole(self):
        text = "# Copyright 2026 Example Ltd.\n# Use of this file is governed by the terms below.\nx=1\n"
        self.assertEqual(flagged("a.sh", text), [])

    def test_spdx_passes(self):
        self.assertEqual(
            flagged("a.js", "// SPDX-License-Identifier: MIT\nlet x;\n"), []
        )

    def test_run_without_cue_fails(self):
        self.assertEqual(
            flagged("a.sh", "# governed by the terms below\n# more\nx=1\n"), [1, 2]
        )


class Shape4Todo(unittest.TestCase):
    def test_todo_with_issue_passes(self):
        self.assertEqual(flagged("a.py", "x = 1  # TODO(#123): drop once fixed\n"), [])

    def test_todo_without_issue_fails(self):
        self.assertEqual(
            flagged("a.py", "x = 1  # TODO: drop this\ny = 2  # TODO(123): x\n"), [1, 2]
        )


class Shape5VersionPin(unittest.TestCase):
    def test_trailing_comment_on_sha_pinned_uses_passes(self):
        text = f"steps:\n  - uses: actions/checkout@{SHA} # v7.0.1\n"
        self.assertEqual(flagged("w.yml", text), [])

    def test_trailing_comment_on_tag_pinned_uses_fails(self):
        self.assertEqual(
            flagged("w.yml", "steps:\n  - uses: actions/checkout@v4 # v4\n"), [2]
        )

    def test_trailing_comment_on_sha_pinned_checkout_ref_passes(self):
        text = f"with:\n  ref: {SHA} # v0.75.0\n"
        self.assertEqual(flagged("w.yml", text), [])

    def test_trailing_comment_on_branch_ref_fails(self):
        self.assertEqual(flagged("w.yml", "with:\n  ref: main # v0.75.0\n"), [2])

    def test_full_line_comment_above_pinned_uses_fails(self):
        text = f"steps:\n  # v7.0.1\n  - uses: actions/checkout@{SHA}\n"
        self.assertEqual(flagged("w.yml", text), [2])


class Shape6IgnoreMarker(unittest.TestCase):
    def test_marker_line_passes(self):
        self.assertEqual(
            flagged("a.sh", "x=1 # keep this wording remove-comments-ignore\n"), []
        )

    def test_same_line_without_marker_fails(self):
        self.assertEqual(flagged("a.sh", "x=1 # keep this wording\n"), [1])


class Shape7DocComment(unittest.TestCase):
    def test_python_docstring_passes(self):
        self.assertEqual(
            flagged("a.py", 'def f():\n    """Return one."""\n    return 1\n'), []
        )

    def test_triple_slash_passes(self):
        self.assertEqual(
            flagged("a.cs", "/// <summary>Adds.</summary>\npublic int Add() => 1;\n"),
            [],
        )

    def test_jsdoc_block_passes(self):
        self.assertEqual(
            flagged(
                "a.js", "/**\n * Adds.\n * @returns {number}\n */\nfunction add() {}\n"
            ),
            [],
        )

    def test_plain_block_comment_fails(self):
        self.assertEqual(
            flagged("a.js", "/*\n * Adds.\n */\nfunction add() {}\n"), [1, 2, 3]
        )

    def test_powershell_help_passes(self):
        text = "function Get-X {\n<#\n.SYNOPSIS\nGets X.\n.PARAMETER Name\nThe name.\n#>\nparam($Name)\n}\n"
        self.assertEqual(flagged("a.ps1", text), [])

    def test_go_doc_on_exported_declaration_passes(self):
        self.assertEqual(
            flagged(
                "a.go",
                "package a\n\n// Foo returns one.\nfunc Foo() int { return 1 }\n",
            ),
            [],
        )

    def test_go_comment_on_unexported_declaration_fails(self):
        self.assertEqual(
            flagged(
                "a.go",
                "package a\n\n// foo returns one.\nfunc foo() int { return 1 }\n",
            ),
            [3],
        )

    def test_script_header_fails(self):
        self.assertEqual(flagged("a.sh", "#!/bin/sh\n# Usage: a.sh <dir>\nx=1\n"), [2])


class Shape8LinkOrRfc(unittest.TestCase):
    def test_url_run_passes_under_necessary(self):
        text = "# The gateway closes idle sockets at 60s,\n# https://example.com/docs/idle\nx=45\n"
        self.assertEqual(flagged("a.sh", text), [])

    def test_rfc_passes_under_necessary(self):
        self.assertEqual(
            flagged("a.py", "x = 1  # header order is fixed by RFC 9110 section 5.3\n"),
            [],
        )

    def test_link_fails_under_none(self):
        self.assertEqual(
            flagged(
                "a.sh", "# see https://example.com/docs/idle\nx=45\n", posture="none"
            ),
            [1],
        )

    def test_unlinked_outside_constraint_note_fails(self):
        self.assertEqual(
            flagged("a.sh", "# The gateway closes idle sockets at 60s\nx=45\n"), [1]
        )

    def test_unlinked_note_passes_with_ignore_marker(self):
        text = "# The gateway closes idle sockets at 60s remove-comments-ignore\nx=45\n"
        self.assertEqual(flagged("a.sh", text), [])


class AdrPointer(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        (self.repo / "docs" / "adr").mkdir(parents=True)
        (self.repo / "docs" / "adr" / "0042-use-postgres.md").write_text("# 42\n")
        (self.repo / "src" / "deep").mkdir(parents=True)

    def lines(self, text, path="src/deep/a.py", posture="necessary"):
        count = text.count("\n") + 1
        got = lint.findings(path, text, [(1, count)], posture, [], self.repo)
        return [int(f.split(":")[1]) for f in got]

    def test_existing_id_passes(self):
        for text in ("# ADR-0042\nx = 1\n", "# See ADR 42\nx = 1\n", "x = 1  # adr0042\n"):
            with self.subTest(text=text):
                self.assertEqual(self.lines(text), [])

    def test_existing_path_passes(self):
        for pointer in (
            "docs/adr/0042-use-postgres.md",
            "See docs/adr/0042",
            "../../docs/adr/0042-use-postgres.md",
        ):
            with self.subTest(pointer=pointer):
                self.assertEqual(self.lines(f"# {pointer}\nx = 1\n"), [])

    def test_block_comment_pointer_passes(self):
        self.assertEqual(self.lines("/* See ADR-0042 */\nint x;\n", path="a.c"), [])

    def test_missing_record_fails(self):
        for text in ("# ADR-0043\nx = 1\n", "# See docs/adr/0043\nx = 1\n"):
            with self.subTest(text=text):
                self.assertEqual(self.lines(text), [1])

    def test_path_outside_the_adr_folder_fails(self):
        (self.repo / "src" / "deep" / "b.py").write_text("")
        self.assertEqual(self.lines("# See src/deep/b.py\nx = 1\n"), [1])

    def test_pointer_with_reason_fails(self):
        self.assertEqual(self.lines("# See ADR-0042: Postgres for the primary store\nx = 1\n"), [1])

    def test_pointer_inside_a_longer_comment_fails(self):
        self.assertEqual(self.lines("# Postgres holds the primary store.\n# ADR-0042\nx = 1\n"), [1, 2])

    def test_pointer_fails_under_none(self):
        self.assertEqual(self.lines("# ADR-0042\nx = 1\n", posture="none"), [1])

    def test_configured_folder_holds_the_records(self):
        (self.repo / "docs" / "decisions").mkdir()
        (self.repo / "docs" / "decisions" / "0007-x.md").write_text("# 7\n")
        text = "# ADR-0007\nx = 1\n# See docs/decisions/0007\ny = 1\n# ADR-0042\nz = 1\n"
        got = lint.findings("a.py", text, [(1, 6)], "necessary", [], self.repo, "docs/decisions")
        self.assertEqual([int(f.split(":")[1]) for f in got], [5])

    def test_folder_outside_the_repository_falls_back_to_the_default(self):
        for adr_dir in ("../elsewhere", "/tmp", "."):
            with self.subTest(adr_dir=adr_dir):
                got = lint.findings("a.py", "# ADR-0042\nx = 1\n", [(1, 2)], "necessary", [], self.repo, adr_dir)
                self.assertEqual(got, [])

    def test_pointer_fails_without_a_repository(self):
        self.assertEqual(flagged("a.py", "# ADR-0042\nx = 1\n"), [1])


class Shape9FloorRest(unittest.TestCase):
    def test_line_after_ignore_marker_passes(self):
        for marker in ("remove-comments-ignore", "dissolve-comments-ignore"):
            with self.subTest(marker=marker):
                self.assertEqual(
                    flagged("a.sh", f"# {marker}\n# kept wording\nx=1\n"), []
                )

    def test_second_line_after_marker_fails(self):
        self.assertEqual(
            flagged("a.sh", "# remove-comments-ignore\n# kept\n# not kept\n"), [3]
        )

    def test_fixme_with_issue_passes(self):
        self.assertEqual(
            flagged("a.py", "x = 1  # FIXME(#9): wrong rounding\ny = 2  # FIXME: z\n"),
            [2],
        )

    def test_requires_and_signature_block_pass(self):
        text = "#Requires -Version 7\nWrite-Output 1\n# SIG # Begin signature block\n# MIIFAbc\n# SIG # End signature block\n"
        self.assertEqual(flagged("a.ps1", text), [])

    def test_reason_on_line_before_waiver_passes(self):
        text = "# the glob must split here\n# shellcheck disable=SC2086\nls $x\n"
        self.assertEqual(flagged("a.sh", text), [])

    def test_reason_on_waiver_line_passes(self):
        text = 'class A {\n  @SuppressWarnings("unchecked") // safe: the list holds only strings\n  void f() {}\n}\n'
        self.assertEqual(flagged("A.java", text), [])

    def test_reason_two_lines_before_waiver_fails(self):
        text = "# the glob must split here\nx=1\n# shellcheck disable=SC2086\nls $x\n"
        self.assertEqual(flagged("a.sh", text), [1])


EXIT_HEADER = (
    "#!/bin/sh\n"
    "# Exit codes:\n"
    "#   0  the scan ran\n"
    "#   2  a usage error: an unknown flag\n"
    "#      or a missing option value\n"
    "x=1\n"
)


class Shape10ExitCodes(unittest.TestCase):
    def test_header_exit_codes_pass_under_necessary(self):
        self.assertEqual(flagged("a.sh", EXIT_HEADER), [])

    def test_header_without_shebang_passes(self):
        self.assertEqual(flagged("a.sh", "# Exits:\n#   0 ok\n#   2 usage\nx=1\n"), [])

    def test_inline_entries_on_heading_pass(self):
        self.assertEqual(flagged("a.py", "# Exit: 0 judged; 2 usage\nx = 1\n"), [])

    def test_continuation_of_inline_entry_passes(self):
        text = "# Exit 2: the default branch could not be read;\n#         never the working copy.\nx=1\n"
        self.assertEqual(flagged("a.sh", text), [])

    def test_shallow_line_after_inline_entry_fails(self):
        text = "# Exit 2: the default branch could not be read;\n# never the working copy.\nx=1\n"
        self.assertEqual(flagged("a.sh", text), [2])

    def test_rest_of_header_still_fails(self):
        text = "#!/bin/sh\n# Scans a tree.\n# Exit codes:\n#   2  usage\n# The scan never fails.\nx=1\n"
        self.assertEqual(flagged("a.sh", text), [2, 5])

    def test_same_text_after_code_fails(self):
        text = "x=1\n" + EXIT_HEADER.split("\n", 1)[1]
        self.assertEqual(flagged("a.sh", text), [2, 3, 4, 5])

    def test_header_exit_codes_fail_under_none(self):
        self.assertEqual(flagged("a.sh", EXIT_HEADER, posture="none"), [2, 3, 4, 5])


class AllowPatterns(unittest.TestCase):
    def test_allow_pattern_passes_repository_marker(self):
        text = "# silent-skip-ok: output discarded\nx=1\n"
        self.assertEqual(flagged("a.sh", text, allow=["silent-skip-ok:"]), [])

    def test_without_allow_pattern_marker_fails(self):
        self.assertEqual(
            flagged("a.sh", "# silent-skip-ok: output discarded\nx=1\n"), [1]
        )

    def test_allow_pattern_is_extended_regex(self):
        text = "# test-scope: a b\nx=1\n"
        self.assertEqual(flagged("a.sh", text, allow=["^# (test|case)-scope:"]), [])


class StayQuiet(unittest.TestCase):
    def test_code_the_old_heuristic_misread(self):
        cases = {
            "a.sh": "run --flag value\necho ${#name}\necho 'a # b' \"c # d\"\ncat <<EOF\n# heredoc body\nEOF\n",
            "a.c": "#include <stdio.h>\nint x;\n",
            "a.yml": "url: http://x.example/a#frag\nname: 'a # b'\n",
            "a.py": "s = '# not a comment'\nt = \"#also not\"\n",
        }
        for path, text in cases.items():
            with self.subTest(path=path):
                self.assertEqual(flagged(path, text), [])


class Cli(unittest.TestCase):
    def test_cli_reads_root_ranges_and_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp, "root")
            (root / "sub").mkdir(parents=True)
            (root / "sub" / "a.sh").write_text("x=1\n# note\n", encoding="utf-8")
            (root / "b.zzzunknown").write_text("# x\n", encoding="utf-8")
            ranges = Path(tmp, "ranges")
            ranges.write_text("sub/a.sh\t1\t2\nb.zzzunknown\t1\t1\n", encoding="utf-8")
            allow = Path(tmp, "allow")
            allow.write_text("", encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--posture",
                    "necessary",
                    "--root",
                    str(root),
                    "--ranges",
                    str(ranges),
                    "--allow",
                    str(allow),
                ],
                input=b"sub/a.sh\0b.zzzunknown\0",
                capture_output=True,
                check=False,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(
            proc.stdout.decode(), "sub/a.sh:2: " + MESSAGE.format("necessary") + "\n"
        )
        self.assertEqual(
            proc.stderr.decode(),
            "comment-lint: b.zzzunknown: no pygments lexer for this name, skipped\n",
        )

    def test_cli_rejects_bad_allow_pattern(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp, "root")
            root.mkdir()
            (root / "a.sh").write_text("# note\n", encoding="utf-8")
            Path(tmp, "ranges").write_text("a.sh\t1\t1\n", encoding="utf-8")
            Path(tmp, "allow").write_text("a[\n", encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--posture",
                    "necessary",
                    "--root",
                    str(root),
                    "--ranges",
                    str(Path(tmp, "ranges")),
                    "--allow",
                    str(Path(tmp, "allow")),
                ],
                input=b"a.sh\0",
                capture_output=True,
                check=False,
            )
        self.assertEqual(proc.returncode, 4)
        self.assertIn("comment_lint_allow", proc.stderr.decode())


class GoDocInsideGroups(unittest.TestCase):
    def test_doc_on_exported_const_in_a_group_passes(self):
        text = "package p\n\nconst (\n\t// Foo is the answer.\n\tFoo = 1\n)\n"
        self.assertEqual(flagged("a.go", text), [])

    def test_doc_on_exported_struct_field_passes(self):
        text = (
            "package p\n\ntype T struct {\n\t// Name is the name.\n\tName string\n}\n"
        )
        self.assertEqual(flagged("a.go", text), [])

    def test_comment_on_unexported_group_member_fails(self):
        text = "package p\n\nconst (\n\t// foo is the answer.\n\tfoo = 1\n)\n"
        self.assertEqual(flagged("a.go", text), [4])

    def test_comment_above_a_statement_in_a_function_fails(self):
        text = "package p\n\nfunc F() {\n\t// call it\n\tPrintln()\n}\n"
        self.assertEqual(flagged("a.go", text), [4])


class MoreDirectives(unittest.TestCase):
    def test_floor_directives_pass(self):
        cases = [
            ("d.c", "// clang-format off\nint x;\n// clang-format on\n"),
            ("d.c", "// cppcheck-suppress nullPointer\nint x;\n"),
            ("d.lua", "-- luacheck: ignore 212\nlocal x = 1\n"),
            ("d.lua", "-- stylua: ignore\nlocal x = 1\n"),
            ("d.lua", "---@diagnostic disable-next-line: undefined-global\nx = 1\n"),
            ("d.py", 'KEY = "x"  # pragma: allowlist secret\n'),
            ("d.py", "y = 1  # pyre-ignore[16]\n"),
            ("d.rb", "# typed: strict\nx = 1\n"),
            ("d.toml", "#:schema ./s.json\nx = 1\n"),
        ]
        for path, text in cases:
            with self.subTest(text=text):
                self.assertEqual(flagged(path, text), [])

    def test_portability_ok_passes(self):
        text = '#!/usr/bin/env bash\n# portability-ok: GNU stat only, Linux-only script\nsize=$(stat -c %s "$1")\necho "$size"\n'
        self.assertEqual(flagged("t.sh", text), [])

    def test_portability_ok_on_the_hit_line_passes(self):
        self.assertEqual(flagged("t.sh", "date -d tomorrow # portability-ok: Linux CI runner only\n"), [])

    def test_portability_scope_passes(self):
        text = "#!/usr/bin/env bash\n# portability-scope: fixture corpus of the portability gate\nx=1\n"
        self.assertEqual(flagged("t.sh", text), [])

    def test_portability_scope_mid_sentence_fails(self):
        self.assertEqual(flagged("t.sh", "x=1\n# the gate honors portability-scope: lines\n"), [2])

    def test_prose_that_resembles_a_directive_fails(self):
        cases = [
            ("a.sh", "x=1\n# the global config\n"),
            ("a.sh", "x=1\n# see ex: the parser\n"),
            ("t.sh", "x=1\n# GNU stat only\n"),
        ]
        for path, text in cases:
            with self.subTest(text=text):
                self.assertEqual(flagged(path, text), [2])

    def test_real_region_modeline_and_global_still_pass(self):
        cases = [
            ("a.cs", "class C {\n#region Fields\nint x;\n#endregion\n}\n"),
            ("a.ts", "// #region helpers\nconst x = 1;\n// #endregion\n"),
            ("a.sh", "x=1\n# vim: set ts=2 sw=2:\n"),
            ("a.js", "/* global window */\nconst x = 1;\n"),
        ]
        for path, text in cases:
            with self.subTest(text=text):
                self.assertEqual(flagged(path, text), [])


class RunsAndLexers(unittest.TestCase):
    def test_blank_line_separates_two_runs(self):
        text = "# See https://example.com/x\n\n# narrative\nx=1\n"
        self.assertEqual(flagged("a.sh", text), [3])

    def test_blank_line_inside_a_block_comment_ends_the_link(self):
        text = "/*\n * See https://example.com/x\n\n * narrative\n */\nconst x = 1;\n"
        self.assertEqual(flagged("a.js", text), [4])

    def test_bare_star_line_inside_a_block_comment_ends_the_link(self):
        text = "/*\n * See https://example.com/x\n *\n * narrative\n */\nconst x = 1;\n"
        self.assertEqual(flagged("a.js", text), [4])

    def test_link_passes_its_own_block_comment_paragraph(self):
        text = "/*\n * The limit follows\n * https://example.com/x\n */\nconst x = 1;\n"
        self.assertEqual(flagged("a.js", text), [])

    def test_license_header_in_blank_separated_paragraphs_passes_whole(self):
        text = (
            "#!/bin/sh\n# Copyright 2026 Example Corp.\n\n"
            "# Provided as is, without warranty of any kind.\n\nx=1\n"
        )
        self.assertEqual(flagged("a.sh", text), [])

    def test_comment_two_blank_lines_below_a_license_fails(self):
        text = "# Copyright 2026 Example Corp.\n\n\n# narrative\nx=1\n"
        self.assertEqual(flagged("a.sh", text), [4])

    def test_mts_and_cts_are_judged_as_typescript(self):
        for path in ("a.mts", "a.cts"):
            with self.subTest(path=path):
                self.assertEqual(flagged(path, "const x = 1; // a note\n"), [1])

    def test_powershell_hash_inside_a_word_is_no_comment(self):
        self.assertEqual(flagged("n.ps1", "dotnet new console -lang C#\n"), [])

    def test_powershell_comment_after_whitespace_still_fails(self):
        self.assertEqual(flagged("n.ps1", "$x = 1 # a note\n"), [1])


DESYNC = "cat >stub <<'STUB'\necho \"$STUB_LOG\" \"it's\"\nSTUB\n"


class ShellTokenRecognition(unittest.TestCase):
    """A '#' starts a shell comment only where POSIX token recognition says so."""

    def test_hash_inside_quotes_after_a_heredoc_is_no_comment(self):
        for line in (
            "printf '#!/bin/bash\\necho m\\n' >a.sh",
            "x='a\\n# stub: finding'",
            'y="b # no"',
            "z=$'c\\n# no'",
        ):
            with self.subTest(line=line):
                self.assertEqual(flagged("a.sh", DESYNC + line + "\n"), [])

    def test_heredoc_bodies_are_no_comments(self):
        cases = (
            'cat <<"EOF"\n# body\nEOF\n',
            "cat <<\\EOF\n# body\nEOF\n",
            "cat <<-'EOF'\n\t# body $EOF_X\n\tEOF\necho '# no'\n",
            "cat <<A <<'B'\n# a\nA\n# b\nB\n",
            "x=$(cat <<EOF\n# body\nEOF\n)\n",
        )
        for text in cases:
            with self.subTest(text=text):
                self.assertEqual(flagged("a.sh", text), [])

    def test_hash_inside_a_word_is_no_comment(self):
        for line in ('url=$base#frag', 'echo "${x}"#tail', "echo 'a'#b", "echo $(id)#x"):
            with self.subTest(line=line):
                self.assertEqual(flagged("a.sh", line + "\n"), [])

    def test_parameter_hash_forms_are_no_comments(self):
        for line in ("n=$#", "m=${#x}", 'p="${x#*/}"', "q=$((16#ff))", "(( 1 << 2 ))"):
            with self.subTest(line=line):
                self.assertEqual(flagged("a.sh", DESYNC + line + "\necho '# no'\n"), [])

    def test_real_comments_still_fail(self):
        cases = (
            (DESYNC + "echo done # trailing\n", [4]),
            ("echo a;# after an operator\n", [1]),
            ("x=$(echo a # inside a substitution\n)\n", [1]),
            ("cat <<EOF\nbody\nEOF\n# after the body\n", [4]),
            ("a=(1 # in an array\n2)\n", [1]),
            ('grep -q x <<<"$1"\n# after a here-string\n', [2]),
            ("[[ $x =~ ((a)+)$ ]] && y=${x:-{\\}}\n# after a regex\n", [2]),
            ("done < <(((${#a[@]})) && printf '%s\\n' x)\n# after <(\n", [2]),
            ('x="$(echo case)"\n# after an argument named case\n', [2]),
            ("x=$(case a in a) echo;; esac)\n# after a case command\n", [2]),
            ("x=$(if true; then case a in (a) :;; esac; fi)\n# after a nested case\n", [2]),
            ("cat <<$'EOF'\nbody\nEOF\n# after an ANSI-C delimiter\n", [4]),
            ("cat <<$'E\\x4fF'\n# body\nEOF\n# after an escaped delimiter\n", [4]),
            ('cat <<$"EOF"\n# body\nEOF\n# after a locale delimiter\n', [4]),
        )
        for text, want in cases:
            with self.subTest(text=text):
                self.assertEqual(flagged("a.sh", text), want)

    def test_an_unparsed_construct_never_hides_later_comments(self):
        cases = (
            ("echo 'unterminated\n# a\necho b # c\n", [2, 3]),
            ('echo "unterminated\n# a\n', [2]),
            ("x=$(echo\n# a\n", [2]),
            ("y=${x\n# a\n", [2]),
            ("(( a ) )\n# a\n", [2]),
            ("cat <<EOF\n# body\nno delimiter\n", [2]),
            ("cat <<'EOF\n# a\n", [2]),
            ('cat <<"EOF\n# a\n', [2]),
            ("cat <<$'EOF\n# a\n", [2]),
        )
        for text, want in cases:
            with self.subTest(text=text):
                self.assertEqual(flagged("a.sh", text), want)

    def test_a_construct_lost_on_a_last_line_without_newline_ends_cleanly(self):
        cases = (
            ("# a\necho 'x", [1]),
            ('# a\necho "x', [1]),
            ("# a\ny=${x", [1]),
            ("# a\necho $(a", [1]),
            ("# a\n$(((a)) && b)", [1]),
        )
        for text, want in cases:
            with self.subTest(text=text):
                self.assertEqual(flagged("a.sh", text), want)


SWEEP_SHELL = (
    "#!/usr/bin/env bash\n"
    + DESYNC
    + "printf '#!/bin/bash\\necho m\\n' >a.sh # one\n"
    + "y=\"b # no $(echo case) ${x#*/} ${#x} $#\"; z=$'c\\n# no'; w=$\"d\"\n"
    + "cat <<'A' <<\"B\" <<$'C\\x44' <<-\\E <<$\"F\" <<G\n# a\nA\n# b\nB\n# c\nCD\n\t# e\n\tE\n# f\nF\n$g\nG\n"
    + "x=$(case a in (a) echo ')';; b) :;; esac) `echo b # in ticks`\n"
    + "(( 1 << 2 )) && q=$((16#ff)) && [[ $x =~ ((a)+)$ ]] && r=${x:-{\\}}\n"
    + "done < <(((${#a[@]})) && printf '%s\\n' x) # two\n"
    + "grep -q x <<<\"$1\" # three\nurl=$base#frag; echo \"${x}\"#tail \\\n  # four\n"
)


def _sweep_texts():
    texts = [("composite", SWEEP_SHELL)]
    for path in sorted((HERE / "fixtures").glob("*.sh.txt")):
        texts.append((path.name, path.read_text(encoding="utf-8")))
    return texts


class ShellTruncationSweep(unittest.TestCase):
    """Cut every shell text at every offset: the scan always finishes, and a comment added after the cut is found."""

    def test_every_prefix_scans_and_a_comment_after_it_is_found(self):
        from pygments.lexers import get_lexer_by_name

        lexer = get_lexer_by_name("bash", stripnl=False)
        cuts = 0
        for name, text in _sweep_texts():
            for cut in range(len(text) + 1):
                cuts += 1
                bare = text[:cut]
                got = lint._CENSUS.tokens(bare, lexer)
                if "".join(value for _, value in got) != bare:
                    self.fail(f"{name} cut at {cut}: the tokens do not cover {bare!r}")
                probe = bare + "\n\n# z\n"
                got = [
                    value
                    for tok, value in lint._CENSUS.tokens(probe, lexer)
                    if lint._CENSUS.is_comment_token(tok)
                ]
                if "# z" not in got:
                    self.fail(f"{name} cut at {cut}: '# z' not found in {probe!r}")
        self.assertGreater(cuts, 1000)


class ScannerFailure(unittest.TestCase):
    def test_strict_scan_is_on_under_test(self):
        self.assertTrue(lint._CENSUS._ShellComments.STRICT)

    def test_a_scan_that_stops_short_falls_back_to_line_comments(self):
        scanner = lint._CENSUS._ShellComments
        real = scanner._command

        def stop_short(self, close, start):
            real(self, close, start)
            self.i = start

        with mock.patch.object(scanner, "STRICT", False), mock.patch.object(
            scanner, "_command", stop_short
        ):
            self.assertEqual(flagged("a.sh", "x='a\n# b'\n  # c\n"), [2, 3])

    def test_a_file_the_reader_fails_on_is_named_and_the_others_still_judged(self):
        real = lint.findings

        def boom(path, *args):
            if path == "bad.sh":
                raise RuntimeError("boom")
            return real(path, *args)

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp, "root")
            root.mkdir()
            (root / "bad.sh").write_text("y=1\n", encoding="utf-8")
            (root / "ok.sh").write_text("x=1\n# note\n", encoding="utf-8")
            ranges = Path(tmp, "ranges")
            ranges.write_text("bad.sh\t1\t1\nok.sh\t1\t2\n", encoding="utf-8")
            out, err = io.StringIO(), io.StringIO()
            stdin = mock.Mock()
            stdin.buffer.read.return_value = b"bad.sh\0ok.sh\0"
            with mock.patch.object(lint, "findings", boom), mock.patch.object(
                sys, "stdin", stdin
            ), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = lint.main(
                    ["--posture", "necessary", "--root", str(root), "--ranges", str(ranges)]
                )
        self.assertEqual(rc, 5)
        self.assertEqual(out.getvalue(), "ok.sh:2: " + MESSAGE.format("necessary") + "\n")
        self.assertIn("comment-lint: bad.sh: not judged, the comment reader failed: boom", err.getvalue())


if __name__ == "__main__":
    unittest.main()
