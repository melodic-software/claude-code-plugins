# GENERATED from plugins/performance/scripts/ratchet.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""Counter ceilings a CI step can enforce: the ratchet behind /performance:protect.

A ceilings file names counters, each with the shell command that measures it,
the `<field>=<number>` token its stdout carries, the ceiling it may not rise
above, and the goal it protects. Only counters belong here. A duration swings
with host load, so a checked-in duration ceiling fails at random and teaches
people to raise it; a count does not move unless the code does.

A per-file counter keeps one ceiling per file instead of one for the repository,
so a fix in one file cannot pay for a new violation in another. Its command
prints one `<path> <field>=<number>` line per file with a count above 0; a file
it does not print counts 0, and a file with no ceiling has a ceiling of 0.

Subcommands:
    check            Run every counter. Exit 1 naming each counter, or each file
                     of a per-file counter, above its ceiling.
    propose-tighten  Print the lower ceiling for every counter or file measured
                     below its own, measured like add. Writes only with --write,
                     and never raises one.
    add              Measure a new counter twice by default (--runs N sets the
                     count, at least 1) and record the agreed value as its
                     ceiling (--per-file: one ceiling per file). Runs that
                     disagree are refused: a ratchet on a counter that moves by
                     itself fails at random (reference/harness-integrity.md
                     rule 1).

Break glass: with "break_glass": true in the ceilings file, a per-file counter's
file may sit one above its ceiling for each inline exception in it of the shape
    ratchet-break-glass(<counter name>): reason=<why>; expires=<YYYY-MM-DD>; approved-by=<person>
An exception missing a field, or past its expiry, fails the check. Exceptions
are read in each file the command prints or the counter has a ceiling for. With
the key false or absent, exceptions are not read.

Commands run through the shell from the current directory, so run this from the
repository root. Nothing here knows which CI system calls it.

File shape:
    {"break_glass": false,
     "counters": [{"name": "...", "command": "...", "field": "spawns",
                   "ceiling": 6, "goal": "..."},
                  {"name": "...", "command": "...", "field": "violations",
                   "ceilings": {"src/a.ts": 3}, "goal": "..."}]}

