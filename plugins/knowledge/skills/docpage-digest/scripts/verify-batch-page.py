#!/usr/bin/env python3
"""Decide one batch-path page from the disk, and write its final status.

A workflow script cannot read the filesystem, so `claimed` in the workflow's result is only what
its agents reported. The launcher runs this after the workflow returns, and only this script writes
`verified`. Without it a page keeps `unverified: awaiting-check`.

Usage:
  verify-batch-page.py --result <page.json> --slice <path> --root <work-root> --started-at <UTC>

<page.json> holds the page's entry from the workflow result. <UTC> is the launcher's clock just
before the launch, as YYYY-MM-DDTHH:MM:SSZ.

Freshness rests on the pin manifest: started-at <= the manifest's pinned_at <= a verdict file's
mtime makes the file this run's, every such file is judged, each must state every pinned sha256,
and the tree must still match the pin. A stage holding a shell can still set an mtime or write these
files, so this proves the disk's state and not who wrote it.

A slice that is outside <work-root>/.work, or is itself a symlink, gets a status line on stdout and
no write. Every other page gets the status on its checklist and handoff, replacing whatever is
there; the checklist's Phase 4 tick is set only for `verified`. A page whose result is not `claimed`
gets the status its result already carries.

Slice files are read as data; the only commands run are this directory's standing gates and
pin-manifest.py, over them.

Exit codes: 0 verified, 1 any other status, 2 usage error (nothing written).
Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True  # the plugin's own tree is not a cache

SCRIPTS = Path(__file__).resolve().parent
VERIFIED = "verified"
AWAITING = "unverified: awaiting-check"
GATE_TIMEOUT_SECONDS = 300
SLUG = re.compile(r"^[a-z0-9][a-z0-9-]{0,30}-[0-9a-f]{8}$")
CARRIED_STATUS = re.compile(r"^(unverified|failed): [a-z0-9-]+$")
PIN_TIME = "%Y-%m-%dT%H:%M:%SZ"

VERDICT_LINE = re.compile(
    r"^\W*(?:overall\s+)?verdict\W+(PASS-WITH-FINDINGS|PASS|FAIL|BLOCKED)\b", re.I | re.M
)
COUNTS_LINE = re.compile(
    r"^\W*findings?(?:\s+counts?)?\W+high\W+(\d+)\W+medium\W+(\d+)\W+low\W+(\d+)", re.I | re.M
)
# Read loosely on purpose: a false match leaves a page unverified, a miss would hide a high finding.
HIGH_FINDING = re.compile(
    r"severity[^\w\n]+high\b|\bhigh[^\w\n]+severity\b|\bfinding[^\w\n]+high\b|\[high\]|\(high\)"
    r"|\|[ \t]*high[ \t]*\||^[ \t]*(?:[-*][ \t]*)?\**high\**[ \t]*[:|]|\bhigh[^\w\n]*[1-9]",
    re.I | re.M,
)
SHA256 = re.compile(r"\b[0-9a-f]{64}\b")
FN_ROW = re.compile(rb"^\*\*F\d+\.\*\*", re.M)

STATUS_LINE = re.compile(
    r"^[^A-Za-z0-9\n]*verification status\b|verification status\W+verified\b", re.I
)
PHASE_4_TICK = re.compile(r"^(\s*[-*]\s+\[)[ xX](\]\s*Phase 4\b)", re.M)
LIST_PREFIX = re.compile(r"^\s*(?:[-*]\s+)?")


def decide_page(ev: dict) -> str:
    """Return `verified` or `unverified: <code>` from facts already read off the disk."""
    if ev["symlink_leaves_root"]:
        return "unverified: symlink-leaves-root"
    if ev["pin"] != "ok":
        return f"unverified: pin-{ev['pin']}"
    for arm, state in ev["arms"].items():
        if state != "pass":
            return f"unverified: verifier-{arm}-{state}"
    if ev["failed_gates"]:
        return f"unverified: gate-{ev['failed_gates'][0]}-fail"
    if not ev["checklist"]:
        return "unverified: checklist-missing"
    if not ev["handoff"]:
        return "unverified: handoff-missing"
    if not ev["status_awaiting"]:
        return "unverified: status-not-awaiting"
    return VERIFIED


def parse_time(text: str) -> float:
    return datetime.strptime(text, PIN_TIME).replace(tzinfo=timezone.utc).timestamp()


def regular(path: Path) -> bool:
    return path.is_file() and not path.is_symlink()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="surrogateescape")


def containment_refusal(page: dict, slice_arg: str, root_arg: str):
    """Return the code that refuses this slice before any read or write, or None."""
    work = os.path.join(os.path.realpath(root_arg), ".work")
    if os.path.islink(slice_arg):
        return "slice-symlink"
    if os.path.dirname(os.path.realpath(slice_arg)) != work or not SLUG.match(os.path.basename(slice_arg)):
        return "slice-outside-root"
    if page.get("slice") != slice_arg or page.get("slug") != os.path.basename(slice_arg):
        return "slice-mismatch"
    if not os.path.isdir(slice_arg):
        return "slice-missing"
    return None


def symlink_leaves_root(slice_dir: Path, work: str) -> bool:
    for base, dirs, files in os.walk(slice_dir, followlinks=False):
        for name in [*dirs, *files]:
            path = os.path.join(base, name)
            if os.path.islink(path) and not os.path.realpath(path).startswith(work + os.sep):
                return True
    return False


def read_pin(slice_dir: Path, started_at: float):
    """Return (state, pinned_at, hashes); state is ok, missing, before-run or moved."""
    try:
        manifest = json.loads(read_text(slice_dir / "verification" / "pin-manifest.json"))
        pinned_at = parse_time(manifest["pinned_at"])
        hashes = {entry["sha256"] for entry in manifest["files"]}
    except (OSError, ValueError, KeyError, TypeError):
        return "missing", 0.0, set()
    if not hashes:
        return "missing", 0.0, set()
    if pinned_at < started_at:
        return "before-run", pinned_at, hashes
    check = subprocess.run(
        [sys.executable, "-I", "-B", str(SCRIPTS / "pin-manifest.py"), str(slice_dir), "--check"],
        capture_output=True,
        check=False,
    )
    return ("ok" if check.returncode == 0 else "moved"), pinned_at, hashes


def judge_verdict(text: str) -> str:
    """Return pass, fail, blocked, high or malformed for one verdict file's text."""
    verdicts = [v.upper() for v in VERDICT_LINE.findall(text)]
    if "FAIL" in verdicts:
        return "fail"
    if "BLOCKED" in verdicts:
        return "blocked"
    if HIGH_FINDING.search(text):
        return "high"
    counts = COUNTS_LINE.findall(text)
    if len(verdicts) != 1 or len(counts) != 1:
        return "malformed"
    medium_or_low = int(counts[0][1]) + int(counts[0][2])
    if (verdicts[0] == "PASS") != (medium_or_low == 0):
        return "malformed"
    return "pass"


