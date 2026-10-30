#!/usr/bin/env bash
# Stages scripts/check_fields.py after a proposed change and writes the change to
# change.diff. The change moves check_bounds's per-field test into a
# bound_problem helper and turns `value < low` into `value <= low`, so a value
# equal to its inclusive minimum, such as runs: 1, is reported as below it (the
# seeded defect). It also rewrites check_env's message from % formatting to
# str.format, which prints the same text (the decoy).
set -euo pipefail

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
mkdir -p "$base/scripts" scripts

cat >"$base/scripts/check_fields.py" <<'PY'
"""Checks one eval case's run fields and env keys against what the loader accepts."""

import re

BOUNDS = (("runs", 1, 50), ("max_turns", 1, 200), ("timeout_seconds", 1, 3600))
ENV_KEY = re.compile(r"^EVAL_[A-Z0-9_]*$")


def check_bounds(fields, findings):
    """Append one message per run field outside its inclusive bounds."""
    for key, low, high in BOUNDS:
        if key not in fields:
            continue
        value = fields[key]
        if not isinstance(value, int) or isinstance(value, bool):
            findings.append("%s %r is not a number" % (key, value))
        elif value > high:
            findings.append("%s %d over the maximum %d" % (key, value, high))
        elif value < low:
            findings.append("%s %d below the minimum %d" % (key, value, low))


def check_env(env, findings):
    """Append one message per env key the loader rejects."""
    for key in sorted(env):
        if not ENV_KEY.match(str(key)):
            findings.append('env key "%s" must match EVAL_[A-Z0-9_]*' % key)


def validate(fields):
    """Every finding for one case's run fields, in a stable order."""
    findings = []
    check_bounds(fields, findings)
    check_env(fields.get("env") or {}, findings)
    return findings
PY

cat >scripts/check_fields.py <<'PY'
"""Checks one eval case's run fields and env keys against what the loader accepts."""

import re

BOUNDS = (("runs", 1, 50), ("max_turns", 1, 200), ("timeout_seconds", 1, 3600))
ENV_KEY = re.compile(r"^EVAL_[A-Z0-9_]*$")


def bound_problem(key, value, low, high):
    """The message for a run field outside its inclusive bounds, or None."""
    if not isinstance(value, int) or isinstance(value, bool):
        return "%s %r is not a number" % (key, value)
    if value > high:
        return "%s %d over the maximum %d" % (key, value, high)
    if value <= low:
        return "%s %d below the minimum %d" % (key, value, low)
    return None


def check_bounds(fields, findings):
    """Append one message per run field outside its inclusive bounds."""
    for key, low, high in BOUNDS:
        if key in fields:
            problem = bound_problem(key, fields[key], low, high)
            if problem:
                findings.append(problem)


def check_env(env, findings):
    """Append one message per env key the loader rejects."""
    for key in sorted(env):
        if not ENV_KEY.match(str(key)):
            findings.append('env key "{}" must match EVAL_[A-Z0-9_]*'.format(key))


def validate(fields):
    """Every finding for one case's run fields, in a stable order."""
    findings = []
    check_bounds(fields, findings)
    check_env(fields.get("env") or {}, findings)
    return findings
PY

diff -u --label a/scripts/check_fields.py --label b/scripts/check_fields.py \
  "$base/scripts/check_fields.py" scripts/check_fields.py >change.diff || test $? -eq 1
