#!/usr/bin/env python3
"""calibrate-judge - measure an llm grader against labeled answers.

    calibrate-judge build --suite <eval dir> --out <dir> [--case <glob>] [--grader <glob>]
    calibrate-judge score --manifest <file> <aggregate-result.json>

An llm grader judges the agent's final message. `build` turns every labeled
sample of every llm grader (`<case>/samples/<grader>.json`, the `pass` and
`fail` lists validate-cases.py reads) into one calibration case whose agent
replies with that sample verbatim, so the judge's verdict on the case is its
verdict on the sample. `score` compares those verdicts with the labels.

build writes, under --out (which must be empty or absent):

    .claude-plugin/plugin.json   an empty plugin, so `claude plugin eval <out>`
                                 runs the suite with no skill to fire
    evals/<case>/prompt.md       the source case's prompt, unchanged, as the
                                 user turn; the sample and the instruction to
                                 reproduce it ride in append_system_prompt
    evals/<case>/graders/<g>.md  the source llm grader, copied as is
    manifest.json                generated case -> source case, grader, sample
                                 index, expected PASS or FAIL, and the sample

The label never reaches the generated files: a must-pass and a must-fail case
differ only in the sample text, and case names are numbered by a hash of the
sample, not by label. The generated suite is then checked with
validate-cases.py; build fails if that reports a FAIL.

An empty or whitespace-only sample is skipped, with one stderr line per sample:
Claude Code answers an empty reply with an injected user turn, so the agent
would answer the real prompt, and an empty answer is a deterministic failure
that needs no judge.

An llm grader whose focus is a file, the created-file list, or mock calls is
skipped: the agent's reply cannot stand in for those. A `trace` focus is kept
with a warning, since the calibration trace carries no tool calls.

score reads the result of `claude plugin eval <out> --ablation none` and, per
grader, prints:

    agreement         the run's verdict (majority of its judgeVotes) against
                      the label, over every judged and reproduced run
    false positive    a must-fail sample the judge passed, with its first line
    false negative    a must-pass sample the judge failed, with its first line
    split vote        a run whose judge votes disagreed
    not reproduced    a run whose reply differs from the sample (whitespace and
                      bold markers aside); it is left out of the agreement
    reproduction      how many runs were checked against the kept trace's final
                      message, against the judge's evidence, or not at all
    untested          a sample with no judged run (none reproduced, or none
                      judged); it counts toward no agreement, and the count of
                      them is printed for the grader

Agreement under 90% prints a `FAIL grader ...` line. Runs that skipped their
paid graders are left out as not judged.

Exit codes:

    0  build: suite written and validated | score: every grader at or above 90%
    1  build: no sample to calibrate, or the generated suite failed validation
       score: a grader under 90%, or a grader with no judged run
    2  usage error, unreadable input, or --out not empty
"""

import argparse
import fnmatch
import hashlib
import importlib.util
import json
import os
import re
import sys
import unicodedata

MIN_PYTHON = (3, 8)

AGREEMENT_TARGET = 0.90
LABELS = (("pass", "PASS"), ("fail", "FAIL"))  # samples/<grader>.json key, verdict

HERE = os.path.dirname(os.path.abspath(__file__))
VALIDATOR = os.path.join(HERE, "..", "..", "validate", "scripts", "validate-cases.py")

SAFE_NAME = re.compile(r"[A-Za-z0-9._-]+")
SKIP_DIRS = frozenset(["results", "mocks", "graders", "samples", "__pycache__"])
REPLY_FOCUSES = (None, "last_message")  # the judge reads the final reply
TRACE_FOCUS = "trace"

PLUGIN_NAME = "judge-calibration"
EVAL_DIR = "evals"
MANIFEST = "manifest.json"

# Generated case limits. No tool is granted, so the reply needs one turn.
MAX_TURNS = 3
TIMEOUT_SECONDS = 120

