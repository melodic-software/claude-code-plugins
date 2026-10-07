#!/usr/bin/env python3
"""run-validity - decide whether a `claude plugin eval` run's score may count.

    run-validity <aggregate-result.json> --runs N

--runs is the run count the eval was invoked with (its --runs, else the case
default). Reads the result file and, where each run's tracePath resolves, the
kept trace (`--keep-temp`). A relative tracePath or suite root is read relative
to the result file. Prints one line per check, detail lines indented under it:

    complete          partial is false
    paid graders      no run skipped its paid graders
    run errors        no run errored, aborted, or ended its trace in an error
    row count         every case holds N rows per arm; runsPerCase is ignored
    traces            how many tracePaths resolve, and what that leaves unchecked
    permission denials  no denied tool call in any trace; a denial is a warning
                      when that run scores the same as every denial-free run
                      of its case in the same arm (there must be one), since
                      it then left the score unchanged. A with-arm denial aimed
                      at or under the plugin's directory (suite.root or a
                      suite.plugins path), at a directory above it, or with
                      no absolute path or no known plugin directory, is
                      always a FAIL
    skill fired       every with-arm run of a should-trigger case fired the skill
    models            the model and judge model, where the result or traces
                      carry them; runs that disagree are a FAIL
    judge votes       a split llm judge vote is a warning
    ceiling           a case whose without-arm is already 1.00 is a warning and
                      is left out of the delta

The last line is `verdict: VALID` or `verdict: INVALID` with its reasons. A
FAIL, or a check that could not run (UNCHECKED), makes the run INVALID; a WARN
does not.

A should-trigger case has a `tool_used` grader on the Skill tool that requires a
call. A case is a no-trigger control, and exempt, when its prompt.md tags or
description mark it one, or it has a max-0 Skill grader with no input_match (or one
aimed at the plugin's own skills) and no grader requiring a call.

Exit codes:

    0  VALID
    1  INVALID
    2  usage error, or the result file is missing, unreadable, or not JSON
"""

import argparse
import json
import os
import re
import sys

MIN_PYTHON = (3, 8)

FULL_SCORE = 1.0
ARMS = ("with", "without")  # cases[].arms.<arm>[]
ONE_ARM_ABLATION = "none"  # suite.ablation value that runs the with-arm only

# Result-file field paths. Correct them in this block, and nowhere else, if a
# real result file shows another shape. Every lookup is tolerant: a missing
# field never raises.
PARTIAL = "partial"
PARTIAL_REASON = "partialReason"
CLAUDE_VERSION = "claudeVersion"
SUITE = "suite"
SUITE_ROOT = "root"  # suite.root, the directory case dirs are relative to
SUITE_ABLATION = "ablation"  # suite.ablation
SUITE_PLUGINS, PLUGIN_PATH = "plugins", "path"  # suite.plugins[].path
CASES = "cases"
CASE_NAME = "name"
CASE_DIR = "dir"  # cases[].dir, relative to suite.root
CASE_PROMPT = "prompt.md"  # <suite.root>/<dir>/prompt.md, its frontmatter
CASE_RUNS_STATED = "runsPerCase"  # the case default, not the run count
CASE_ARMS = "arms"
CASE_GRADER_DEFS = "graders"  # cases[].graders[]: name, type, config
GRADER_CONFIG = "config"  # cases[].graders[].config
CONFIG_TOOL, CONFIG_MIN, CONFIG_MAX = "tool", "min", "max"
CONFIG_INPUT_MATCH = "input_match"
RUN_ERROR = "error"  # cases[].arms.<arm>[].error, null when the run ended normally
RUN_ABORTED = "aborted"  # present when a mock stopped the run
RUN_SKIPPED_PAID = "skippedPaidGraders"
RUN_SCORE = "score"
RUN_TRACE = "tracePath"  # absent or deleted unless the run passed --keep-temp
RUN_GRADERS = "graders"  # cases[].arms.<arm>[].graders[]
GRADER_NAME = "name"
GRADER_TYPE = "type"
GRADER_PASSED = "passed"
GRADER_VOTES = "judgeVotes"  # llm graders: one boolean per vote
# The result file names neither model as of Claude Code 2.1.287; these keys are
# read at the top level and under suite in case a later schema adds them.
MODEL_KEYS = ("model",)
JUDGE_MODEL_KEYS = ("judgeModel", "judge_model")

