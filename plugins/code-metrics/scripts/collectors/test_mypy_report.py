#!/usr/bin/env python3
"""Output-based tests for the mypy-report adapter at its command line.

mypy is an unmanaged out-of-process dependency, so it is stubbed: each test
generates a fake `mypy` in a temporary directory prepended to PATH that copies
the committed capture fixtures/tool-output/mypy-any-exprs.txt into the report
directory the adapter asked for (design T13; no executable is committed). The
table parser is also driven directly, because a capture with zero `Any`
expressions cannot show that a non-zero count is read from the right column.
"""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "mypy-report.py"
CAPTURE = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "mypy-any-exprs.txt"
# The table mypy 1.19.1 writes when a blocking error (a duplicate module name)
# aborts the build before analysis: no module rows and a Total of 0 over 0.
ABORTED = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "mypy-any-exprs-aborted.txt"
# A real mypy 1.19.1 table over `pkg/a.py`, `pkg-x/b.py` and `c.py` run from
# their parent directory: a dotted module, a bare stem under a hyphenated
# directory (the walk stops there), and a plain top-level module.
MODULES = SCRIPT_DIR.parent / "fixtures" / "tool-output" / "mypy-any-exprs-modules.txt"
STUB_ERROR = (
    'pkg-x/b.py:1: error: Library stubs not installed for "yaml"  [import-untyped]'
)
SOURCES = "plugins/code-metrics/scripts/fixtures/sources"
REPO_ROOT = SCRIPT_DIR.parents[3]


def load_module():
    spec = importlib.util.spec_from_file_location("cm_mypy_report", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_stub(
    directory: Path,
    exit_code: int = 0,
    capture: Path | None = CAPTURE,
    stdout_line: str = "",
    stderr_line: str = "",
    argv_log: Path | None = None,
    reject_explicit_bases: bool = False,
) -> None:
    """Write a `mypy` stub that replays the capture into the report directory.

    With `argv_log` the stub also records every argument it received, one per
    line and one run after another, so a test can assert on the flags the
    adapter passes. With `reject_explicit_bases` the stub answers a run
    carrying `--explicit-package-bases` the way mypy does when the config
    turns namespace packages off: the usage error on stderr and exit 2,
    before any report is written.
    """
    copy = (
        f'cp "{capture}" "$dir/any-exprs.txt"\n'
        if capture is not None
        else "# the report is never written\n"
    )
    log = f'printf \'%s\\n\' "$@" >>"{argv_log}"\n' if argv_log is not None else ""
    reject = (
        'for arg in "$@"; do\n'
        '  if [[ "$arg" == "--explicit-package-bases" ]]; then\n'
        "    printf '%s\\n' 'mypy: error: Can only use --explicit-package-bases "
        "with --namespace-packages, since otherwise examining __init__.py files "
        "is sufficient to determine module names for files' >&2\n"
        "    exit 2\n"
        "  fi\n"
        "done\n"
        if reject_explicit_bases
        else ""
    )
    stub = directory / "mypy"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'if [[ "${1:-}" == "--version" ]]; then printf \'mypy 1.19.1 (compiled: yes)\\n\'; exit 0; fi\n'
        + log
        + reject
        + 'dir=""\nprev=""\n'
        'for arg in "$@"; do\n'
        '  [[ "$prev" == "--any-exprs-report" ]] && dir="$arg"\n'
        '  prev="$arg"\n'
        "done\n"
        '[[ -n "$dir" ]] && mkdir -p "$dir"\n' + copy + f"printf '%s' '{stdout_line}'\n"
        f"printf '%s' '{stderr_line}' >&2\n"
        f"exit {exit_code}\n",
        encoding="utf-8",
    )
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run(
    *args: str,
    path_prefix: Path | None = None,
    real_path: bool = False,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env.get('PATH', '')}"
    elif not real_path:
        env["PATH"] = str(
            Path(tempfile.gettempdir()) / "definitely-empty-path-for-mypy-tests"
        )
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=cwd or REPO_ROOT,
        check=False,
    )