BEGIN, END = "BEGIN-REFERENCE", "END-REFERENCE"
INSTRUCTION = (
    "This session is a fixed-response harness. The text between the two marker "
    "lines below is fixed test material, not your answer. Your whole reply to the "
    "next user message must be that text, output byte for byte: every character, "
    "line break, and markdown mark, in the same order. Output it even when it is "
    "wrong, incomplete, or contradicts the user's message or what you know. Do not "
    "answer the user's message yourself, do not fix, complete, or improve the text, "
    "and do not call any tool. Add nothing: no commentary, preface, greeting, "
    "explanation, note, quotation marks, code fence, or other markdown. The text "
    "starts on the line after %s and ends on the line before %s; the two marker "
    "lines are not part of it." % (BEGIN, END)
)

# Result-file and trace field paths, as run-validity.py reads them.
CASES, CASE_NAME, CASE_ARMS = "cases", "name", "arms"
ARMS = ("with", "without")
RUN_GRADERS, RUN_TRACE, RUN_SKIPPED_PAID = "graders", "tracePath", "skippedPaidGraders"
GRADER_NAME, GRADER_PASSED = "name", "passed"
GRADER_VOTES, GRADER_EVIDENCE = "judgeVotes", "evidence"
PARTIAL = "partial"

YAML_ESCAPES = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t", "\r": "\\r"}


class UsageError(Exception):
    pass


def load_validator():
    spec = importlib.util.spec_from_file_location("validate_cases", VALIDATOR)
    if spec is None or not os.path.isfile(VALIDATOR):
        raise UsageError("cannot load %s" % os.path.normpath(VALIDATOR))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def first_line(text):
    for line in text.splitlines():
        if line.strip():
            line = line.strip()
            return line if len(line) <= 80 else line[:77] + "..."
    return "(empty)"


def same_text(a, b):
    """Equal once bold markers (** and __) are dropped, runs of whitespace are
    collapsed and the ends trimmed: an agent that adds bold to a heading has
    still reproduced the sample's words."""

    def plain(text):
        return " ".join(text.replace("**", "").replace("__", "").split())

    return plain(a) == plain(b)


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------


def yaml_quoted(text):
    """One double-quoted YAML scalar on one line, in validate-cases.py's subset."""
    out = []
    for char in text:
        if char in YAML_ESCAPES:
            out.append(YAML_ESCAPES[char])
        elif unicodedata.category(char) == "Cc":
            raise ValueError("control character U+%04X" % ord(char))
        else:
            out.append(char)
    return '"%s"' % "".join(out)


def system_prompt(sample):
    return "%s\n%s\n%s\n%s" % (INSTRUCTION, BEGIN, sample, END)


def split_body(text):
    """(frontmatter or None, body) of a markdown file."""
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                return "\n".join(lines[1:index]), "\n".join(lines[index + 1 :])
    return None, text


def source_prompt(case_dir, validator):
    """The prompt the source case sends: prompt.md's body, else execution.prompt."""
    prompt_md = os.path.join(case_dir, "prompt.md")
    if os.path.isfile(prompt_md):
        return split_body(read_text(prompt_md))[1].strip("\n")
    data = validator.parse_yaml(read_text(os.path.join(case_dir, "case.yaml")))
    execution = data.get("execution")
    prompt = execution.get("prompt") if isinstance(execution, dict) else None
    return prompt.strip("\n") if isinstance(prompt, str) else ""


def llm_graders(case_dir, validator, notes, case):
    """(name, focus, grader file text) for every llm grader in the case."""
    found = []
    yaml_path = os.path.join(case_dir, "case.yaml")
    if os.path.isfile(yaml_path):
        data = validator.parse_yaml(read_text(yaml_path))
        for entry in data.get("graders") or []:
            if isinstance(entry, dict) and entry.get("type") == "llm":
                name = str(entry.get("name"))
                if not SAFE_NAME.fullmatch(name) or name in (".", ".."):
                    notes.append(
                        "skip %s/case.yaml grader %r: a grader name must be one path "
                        "segment of letters, digits, '.', '_' or '-'" % (case, name)
                    )
                    continue
                lines = ["---", "type: llm"]
                for key in ("focus", "weight", "arm"):
                    if isinstance(entry.get(key), (str, int, float)):
                        lines.append("%s: %s" % (key, entry[key]))
                body = "\n".join(lines + ["---", "", str(entry.get("criteria", ""))])
                found.append((name, entry.get("focus"), body + "\n"))
    grader_dir = os.path.join(case_dir, "graders")
    for filename in sorted(os.listdir(grader_dir)) if os.path.isdir(grader_dir) else []:
        if not filename.endswith(".md"):
            continue
        text = read_text(os.path.join(grader_dir, filename))
        block, _ = split_body(text)
        try:
            options = validator.parse_yaml(block or "")
        except validator.ParseError as error:
            notes.append("skip %s/graders/%s: %s" % (case, filename, error.construct))
            continue
        if options.get("type") == "llm":
            found.append((filename[:-3], options.get("focus"), text))
    return found