# Trace (out/trace.jsonl) shapes, one JSON object per line.
LINE_TYPE, LINE_SUBTYPE = "type", "subtype"
TRACE_INIT = ("system", "init")  # type, subtype of the line carrying the model
TRACE_MODEL = "model"
TRACE_RESULT = "result"  # type of the closing line
TRACE_RESULT_ERROR = "is_error"
TRACE_DENIALS = "permission_denials"  # on the result line
DENIAL_TOOL, DENIAL_ID, DENIAL_INPUT = "tool_name", "tool_use_id", "tool_input"
MESSAGE, CONTENT, BLOCK_TYPE = "message", "content", "type"  # message.content[].type
TOOL_USE, USE_ID, USE_NAME, USE_INPUT = "tool_use", "id", "name", "input"
TOOL_RESULT, RESULT_USE_ID, RESULT_ERROR = "tool_result", "tool_use_id", "is_error"
DENIAL_TEXT = "denied by your permission settings"  # in an is_error tool_result
# The input a denial line prints: Read's file, or Grep's and Glob's search root,
# else the call's first input value.
TARGET_KEYS = ("file_path", "path")

# The suite's skill-fired convention and the no-trigger control markers.
SKILL_TOOL = "Skill"
FIRE_GRADER_TYPE = "tool_used"
CONTROL_TAGS = ("control", "no-trigger", "negative-control")
CONTROL_DESCRIPTION = re.compile(
    r"\bno[- ]trigger\b|\bwithout invoking\b|\bmust not (?:fire|trigger|invoke)\b",
    re.IGNORECASE,
)

PASS, WARN, FAIL, UNCHECKED = "PASS", "WARN", "FAIL", "UNCHECKED"


def as_list(value):
    return [v for v in value if isinstance(v, dict)] if isinstance(value, list) else []


def as_dict(value):
    return value if isinstance(value, dict) else {}


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def resolve(path, base):
    if not isinstance(path, str) or not path:
        return None
    return path if os.path.isabs(path) else os.path.join(base, path)


def plural(n, word):
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


def where(case, arm, index):
    return "case %s, %s-arm run %d" % (case.get(CASE_NAME), arm, index)


class Run:
    def __init__(self, case, arm, index, row, base):
        self.case, self.arm, self.row = case, arm, row
        self.where = where(case, arm, index)
        self.trace_path = resolve(row.get(RUN_TRACE), base)
        self.trace = read_trace(self.trace_path) if self.trace_path else None


def read_trace(path):
    """The trace's JSON lines, or None when the file cannot be read or holds none."""
    try:
        with open(path, encoding="utf-8") as handle:
            lines = []
            for text in handle:
                try:
                    line = json.loads(text)
                except ValueError:
                    continue
                if isinstance(line, dict):
                    lines.append(line)
            return lines or None
    except OSError:
        return None


def frontmatter(path):
    """description and tags from a prompt.md, or {} when it cannot be read."""
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, TypeError):
        return {}
    parts = text.split("---", 2)
    if not text.startswith("---") or len(parts) < 3:
        return {}
    fields, key = {"tags": []}, None
    for line in parts[1].splitlines():
        item = re.match(r"\s*-\s+(.+)", line)
        if item and key == "tags":
            fields["tags"].append(item.group(1).strip().strip("'\""))
            continue
        pair = re.match(r"(\w+):\s*(.*)", line)
        if not pair:
            continue
        key, value = pair.group(1), pair.group(2).strip()
        if key == "tags" and value.startswith("["):
            fields["tags"] = [
                t.strip().strip("'\"") for t in value.strip("[]").split(",")
            ]
        elif key == "description":
            fields["description"] = value.strip("'\"")
    return fields