class MypyReportProbeTests(unittest.TestCase):
    def test_probe_fails_when_mypy_is_absent(self) -> None:
        result = run("probe")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not on PATH", result.stderr)

    def test_probe_prints_the_version_when_the_stub_resolves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run("probe", path_prefix=Path(tmp))
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "1.19.1"))


def rows_of(result: subprocess.CompletedProcess) -> list[dict]:
    return [json.loads(line) for line in result.stdout.splitlines()]


class MypyReportCollectTests(unittest.TestCase):
    def test_collect_prints_a_row_per_scope_file_and_the_lane_row(self) -> None:
        # The capture lists `cm_sample`, the bare stem mypy gives a file under
        # a hyphenated directory (`code-metrics`): a file row for the scope
        # path plus the lane row summing it.
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = rows_of(result)
            self.assertEqual(len(rows), 2)
            # The lane row leads: the lane's figure is the first row.
            lane_row, file_row = rows
            values = {
                "any_expressions": 0,
                "expressions_total": 13,
                "type_coverage_pct": 100.0,
            }
            self.assertEqual(
                (file_row["file"], file_row["function"], file_row["labels"]),
                (f"{SOURCES}/cm_sample.py", None, []),
            )
            self.assertEqual(file_row["values"], values)
            self.assertEqual((lane_row["file"], lane_row["function"]), (None, None))
            self.assertEqual(lane_row["lane"], "python")
            self.assertEqual(lane_row["collector"], "mypy-report")
            self.assertEqual(lane_row["values"], values)
            self.assertEqual(lane_row["labels"], ["lane-total"])
            self.assertEqual(result.stderr, "")

    def _collect_modules(
        self, tmp: str, *files: str, exit_code: int = 1
    ) -> subprocess.CompletedProcess:
        make_stub(
            Path(tmp),
            exit_code=exit_code,
            capture=MODULES,
            stdout_line=STUB_ERROR if exit_code else "",
        )
        return run(
            "collect",
            "python",
            "type_coverage",
            *files,
            path_prefix=Path(tmp),
            cwd=Path(tmp),
        )

    def test_module_rows_map_to_scope_files_and_the_lane_row_sums_them(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect_modules(tmp, "pkg/a.py", "pkg-x/b.py", "c.py")
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = rows_of(result)
            self.assertEqual(
                [(r["file"], tuple(r["values"].values())) for r in rows],
                [
                    (None, (8, 26, 69.23)),
                    ("pkg/a.py", (5, 9, 44.44)),
                    ("pkg-x/b.py", (3, 11, 72.73)),
                    ("c.py", (0, 6, 100.0)),
                ],
            )
            self.assertEqual(rows[0]["labels"], ["lane-total", "mypy-reported-errors"])
            self.assertEqual([r["labels"] for r in rows[1:]], [[], [], []])

    def test_a_src_layout_matches_the_shorter_names_a_config_base_gives(self) -> None:
        # `mypy_path = src` makes mypy name src/pkg/a.py `pkg.a` while the
        # cwd-based derivation says `src.pkg.a`: the listed name is matched to
        # the one scope file whose derived name ends in it.
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect_modules(
                tmp, "src/pkg/a.py", "src/pkg-x/b.py", "src/c.py", exit_code=0
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                [r["file"] for r in rows_of(result)],
                [None, "src/pkg/a.py", "src/pkg-x/b.py", "src/c.py"],
            )
            self.assertEqual(result.stderr, "")

    def test_the_lane_row_covers_the_scope_and_names_what_it_left_out(self) -> None:
        # A change scope of two files: the lane row is those two files'
        # coverage, and the module the table lists for neither is noted.
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect_modules(tmp, "pkg/a.py", "c.py", exit_code=0)
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = rows_of(result)
            self.assertEqual([r["file"] for r in rows], [None, "pkg/a.py", "c.py"])
            self.assertEqual(
                rows[0]["values"],
                {
                    "any_expressions": 5,
                    "expressions_total": 15,
                    "type_coverage_pct": 66.67,
                },
            )
            self.assertEqual(rows[0]["labels"], ["lane-total"])
            self.assertEqual(
                result.stderr.strip(),
                "1 listed module(s) matched no scope file and are not counted in the lane row",
            )

    def test_a_scope_file_mypy_did_not_list_is_counted_in_the_note(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect_modules(
                tmp, "pkg/a.py", "pkg-x/b.py", "c.py", "extra/z.py", exit_code=0
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(rows_of(result)), 4)
            self.assertEqual(result.stderr.strip(), "1 scope file(s) mypy did not list")

    def test_no_match_at_all_falls_back_to_the_total_row_and_says_so(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect_modules(tmp, "elsewhere/z.py", exit_code=0)
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = rows_of(result)
            self.assertEqual(len(rows), 1)
            self.assertEqual(
                (rows[0]["file"], tuple(rows[0]["values"].values())),
                (None, (8, 26, 69.23)),
            )
            self.assertIn("none of the 3 listed module(s) matched", result.stderr)

    def test_an_exit_1_note_counts_the_errors_and_the_missing_stubs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self._collect_modules(tmp, "pkg/a.py", "pkg-x/b.py", "c.py")
            self.assertEqual(
                result.stderr.strip(), "mypy reported 1 error (1 missing stub)"
            )

    def test_collect_removes_the_report_directory_it_asked_mypy_for(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp))
            before = set(Path(tempfile.gettempdir()).glob("*"))
            run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            leaked = [
                p
                for p in set(Path(tempfile.gettempdir()).glob("*")) - before
                if (p / "any-exprs.txt").exists()
            ]
            self.assertEqual(leaked, [])

    def test_a_reporting_exit_code_still_yields_a_row_and_a_label(self) -> None:
        # mypy exits 1 on any type error while still writing the report (T1).
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(
                Path(tmp),
                exit_code=1,
                stdout_line="cm_sample.py:5: error: Incompatible return value type",
            )
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            lane_row = rows_of(result)[0]
            self.assertEqual(lane_row["labels"], ["lane-total", "mypy-reported-errors"])
            self.assertEqual(lane_row["values"]["expressions_total"], 13)
            self.assertEqual(
                result.stderr.strip(), "mypy reported 1 error (0 missing stubs)"
            )

    def test_a_fatal_exit_is_exit_4_with_the_tool_stderr_relayed(self) -> None:
        # mypy exits 2 on a blocking error (a duplicate module name, a usage or
        # config error) before analysing anything, and still writes a report
        # whose Total row reads 0 over 0. Nothing was measured: the tool
        # resolved but cannot run on these files, which is the adapter
        # contract's exit 4, an `unavailable` row carrying mypy's own message.
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(
                Path(tmp),
                exit_code=2,
                capture=ABORTED,
                stderr_line='plugins/b/lib/x.py: error: Duplicate module named "lib.x"',
            )
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 4, result.stderr)
            self.assertIn("Duplicate module named", result.stderr)
            self.assertIn("exit 2", result.stderr)
            self.assertEqual(result.stdout, "")

    def test_no_report_written_is_exit_3_with_the_tool_stderr_relayed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(
                Path(tmp),
                exit_code=0,
                capture=None,
                stderr_line="mypy: something ate the report directory",
            )
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("ate the report directory", result.stderr)
            self.assertEqual(result.stdout, "")

    def test_zero_expressions_is_null_coverage_never_100(self) -> None:
        # A Total of 0 over 0 is "nothing was counted", which the report
        # contract renders as null, not as the 100.00% mypy prints.
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(Path(tmp), exit_code=0, capture=ABORTED)
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = rows_of(result)
            # An empty table lists no module, so the lane row is the only row.
            self.assertEqual(len(rows), 1)
            self.assertEqual(
                rows[0]["values"],
                {
                    "any_expressions": 0,
                    "expressions_total": 0,
                    "type_coverage_pct": None,
                },
            )

    def test_collect_passes_explicit_package_bases_and_a_devnull_cache_dir(
        self,
    ) -> None:
        # --explicit-package-bases derives module names from the path, so two
        # same-named files under identifier-named directories no longer abort
        # the build; --cache-dir os.devnull is mypy's documented "disable
        # caching" value and keeps .mypy_cache out of the consumer's tree.
        with tempfile.TemporaryDirectory() as tmp:
            argv_log = Path(tmp) / "argv"
            make_stub(Path(tmp), argv_log=argv_log)
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            argv = argv_log.read_text(encoding="utf-8").splitlines()
            self.assertIn("--explicit-package-bases", argv)
            self.assertIn("--show-error-codes", argv)
            self.assertIn("--no-pretty", argv)
            self.assertIn("--cache-dir", argv)
            self.assertEqual(argv[argv.index("--cache-dir") + 1], os.devnull)
            self.assertEqual(argv[-1], f"{SOURCES}/cm_sample.py")

    def test_a_config_without_namespace_packages_reruns_in_mypys_own_naming(
        self,
    ) -> None:
        # mypy allows --explicit-package-bases only with namespace packages on;
        # a consumer config that turns them off makes the first run a usage
        # error (exit 2, nothing measured). That is not the consumer's tree
        # failing, so the run repeats without the flag and the note says which
        # naming the rows follow. The capture's names (`pkg.a`, `b`, `c`) are
        # the ones mypy's __init__.py walk gives too, so the rows still map.
        with tempfile.TemporaryDirectory() as tmp:
            argv_log = Path(tmp) / "argv"
            make_stub(
                Path(tmp),
                capture=MODULES,
                argv_log=argv_log,
                reject_explicit_bases=True,
            )
            result = run(
                "collect",
                "python",
                "type_coverage",
                "pkg/a.py",
                "pkg-x/b.py",
                "c.py",
                path_prefix=Path(tmp),
                cwd=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = rows_of(result)
            self.assertEqual(
                [r["file"] for r in rows], [None, "pkg/a.py", "pkg-x/b.py", "c.py"]
            )
            self.assertEqual(rows[0]["labels"], ["lane-total"])
            self.assertEqual(
                result.stderr.strip(),
                "namespace packages are off in the mypy config, so modules are "
                "named from __init__.py packages rather than their paths",
            )
            argv = argv_log.read_text(encoding="utf-8").splitlines()
            # Two runs: the flag on the first only, the report asked for twice.
            self.assertEqual(argv.count("--explicit-package-bases"), 1)
            self.assertEqual(argv.count("--any-exprs-report"), 2)
            self.assertLess(
                argv.index("--explicit-package-bases"),
                argv.index("--any-exprs-report", argv.index("--any-exprs-report") + 1),
            )

    def test_a_usage_error_that_is_not_the_pairing_rule_is_still_exit_4(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_stub(
                Path(tmp),
                exit_code=2,
                capture=ABORTED,
                stderr_line="mypy: error: unrecognized arguments: --frobnicate",
            )
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 4, result.stderr)
            self.assertIn("--frobnicate", result.stderr)

    @unittest.skipUnless(shutil.which("mypy"), "the real mypy is not on PATH")
    def test_the_real_mypy_leaves_no_cache_in_the_working_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "cm_real.py"
            source.write_text("def add(a: int, b: int) -> int:\n    return a + b\n")
            result = run(
                "collect",
                "python",
                "type_coverage",
                "cm_real.py",
                real_path=True,
                cwd=Path(tmp),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((Path(tmp) / ".mypy_cache").exists())
            rows = rows_of(result)
            self.assertEqual([r["file"] for r in rows], [None, "cm_real.py"])
            self.assertGreater(rows[1]["values"]["expressions_total"], 0)
            self.assertEqual(rows[0]["values"], rows[1]["values"])

    def test_an_unreadable_table_is_exit_3(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            garbled = Path(tmp) / "garbled.txt"
            garbled.write_text("no total row here\n", encoding="utf-8")
            make_stub(Path(tmp), capture=garbled)
            result = run(
                "collect",
                "python",
                "type_coverage",
                f"{SOURCES}/cm_sample.py",
                path_prefix=Path(tmp),
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("no Total row", result.stderr)


class MypyReportTableTests(unittest.TestCase):
    def test_the_total_row_is_read_from_a_table_with_several_modules(self) -> None:
        module = load_module()
        table = (
            "      Name   Anys   Exprs   Coverage\n"
            "-------------------------------------\n"
            "  cm_first      3       4     25.00%\n"
            " cm_second      0      12    100.00%\n"
            "-------------------------------------\n"
            "     Total      3      16     81.25%\n"
        )
        self.assertEqual(module.parse_total(table), (3, 16, 81.25))
        modules, total = module.parse_table(table)
        self.assertEqual(total, (3, 16, 81.25))
        self.assertEqual(
            modules, {"cm_first": (3, 4, 25.0), "cm_second": (0, 12, 100.0)}
        )

    def test_a_table_without_a_total_row_is_a_value_error(self) -> None:
        module = load_module()
        with self.assertRaises(ValueError):
            module.parse_total("      Name   Anys   Exprs   Coverage\n")

    def test_the_lane_row_percentage_is_formatted_as_mypy_formats_it(self) -> None:
        module = load_module()
        # This repository's whole-tree Total: mypy prints 89.96% for it.
        self.assertEqual(
            module._summed([(14961, 149042, 89.96)]), (14961, 149042, 89.96)
        )
        self.assertEqual(module._summed([(0, 0, None)]), (0, 0, None))


class MypyReportModuleNameTests(unittest.TestCase):
    """`module_name` re-derives mypy's crawl with the cwd as the only base."""

    def test_names_follow_mypy_under_explicit_package_bases(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            base = os.path.normcase(os.path.realpath(tmp))
            for rel in (
                "plugins/perf/lib/x.py",
                "claude-ops/lib/x.py",
                "pkg/sub/__init__.py",
                "pkg/sub/c.pyi",
                "top.py",
                "dir-with-dash/deeper/__init__.py",
                "dir-with-dash/deeper/leaf.py",
            ):
                path = Path(base) / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            cases = {
                # every directory up to the base is an identifier: the dotted path
                "plugins/perf/lib/x.py": "plugins.perf.lib.x",
                # the walk stops at a non-identifier directory: the stem alone
                "claude-ops/lib/x.py": "x",
                # a package names its directory; a stub keeps its stem
                "pkg/sub/__init__.py": "pkg.sub",
                "pkg/sub/c.pyi": "pkg.sub.c",
                "top.py": "top",
                # a package under a non-identifier directory is still a package
                "dir-with-dash/deeper/__init__.py": "deeper",
                "dir-with-dash/deeper/leaf.py": "deeper.leaf",
            }
            for rel, expected in cases.items():
                with self.subTest(rel=rel):
                    self.assertEqual(
                        module.module_name(os.path.join(base, rel), base), expected
                    )

    def test_a_file_outside_the_base_is_its_stem(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            outside = Path(tmp) / "somewhere" / "else" / "mod.py"
            outside.parent.mkdir(parents=True)
            outside.touch()
            base = os.path.normcase(os.path.realpath(Path(tmp) / "base"))
            self.assertEqual(module.module_name(str(outside), base), "mod")


class MypyReportErrorNoteTests(unittest.TestCase):
    def test_the_note_counts_error_lines_and_missing_stub_codes(self) -> None:
        module = load_module()
        stdout = "\n".join(
            [
                'a.py:1: error: Library stubs not installed for "yaml"  [import-untyped]',
                'a.py:1: note: Hint: "python3 -m pip install types-PyYAML"',
                'b.py:2: error: Cannot find implementation or library stub for module named "x"  [import-not-found]',
                "c.py:3: error: Incompatible return value type  [return-value]",
            ]
        )
        self.assertEqual(
            module.error_note(stdout), "mypy reported 3 errors (2 missing stubs)"
        )
        self.assertEqual(
            module.error_note(""), "mypy reported 0 errors (0 missing stubs)"
        )


class MypyReportVerbTests(unittest.TestCase):
    def test_other_verbs(self) -> None:
        self.assertEqual(run("measures").stdout.strip(), "python/type_coverage")
        self.assertIn("mypy", run("install_hint").stdout)
        self.assertEqual(run("collect", "python", "cyclomatic", "x.py").returncode, 2)
        self.assertEqual(run().returncode, 2)


if __name__ == "__main__":
    unittest.main()
