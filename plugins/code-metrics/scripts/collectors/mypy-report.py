#!/usr/bin/env python3
"""Adapter for `mypy --any-exprs-report`, the Python type-debt collector.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

mypy writes `any-exprs.txt` into the directory given to `--any-exprs-report`:
a fixed-width table with the columns Name, Anys, Exprs, Coverage, one row per
module it was given, and a `Total` row. This adapter prints one row per scope
file whose module mypy listed (`file` set, `function` null) and one lane row
(`file` null, label `lane-total`) whose values are the sum of those file rows,
so a change-scoped run reports the scope's own coverage. The report directory
is a temporary one, created and removed here, because mypy overwrites the
whole directory.

Facts probed against mypy 1.19.1 (its documentation and source at that tag,
unchanged at 2.3.1) and replayed by fixtures/tool-output/mypy-any-exprs.txt,
mypy-any-exprs-modules.txt and mypy-any-exprs-aborted.txt:

- the table is whitespace-aligned and the Coverage column carries a trailing
  percent sign; the Name column is the module name, never the path;
- the module name is what `mypy/find_sources.py` (`SourceFinder.crawl_up`)
  derives with the working directory as the only explicit base: walking up
  from the file's directory, a directory holding `__init__.py[i]` is a
  package and its name joins the module; otherwise the walk continues only
  while each directory name is a Python identifier and reaches the base, and
  stops with no prefix at the first directory whose name is not one. So
  `plugins/perf/lib/x.py` is `plugins.perf.lib.x` and `claude-ops/lib/x.py`
  is the bare `x`. `module_name` re-derives that rule; checked against a
  real 186-file run of this repository (182 of 182 listed names matched);
- mypy exits 1 on any type error and still writes the report (design T1), so
  exit 1 with a readable report is exit 0 here, with the lane row labelled
  `mypy-reported-errors` and a note on stderr (which the dispatcher relays as
  the run row's reason) counting the errors and the missing-stub ones, the
  codes `import-untyped` and `import-not-found`. Error lines go to stdout as
  `<path>:<line>: error: <text>  [<code>]`; `--show-error-codes` is passed so
  a consumer config hiding the codes does not hide the count, and
  `--no-pretty` so a consumer's `pretty = true` does not wrap the code onto a
  continuation line;
- mypy lists only the files it was given: a module it follows through an
  import is type-checked for their sake but has no table row, so every listed
  module is a scope file under some naming. When the consumer's mypy config
  adds a base (`mypy_path = src`, the src layout) mypy names `src/pkg/m.py`
  `pkg.m` while the cwd-based derivation says `src.pkg.m`, so a listed name
  no derived name equals is matched to the one scope file whose derived name
  ends in `.` plus that name, and left out when that is ambiguous;
- mypy exits 2 on a blocking error (a duplicate module name, a usage or config
  error) before analysing anything, and still writes a report whose only row
  is `Total 0 0 100.00%`. Nothing was measured, so exit 2 is the adapter
  contract's exit 4 (the tool resolved but cannot run on these files) with
  mypy's stderr relayed, never a 100% row. An unwritten or unreadable report on
  any other exit is exit 3;
- a Total row with 0 expressions is `type_coverage_pct: null`, because nothing
  was counted; mypy's 100.00% for an empty build is not a measurement;
- `--explicit-package-bases` derives each module name from its path relative
  to the working directory (or a MYPYPATH entry), so two same-named files under
  identifier-named directories (`a/foo.py`, `b/foo.py`) no longer collide. The
  walk stops at a directory whose name is not a Python identifier, so
  same-named files under two hyphenated directories still collide and reach the
  exit-4 path with mypy's message. mypy accepts the flag only while namespace
  packages are on (its default), so when the consumer's config turns them off
  mypy refuses the pairing with a usage error (exit 2); the run then repeats
  without the flag, in mypy's own naming mode (packages from `__init__.py`
  files), and a stderr note says so. The shorter names that mode gives are
  matched by the same suffix pass a config base uses; same-named files collide
  again in it, the consumer's own configuration;
- `--cache-dir os.devnull` is mypy's documented "disable caching" value (mypy
  compares the option to os.devnull by string equality, `/dev/null` on POSIX
  and `nul` on Windows), so no `.mypy_cache` is written into the consumer's
  tree; over this repository's 179 files caching saved nothing (6.8s without a
  cache against 8.2s with a warm one).

The percentage is mypy's own Coverage figure over expressions, which is not the
`type-coverage` identifier ratio the TypeScript lane reports. The two are never
compared with each other.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Optional

from adapter_paths import files_from

MIN_PYTHON = (3, 9)
NAME = "mypy-report"
TOOL = "mypy"
MEASURE = "type_coverage"
LANE = "python"
# mypy's exit for a blocking error (duplicate module, usage or config error):
# it stops before analysing anything and its report carries no measurement.
FATAL_EXIT = 2
# mypy's own order: a stub beside a module wins (find_sources.PY_EXTENSIONS).
PY_EXTENSIONS = (".pyi", ".py")
# The error codes mypy gives an import it found no stubs or implementation for.
MISSING_STUB_CODES = ("[import-untyped]", "[import-not-found]")


def probe() -> int:
    exe = shutil.which(TOOL)
    if not exe:
        print(f"{TOOL} not on PATH", file=sys.stderr)
        return 1
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        print(f"{TOOL} --version failed: {exc}", file=sys.stderr)
        return 1
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", out.stdout + out.stderr)
    print(match.group(1) if match else "unknown-version")
    return 0


# (anys, exprs, coverage percent or None); Optional because this alias is
# evaluated at import time and the floor is Python 3.9.
Counts = tuple[int, int, Optional[float]]


def _counts(fields: list[str]) -> Counts:
    anys, exprs = int(fields[1]), int(fields[2])
    # mypy prints 100.00% for an empty module; nothing was counted, so the
    # percentage is null, never 100.
    return anys, exprs, float(fields[3].rstrip("%")) if exprs else None


def parse_table(table: str) -> tuple[dict[str, Counts], Counts]:
    """Return ({module: counts}, total counts) from the any-exprs table."""
    modules: dict[str, Counts] = {}
    total: Counts | None = None
    for line in table.splitlines():
        fields = line.split()
        if len(fields) != 4 or fields[0] == "Name" or not fields[1].isdigit():
            continue
        if fields[0] == "Total":
            total = _counts(fields)
        else:
            modules[fields[0]] = _counts(fields)
    if total is None:
        raise ValueError("the any-exprs report has no Total row")
    return modules, total


def parse_total(table: str) -> Counts:
    """The table's `Total` row alone."""
    return parse_table(table)[1]