def grader_input_match(case, grader, root):
    """A grader's input_match, from the result config or its graders/<name>.md."""
    config = as_dict(grader.get(GRADER_CONFIG))
    if isinstance(config.get(CONFIG_INPUT_MATCH), str):
        return config[CONFIG_INPUT_MATCH]
    case_dir, name = case.get(CASE_DIR), grader.get(GRADER_NAME)
    if not root or not isinstance(case_dir, str) or not isinstance(name, str):
        return None
    path = os.path.join(root, case_dir, "graders", name + ".md")
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError:
        return None
    parts = text.split("---", 2)
    if not text.startswith("---") or len(parts) < 3:
        return None
    pair = re.search(r"^input_match:\s*(.+?)\s*$", parts[1], re.MULTILINE)
    if not pair:
        return None
    value = pair.group(1)
    if value.startswith('"'):
        try:
            return json.loads(value)
        except ValueError:
            return value.strip('"')
    return value.strip("'")


def targets_own_skills(pattern, root):
    """True when pattern matches a Skill call to one of this plugin's own skills."""
    if not root:
        return False
    try:
        names = os.listdir(os.path.join(root, "skills"))
        found = re.compile(pattern)
    except (OSError, re.error):
        return False
    plugin = os.path.basename(os.path.normpath(root))
    return any(
        found.search(json.dumps({"skill": skill}))
        for name in names
        for skill in (name, "%s:%s" % (plugin, name))
    )


def skill_graders(case, root):
    """(names of graders requiring a Skill call, True when an unscoped one forbids a call).

    A max-0 grader is unscoped when it has no input_match or its input_match targets
    this plugin's own skills; a guard on another skill does not make a control.
    """
    requiring, forbids = [], False
    for grader in as_list(case.get(CASE_GRADER_DEFS)):
        config = as_dict(grader.get(GRADER_CONFIG))
        if (
            grader.get(GRADER_TYPE) != FIRE_GRADER_TYPE
            or config.get(CONFIG_TOOL) != SKILL_TOOL
        ):
            continue
        if config.get(CONFIG_MAX) == 0:
            pattern = grader_input_match(case, grader, root)
            if pattern is None or targets_own_skills(pattern, root):
                forbids = True
        elif not (is_number(config.get(CONFIG_MIN)) and config[CONFIG_MIN] < 1):
            requiring.append(grader.get(GRADER_NAME))
    return requiring, forbids


def is_control(case, root):
    """Control: tagged or described as one, else it forbids own-skill calls and
    requires none (a should-trigger case may also carry a max-0 guard)."""
    case_dir = case.get(CASE_DIR)
    if root and isinstance(case_dir, str):
        fields = frontmatter(os.path.join(root, case_dir, CASE_PROMPT))
        tags = [t.lower() for t in fields.get("tags", [])]
        if any(t in CONTROL_TAGS for t in tags) or CONTROL_DESCRIPTION.search(
            fields.get("description", "")
        ):
            return True
    requiring, forbids = skill_graders(case, root)
    return forbids and not requiring


def check_complete(result, runs):
    if not runs:
        return (
            FAIL,
            "the result holds no runs",
            [],
            "the result holds no runs, so nothing was measured",
        )
    if result.get(PARTIAL) is True:
        return (
            FAIL,
            "partial is true (%s): the suite did not finish"
            % result.get(PARTIAL_REASON),
            [],
            "the run is partial (%s)" % result.get(PARTIAL_REASON),
        )
    return PASS, "partial is false", [], None


def check_paid(runs):
    hits = [r.where for r in runs if r.row.get(RUN_SKIPPED_PAID) is True]
    if hits:
        return (
            FAIL,
            "%s skipped paid graders" % plural(len(hits), "run"),
            hits,
            (
                "%s skipped paid graders, which then score as failures"
                % plural(len(hits), "run")
            ),
        )
    return PASS, "no run skipped its paid graders", [], None