Exit: 0 every counter at or below its ceiling; 1 a counter or file above it, or
a malformed or expired break-glass exception; 2 the ratchet could not run (a
malformed file, a missing field, a failed command).
"""

from __future__ import annotations

import argparse
import datetime
import json
import math
import os
import re
import subprocess
import sys
from typing import NoReturn

DEFAULT_FILE = ".performance/ratchets.json"
KEYS = ("name", "command", "field", "ceiling", "goal")
PER_FILE_KEYS = ("name", "command", "field", "ceilings", "goal")
TIMEOUT_SECONDS = 300
NUMBER = r"(\d+(?:\.\d+)?)"
MARKER = re.compile(r"ratchet-break-glass\(([^)]*)\):(.*)")
EXCEPTION_FIELDS = ("reason", "expires", "approved-by")


def fail(message: str) -> NoReturn:
    print(f"HARNESS FAIL: {message}", file=sys.stderr)
    raise SystemExit(2)


def is_number(value: object) -> bool:
    # bool is an int subclass; `"ceiling": true` is a typo, not a ceiling of 1.
    # json.load accepts NaN and Infinity, and a NaN ceiling compares false both
    # ways, so every counter would read as equal to it and pass.
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
    )


def load(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as error:
        fail(f"cannot read the ceilings file {path}: {error}")
    except json.JSONDecodeError as error:
        fail(f"{path} is not valid JSON: {error}")
    validate(path, data)
    return data


def validate(path: str, data: object) -> None:
    if not isinstance(data, dict) or set(data) - {"break_glass"} != {"counters"}:
        fail(f'{path} must be an object with the key "counters" and, optionally, "break_glass".')
    if not isinstance(data.get("break_glass", False), bool):
        fail(f'{path}: "break_glass" must be true or false.')
    counters = data["counters"]
    if not isinstance(counters, list):
        fail(f'{path}: "counters" must be a list.')
    seen: set[str] = set()
    for index, counter in enumerate(counters):
        where = f"{path} counters[{index}]"
        if not isinstance(counter, dict) or set(counter) not in (set(KEYS), set(PER_FILE_KEYS)):
            # Exact keys, so a misspelled "ceilling" fails here instead of
            # leaving a counter with no ceiling that nothing ever checks.
            fail(
                f"{where} must carry exactly the keys {', '.join(KEYS)}, "
                f"or {', '.join(PER_FILE_KEYS)} for a per-file counter."
            )
        for key in ("name", "command", "field", "goal"):
            if not isinstance(counter[key], str) or not counter[key].strip():
                fail(f"{where}: {key} must be a non-empty string.")
        if "ceilings" in counter:
            ceilings = counter["ceilings"]
            if not isinstance(ceilings, dict):
                fail(f"{where}: ceilings must be an object of file path to ceiling.")
            for file, ceiling in ceilings.items():
                if not file.strip() or not is_number(ceiling) or ceiling < 0:
                    fail(f"{where}: ceilings[{file!r}] must be a finite number of at least 0.")
        elif not is_number(counter["ceiling"]):
            fail(
                f"{where}: ceiling must be a finite number, got {counter['ceiling']!r}."
            )
        if counter["name"] in seen:
            fail(f"{where}: duplicate counter name {counter['name']!r}.")
        seen.add(counter["name"])


def save(path: str, data: dict) -> None:
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
    except OSError as error:
        fail(f"cannot write the ceilings file {path}: {error}")


def run(name: str, command: str) -> str:
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            check=False,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        fail(f"counter {name!r}: the command ran past {TIMEOUT_SECONDS}s.")
    if result.returncode != 0:
        # A counter whose command failed measured nothing. Reading a field out
        # of whatever it printed first would pass a ratchet on a subject that
        # never ran.
        fail(
            f"counter {name!r}: the command exited {result.returncode}. "
            f"stdout: {result.stdout.strip()!r} stderr: {result.stderr.strip()!r}"
        )
    return result.stdout


def number(name: str, field: str, text: str) -> int | float:
    value = float(text) if "." in text else int(text)
    if not is_number(value):
        # A digit string past float range parses to inf.
        fail(f"counter {name!r}: {field}={text[:40]}... is not a finite number.")
    return value


def measure(counter: dict) -> int | float | dict[str, int | float]:
    name, field = counter["name"], counter["field"]
    stdout = run(name, counter["command"])
    if "ceilings" in counter:
        return per_file_counts(name, field, stdout)
    pattern = rf"(?<![\w.-]){re.escape(field)}={NUMBER}(?![\w.])"
    match = re.search(pattern, stdout)
    if match is None:
        fail(
            f"counter {name!r}: no numeric {field}=<number> token in the command's "
            f"stdout: {stdout.strip()!r}"
        )
    return number(name, field, match.group(1))


def per_file_counts(name: str, field: str, stdout: str) -> dict[str, int | float]:
    # Every non-blank line must be a count: a line the pattern skips could be a
    # file whose violations go unchecked.
    line_pattern = re.compile(rf"(\S.*?)\s+{re.escape(field)}={NUMBER}")
    counts: dict[str, int | float] = {}
    for line in stdout.splitlines():
        if not line.strip():
            continue
        match = line_pattern.fullmatch(line.strip())
        if match is None:
            fail(
                f"counter {name!r}: the line {line.strip()!r} is not "
                f"'<path> {field}=<number>'."
            )
        path = match.group(1)
        if path in counts:
            fail(f"counter {name!r}: {path} is printed twice.")
        counts[path] = number(name, field, match.group(2))
    return counts


def exception_problem(text: str, today: datetime.date) -> str | None:
    fields: dict[str, str] = {}
    for part in text.strip().removesuffix("-->").removesuffix("*/").split(";"):
        key, _, value = part.partition("=")
        fields[key.strip()] = value.strip()
    missing = [key for key in EXCEPTION_FIELDS if not fields.get(key)]
    if missing:
        return f"missing {', '.join(missing)}"
    try:
        expires = datetime.date.fromisoformat(fields["expires"])
    except ValueError:
        return f"expires={fields['expires']!r} is not a YYYY-MM-DD date"
    if expires < today:
        return f"expired {expires.isoformat()}"
    return None


def exceptions(name: str, path: str) -> tuple[int, list[str]]:
    """Count the valid break-glass exceptions for counter `name` in `path`."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        # A file that cannot be read grants nothing, so its count still fails.
        return 0, []
    today = datetime.date.today()
    valid, problems = 0, []
    for line_number, line in enumerate(lines, 1):
        match = MARKER.search(line)
        if match is None or match.group(1).strip() != name:
            continue
        problem = exception_problem(match.group(2), today)
        if problem:
            problems.append(f"{path}:{line_number}: {problem}")
        else:
            valid += 1
    return valid, problems


