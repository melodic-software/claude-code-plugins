#!/usr/bin/env python3
"""noise-report - put noise lines beside a `claude plugin eval` result.

    noise-report <aggregate-result.json> [--threshold T]
                 [--interval-method normal|wilson|jeffreys] [--grader-agreement]

Reads one result file and prints, one finding per line:

    not comparable    a case left out: a run errored, skipped its paid graders,
                      has no score, or the result omits the case's delta
    score check       a run whose reported score disagrees with its graders
    <arm>-arm mean    the mean case score with a 95% normal interval
    cost              the suite's list-price estimate, beside the scores
    near ceiling      the without-arm mean is 0.95 or higher
    delta             with minus without, paired over cases, 95% normal interval
    verdict           n too small to call | within noise | the interval excludes 0
    pass count        cases at or above --threshold (default 1.0) per arm, with
                      the --interval-method interval (default normal)
    judge agreement   with --grader-agreement: per llm grader, how often its
                      judge votes agreed, read from votes the result holds

A partial result prints one line and nothing else. Score intervals are always
normal; --interval-method changes only the pass-count interval. The reasons are
in plugins/evals/skills/methodology/reference/local-decisions.md, "Interval
method".

Exit codes:

    0  the report printed
    2  usage error, or the result file is missing, unreadable, or not JSON
"""

import argparse
import json
import math
import sys

MIN_PYTHON = (3, 8)

Z95 = 1.959963984540054
MIN_CASES = 3
CEILING = 0.95
ARMS = ("with", "without")  # cases[].arms.<arm>[]

# Result-file field paths read here that the plugin-evals docs page does not
# name. Correct them in this block, and nowhere else, if a real result file
# shows another shape. Every lookup is tolerant: a missing field never raises.
CASE_GRADER_DEFS = "graders"  # cases[].graders[]: name, type, weight
RUN_SCORE = "score"  # cases[].arms.<arm>[].score
RUN_GRADERS = "graders"  # cases[].arms.<arm>[].graders[]
GRADER_NAME = "name"  # graders[].name, the join key to the case definition
GRADER_TYPE = "type"  # cases[].graders[].type
GRADER_PASSED = "passed"  # cases[].arms.<arm>[].graders[].passed
GRADER_WEIGHT = "weight"  # graders[].weight, run result first, then definition
GRADER_SCORED = "scored"  # cases[].arms.<arm>[].graders[].scored, true when absent
# Judge votes on an llm grader's run result. judgeVotes is the key
# reading-results.md records from measured files; the others are read in case
# a later schema renames it. A grader holding none of these keys counts as
# holding no votes.
GRADER_VOTES = ("judgeVotes", "votes", "judge_votes")  # graders[].<key>[]
VOTE_VERDICT = ("passed", "pass", "verdict", "vote")  # a vote that is an object


def mean(values):
    return sum(values) / len(values)


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def definitions(case):
    defs = case.get(CASE_GRADER_DEFS)
    if not isinstance(defs, list):
        return {}
    return {d.get(GRADER_NAME): d for d in defs if isinstance(d, dict)}


def grader_weight(grader, defs):
    weight = grader.get(GRADER_WEIGHT)
    if not is_number(weight):
        weight = defs.get(grader.get(GRADER_NAME), {}).get(GRADER_WEIGHT)
    return float(weight) if is_number(weight) and weight > 0 else 1.0


def recomputed_score(run, defs):
    """Weighted fraction of scored graders passed, or None with nothing to score."""
    graders = run.get(RUN_GRADERS)
    graders = (
        [g for g in graders if isinstance(g, dict)] if isinstance(graders, list) else []
    )
    scored = [g for g in graders if g.get(GRADER_SCORED) is not False]
    total = sum(grader_weight(g, defs) for g in scored)
    if not total:
        return None
    return (
        sum(grader_weight(g, defs) for g in scored if g.get(GRADER_PASSED) is True)
        / total
    )