def check_errors(runs):
    details = []
    for r in runs:
        if r.row.get(RUN_ERROR) is not None:
            details.append("%s: error %s" % (r.where, r.row.get(RUN_ERROR)))
        if r.row.get(RUN_ABORTED):
            details.append(
                "%s: aborted %s" % (r.where, json.dumps(r.row.get(RUN_ABORTED)))
            )
        if r.trace and any(
            line.get(LINE_TYPE) == TRACE_RESULT and line.get(TRACE_RESULT_ERROR) is True
            for line in r.trace
        ):
            details.append(
                "%s: its trace ends in an error (%s)" % (r.where, r.trace_path)
            )
    if details:
        count = plural(len(details), "run error")
        return FAIL, count, details, count
    return PASS, "no run errored or aborted", [], None


def check_rows(cases, runs_wanted, arms):
    details, per_case = [], set()
    for case in cases:
        for arm in arms:
            count = len(as_list(as_dict(case.get(CASE_ARMS)).get(arm)))
            if count != runs_wanted:
                details.append(
                    "case %s, %s-arm: %s, --runs asked for %d"
                    % (case.get(CASE_NAME), arm, plural(count, "row"), runs_wanted)
                )
        per_case.add(case.get(CASE_RUNS_STATED))
    ignored = ""
    stated = [v for v in per_case if v is not None]
    if any(v != runs_wanted for v in stated):
        ignored = "; runsPerCase reads %s and is not used" % ", ".join(
            str(v) for v in sorted(stated, key=str)
        )
    if details:
        return (
            FAIL,
            "%s off the requested count%s" % (plural(len(details), "arm"), ignored),
            details,
            "%s hold a row count other than --runs %d"
            % (plural(len(details), "arm"), runs_wanted),
        )
    return (
        PASS,
        "%s per arm in every case, as --runs %d asked%s"
        % (plural(runs_wanted, "row"), runs_wanted, ignored),
        [],
        None,
    )


def denials(run):
    """Every denied tool call in one trace, keyed by tool_use_id, as (detail line,
    target path or None)."""
    calls, found = {}, {}
    for line in run.trace:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) == TOOL_USE:
                calls[block.get(USE_ID)] = (
                    block.get(USE_NAME),
                    as_dict(block.get(USE_INPUT)),
                )
            elif (
                block.get(BLOCK_TYPE) == TOOL_RESULT
                and block.get(RESULT_ERROR) is True
                and DENIAL_TEXT in json.dumps(block.get(CONTENT))
            ):
                found.setdefault(block.get(RESULT_USE_ID), None)
        if line.get(LINE_TYPE) == TRACE_RESULT:
            for denial in as_list(line.get(TRACE_DENIALS)):
                found[denial.get(DENIAL_ID)] = (
                    denial.get(DENIAL_TOOL),
                    as_dict(denial.get(DENIAL_INPUT)),
                )
    out = []
    for use_id, call in found.items():
        name, tool_input = call or calls.get(use_id, (None, {}))
        path = next((tool_input[k] for k in TARGET_KEYS if k in tool_input), None)
        target = path if path is not None else next(iter(tool_input.values()), "")
        out.append(
            (
                "%s: %s %s (%s)" % (run.where, name or "tool", target, run.trace_path),
                path if isinstance(path, str) else None,
            )
        )
    return out


def inside(path, roots):
    """True unless path is rooted and neither under nor above any plugin root.
    An ancestor of a root covers the plugin's files, so it counts as inside; so
    do no path, a relative path and no known root. Rooted, not isabs: on Windows
    /tmp/x has no drive, so Python 3.13+ isabs calls it relative, yet it names
    one place on the current drive. A root on another drive cannot hold path.
    Symlinks resolve on both sides."""
    rooted = os.path.splitdrive(path or "")[1][:1] in (os.sep, os.altsep)
    if not rooted or not roots:
        return True
    path = os.path.realpath(path)
    drive = os.path.normcase(os.path.splitdrive(path)[0])
    return any(
        os.path.commonpath([path, r]) in (path, r)
        for r in (os.path.realpath(root) for root in roots)
        if os.path.normcase(os.path.splitdrive(r)[0]) == drive
    )