def judge_files(counter: dict, counts: dict, break_glass: bool) -> list[tuple]:
    """One (path, value, ceiling, allowed, problems) row per counted or ceilinged file."""
    ceilings = counter["ceilings"]
    rows = []
    for path in sorted(set(counts) | set(ceilings)):
        allowed, problems = exceptions(counter["name"], path) if break_glass else (0, [])
        rows.append((path, counts.get(path, 0), ceilings.get(path, 0), allowed, problems))
    return rows


def check_per_file(counter: dict, counts: dict, break_glass: bool) -> int:
    name, field = counter["name"], counter["field"]
    above = below = 0
    for path, value, ceiling, allowed, problems in judge_files(counter, counts, break_glass):
        for problem in problems:
            above += 1
            print(f"BROKEN {name}: break-glass exception at {problem}")
        if value > ceiling + allowed:
            above += 1
            print(
                f"ABOVE  {name}: {path} {field}={value} > ceiling {ceiling} "
                f"(protects: {counter['goal']})"
            )
        elif value > ceiling:
            print(
                f"EXCEPT {name}: {path} {field}={value} > ceiling {ceiling}, "
                f"held by {allowed} break-glass exception(s)"
            )
        elif value < ceiling:
            below += 1
    total = sum(counts.values())
    if not above:
        tail = f"; propose-tighten can lower {below}" if below else ""
        print(f"OK     {name}: every file at or below its ceiling ({field}={total} total){tail}")
    return above


def cmd_check(args: argparse.Namespace) -> int:
    data = load(args.file)
    counters = data["counters"]
    if not counters:
        fail(f"{args.file} lists no counters; a check over nothing protects nothing.")
    break_glass = data.get("break_glass", False)
    above = 0
    for counter in counters:
        value = measure(counter)
        if "ceilings" in counter:
            above += check_per_file(counter, value, break_glass)
            continue
        ceiling = counter["ceiling"]
        if value > ceiling:
            above += 1
            print(
                f"ABOVE  {counter['name']}: {counter['field']}={value} > "
                f"ceiling {ceiling} (protects: {counter['goal']})"
            )
        elif value < ceiling:
            print(
                f"OK     {counter['name']}: {counter['field']}={value} < "
                f"ceiling {ceiling}; propose-tighten can lower it"
            )
        else:
            print(f"OK     {counter['name']}: {counter['field']}={value} = ceiling")
    return 1 if above else 0


def measure_runs(counter: dict, runs: int) -> int | float | dict[str, int | float]:
    values = [measure(counter) for _ in range(runs)]
    if any(value != values[0] for value in values[1:]):
        fail(
            f"counter {counter['name']!r} measured {' then '.join(map(str, values))} "
            f"on an unchanged subject. A ratchet on a counter that moves by itself "
            f"fails at random; pin whatever varies (a cache, a clock, a temp path) first."
        )
    return values[0]


def positive_int(text: str) -> int:
    try:
        value = int(text)
    except ValueError:
        value = 0
    if value < 1:
        raise argparse.ArgumentTypeError(
            f"must be an integer of at least 1, got {text!r}"
        )
    return value