def run_score(run, defs, where, notes):
    """The run's reported score, cross-checked against its graders; recomputed when absent."""
    reported = run.get(RUN_SCORE)
    computed = recomputed_score(run, defs)
    if not is_number(reported):
        return computed
    if computed is not None and abs(reported - computed) > 1e-6:
        notes.append(
            "score check: %s reports %.2f, its graders give %.2f; the reported score is used"
            % (where, reported, computed)
        )
    return float(reported)


def arm_runs(case, arm):
    arms = case.get("arms")
    runs = arms.get(arm) if isinstance(arms, dict) else None
    return (
        [run for run in runs if isinstance(run, dict)] if isinstance(runs, list) else []
    )


def incomparable(case):
    """Why a case's arms cannot be compared, or None when they can."""
    for arm in ARMS:
        for index, run in enumerate(arm_runs(case, arm), 1):
            if run.get("error") is not None:
                return "%s-arm run %d ended with an error" % (arm, index)
            if run.get("skippedPaidGraders") is True:
                return "%s-arm run %d skipped its paid graders" % (arm, index)
    aggregates = case.get("aggregates")
    if (
        arm_runs(case, "without")
        and isinstance(aggregates, dict)
        and "score" in aggregates
        and "delta" not in aggregates
    ):
        return "the result omits its delta"
    return None


def case_score(case, arm, notes):
    """Mean run score for one arm; None when the arm has no runs or a run has no score."""
    defs = definitions(case)
    scores = [
        run_score(
            run, defs, "case %s, %s-arm run %d" % (case.get("name"), arm, index), notes
        )
        for index, run in enumerate(arm_runs(case, arm), 1)
    ]
    if not scores or None in scores:
        return None
    return mean(scores)


def normal_interval(values, low, high):
    """Mean and 95% normal-approximation interval, clamped to [low, high]."""
    m = mean(values)
    sd = math.sqrt(sum((v - m) ** 2 for v in values) / (len(values) - 1))
    half = Z95 * sd / math.sqrt(len(values))
    return m, max(low, m - half), min(high, m + half)


def beta_cf(a, b, x):
    """Continued fraction for the regularized incomplete beta function."""
    tiny = 1e-300
    c, d = 1.0, 1.0 - (a + b) * x / (a + 1.0)
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 300):
        for numerator in (
            m * (b - m) * x / ((a + 2 * m - 1) * (a + 2 * m)),
            -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 2 * m + 1)),
        ):
            d = 1.0 + numerator * d
            d = 1.0 / (d if abs(d) > tiny else tiny)
            c = 1.0 + numerator / c
            c = c if abs(c) > tiny else tiny
            h *= d * c
        if abs(d * c - 1.0) < 1e-12:
            break
    return h


def beta_cdf(x, a, b):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    front = math.exp(
        math.lgamma(a + b)
        - math.lgamma(a)
        - math.lgamma(b)
        + a * math.log(x)
        + b * math.log(1.0 - x)
    )
    if x < (a + 1.0) / (a + b + 2.0):
        return front * beta_cf(a, b, x) / a
    return 1.0 - front * beta_cf(b, a, 1.0 - x) / b


def beta_quantile(q, a, b):
    lo, hi = 0.0, 1.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        if beta_cdf(mid, a, b) < q:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def proportion_interval(k, n, method):
    """95% interval on k passes out of n by the named method."""
    p = k / n
    if method == "wilson":
        z2 = Z95 * Z95
        denom = 1.0 + z2 / n
        center = (p + z2 / (2 * n)) / denom
        half = Z95 * math.sqrt(p * (1 - p) / n + z2 / (4 * n * n)) / denom
        return max(0.0, center - half), min(1.0, center + half)
    if method == "jeffreys":
        lo = 0.0 if k == 0 else beta_quantile(0.025, k + 0.5, n - k + 0.5)
        hi = 1.0 if k == n else beta_quantile(0.975, k + 0.5, n - k + 0.5)
        return lo, hi
    half = Z95 * math.sqrt(p * (1 - p) / n)
    return max(0.0, p - half), min(1.0, p + half)


