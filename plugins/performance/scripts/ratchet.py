"""Counter ceilings a CI step can enforce: the ratchet behind /performance:protect.

A ceilings file names counters, each with the shell command that measures it,
the `<field>=<number>` token its stdout carries, the ceiling it may not rise
above, and the goal it protects. Only counters belong here. A duration swings
with host load, so a checked-in duration ceiling fails at random and teaches
people to raise it; a count does not move unless the code does.

Subcommands:
    check            Run every counter. Exit 1 naming each counter above its
                     ceiling.
    propose-tighten  Print the lower ceiling for every counter measured below
                     its own. Writes only with --write, and never raises one.
    add              Measure a new counter TWICE and record the agreed value as
                     its ceiling. Two runs that disagree are refused: a ratchet
                     on a counter that moves by itself fails at random
                     (reference/harness-integrity.md rule 1).

Commands run through the shell from the current directory, so run this from the
repository root. Nothing here knows which CI system calls it.

File shape:
    {"counters": [{"name": "...", "command": "...", "field": "spawns",
                   "ceiling": 6, "goal": "..."}]}

Exit: 0 every counter at or below its ceiling; 1 a counter above it; 2 the
ratchet could not run (a malformed file, a missing field, a failed command).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from typing import NoReturn

DEFAULT_FILE = ".performance/ratchets.json"
KEYS = ("name", "command", "field", "ceiling", "goal")


def fail(message: str) -> NoReturn:
    print(f"HARNESS FAIL: {message}", file=sys.stderr)
    raise SystemExit(2)


def is_number(value: object) -> bool:
    # bool is an int subclass; `"ceiling": true` is a typo, not a ceiling of 1.
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def load(path: str) -> list[dict]:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as error:
        fail(f"cannot read the ceilings file {path}: {error}")
    except json.JSONDecodeError as error:
        fail(f"{path} is not valid JSON: {error}")
    return validate(path, data)


def validate(path: str, data: object) -> list[dict]:
    if not isinstance(data, dict) or set(data) != {"counters"}:
        fail(f'{path} must be an object with exactly one key, "counters".')
    counters = data["counters"]
    if not isinstance(counters, list):
        fail(f'{path}: "counters" must be a list.')
    seen: set[str] = set()
    for index, counter in enumerate(counters):
        where = f"{path} counters[{index}]"
        if not isinstance(counter, dict) or set(counter) != set(KEYS):
            # Exact keys, so a misspelled "ceilling" fails here instead of
            # leaving a counter with no ceiling that nothing ever checks.
            fail(f"{where} must carry exactly the keys {', '.join(KEYS)}.")
        for key in ("name", "command", "field", "goal"):
            if not isinstance(counter[key], str) or not counter[key].strip():
                fail(f"{where}: {key} must be a non-empty string.")
        if not is_number(counter["ceiling"]):
            fail(f"{where}: ceiling must be a number, got {counter['ceiling']!r}.")
        if counter["name"] in seen:
            fail(f"{where}: duplicate counter name {counter['name']!r}.")
        seen.add(counter["name"])
    return counters


def save(path: str, counters: list[dict]) -> None:
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"counters": counters}, handle, indent=2)
            handle.write("\n")
    except OSError as error:
        fail(f"cannot write the ceilings file {path}: {error}")


def measure(name: str, command: str, field: str) -> int | float:
    result = subprocess.run(
        command, shell=True, capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        # A counter whose command failed measured nothing. Reading a field out
        # of whatever it printed first would pass a ratchet on a subject that
        # never ran.
        fail(
            f"counter {name!r}: the command exited {result.returncode}. "
            f"stdout: {result.stdout.strip()!r} stderr: {result.stderr.strip()!r}"
        )
    pattern = rf"(?<![\w.-]){re.escape(field)}=(\d+(?:\.\d+)?)(?![\w.])"
    match = re.search(pattern, result.stdout)
    if match is None:
        fail(
            f"counter {name!r}: no numeric {field}=<number> token in the command's "
            f"stdout: {result.stdout.strip()!r}"
        )
    text = match.group(1)
    return float(text) if "." in text else int(text)


def cmd_check(args: argparse.Namespace) -> int:
    counters = load(args.file)
    if not counters:
        fail(f"{args.file} lists no counters; a check over nothing protects nothing.")
    above = 0
    for counter in counters:
        value = measure(counter["name"], counter["command"], counter["field"])
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


def cmd_propose_tighten(args: argparse.Namespace) -> int:
    counters = load(args.file)
    changed = 0
    above = 0
    for counter in counters:
        value = measure(counter["name"], counter["command"], counter["field"])
        if value > counter["ceiling"]:
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
        save(args.file, counters)
        print(f"wrote {changed} lower ceiling(s) to {args.file}")
    else:
        print("dry run; pass --write to record these ceilings")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    # A missing file starts empty; a malformed one still fails loudly in load().
    counters = load(args.file) if os.path.exists(args.file) else []
    entry = {key: getattr(args, key) for key in KEYS if key != "ceiling"}
    entry["ceiling"] = 0
    validate(args.file, {"counters": [*counters, entry]})
    first = measure(args.name, args.command, args.field)
    second = measure(args.name, args.command, args.field)
    if first != second:
        fail(
            f"counter {args.name!r} measured {first} then {second} on an unchanged "
            f"subject. A ratchet on a counter that moves by itself fails at random; "
            f"pin whatever varies (a cache, a clock, a temp path) first."
        )
    entry["ceiling"] = first
    counters.append({key: entry[key] for key in KEYS})
    save(args.file, counters)
    print(f"added {args.name}: ceiling {first} ({args.field}), in {args.file}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n", 1)[0])
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("check", "propose-tighten", "add"):
        child = sub.add_parser(name)
        child.add_argument("--file", default=DEFAULT_FILE)
        if name == "propose-tighten":
            child.add_argument("--write", action="store_true")
        if name == "add":
            for flag in ("--name", "--command", "--field", "--goal"):
                child.add_argument(flag, required=True)
    args = parser.parse_args()
    handler = {
        "check": cmd_check,
        "propose-tighten": cmd_propose_tighten,
        "add": cmd_add,
    }[args.action]
    return handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
