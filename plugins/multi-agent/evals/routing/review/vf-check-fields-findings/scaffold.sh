#!/usr/bin/env bash
# Stages scripts/check_fields.py and findings.md, four findings a reviewer
# raised against it. F1 and F4 are real defects: check_bounds's mutable default
# list is shared by every call validate makes, and isinstance(value, int) is
# true for a bool. F2 and F3 are false: finditer returns non-overlapping
# matches, and iterating a dict, sorted or not, yields its keys.
set -euo pipefail

mkdir -p scripts

cat >scripts/check_fields.py <<'PY'
"""Checks one eval case's run fields and env keys and returns the problems."""

import re

BOUNDS = (("runs", 1, 50), ("max_turns", 1, 200), ("timeout_seconds", 1, 3600))
ENV_KEY = re.compile(r"^EVAL_[A-Z0-9_]*$")
COUNT_MATCH = re.compile(r"^count:([0-9]+)$")


def check_bounds(fields, findings=[]):
    """Append one message per run field outside its inclusive bounds."""
    for key, low, high in BOUNDS:
        if key not in fields:
            continue
        value = fields[key]
        if not isinstance(value, int):
            findings.append("%s %r is not a number" % (key, value))
        elif value > high:
            findings.append("%s %d over the maximum %d" % (key, value, high))
        elif value < low:
            findings.append("%s %d below the minimum %d" % (key, value, low))
    return findings


def check_env(env):
    """One message per env key the loader rejects, in key order."""
    return [
        'env key "%s" must match EVAL_[A-Z0-9_]*' % key
        for key in sorted(env)
        if not ENV_KEY.match(str(key))
    ]


def count_matches(regex, text, mode):
    """Whether text holds exactly the number of matches a count:N mode asks for."""
    wanted = COUNT_MATCH.match(mode)
    if not wanted:
        raise ValueError("not a count mode: %s" % mode)
    return sum(1 for _ in regex.finditer(text)) == int(wanted.group(1))


def validate(case):
    """Every problem in one case's run fields and env keys."""
    problems = check_bounds(case.get("fields") or {})
    problems += check_env(case.get("env") or {})
    return problems
PY

cat >findings.md <<'MD'
# Review findings: scripts/check_fields.py

F1. `check_bounds` takes `findings=[]` as a default. The list is created once, when the function is
defined, so every call `validate` makes appends to the same list: problems from one case show up in
the result for every case validated after it.

F2. `count_matches` counts overlapping matches. `finditer` resumes the search one character after
each match starts, so the pattern `aa` against `aaa` counts 2 matches where the loader counts 1, and
a `count:1` grader fails a reply it should pass.

F3. `check_env` iterates `sorted(env)`, which sorts the dict's values rather than its keys, so
`ENV_KEY` is matched against the values and a bad key such as `PATH` is never reported.

F4. `isinstance(value, int)` is true for `True` and `False`, because `bool` is a subclass of `int`,
so `runs: true` passes the bounds check as 1 instead of being reported as not a number.
MD