def same_as_clean(run, found, runs, roots):
    """True when a denied run scores the same as every denial-free run of its case
    in the same arm, the case has at least one, every sibling in that arm has a
    readable trace, and no with-arm denial is aimed inside the plugin."""
    if run.arm == "with" and any(inside(path, roots) for _, path in found[run]):
        return False
    siblings = [
        r for r in runs if r.case is run.case and r.arm == run.arm and r is not run
    ]
    if any(r not in found for r in siblings):
        return False
    score = run.row.get(RUN_SCORE)
    clean = [r.row.get(RUN_SCORE) for r in siblings if not found[r]]
    return (
        is_number(score)
        and bool(clean)
        and all(is_number(s) and abs(s - score) < 1e-9 for s in clean)
    )


def check_denials(runs, roots):
    traced = [r for r in runs if r.trace is not None]
    found = {r: denials(r) for r in traced}
    denied = [r for r in traced if found[r]]
    warned = [r for r in denied if same_as_clean(r, found, runs, roots)]
    failed = [r for r in denied if r not in warned]
    details = [line for r in denied for line, _ in found[r]]
    summary = "%s in %s" % (plural(len(details), "denial"), plural(len(denied), "run"))
    warned_cases = sorted({r.case.get(CASE_NAME) for r in warned}, key=str)
    if warned:
        summary += (
            "; runs scoring the same as their case's denial-free runs in the same"
            " arm, with no with-arm denial inside the plugin, are warnings: %s"
            % ", ".join(warned_cases)
        )
    if failed:
        reason = "%s in the traces" % plural(
            sum(len(found[r]) for r in failed), "permission denial"
        )
        if warned:
            reason += " (warnings only, not counted: case %s)" % ", ".join(warned_cases)
        return FAIL, summary, details, reason
    if warned and len(traced) == len(runs):
        return (
            WARN,
            summary,
            details,
            "permission denials in case %s" % ", ".join(warned_cases),
        )
    if len(traced) < len(runs):
        missing = len(runs) - len(traced)
        return (
            UNCHECKED,
            "%s; %s not read"
            % (
                summary if warned else "no denial in the %d traces read" % len(traced),
                plural(missing, "trace"),
            ),
            details,
            "permission denials unchecked in %s with no readable trace"
            % plural(missing, "run"),
        )
    return PASS, "no denied tool call in %s" % plural(len(traced), "trace"), [], None


def check_fired(cases, runs, root):
    unfired, unread, controls, unknown, checked = [], [], [], [], 0
    for case in cases:
        requiring, _ = skill_graders(case, root)
        if is_control(case, root):
            controls.append(case.get(CASE_NAME))
            continue
        if not requiring:
            unknown.append(case.get(CASE_NAME))
            continue
        for r in runs:
            if r.case is not case or r.arm != "with":
                continue
            results = {g.get(GRADER_NAME): g for g in as_list(r.row.get(RUN_GRADERS))}
            verdicts = [
                results[n].get(GRADER_PASSED) for n in requiring if n in results
            ]
            if not verdicts:
                unread.append("%s: no skill-fired grader result" % r.where)
            elif all(v is True for v in verdicts):
                checked += 1
            else:
                unfired.append("%s (%s)" % (r.where, r.trace_path or "no trace"))
    notes = []
    if controls:
        notes.append("exempt as no-trigger controls: %s" % ", ".join(controls))
    if unknown:
        notes.append("no skill-fired grader, so not checked: %s" % ", ".join(unknown))
    tail = ("; " + "; ".join(notes)) if notes else ""
    if unfired:
        return (
            FAIL,
            "%d of %d with-arm runs of should-trigger cases did not fire%s"
            % (len(unfired), len(unfired) + checked + len(unread), tail),
            ["unfired: " + u for u in unfired] + unread,
            (
                "the skill did not fire in %s of a should-trigger case"
                % plural(len(unfired), "with-arm run")
            ),
        )
    if unread:
        return (
            UNCHECKED,
            "%s carry no skill-fired result%s" % (plural(len(unread), "run"), tail),
            unread,
            "skill firing unchecked in %s" % plural(len(unread), "run"),
        )
    if unknown:
        return WARN, "fired in %s%s" % (plural(checked, "with-arm run"), tail), [], None
    return (
        PASS,
        "fired in all %s of should-trigger cases%s"
        % (plural(checked, "with-arm run"), tail),
        [],
        None,
    )


