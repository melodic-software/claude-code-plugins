#!/usr/bin/env python3
"""Adapter for `jscpd`, the clone detector behind every duplication lane.

Adapter contract (design/contracts.md section 3): `probe`, `measures`,
`collect <lane> <measure> <file>...`, `install_hint`.

jscpd only writes its report to a file, so `collect` runs it with
`--reporters json --output <tmpdir>`, reads `<tmpdir>/jscpd-report.json`,
prints the translated rows, and deletes the temporary directory. Both
maintained majors are translated: the 4.x line (Node) and the 5.x line (Rust)
write `duplicates[]` entries with `firstFile`/`secondFile` under the same
report name, and this adapter reads only those keys plus `lines` and `tokens`
(verified 2026-09-11 against jscpd 4.3.0 and 5.2.0; recheck when a major above
5 ships). 5.2.0 adds a per-duplicate `kind` (`exact`) that is not read, and
the two majors tokenize differently, so a clone count can differ between them
on the same input.
`--absolute` is passed because jscpd otherwise names files relative to the
common ancestor of its inputs, which collapses two vendored copies that share
a basename into one indistinguishable name; the absolute paths are made
relative to the working directory here.

Each duplicate becomes one clone-group row: `file` and `function` are null,
`instances[]` carries every copy with its line range, and `values` carries
`lines` and `tokens`. Tunables arrive as environment variables the calling
skill exports from the resolved configuration:

  CODE_METRICS_DUP_MIN_TOKENS  jscpd --min-tokens  (default 50)
  CODE_METRICS_DUP_MIN_LINES   jscpd --min-lines   (default 5)
  CODE_METRICS_DUP_IGNORE      jscpd --ignore, comma-separated globs (default none)
  CODE_METRICS_DUP_MAX_SIZE    files larger than this are skipped (default 1mb;
                               empty or 0 means no cap; kb/mb/gb are binary)
  CODE_METRICS_DUP_MAX_LINES   files with more lines are skipped (default none;
                               empty or 0 means no cap)

The caps are applied HERE, before jscpd runs, and not delegated to jscpd's
own `--max-size`/`--max-lines`: the two majors disagree on what those flags
default to (4.x caps at 1000 lines and 100kb, 5.x at 1mb and no line cap),
on what `0` means (4.x reads `--max-lines 0` as the default and `--max-size 0`
as "skip everything"), and neither names a skipped file in the report, so a
file left out of the scan would be invisible. jscpd is passed one more than
the adapter's own bound (or a bound no real file reaches when there is no
cap) so the pre-filter is the only gate on either major. Every skip is
reported as one line to the file named by CODE_METRICS_PARTIAL_REASON_FILE
(the dispatcher's channel for a `partial` run row), or to stderr when that
variable is unset. `statistics.total.sources` in the jscpd report counts token
sources, not files, and is not read for this purpose.

jscpd's own exit code is not read: it exits non-zero when a `--threshold` or
`--exit-code` run finds clones, and this adapter passes neither, so the report
file is the only success signal (design T1: a collector succeeds when it
produced parseable output).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

from adapter_paths import files_from

MIN_PYTHON = (3, 9)
NAME = "jscpd"
REPORT_BASENAME = "jscpd-report.json"
DEFAULT_MIN_TOKENS = "50"
DEFAULT_MIN_LINES = "5"
DEFAULT_MAX_SIZE = "1mb"
# Passed to jscpd when the adapter applies no cap of its own: bounds no real
# file reaches, so jscpd's own gate can never skip a file this adapter did not
# name; both are accepted by both majors (`0` is not), verified 2026-09-11
# against 4.3.0 and 5.2.0 with the line bound at the signed 32-bit maximum.
NO_LINE_CAP = 2_147_483_647
NO_SIZE_CAP = 1 << 40
_SIZE_UNITS = {"": 1, "b": 1, "kb": 1024, "mb": 1024**2, "gb": 1024**3}
_SIZE_RE = re.compile(r"^(\d+(?:\.\d+)?)\s*([kmg]?b)?$")


def _normalize(path: str) -> str:
    path = path.replace("\\", "/")
    if os.path.isabs(path):
        try:
            path = os.path.relpath(path, os.getcwd())
        except ValueError:
            return path
    while path.startswith("./"):
        path = path[2:]
    return path.replace("\\", "/")


def _resolve() -> str | None:
    exe = shutil.which(NAME)
    if exe:
        return exe
    local = os.path.join(".", "node_modules", ".bin", NAME)
    if os.path.isfile(local) and os.access(local, os.X_OK):
        return local
    return None


def probe() -> int:
    exe = _resolve()
    if not exe:
        print("jscpd not on PATH or in ./node_modules/.bin", file=sys.stderr)
        return 1
    try:
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, check=False
        )
    except OSError as exc:
        print(f"jscpd --version failed: {exc}", file=sys.stderr)
        return 1
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", out.stdout + out.stderr)
    print(match.group(1) if match else "unknown-version")
    return 0


def parse_size(text: str) -> int | None:
    """Bytes for a size such as `1mb`, `100kb`, `2048`; None for no cap.

    Units are binary (1kb = 1024 bytes), the multiplier jscpd's own grammar
    uses. Empty and `0` mean no cap. Anything else raises ValueError.
    """
    text = (text or "").strip().lower()
    if not text:
        return None
    match = _SIZE_RE.match(text)
    if not match:
        raise ValueError(f"not a size: {text!r} (expected e.g. 1mb, 100kb, 2048)")
    value = int(float(match.group(1)) * _SIZE_UNITS[match.group(2) or ""])
    return value if value > 0 else None


def parse_lines(text: str) -> int | None:
    """A positive line cap, or None for no cap (empty, 0, or negative)."""
    text = (text or "").strip()
    if not text:
        return None
    try:
        value = int(text)
    except ValueError as exc:
        raise ValueError(f"not a line count: {text!r}") from exc
    return value if value > 0 else None


def count_lines(path: str) -> int:
    """Newline count, plus one for a final line without a newline."""
    lines = 0
    last = b"\n"
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b""):
            lines += chunk.count(b"\n")
            last = chunk[-1:]
    if last != b"\n":
        lines += 1
    return lines


def prefilter(
    files: list[str], size_cap: int | None, line_cap: int | None
) -> tuple[list[str], list[tuple[str, int, int | None]]]:
    """Split `files` into the ones jscpd scans and the ones a cap skips.

    A skipped entry is `(path, bytes, lines)`; `lines` is None when no line cap
    is set, because counting lines reads the whole file and the size cap
    needs only a stat. A file that cannot be stat'ed is kept, so jscpd (and its
    own error message) decides what to do with it.
    """
    kept: list[str] = []
    skipped: list[tuple[str, int, int | None]] = []
    for path in files:
        try:
            size = os.stat(path).st_size
        except OSError:
            kept.append(path)
            continue
        lines: int | None = None
        if size_cap is not None and size > size_cap:
            skipped.append((path, size, None))
            continue
        if line_cap is not None:
            try:
                lines = count_lines(path)
            except OSError:
                kept.append(path)
                continue
            if lines > line_cap:
                skipped.append((path, size, lines))
                continue
        kept.append(path)
    return kept, skipped


def report_skips(
    skipped: list[tuple[str, int, int | None]],
    total: int,
    size_text: str,
    lines_text: str,
) -> None:
    """One line naming how many files a cap left out, and the largest one."""
    if not skipped:
        return
    largest = max(skipped, key=lambda entry: entry[1])
    path, size, lines = largest
    if lines is None:
        try:
            lines = count_lines(path)
        except OSError:
            lines = 0
    reason = (
        f"{len(skipped)} of {total} files skipped by duplication.max_size "
        f"{size_text or 'none'} / max_lines {lines_text or 'none'}; "
        f"largest: {_normalize(path)} ({size} bytes, {lines} lines)"
    )
    target = os.environ.get("CODE_METRICS_PARTIAL_REASON_FILE") or ""
    if target:
        try:
            with open(target, "w", encoding="utf-8") as handle:
                handle.write(reason + "\n")
            return
        except OSError as exc:
            print(f"jscpd.py: cannot write {target}: {exc}", file=sys.stderr)
    print(f"jscpd.py: {reason}", file=sys.stderr)


def _instance(entry: dict) -> dict:
    return {
        "file": _normalize(str(entry.get("name", ""))),
        "start_line": entry.get("start"),
        "end_line": entry.get("end"),
    }


def translate(raw: str, lane: str) -> list[dict]:
    document = json.loads(raw)
    rows: list[dict] = []
    for duplicate in document.get("duplicates", []):
        instances = [
            _instance(duplicate[key])
            for key in ("firstFile", "secondFile")
            if isinstance(duplicate.get(key), dict)
        ]
        if not instances:
            continue
        rows.append(
            {
                "file": None,
                "function": None,
                "lane": lane,
                "instances": instances,
                "values": {
                    "lines": duplicate.get("lines"),
                    "tokens": duplicate.get("tokens"),
                },
                "collector": NAME,
                "labels": ["token-based"],
            }
        )
    return rows


def _command(
    exe: str,
    output: str,
    files: list[str],
    size_cap: int | None = None,
    line_cap: int | None = None,
) -> list[str]:
    command = [
        exe,
        "--reporters",
        "json",
        "--output",
        output,
        "--min-tokens",
        os.environ.get("CODE_METRICS_DUP_MIN_TOKENS") or DEFAULT_MIN_TOKENS,
        "--min-lines",
        os.environ.get("CODE_METRICS_DUP_MIN_LINES") or DEFAULT_MIN_LINES,
        # One above the adapter's own bound: the pre-filter already removed
        # every file over it, so jscpd's gate never fires on either major.
        "--max-size",
        str(size_cap + 1 if size_cap is not None else NO_SIZE_CAP),
        "--max-lines",
        str(line_cap + 1 if line_cap is not None else NO_LINE_CAP),
        "--absolute",
        "--silent",
    ]
    ignore = os.environ.get("CODE_METRICS_DUP_IGNORE") or ""
    if ignore.strip():
        command += ["--ignore", ignore.strip()]
    return command + files


def collect(lane: str, measure: str, files: list[str]) -> int:
    if measure != "duplication":
        print(f"jscpd.py: cannot collect {measure}", file=sys.stderr)
        return 2
    exe = _resolve()
    if not exe:
        print("jscpd not on PATH or in ./node_modules/.bin", file=sys.stderr)
        return 3
    size_text = os.environ.get("CODE_METRICS_DUP_MAX_SIZE", DEFAULT_MAX_SIZE)
    lines_text = os.environ.get("CODE_METRICS_DUP_MAX_LINES", "")
    try:
        size_cap = parse_size(size_text)
        line_cap = parse_lines(lines_text)
    except ValueError as exc:
        print(f"jscpd.py: {exc}", file=sys.stderr)
        return 2
    kept, skipped = prefilter(files, size_cap, line_cap)
    report_skips(skipped, len(files), size_text.strip(), lines_text.strip())
    if not kept:
        # Nothing left to scan is a measurement of zero, not a failure; the
        # skip line above says what was left out.
        return 0
    output = tempfile.mkdtemp(prefix="code-metrics-jscpd-")
    try:
        result = subprocess.run(
            _command(exe, output, kept, size_cap, line_cap),
            capture_output=True,
            text=True,
            check=False,
        )
        report = os.path.join(output, REPORT_BASENAME)
        try:
            with open(report, encoding="utf-8") as handle:
                rows = translate(handle.read(), lane)
        except (OSError, json.JSONDecodeError, ValueError, TypeError) as exc:
            print(
                f"jscpd.py: no parseable {REPORT_BASENAME} ({exc}); "
                f"stderr: {result.stderr.strip()}",
                file=sys.stderr,
            )
            return 3
    finally:
        shutil.rmtree(output, ignore_errors=True)
    for row in rows:
        print(json.dumps(row))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(
            "usage: jscpd.py probe|measures|collect <lane> <measure> <file>...|install_hint",
            file=sys.stderr,
        )
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "probe":
        return probe()
    if verb == "measures":
        print("*/duplication")
        return 0
    if verb == "install_hint":
        print(
            "jscpd: https://github.com/kucherenko/jscpd (npm install -g jscpd, or add it to the repository's devDependencies); this plugin never installs it"
        )
        return 0
    if verb == "collect":
        if len(rest) < 2:
            print("usage: jscpd.py collect <lane> <measure> <file>...", file=sys.stderr)
            return 2
        return collect(rest[0], rest[1], files_from(rest[2:]))
    print(f"jscpd.py: unknown verb {verb}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("jscpd.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