def _has_init(directory: str) -> bool:
    return any(
        os.path.isfile(os.path.join(directory, "__init__" + ext))
        for ext in PY_EXTENSIONS
    )


def _join(prefix: str, name: str) -> str:
    return f"{prefix}.{name}" if prefix else name


def _crawl_dir(directory: str, base: str) -> str | None:
    """The module prefix a directory contributes, or None when the walk
    reaches neither the base nor a package (mypy's `_crawl_up_helper`)."""
    if os.path.normcase(directory) == base:
        return ""
    parent, name = os.path.split(directory)
    if not name or parent == directory:
        return None
    if name.endswith("-stubs"):
        name = name[:-6]
    if _has_init(directory):
        # A package is always named, whatever lies above it; mypy refuses a
        # package whose directory name is not an identifier (exit 2, the
        # exit-4 path here), so the file cannot reach this point.
        return _join(_crawl_dir(parent, base) or "", name)
    if not name.isidentifier():
        return None
    prefix = _crawl_dir(parent, base)
    return None if prefix is None else _join(prefix, name)


def module_name(path: str, base: str) -> str:
    """The module mypy names `path` under `--explicit-package-bases` with
    `base` (an absolute, normcased directory) as the only base."""
    parent, filename = os.path.split(os.path.abspath(path))
    stem = filename
    for ext in PY_EXTENSIONS:
        if filename.endswith(ext):
            stem = filename[: -len(ext)]
            break
    prefix = _crawl_dir(parent, base) or ""
    return prefix if stem == "__init__" else _join(prefix, stem)