def discover(suite):
    cases = []
    for dirpath, dirnames, filenames in os.walk(suite):
        dirnames[:] = sorted(
            d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")
        )
        if dirpath != suite and ("prompt.md" in filenames or "case.yaml" in filenames):
            cases.append(dirpath)
            dirnames[:] = []
    return sorted(cases)


def samples_for(case_dir, grader, notes, case):
    """[(label key, 1-based index, answer, why)] from samples/<grader>.json."""
    path = os.path.join(case_dir, "samples", grader + ".json")
    if not os.path.isfile(path):
        return []
    try:
        data = json.loads(read_text(path))
    except (OSError, ValueError) as error:
        notes.append("skip %s/samples/%s.json: %s" % (case, grader, error))
        return []
    out = []
    for key, _ in LABELS:
        items = data.get(key) if isinstance(data, dict) else None
        for index, item in enumerate(items if isinstance(items, list) else [], 1):
            answer = item.get("answer") if isinstance(item, dict) else None
            if not isinstance(answer, str):
                notes.append(
                    "skip %s/%s must-%s sample %d: answer is not text"
                    % (case, grader, key, index)
                )
                continue
            if not answer.strip():
                notes.append(
                    "skip %s/%s must-%s sample %d: empty answer; an empty answer "
                    "is a deterministic failure that needs no judge"
                    % (case, grader, key, index)
                )
                continue
            out.append((key, index, answer, item.get("why", "")))
    return out


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def prompt_md(sample, prompt):
    return (
        "---\n"
        'description: "Judge calibration case; its source and label are in the manifest"\n'
        "max_turns: %d\n"
        "timeout_seconds: %d\n"
        "allowed_tools: []\n"
        "append_system_prompt: %s\n"
        "---\n\n%s\n"
        % (MAX_TURNS, TIMEOUT_SECONDS, yaml_quoted(system_prompt(sample)), prompt)
    )


