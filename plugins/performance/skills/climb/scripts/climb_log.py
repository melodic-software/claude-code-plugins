#!/usr/bin/env python3
"""Attempt log and keep rule for /performance:climb.

append  Add one attempt row to the tab-separated log. Writes only the --log file.
show    Print the log's header and rows.
decide  Print kept or reverted from the keep rule file and two measurements.
        Reads only its arguments and the rule file.

Exit: 0 done; 2 a bad argument, a bad value, or a malformed log or rule file.
Nothing is written on exit 2.
"""

import argparse
import json
import math
import sys
from pathlib import Path

FIELDS = (
    "id",
    "hypothesis",
    "change",
    "before",
    "after",
    "delta",
    "tests",
    "verdict",
    "note",
)
VALUE_SETS = {"tests": ("pass", "fail"), "verdict": ("kept", "reverted")}
OPTIONAL = ("note",)
RULE_KEYS = {"counter", "direction", "gain_floor"}
DIRECTIONS = ("lower", "higher")


class Refused(Exception):
    pass


def check_field(name, value):
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        raise Refused(f"{name} is not valid UTF-8") from None
    # The log is read back with str.splitlines(), so a field may hold none of
    # the characters it splits on, not only \n and \r.
    if "\t" in value or (value and value.splitlines() != [value]):
        raise Refused(f"{name} contains a tab or line break")
    if not value and name not in OPTIONAL:
        raise Refused(f"{name} is empty")
    allowed = VALUE_SETS.get(name)
    if allowed and value not in allowed:
        raise Refused(f"{name} must be one of {', '.join(allowed)}, got {value!r}")


def read_rows(log):
    lines = log.read_text(encoding="utf-8").splitlines()
    if not lines:
        return []
    if tuple(lines[0].split("\t")) != FIELDS:
        raise Refused(f"{log} does not start with the climb log header")
    for number, line in enumerate(lines[1:], start=2):
        if len(line.split("\t")) != len(FIELDS):
            raise Refused(f"{log} line {number} does not have {len(FIELDS)} fields")
    return lines


def append(args):
    values = [getattr(args, name) for name in FIELDS]
    for name, value in zip(FIELDS, values, strict=True):
        check_field(name, value)
    log = Path(args.log)
    if not log.parent.is_dir():
        raise Refused(f"log directory does not exist: {log.parent}")
    text = "\t".join(values) + "\n"
    if not log.exists() or not read_rows(log):
        text = "\t".join(FIELDS) + "\n" + text
    with log.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def show(args):
    log = Path(args.log)
    if not log.exists():
        print(f"no attempts logged yet: {log}", file=sys.stderr)
        return
    for line in read_rows(log):
        print(line)


def number(name, raw):
    try:
        value = float(raw)
    except ValueError:
        raise Refused(f"{name} is not a number: {raw!r}") from None
    if not math.isfinite(value):
        raise Refused(f"{name} is not a finite number: {raw!r}")
    return value


def load_rule(path):
    try:
        rule = json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise Refused(f"keep rule file not found: {path}") from None
    except (OSError, ValueError) as error:
        raise Refused(f"keep rule file is not readable JSON: {error}") from None
    if not isinstance(rule, dict) or set(rule) != RULE_KEYS:
        raise Refused(
            f"keep rule must hold exactly the keys {', '.join(sorted(RULE_KEYS))}"
        )
    if not isinstance(rule["counter"], str) or not rule["counter"].strip():
        raise Refused("counter must be a non-empty string")
    if rule["direction"] not in DIRECTIONS:
        raise Refused(f"direction must be one of {', '.join(DIRECTIONS)}")
    floor = rule["gain_floor"]
    if isinstance(floor, bool) or not isinstance(floor, (int, float)):
        raise Refused("gain_floor must be a number at or above 0")
    try:
        floor = float(floor)
    except OverflowError:
        raise Refused("gain_floor is out of range for a number") from None
    if not math.isfinite(floor) or floor < 0:
        raise Refused("gain_floor must be a number at or above 0")
    rule["gain_floor"] = floor
    return rule


def decide(args):
    rule = load_rule(args.rule)
    before = number("before", args.before)
    after = number("after", args.after)
    gain = before - after if rule["direction"] == "lower" else after - before
    print("kept" if gain > rule["gain_floor"] else "reverted")


def parser():
    top = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    commands = top.add_subparsers(dest="command", required=True)
    add = commands.add_parser("append", help="add one attempt row")
    add.add_argument("--log", required=True)
    for name in FIELDS:
        add.add_argument(f"--{name}", required=True)
    add.set_defaults(run=append)
    view = commands.add_parser("show", help="print the log")
    view.add_argument("--log", required=True)
    view.set_defaults(run=show)
    rule = commands.add_parser("decide", help="apply the keep rule")
    rule.add_argument("--rule", required=True)
    rule.add_argument("--before", required=True)
    rule.add_argument("--after", required=True)
    rule.set_defaults(run=decide)
    return top


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        args.run(args)
    except Refused as error:
        print(f"climb_log: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