def error_note(stdout: str) -> str:
    """`mypy reported N errors (M missing stubs)` from mypy's error lines."""
    lines = [line for line in stdout.splitlines() if ": error:" in line]
    stubs = [line for line in lines if line.rstrip().endswith(MISSING_STUB_CODES)]
    return (
        f"mypy reported {len(lines)} error{'s' if len(lines) != 1 else ''} "
        f"({len(stubs)} missing stub{'s' if len(stubs) != 1 else ''})"
    )


def _row(lane: str, file: str | None, counts: Counts, labels: list[str]) -> dict:
    anys, exprs, coverage = counts
    return {
        "file": file,
        "function": None,
        "lane": lane,
        "values": {
            "any_expressions": anys,
            "expressions_total": exprs,
            "type_coverage_pct": coverage,
        },
        "collector": NAME,
        "labels": labels,
    }


def _summed(rows: list[Counts]) -> Counts:
    anys = sum(r[0] for r in rows)
    exprs = sum(r[1] for r in rows)
    # mypy's own formatting of the percentage, so a lane row over every
    # listed module reads exactly as mypy's Total row does.
    return anys, exprs, float(f"{(exprs - anys) / exprs * 100:.2f}") if exprs else None


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != MEASURE:
        print(f"{NAME}.py: cannot collect {measure}", file=sys.stderr)
        return 2
    exe = shutil.which(TOOL)
    if not exe:
        print(f"{TOOL} not on PATH", file=sys.stderr)
        return 3
    report_dir = tempfile.mkdtemp(prefix="code-metrics-mypy-")
    naming_note = ""
    try:
        result = _run_mypy(exe, report_dir, files, explicit_bases=True)
        if result.returncode == FATAL_EXIT and _rejects_explicit_bases(result.stderr):
            # The consumer's config turns namespace packages off, and mypy
            # allows --explicit-package-bases only with them on. Overriding
            # that config would measure a project the consumer did not
            # configure, so the run repeats in mypy's own naming mode
            # (packages from __init__.py files) and says so.
            result = _run_mypy(exe, report_dir, files, explicit_bases=False)
            naming_note = (
                "namespace packages are off in the mypy config, so modules are "
                "named from __init__.py packages rather than their paths"
            )
        if result.returncode == FATAL_EXIT:
            # A blocking error stopped mypy before analysis; the report it still
            # wrote is empty, so there is no measurement to read. The tool
            # resolved but cannot run on these files: the dispatcher writes an
            # `unavailable` row carrying this reason (exit 4).
            # mypy prints its error lines to stdout and usage errors to
            # stderr, so the reason carries both.
            said = " ".join(
                part.strip().replace("\n", " ")
                for part in (result.stdout, result.stderr)
                if part.strip()
            )
            print(
                f"mypy could not analyse these files (exit {FATAL_EXIT}): {said}",
                file=sys.stderr,
            )
            return 4
        report = os.path.join(report_dir, "any-exprs.txt")
        try:
            with open(report, encoding="utf-8") as handle:
                table = handle.read()
        except OSError:
            print(
                f"{NAME}.py: mypy wrote no any-exprs report (exit {result.returncode}); "
                f"stderr: {result.stderr.strip()}",
                file=sys.stderr,
            )
            return 3
    finally:
        shutil.rmtree(report_dir, ignore_errors=True)
    try:
        modules, total = parse_table(table)
    except ValueError as exc:
        print(f"{NAME}.py: unparsable report ({exc})", file=sys.stderr)
        return 3
    matched = match_modules(modules, files)
    notes: list[str] = [naming_note] if naming_note else []
    if result.returncode != 0:
        notes.append(error_note(result.stdout))
    labels = ["lane-total"] + (["mypy-reported-errors"] if result.returncode else [])
    by_path = {path: name for name, path in matched.items()}
    # File rows in scope order, whatever order the names matched in.
    file_rows = [_row(lane, p, modules[by_path[p]], []) for p in files if p in by_path]
    if file_rows:
        lane_counts = _summed([modules[name] for name in matched])
        left_out = len(modules) - len(matched)
        if left_out:
            notes.append(
                f"{left_out} listed module(s) matched no scope file and are not "
                "counted in the lane row"
            )
    else:
        # Nothing listed matched (mypy named its modules from a base this
        # adapter cannot recover), or nothing was listed at all: the lane row
        # is mypy's own Total.
        lane_counts = total
        if modules:
            notes.append(
                f"none of the {len(modules)} listed module(s) matched a scope "
                "file; the lane row is mypy's own Total and no file rows are emitted"
            )
    unlisted = len(files) - len(matched)
    if unlisted and modules:
        notes.append(f"{unlisted} scope file(s) mypy did not list")
    # The lane row leads, so the lane's figure is the first row a reader of
    # the raw rows meets.
    for row in [_row(lane, None, lane_counts, labels), *file_rows]:
        print(json.dumps(row))
    if notes:
        print("; ".join(notes), file=sys.stderr)
    return 0