def recorded(result, keys):
    for scope in (result, as_dict(result.get(SUITE))):
        for key in keys:
            if isinstance(scope.get(key), str) and scope.get(key):
                return scope[key]
    return None


def check_models(result, runs):
    traced = [r for r in runs if r.trace is not None]
    models = {}
    for r in traced:
        for line in r.trace:
            if (line.get(LINE_TYPE), line.get(LINE_SUBTYPE)) == TRACE_INIT and line.get(
                TRACE_MODEL
            ):
                models.setdefault(line[TRACE_MODEL], []).append(r)
                break
    stated = recorded(result, MODEL_KEYS)
    if stated:
        models.setdefault(stated, [])
    judge = recorded(result, JUDGE_MODEL_KEYS)
    version = result.get(CLAUDE_VERSION) or "not recorded"
    judge_text = (
        "judge model %s" % judge
        if judge
        else "judge model not recorded in the result or the traces; record the --judge-model the run used"
    )
    if len(models) > 1:
        details = [
            "%s: %s" % (model, ", ".join(r.where for r in rs) or "the result file")
            for model, rs in sorted(models.items())
        ]
        return (
            FAIL,
            "runs used %d different models; %s" % (len(models), judge_text),
            details,
            ("runs used different models (%s)" % ", ".join(sorted(models))),
        )
    if not models:
        return (
            WARN,
            "model not recorded in the result or the traces; Claude Code %s; %s"
            % (version, judge_text),
            [],
            None,
        )
    ((model, rs),) = models.items()
    status = PASS if judge else WARN
    return (
        status,
        "model %s in %d of %d traces; Claude Code %s; %s"
        % (model, len(rs), len(runs), version, judge_text),
        [],
        None,
    )


def check_votes(runs):
    details = []
    for r in runs:
        for grader in as_list(r.row.get(RUN_GRADERS)):
            votes = grader.get(GRADER_VOTES)
            if isinstance(votes, list) and len(set(map(bool, votes))) > 1:
                details.append(
                    "%s, grader %s: %s"
                    % (
                        r.where,
                        grader.get(GRADER_NAME),
                        " ".join("PASS" if v else "FAIL" for v in votes),
                    )
                )
    if details:
        return (
            WARN,
            "%s; read its explanation and evidence before trusting it"
            % plural(len(details), "split vote"),
            details,
            None,
        )
    return PASS, "no split llm judge vote", [], None


def arm_score(case, arm):
    scores = [r.get(RUN_SCORE) for r in as_list(as_dict(case.get(CASE_ARMS)).get(arm))]
    if not scores or not all(is_number(s) for s in scores):
        return None
    return sum(scores) / len(scores)