def build(args):
    validator = load_validator()
    suite = os.path.abspath(args.suite)
    out = os.path.abspath(args.out)
    if not os.path.isdir(suite):
        raise UsageError("not a directory: %s" % args.suite)
    if os.path.exists(out) and (not os.path.isdir(out) or os.listdir(out)):
        raise UsageError("--out must be empty or absent: %s" % args.out)

    notes, entries, groups = [], [], []
    for case_dir in discover(suite):
        case = os.path.relpath(case_dir, suite).replace(os.sep, "/")
        if args.case and not (
            fnmatch.fnmatchcase(case, args.case)
            or fnmatch.fnmatchcase(os.path.basename(case_dir), args.case)
        ):
            continue
        try:
            graders = llm_graders(case_dir, validator, notes, case)
            prompt = source_prompt(case_dir, validator)
        except validator.ParseError as error:
            notes.append("skip %s: case.yaml not parsed (%s)" % (case, error.construct))
            continue
        if graders and not prompt.strip():
            notes.append("skip %s: the case has no prompt text" % case)
            continue
        for grader, focus, grader_text in graders:
            if args.grader and not fnmatch.fnmatchcase(grader, args.grader):
                continue
            samples = samples_for(case_dir, grader, notes, case)
            if not samples:
                continue
            if focus not in REPLY_FOCUSES and focus != TRACE_FOCUS:
                notes.append(
                    "skip %s/%s: focus %s is not the reply, so a reproduced "
                    "answer cannot stand in for it" % (case, grader, json.dumps(focus))
                )
                continue
            if focus == TRACE_FOCUS:
                notes.append(
                    "warn %s/%s: focus trace; the calibration trace holds the "
                    "reply and no tool calls, unlike a real run" % (case, grader)
                )
            answers = {}
            for key, _, answer, _ in samples:
                answers.setdefault(" ".join(answer.split()), set()).add(key)
            if any(len(keys) > 1 for keys in answers.values()):
                notes.append(
                    "warn %s/%s: the same answer is labeled both pass and fail"
                    % (case, grader)
                )
            ordered = sorted(
                samples,
                key=lambda s: (
                    hashlib.sha256(s[2].encode("utf-8")).hexdigest(),
                    s[0],
                    s[1],
                ),
            )
            stem = "%s--%s" % (case.replace("/", "__"), grader)
            count = {"pass": 0, "fail": 0}
            for number, (key, index, answer, why) in enumerate(ordered, 1):
                name = "%s--%02d" % (stem, number)
                try:
                    text = prompt_md(answer, prompt)
                except ValueError as error:
                    notes.append(
                        "skip %s/%s must-%s sample %d: %s"
                        % (case, grader, key, index, error)
                    )
                    continue
                write(os.path.join(out, EVAL_DIR, name, "prompt.md"), text)
                write(
                    os.path.join(out, EVAL_DIR, name, "graders", grader + ".md"),
                    grader_text,
                )
                count[key] += 1
                entries.append(
                    {
                        "case": name,
                        "sourceCase": case,
                        "grader": grader,
                        "focus": focus or "last_message",
                        "label": key,
                        "sampleIndex": index,
                        "expected": dict(LABELS)[key],
                        "why": why,
                        "answer": answer,
                    }
                )
            groups.append((case, grader, count))

    for note in notes:
        sys.stderr.write(note + "\n")
    if not entries:
        print("no labeled sample of an llm grader matched; nothing written")
        return 1

    write(
        os.path.join(out, ".claude-plugin", "plugin.json"),
        json.dumps(
            {
                "name": PLUGIN_NAME,
                "description": "Generated judge-calibration suite; holds no components",
            },
            indent=2,
        )
        + "\n",
    )
    write(
        os.path.join(out, MANIFEST),
        json.dumps(
            {"schemaVersion": 1, "suite": suite, "evalDir": EVAL_DIR, "cases": entries},
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
    )

    print(
        "wrote %d calibration cases to %s" % (len(entries), os.path.join(out, EVAL_DIR))
    )
    for case, grader, count in groups:
        print(
            "  %s/%s: %d (%d must-pass, %d must-fail)"
            % (
                case,
                grader,
                count["pass"] + count["fail"],
                count["pass"],
                count["fail"],
            )
        )
    print("manifest: %s" % os.path.join(out, MANIFEST))

    findings = validator.validate(os.path.join(out, EVAL_DIR))
    failed = [f for f in findings if f.level == "FAIL"]
    for finding in failed:
        print("  " + finding.line())
    print(
        "validate-cases: %s (%d FAIL, %d WARN)"
        % (
            "FAIL" if failed else "PASS",
            len(failed),
            sum(1 for f in findings if f.level == "WARN"),
        )
    )
    if failed:
        return 1
    print(
        "run:   claude plugin eval %s --trust-plugin --ablation none --threshold 0 "
        "--runs 3 --judge-model <the judge model the suite runs with> --keep-temp "
        "--no-publish --json %s" % (out, os.path.join(out, "results.json"))
    )
    print(
        "score: python3 %s score --manifest %s %s"
        % (
            os.path.abspath(__file__),
            os.path.join(out, MANIFEST),
            os.path.join(out, "results.json"),
        )
    )
    return 0


# --------------------------------------------------------------------------
# score
# --------------------------------------------------------------------------


def load_json(path, what):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as error:
        raise UsageError("cannot read %s %s (%s)" % (what, path, error))
    if not isinstance(data, dict):
        raise UsageError("%s %s is not a JSON object" % (what, path))
    return data


def trace_reply(path):
    """The final message of a kept trace, or None when the trace cannot be read."""
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
    except OSError:
        return None
    if not lines:
        return None
    for line in reversed(lines):
        if line.get("type") == "result" and isinstance(line.get("result"), str):
            return line["result"]
    for line in reversed(lines):
        message = line.get("message") if line.get("type") == "assistant" else None
        content = message.get("content") if isinstance(message, dict) else None
        texts = [
            b.get("text", "")
            for b in content or []
            if isinstance(b, dict) and b.get("type") == "text"
        ]
        if texts:
            return "".join(texts)
    return ""


def verdict(grader):
    """('PASS' | 'FAIL', votes list or None) for one grader result."""
    votes = grader.get(GRADER_VOTES)
    if isinstance(votes, list) and votes:
        passes = sum(1 for v in votes if v is True)
        return ("PASS" if passes * 2 > len(votes) else "FAIL"), votes
    return ("PASS" if grader.get(GRADER_PASSED) is True else "FAIL"), None


def vote_text(votes):
    return " ".join("PASS" if v is True else "FAIL" for v in votes)


class Tally:
    def __init__(self, key):
        self.key = key
        self.agree = self.judged = 0
        self.samples = set()
        self.expected = []
        self.fp, self.fn, self.split, self.unreproduced = [], [], [], []
        self.unchecked = []
        self.missing, self.not_judged, self.no_grader = [], [], []
        self.checked = {"trace": 0, "judge evidence": 0, "unchecked": 0}


def describe(entry):
    return 'must-%s sample %d: "%s"' % (
        entry["label"],
        entry["sampleIndex"],
        first_line(entry["answer"]),
    )


def score_run(tally, entry, run, where, base):
    graders = run.get(RUN_GRADERS) if isinstance(run.get(RUN_GRADERS), list) else []
    grader = next(
        (
            g
            for g in graders
            if isinstance(g, dict) and g.get(GRADER_NAME) == entry["grader"]
        ),
        None,
    )
    if grader is None:
        tally.no_grader.append(where)
        return
    if run.get(RUN_SKIPPED_PAID) is True:
        tally.not_judged.append(where)
        return

    reply, source = None, "unchecked"
    trace = run.get(RUN_TRACE)
    if isinstance(trace, str) and trace:
        reply = trace_reply(
            trace if os.path.isabs(trace) else os.path.join(base, trace)
        )
        source = "trace" if reply is not None else source
    evidence = grader.get(GRADER_EVIDENCE)
    if reply is None and entry["focus"] != TRACE_FOCUS and isinstance(evidence, str):
        reply, source = evidence, "judge evidence"
    tally.checked[source] += 1
    if reply is None:
        tally.unchecked.append(where)
    if reply is not None and not same_text(reply, entry["answer"]):
        tally.unreproduced.append(
            '%s: reply begins "%s" (%s)' % (where, first_line(reply), source)
        )
        return

    said, votes = verdict(grader)
    sample = describe(entry)
    votes_note = "votes " + vote_text(votes) if votes else "no judgeVotes, read passed"
    tally.judged += 1
    tally.samples.add(entry["case"])
    if said == entry["expected"]:
        tally.agree += 1
    elif said == "PASS":
        tally.fp.append("%s (%s) %s" % (where, sample, votes_note))
    else:
        tally.fn.append("%s (%s) %s" % (where, sample, votes_note))
    if votes and len(set(v is True for v in votes)) > 1:
        tally.split.append(
            "%s: %s, %s the label"
            % (
                where,
                vote_text(votes),
                "agrees with" if said == entry["expected"] else "misses",
            )
        )


def score(args):
    manifest = load_json(args.manifest, "manifest")
    result = load_json(args.result, "result")
    entries = manifest.get("cases")
    if not isinstance(entries, list) or not entries:
        raise UsageError("manifest %s lists no cases" % args.manifest)
    base = os.path.dirname(os.path.abspath(args.result))
    by_name = {
        c.get(CASE_NAME): c for c in result.get(CASES) or [] if isinstance(c, dict)
    }

    tallies = {}
    for entry in entries:
        key = "%s/%s" % (entry["sourceCase"], entry["grader"])
        tally = tallies.setdefault(key, Tally(key))
        tally.expected.append((entry["case"], describe(entry)))
        case = by_name.get(entry["case"])
        if case is None:
            tally.missing.append(entry["case"])
            continue
        arms = case.get(CASE_ARMS) if isinstance(case.get(CASE_ARMS), dict) else {}
        for arm in ARMS:
            for index, run in enumerate(arms.get(arm) or [], 1):
                if isinstance(run, dict):
                    where = "%s %s-arm run %d" % (entry["case"], arm, index)
                    score_run(tally, entry, run, where, base)

    if result.get(PARTIAL) is True:
        print("note: the result is partial (%s)" % result.get("partialReason"))
    unknown = sorted(n for n in by_name if n not in {e["case"] for e in entries})
    if unknown:
        print("note: %d result cases are not in the manifest" % len(unknown))

    failed, untested_total = [], 0
    for key in sorted(tallies):
        t = tallies[key]
        untested = [(c, d) for c, d in t.expected if c not in t.samples]
        untested_total += len(untested)
        if t.judged:
            rate = t.agree / t.judged
            line = "agreement %d/%d runs (%.1f%%) over %d samples" % (
                t.agree,
                t.judged,
                100 * rate,
                len(t.samples),
            )
        else:
            rate, line = None, "no judged run"
        print("grader %s: %s" % (key, line))
        for label, items in (
            ("false positive", t.fp),
            ("false negative", t.fn),
            ("split vote", t.split),
            ("not reproduced, left out", t.unreproduced),
            ("reproduction unchecked, no trace or evidence", t.unchecked),
            ("not judged, paid graders skipped", t.not_judged),
            ("grader missing from run", t.no_grader),
            ("missing from the result", t.missing),
        ):
            for item in items:
                print("  %s: %s" % (label, item))
        print(
            "  reproduction: %d checked against traces, %d against judge evidence, "
            "%d unchecked"
            % (t.checked["trace"], t.checked["judge evidence"], t.checked["unchecked"])
        )
        print(
            "  samples with no reproduced run: %d of %d"
            % (len(untested), len(t.expected))
        )
        for name, text in untested:
            print("  untested: %s (%s), counted in no agreement" % (name, text))
        if rate is None or rate < AGREEMENT_TARGET - 1e-9:
            failed.append(key)
            print(
                "FAIL grader %s: %s under the %d%% target"
                % (
                    key,
                    "no judged run is"
                    if rate is None
                    else "agreement %.1f%% is" % (100 * rate),
                    round(100 * AGREEMENT_TARGET),
                )
            )
    note = "; %d untested" % untested_total if untested_total else ""
    if failed:
        print("verdict: FAIL (%s)%s" % (", ".join(failed), note))
        return 1
    print(
        "verdict: PASS (every grader at or above %d%%%s)"
        % (round(100 * AGREEMENT_TARGET), note)
    )
    return 0


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            "error: calibrate-judge needs Python %d.%d or newer\n" % MIN_PYTHON
        )
        return 2
    parser = argparse.ArgumentParser(
        prog="calibrate-judge",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command")
    b = sub.add_parser("build", help="write a calibration suite and its manifest")
    b.add_argument("--suite", required=True, help="the eval dir holding the cases")
    b.add_argument("--out", required=True, help="an empty or absent output dir")
    b.add_argument("--case", help="only source cases whose name matches this glob")
    b.add_argument("--grader", help="only llm graders whose name matches this glob")
    s = sub.add_parser("score", help="compare judge verdicts with the labels")
    s.add_argument("--manifest", required=True, help="the manifest build wrote")
    s.add_argument("result", help="aggregate-result.json of the calibration run")
    try:
        args = parser.parse_args(argv)
    except SystemExit as error:
        return 0 if error.code == 0 else 2
    if args.command is None:
        parser.print_usage(sys.stderr)
        return 2
    try:
        return build(args) if args.command == "build" else score(args)
    except UsageError as error:
        sys.stderr.write("error: %s\n" % error)
        return 2


if __name__ == "__main__":
    sys.exit(main())