def _run_mypy(
    exe: str, report_dir: str, files: list[str], explicit_bases: bool
) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            exe,
            "--any-exprs-report",
            report_dir,
            "--no-error-summary",
            "--show-error-codes",
            "--no-pretty",
            *(["--explicit-package-bases"] if explicit_bases else []),
            "--cache-dir",
            os.devnull,
            *files,
        ],
        capture_output=True,
        text=True,
        check=False,
    )


def _rejects_explicit_bases(stderr: str) -> bool:
    """True when mypy's usage error is the one pairing rule this adapter can
    trip: `Can only use --explicit-package-bases with --namespace-packages`."""
    return "--explicit-package-bases" in stderr and "--namespace-packages" in stderr


def match_modules(modules: dict[str, Counts], files: list[str]) -> dict[str, str]:
    """Map each listed module to the scope file it names: by the cwd-based
    derivation first, then, for a listed name no derived name equals, the one
    scope file whose derived name ends in `.` plus it (a base the consumer's
    config added, such as `mypy_path = src`); an ambiguous suffix matches
    nothing."""
    base = os.path.normcase(os.path.abspath(os.getcwd()))
    derived = [(module_name(path, base), path) for path in files]
    matched: dict[str, str] = {}
    for name, path in derived:
        if name in modules and name not in matched:
            matched[name] = path
    taken = set(matched.values())
    for listed in modules:
        if listed in matched:
            continue
        candidates = [
            path
            for name, path in derived
            if path not in taken and name.endswith("." + listed)
        ]
        if len(candidates) == 1:
            matched[listed] = candidates[0]
            taken.add(candidates[0])
    return matched


def main(argv: list[str]) -> int:
    if not argv:
        print(
            f"usage: {NAME}.py probe|measures|collect <lane> <measure> <file>...|install_hint",
            file=sys.stderr,
        )
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "probe":
        return probe()
    if verb == "measures":
        print(f"{LANE}/{MEASURE}")
        return 0
    if verb == "install_hint":
        print(
            "mypy: https://mypy.readthedocs.io (pip install mypy, pipx install mypy, or uv tool install mypy)"
        )
        return 0
    if verb == "collect":
        if len(rest) < 2:
            print(
                f"usage: {NAME}.py collect <lane> <measure> <file>...", file=sys.stderr
            )
            return 2
        return collect(rest[0], rest[1], files_from(rest[2:]))
    print(f"{NAME}.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "mypy-report.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