def check_ceiling(cases, arms):
    if "without" not in arms:
        return PASS, "no without-arm in this run, so no ceiling to read", [], None
    at_ceiling, deltas = [], []
    for case in cases:
        with_score, without_score = arm_score(case, "with"), arm_score(case, "without")
        if without_score is None or with_score is None:
            continue
        if without_score >= FULL_SCORE - 1e-9:
            at_ceiling.append(case.get(CASE_NAME))
        else:
            deltas.append(with_score - without_score)
    if not at_ceiling:
        return PASS, "no case has its without-arm at 1.00", [], None
    rest = (
        "the delta over the other %s is %+.2f"
        % (plural(len(deltas), "case"), sum(deltas) / len(deltas))
        if deltas
        else "no case is left for a delta"
    )
    return (
        WARN,
        "without-arm already at 1.00 in %s; excluded from the delta, and %s"
        % (", ".join(at_ceiling), rest),
        [],
        None,
    )


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            "error: run-validity needs Python %d.%d or newer\n" % MIN_PYTHON
        )
        return 2
    parser = argparse.ArgumentParser(
        prog="run-validity",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("result", help="path to aggregate-result.json")
    parser.add_argument(
        "--runs",
        type=int,
        required=True,
        help="the run count the eval was invoked with",
    )
    args = parser.parse_args(argv)
    if args.runs < 1:
        sys.stderr.write("error: --runs must be 1 or more\n")
        return 2
    try:
        with open(args.result, encoding="utf-8") as handle:
            result = json.load(handle)
    except (OSError, ValueError) as error:
        sys.stderr.write("error: cannot read %s (%s)\n" % (args.result, error))
        return 2
    if not isinstance(result, dict):
        sys.stderr.write("error: %s is not a result document\n" % args.result)
        return 2

    base = os.path.dirname(os.path.abspath(args.result))
    suite = as_dict(result.get(SUITE))
    root = resolve(suite.get(SUITE_ROOT), base)
    plugin_roots = [
        os.path.normpath(p)
        for p in [root]
        + [
            resolve(plugin.get(PLUGIN_PATH), base)
            for plugin in as_list(suite.get(SUITE_PLUGINS))
        ]
        if p
    ]
    arms = ("with",) if suite.get(SUITE_ABLATION) == ONE_ARM_ABLATION else ARMS
    cases = as_list(result.get(CASES))
    runs = [
        Run(case, arm, index, row, base)
        for case in cases
        for arm in ARMS
        for index, row in enumerate(as_list(as_dict(case.get(CASE_ARMS)).get(arm)), 1)
    ]
    unresolved = [r for r in runs if r.trace is None]

    checks = [
        ("complete", check_complete(result, runs)),
        ("paid graders", check_paid(runs)),
        ("run errors", check_errors(runs)),
        ("row count", check_rows(cases, args.runs, arms)),
    ]
    lines = []
    for name, (status, summary, details, _) in checks:
        lines.append("check %s: %s (%s)" % (name, status, summary))
        lines += ["  " + d for d in details]
    if unresolved:
        lines.append(
            "traces: %d of %d tracePaths do not resolve (the run needs --keep-temp, and its"
            " directories must still exist); permission denials and the trace model are"
            " unchecked for those runs" % (len(unresolved), len(runs))
        )
        lines += [
            "  %s: %s" % (r.where, r.trace_path or "no tracePath") for r in unresolved
        ]
    else:
        lines.append("traces: %d of %d tracePaths resolve" % (len(runs), len(runs)))
    later = [
        ("permission denials", check_denials(runs, plugin_roots)),
        ("skill fired", check_fired(cases, runs, root)),
        ("models", check_models(result, runs)),
        ("judge votes", check_votes(runs)),
        ("ceiling", check_ceiling(cases, arms)),
    ]
    for name, (status, summary, details, _) in later:
        lines.append("check %s: %s (%s)" % (name, status, summary))
        lines += ["  " + d for d in details]
    checks += later

    reasons = [
        reason for _, (status, _, _, reason) in checks if status in (FAIL, UNCHECKED)
    ]
    warned = [
        reason or name for name, (status, _, _, reason) in checks if status == WARN
    ]
    for line in lines:
        print(line)
    if reasons:
        print("verdict: INVALID (%s)" % "; ".join(reasons))
        return 1
    print("verdict: VALID" + (" (warnings: %s)" % ", ".join(warned) if warned else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
