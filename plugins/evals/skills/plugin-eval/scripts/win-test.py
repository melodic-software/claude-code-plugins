#!/usr/bin/env python3
"""win-test - decide whether a proposed skill edit beats the unchanged skill.

    win-test --a <A.json> --a2 <A2.json> [--edit <B.json>]
             [--health <summary.md>]... [--validity <run-validity output>]...
             [--margin M] [--max-cost-usd C]

A and A2 are two `claude plugin eval` results of the unchanged skill (an A/A
pair); B is the result of the same suite with the edit applied. Case scores and
the paired 95% normal interval come from noise-report.py, loaded from this
script's directory. Each gate below stops the run with one `gate:` line naming
it and its numbers; with no --edit, passing every baseline gate prints
`proceed:`, and with --edit, passing every gate prints `win:`.

    partial     a result did not finish
    validity    a --validity file's last line is not `verdict: VALID`
    cost        A's list-price estimate is above --max-cost-usd (default 5),
                so a later pass of the same suite would not fit under it
    cases       fewer than 3 cases scored in every result, after leaving out
                each case a --health file reads `skill loaded: no` or
                `skill loaded: unknown` (summarize.mjs health lines)
    headroom    A's with-arm mean is 0.95 or higher
    aa-noise    the A/A with-arm change (A2 minus A) has an interval that
                excludes 0
    aa-drop     a case's with-arm score fell by a third or more from A to A2
    edit-drop   a case's with-arm score fell by a third or more from A to B
    margin      the edit's with-arm change (B minus A) has an interval whose
                lower end is below --margin (default 0.05) or not above the
                A/A change's upper end

Exit codes:

    0  proceed (no --edit) or win (--edit)
    1  a gate stopped the run
    2  usage error, or a file is missing or unreadable
"""

import argparse
import importlib.util
import re
import sys
from pathlib import Path

MIN_PYTHON = (3, 8)

HEALTH_LINE = re.compile(r"^- (.+?): skill loaded: (yes|no|unknown)\b")
VALID_LINE = re.compile(r"^verdict: VALID\b")