def pass_count_line(arm, scores, threshold, method):
    k = sum(1 for s in scores if s >= threshold - 1e-9)
    lo, hi = proportion_interval(k, len(scores), method)
    return (
        "%s-arm pass count at threshold %.2f: %d of %d, 95%% interval %.2f to %.2f (%s)"
        % (
            arm,
            threshold,
            k,
            len(scores),
            lo,
            hi,
            method,
        )
    )


def arm_line(arm, scores):
    if len(scores) < 2:
        return "%s-arm mean: %.2f (%d case; an interval needs 2 or more)" % (
            arm,
            mean(scores),
            len(scores),
        )
    m, lo, hi = normal_interval(scores, 0.0, 1.0)
    return "%s-arm mean: %.2f, 95%% interval %.2f to %.2f (normal, %d cases)" % (
        arm,
        m,
        lo,
        hi,
        len(scores),
    )


def paired_delta(deltas):
    n = len(deltas)
    lines = []
    if n >= 2:
        m, lo, hi = normal_interval(deltas, -1.0, 1.0)
        lines.append(
            "delta (with minus without), paired over %d cases: %+.2f, 95%% interval %+.2f to %+.2f"
            % (n, m, lo, hi)
        )
    if n < MIN_CASES:
        lines.append(
            "verdict: n too small to call (comparable cases: %d; %d or more are needed)"
            % (n, MIN_CASES)
        )
    elif len(set(round(d, 9) for d in deltas)) == 1:
        lines.append(
            "verdict: n too small to call (every per-case delta is %+.2f, so the interval has zero width)"
            % deltas[0]
        )
    elif lo <= 0 <= hi:
        lines.append("verdict: within noise (the interval contains 0)")
    else:
        lines.append(
            "verdict: the interval excludes 0, so the difference is larger than the noise at %d cases"
            % n
        )
    return lines


def vote_value(vote):
    """True for a PASS vote, False for a FAIL vote, None when unreadable."""
    if isinstance(vote, dict):
        vote = next((vote[key] for key in VOTE_VERDICT if key in vote), None)
    if isinstance(vote, bool):
        return vote
    if isinstance(vote, str) and vote.strip().upper() in ("PASS", "FAIL"):
        return vote.strip().upper() == "PASS"
    return None


def run_votes(grader):
    """The grader's readable votes, or None when it holds none."""
    for key in GRADER_VOTES:
        raw = grader.get(key)
        if isinstance(raw, list) and raw:
            votes = [vote_value(vote) for vote in raw]
            return None if None in votes else votes
    return None