def tighten_per_file(counter: dict, counts: dict, break_glass: bool) -> tuple[int, int]:
    name = counter["name"]
    changed = above = 0
    lowered: dict[str, int | float] = {}
    for path, value, ceiling, allowed, problems in judge_files(counter, counts, break_glass):
        for problem in problems:
            print(f"BROKEN {name}: break-glass exception at {problem}")
        if problems or value > ceiling + allowed:
            above += 1
            if value > ceiling + allowed:
                print(f"ABOVE  {name}: {path} {value} > ceiling {ceiling}")
        elif value < ceiling:
            changed += 1
            print(f"TIGHTEN {name}: {path} ceiling {ceiling} -> {value}")
            ceiling = value
        # A file held above its ceiling by an exception keeps that ceiling:
        # tightening never raises one.
        if ceiling > 0:
            lowered[path] = ceiling
    counter["ceilings"] = lowered
    return changed, above


def cmd_propose_tighten(args: argparse.Namespace) -> int:
    data = load(args.file)
    counters = data["counters"]
    if not counters:
        fail(f"{args.file} lists no counters; there is nothing to tighten.")
    break_glass = data.get("break_glass", False)
    changed = 0
    above = 0
    for counter in counters:
        # Agreeing runs, as in add: one noisy dip must not lower a ceiling.
        value = measure_runs(counter, args.runs)
        if "ceilings" in counter:
            file_changed, file_above = tighten_per_file(counter, value, break_glass)
            changed += file_changed
            above += file_above
        elif value > counter["ceiling"]:
            above += 1
            print(f"ABOVE  {counter['name']}: {value} > ceiling {counter['ceiling']}")
        elif value < counter["ceiling"]:
            changed += 1
            print(f"TIGHTEN {counter['name']}: ceiling {counter['ceiling']} -> {value}")
            counter["ceiling"] = value
    if above:
        # Tightening past a regression would hide it; the regression is the news.
        print("nothing written: a counter is above its ceiling; run check.")
        return 1
    if not changed:
        print("no ceiling can tighten")
    elif args.write:
        save(args.file, data)
        print(f"wrote {changed} lower ceiling(s) to {args.file}")
    else:
        print("dry run; pass --write to record these ceilings")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    # A missing file starts empty; a malformed one still fails loudly in load().
    data = load(args.file) if os.path.exists(args.file) else {"counters": []}
    if args.break_glass is not None:
        data["break_glass"] = args.break_glass == "on"
    # The ceiling stands in until measured; validating now refuses a bad or
    # duplicate entry before its command runs.
    entry = {key: getattr(args, key) for key in ("name", "command", "field", "goal")}
    entry["ceilings" if args.per_file else "ceiling"] = {} if args.per_file else 0
    validate(args.file, {**data, "counters": [*data["counters"], entry]})
    value = measure_runs(entry, args.runs)
    if args.per_file:
        entry["ceilings"] = {path: count for path, count in value.items() if count > 0}
        shown = f"{len(entry['ceilings'])} file ceiling(s), {sum(value.values())} total"
    else:
        entry["ceiling"] = shown = value
    data["counters"].append(entry)
    save(args.file, data)
    print(f"added {args.name}: ceiling {shown} ({args.field}), in {args.file}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n", 1)[0])
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("check", "propose-tighten", "add"):
        child = sub.add_parser(name)
        child.add_argument("--file", default=DEFAULT_FILE)
        if name != "check":
            child.add_argument("--runs", type=positive_int, default=2)
        if name == "propose-tighten":
            child.add_argument("--write", action="store_true")
        if name == "add":
            for flag in ("--name", "--command", "--field", "--goal"):
                child.add_argument(flag, required=True)
            child.add_argument("--per-file", action="store_true")
            child.add_argument("--break-glass", choices=("on", "off"))
    args = parser.parse_args()
    handler = {
        "check": cmd_check,
        "propose-tighten": cmd_propose_tighten,
        "add": cmd_add,
    }[args.action]
    return handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