def arm_state(slice_dir: Path, arm: str, pinned_at: float, hashes: set) -> str:
    """Judge every verdict file of this run for one arm; a retry can leave more than one."""
    files = [p for p in sorted((slice_dir / "verification").glob(f"verifier-{arm}-*.md")) if regular(p)]
    if not files:
        return "missing"
    states = []
    for path in files:
        if path.stat().st_mtime >= pinned_at:
            text = read_text(path)
            states.append(judge_verdict(text))
            if not hashes <= set(SHA256.findall(text)):
                states.append("stale")
    for state in ("fail", "blocked", "high", "malformed", "stale"):
        if state in states:
            return state
    return "pass" if states else "stale"


def gate_commands(slice_dir: Path) -> dict:
    source = slice_dir / "source.md"
    if not source.exists():
        source = slice_dir / "source.txt"
    digests = sorted(p for p in (slice_dir / "digests").glob("*.md") if p.is_file())
    digest_args = [arg for d in digests for arg in ("--digest", str(d))]
    commands = {
        "check-fences-exact": ["--source", str(source), *digest_args],
        "check-snippets": ["--source", str(source), *digest_args],
        "check-prose-terms": digest_args,
        "check-sources-parity": [str(slice_dir)],
    }
    html = slice_dir / "source.html"
    rows = [d for d in digests if FN_ROW.search(d.read_bytes())]
    if html.exists() and rows:
        commands["check-html-rows"] = [str(html), *map(str, rows)]
    return commands


def failed_gates(slice_dir: Path) -> list:
    failed = []
    for gate, args in gate_commands(slice_dir).items():
        try:
            passed = subprocess.run(
                [sys.executable, "-I", "-B", str(SCRIPTS / f"{gate}.py"), *args],
                capture_output=True,
                check=False,
                timeout=GATE_TIMEOUT_SECONDS,
            ).returncode == 0
        except subprocess.TimeoutExpired:
            passed = False
        if not passed:
            failed.append(gate)
    return failed


def status_spans(lines: list) -> list:
    """Return (start, end) per status line; a template line may wrap inside its parenthesis."""
    spans = []
    i = 0
    while i < len(lines):
        if STATUS_LINE.search(lines[i]):
            end = i + 1
            if "(" in lines[i] and ")" not in lines[i]:
                while end < len(lines) and end < i + 4 and ")" not in lines[end - 1]:
                    end += 1
            spans.append((i, end))
            i = end
        else:
            i += 1
    return spans


def is_awaiting(path: Path) -> bool:
    lines = read_text(path).splitlines()
    spans = status_spans(lines)
    return len(spans) == 1 and lines[spans[0][1] - 1].rstrip(" \t`*.").endswith(AWAITING)