def agreement(cases):
    """One judge-agreement line per llm grader, read from votes the result holds."""
    tallies, judged = {}, False
    for case in cases:
        defs = definitions(case)
        for arm in ARMS:
            for run in arm_runs(case, arm):
                for grader in run.get(RUN_GRADERS) or []:
                    if not isinstance(grader, dict):
                        continue
                    name = grader.get(GRADER_NAME)
                    kind = defs.get(name, {}).get(GRADER_TYPE, grader.get(GRADER_TYPE))
                    votes = run_votes(grader)
                    if kind != "llm" and not (kind is None and votes):
                        continue
                    judged = True
                    if votes:
                        tallies.setdefault((case.get("name"), name), []).append(votes)
    if not judged:
        return ["no llm grader in this result, so there is no judge agreement to read"]
    if not tallies:
        return ["the result file holds no judge votes, so agreement cannot be read"]
    lines = []
    for (case_name, name), runs in tallies.items():
        unanimous = sum(1 for votes in runs if len(set(votes)) == 1)
        matching = sum(
            sum(1 for vote in votes if vote == (2 * sum(votes) >= len(votes)))
            for votes in runs
        )
        lines.append(
            "judge agreement: case %s, grader %s: unanimous in %d of %d runs"
            " (%d of %d votes match their run's majority)"
            % (
                case_name,
                name,
                unanimous,
                len(runs),
                matching,
                sum(len(v) for v in runs),
            )
        )
    return lines


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            "error: noise-report needs Python %d.%d or newer\n" % MIN_PYTHON
        )
        return 2
    parser = argparse.ArgumentParser(
        prog="noise-report",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("result", help="path to aggregate-result.json")
    parser.add_argument(
        "--threshold", type=float, default=1.0, help="case pass threshold (default 1.0)"
    )
    parser.add_argument(
        "--interval-method",
        default="normal",
        help="interval on the pass count: normal (default), wilson or jeffreys;"
        " any other value falls back to normal",
    )
    parser.add_argument(
        "--grader-agreement",
        action="store_true",
        help="report judge-vote agreement per llm grader",
    )
    args = parser.parse_args(argv)
    try:
        with open(args.result, encoding="utf-8") as handle:
            result = json.load(handle)
    except (OSError, ValueError) as error:
        sys.stderr.write("error: cannot read %s (%s)\n" % (args.result, error))
        return 2
    if not isinstance(result, dict):
        sys.stderr.write("error: %s is not a result document\n" % args.result)
        return 2
    if result.get("partial") is True:
        print(
            "partial result (%s): the suite did not finish, so no noise line is computed;"
            " keep this result out of any trend" % result.get("partialReason")
        )
        return 0
    method = args.interval_method
    lines = []
    if method not in ("normal", "wilson", "jeffreys"):
        lines.append(
            "interval method %r is not normal, wilson or jeffreys; using normal"
            % method
        )
        method = "normal"
    lines += report(result, args.threshold, method)
    if args.grader_agreement:
        cases = result.get("cases")
        lines += agreement(
            [c for c in cases if isinstance(c, dict)] if isinstance(cases, list) else []
        )
    for line in lines:
        print(line)
    return 0


def report(result, threshold, method):
    cases = result.get("cases")
    cases = [c for c in cases if isinstance(c, dict)] if isinstance(cases, list) else []
    lines, notes, rows = [], [], []
    two_arm = any(arm_runs(case, "without") for case in cases)
    for case in cases:
        reason = incomparable(case)
        if reason is None and two_arm and not arm_runs(case, "without"):
            reason = "no without-arm runs for this case"
        row = {arm: case_score(case, arm, notes) for arm in ARMS}
        if reason is None and row["with"] is None:
            reason = "a with-arm run has no score to read"
        if reason is None and arm_runs(case, "without") and row["without"] is None:
            reason = "a without-arm run has no score to read"
        if reason is not None:
            lines.append("not comparable: case %s (%s)" % (case.get("name"), reason))
            continue
        rows.append(row)
    lines.extend(notes)
    scores = {arm: [row[arm] for row in rows if row[arm] is not None] for arm in ARMS}
    if not scores["with"]:
        lines.append("no comparable case in this result, so there is nothing to report")
        return lines
    for arm in ARMS:
        if scores[arm]:
            lines.append(arm_line(arm, scores[arm]))
    if is_number(result.get("costUsd")):
        lines.append(
            "cost: %.2f USD for the whole suite (list-price estimate)"
            % result["costUsd"]
        )
    if scores["without"]:
        baseline = mean(scores["without"])
        if baseline >= CEILING:
            lines.append(
                "near ceiling: without-arm mean %.2f is at or above %.2f;"
                " the baseline leaves no headroom" % (baseline, CEILING)
            )
        pairs = [row for row in rows if row["without"] is not None]
        lines.extend(paired_delta([row["with"] - row["without"] for row in pairs]))
    else:
        lines.append("no without-arm runs in this result, so there is no delta to read")
    for arm in ARMS:
        if scores[arm]:
            lines.append(pass_count_line(arm, scores[arm], threshold, method))
    return lines


if __name__ == "__main__":
    sys.exit(main())