def load_noise_report():
    path = Path(__file__).resolve().with_name("noise-report.py")
    spec = importlib.util.spec_from_file_location("noise_report", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


NR = load_noise_report()


def cell(name):
    """A case name as summarize.mjs's cell() prints it in a health line."""
    text = re.sub(r"[\r\n]+", " ", str(name))
    return text.replace("|", "\\|").replace("@", "@​")


def read_text(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError as error:
        raise SystemExit("error: cannot read %s (%s)" % (path, error)) from None


def excluded_cells(paths):
    """{printed case name: reason} for each case a health file reads no or unknown."""
    out = {}
    for path in paths:
        for line in read_text(path).splitlines():
            match = HEALTH_LINE.match(line)
            if match and match.group(2) != "yes":
                out.setdefault(match.group(1), "skill loaded: %s" % match.group(2))
    return out


def is_valid(path):
    lines = [line.strip() for line in read_text(path).splitlines() if line.strip()]
    return bool(lines) and bool(VALID_LINE.match(lines[-1]))


def change(rows, base, names):
    """(mean, low, high, per-case deltas) of with-arm rows minus base, paired by name."""
    deltas = [rows[name]["with"] - base[name]["with"] for name in names]
    if len(set(round(d, 9) for d in deltas)) == 1:
        return deltas[0], deltas[0], deltas[0], deltas
    m, lo, hi = NR.normal_interval(deltas, -1.0, 1.0)
    return m, lo, hi, deltas


def drops(rows, base, names):
    return [n for n in names if base[n]["with"] - rows[n]["with"] >= NR.DROP - 1e-9]


def interval(label, m, lo, hi, n):
    return "%s, paired over %d cases: %+.2f, 95%% interval %+.2f to %+.2f" % (
        label,
        n,
        m,
        lo,
        hi,
    )


def decide(results, health, validity, margin, max_cost):
    """(gate name or None, lines). results maps a, a2 and optionally b to documents."""
    lines = []

    def stop(gate, detail):
        lines.append("gate: %s: %s" % (gate, detail))
        return gate, lines

    for label, doc in results.items():
        if doc.get("partial") is True:
            return stop(
                "partial",
                "pass %s did not finish (%s)" % (label, doc.get("partialReason")),
            )
    invalid = [path for path in validity if not is_valid(path)]
    if invalid:
        return stop("validity", "run-validity is not VALID for %s" % ", ".join(invalid))
    cost = results["a"].get("costUsd")
    if NR.is_number(cost) and cost > max_cost:
        return stop(
            "cost",
            "pass a cost %.2f USD, above the %.2f USD a pass may spend" % (cost, max_cost),
        )
    out = excluded_cells(health)
    rows = {label: NR.case_rows(doc)[0] for label, doc in results.items()}
    names = sorted(
        (n for n in rows["a"] if all(n in r for r in rows.values())), key=str
    )
    for name in [n for n in names if cell(n) in out]:
        lines.append("excluded: case %s (%s)" % (name, out[cell(name)]))
    names = [n for n in names if cell(n) not in out]
    if len(names) < NR.MIN_CASES:
        return stop(
            "cases",
            "%d cases scored in every pass after exclusions; %d or more are needed"
            % (len(names), NR.MIN_CASES),
        )
    a, a2 = rows["a"], rows["a2"]
    base_mean = NR.mean([a[n]["with"] for n in names])
    lines.append("a with-arm mean: %.2f over %d cases" % (base_mean, len(names)))
    if base_mean >= NR.CEILING - 1e-9:
        return stop(
            "headroom",
            "pass a with-arm mean %.2f is at or above %.2f" % (base_mean, NR.CEILING),
        )
    m, lo, hi, _ = change(a2, a, names)
    lines.append(interval("a/a with-arm change (a2 minus a)", m, lo, hi, len(names)))
    if lo > 0 or hi < 0:
        return stop("aa-noise", "the a/a interval %+.2f to %+.2f excludes 0" % (lo, hi))
    fell = drops(a2, a, names)
    if fell:
        return stop(
            "aa-drop",
            "; ".join(
                "case %s fell from %.2f to %.2f" % (n, a[n]["with"], a2[n]["with"])
                for n in fell
            ),
        )
    if "b" not in rows:
        lines.append("proceed: the baseline passes every gate (a/a upper end %+.2f)" % hi)
        return None, lines
    b = rows["b"]
    bm, blo, bhi, _ = change(b, a, names)
    lines.append(interval("edit with-arm change (b minus a)", bm, blo, bhi, len(names)))
    fell = drops(b, a, names)
    if fell:
        return stop(
            "edit-drop",
            "; ".join(
                "case %s fell from %.2f to %.2f" % (n, a[n]["with"], b[n]["with"])
                for n in fell
            ),
        )
    if blo < margin - 1e-9 or blo <= hi + 1e-9:
        return stop(
            "margin",
            "the edit's lower end %+.2f must be at or above %+.2f and above the a/a"
            " upper end %+.2f" % (blo, margin, hi),
        )
    lines.append(
        "win: the edit's lower end %+.2f is at or above %+.2f and above the a/a"
        " upper end %+.2f" % (blo, margin, hi)
    )
    return None, lines


def load(path):
    doc = NR.load_result(path)
    if doc is None:
        raise SystemExit(2)
    return doc


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write("error: win-test needs Python %d.%d or newer\n" % MIN_PYTHON)
        return 2
    parser = argparse.ArgumentParser(
        prog="win-test",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--a", required=True, help="result of the unchanged skill")
    parser.add_argument("--a2", required=True, help="second result of the unchanged skill")
    parser.add_argument("--edit", help="result with the proposed edit applied")
    parser.add_argument("--health", action="append", default=[], help="a summarize.mjs summary")
    parser.add_argument("--validity", action="append", default=[], help="a run-validity output")
    parser.add_argument("--margin", type=float, default=0.05, help="superiority margin")
    parser.add_argument("--max-cost-usd", type=float, default=5.0, help="per-pass ceiling")
    args = parser.parse_args(argv)
    try:
        results = {"a": load(args.a), "a2": load(args.a2)}
        if args.edit:
            results["b"] = load(args.edit)
        gate, lines = decide(
            results, args.health, args.validity, args.margin, args.max_cost_usd
        )
    except SystemExit as error:
        if isinstance(error.code, str):
            sys.stderr.write(error.code + "\n")
        return 2
    for line in lines:
        print(line)
    return 1 if gate else 0


if __name__ == "__main__":
    sys.exit(main())