def rewrite_status(text: str, status: str, first_line: bool) -> str:
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()
    spans = status_spans(lines)
    prefix = ""
    if spans and not first_line:
        prefix = LIST_PREFIX.match(lines[spans[0][0]]).group(0)
    fresh = f"{prefix}Verification status: {status}"
    out = []
    at = 0
    for number, (start, end) in enumerate(spans):
        out += lines[at:start]
        if number == 0 and not first_line:
            out.append(fresh)
        at = end
    out += lines[at:]
    if first_line:
        out.insert(0, fresh)
    elif not spans:
        out.append(fresh)
    return newline.join(out) + newline


def replace_file(path: Path, text: str) -> None:
    """Swap the new text in, so a link at this path is replaced and its target left alone."""
    handle, temp = tempfile.mkstemp(dir=path.parent, prefix=".status-")
    try:
        with os.fdopen(handle, "w", encoding="utf-8", errors="surrogateescape", newline="") as out:
            out.write(text)
        os.replace(temp, path)
    except OSError:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def write_status(slice_dir: Path, status: str) -> None:
    checklist = slice_dir / "docpage-digest-checklist.md"
    handoff = slice_dir / "interview-handoff.md"
    if checklist.is_symlink() or checklist.is_file():
        text = "" if checklist.is_symlink() else read_text(checklist)
        text = rewrite_status(text, status, first_line=False)
        tick = "x" if status == VERIFIED else " "
        replace_file(checklist, PHASE_4_TICK.sub(rf"\g<1>{tick}\g<2>", text))
    if handoff.is_symlink() or handoff.is_file():
        text = "" if handoff.is_symlink() else read_text(handoff)
        replace_file(handoff, rewrite_status(text, status, first_line=True))


def page_status(page: dict, slice_dir: Path, work: str, started_at: float) -> str:
    if page.get("status") != "claimed":
        carried = page.get("verification")
        return carried if isinstance(carried, str) and CARRIED_STATUS.match(carried) else "unverified: result-malformed"
    checklist = slice_dir / "docpage-digest-checklist.md"
    handoff = slice_dir / "interview-handoff.md"
    ev = {
        "symlink_leaves_root": symlink_leaves_root(slice_dir, work),
        "pin": "missing",
        "arms": {},
        "failed_gates": [],
        "checklist": regular(checklist),
        "handoff": regular(handoff),
        "status_awaiting": False,
    }
    if not ev["symlink_leaves_root"]:
        ev["pin"], pinned_at, hashes = read_pin(slice_dir, started_at)
        ev["arms"] = {arm: arm_state(slice_dir, arm, pinned_at, hashes) for arm in ("a", "b")}
        ev["failed_gates"] = failed_gates(slice_dir)
        ev["status_awaiting"] = ev["checklist"] and ev["handoff"] and is_awaiting(checklist) and is_awaiting(handoff)
    return decide_page(ev)


def usage_error(message: str) -> int:
    print(f"verify-batch-page: ERROR: {message}", file=sys.stderr)
    return 2


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="verify-batch-page", description=__doc__.split("\n")[0])
    parser.add_argument("--result", required=True, help="JSON file holding the page's result entry")
    parser.add_argument("--slice", required=True, help="the slice path from that entry")
    parser.add_argument("--root", required=True, help="the work root the workflow was launched with")
    parser.add_argument("--started-at", required=True, help="launch time, YYYY-MM-DDTHH:MM:SSZ")
    args = parser.parse_args(argv)
    try:
        page = json.loads(Path(args.result).read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        return usage_error(f"cannot read {args.result}: {err}")
    if not isinstance(page, dict):
        return usage_error(f"{args.result} does not hold one page's result entry")
    try:
        started_at = parse_time(args.started_at)
    except ValueError:
        return usage_error(f"--started-at is not YYYY-MM-DDTHH:MM:SSZ: {args.started_at}")
    if not os.path.isdir(args.root):
        return usage_error(f"--root is not a directory: {args.root}")

    refusal = containment_refusal(page, args.slice, args.root)
    if refusal:
        print(f"unverified: {refusal}")
        return 1

    work = os.path.join(os.path.realpath(args.root), ".work")
    slice_dir = Path(args.slice)
    try:
        status = page_status(page, slice_dir, work, started_at)
    except OSError:
        status = "unverified: check-read-failed"
    try:
        write_status(slice_dir, status)
    except OSError:
        status = "unverified: status-write-failed"
        try:
            write_status(slice_dir, status)
        except OSError as err:
            print(f"verify-batch-page: ERROR: cannot write the status: {err}", file=sys.stderr)
    print(status)
    return 0 if status == VERIFIED else 1


if __name__ == "__main__":
    sys.exit(main())
