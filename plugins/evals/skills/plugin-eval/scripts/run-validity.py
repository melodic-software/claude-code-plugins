#!/usr/bin/env python3
"""run-validity - decide whether a `claude plugin eval` run's score may count.

    run-validity <aggregate-result.json> --runs N [--scaffolded] [--measured-fire CASE]...

--runs is the run count the eval was invoked with (its --runs, else the case
default). --scaffolded records that the eval was invoked with --scaffold, which
the result file does not record. --measured-fire names a should-trigger case
whose firing is the quantity a comparison measures, such as the base side of a
change that makes a skill fire; the skill-fired check reports its misses as a
measured rate, as for an invocation probe, and every other check is unchanged. Reads the result file, each case's case.yaml,
and, where each run's tracePath resolves, the kept trace (`--keep-temp`). A
relative tracePath or suite root is read relative to the result file. Prints
one line per check, detail lines indented under it:

    complete          partial is false
    paid graders      no run skipped its paid graders
    run errors        no run errored, aborted, or ended its trace in an error; in
                      an invocation-probe case, a max-turns error in a run whose
                      trace holds a Skill call is a warning, since the graded
                      call already happened
    row count         every case holds N rows per arm; runsPerCase is ignored. A
                      case whose case.yaml sets context.history_file and whose
                      result records no without-arm key at all ran single-arm by
                      design (a path target runs it with-arm only): a warning
                      with no delta. An empty or short without-arm still fails
    scaffold          no case sets context.scaffold_script in its case.yaml,
                      or the pass ran with --scaffold (--scaffolded); without
                      it, both arms of such a case ran in an empty workspace.
                      A case.yaml that cannot be located, read or parsed,
                      including a suite root or case dir that does not exist,
                      is UNCHECKED; an existing case dir with no case.yaml has
                      no script
    traces            how many tracePaths resolve, and what that leaves unchecked
    session started   no run ended at 0 turns with no run error, no failed Bash
                      result reports the sandbox failing to start, and no run of 2
                      or more Bash calls had every one fail with no output; each
                      means the run measured a session that never ran, or ran with
                      no working shell. A failed call that printed output ran in a
                      working shell, whatever its exit code. A 0-turn run whose
                      trace holds assistant messages ran in a forked session (a
                      slash-invoked `context: fork` skill) and passes
    permission denials  no denied tool call in any trace; a denial is a warning
                      when that run scores the same as every denial-free run
                      of its case in the same arm (there must be one), since
                      it then left the score unchanged, or when every run of
                      its case in both arms was denied the same named call
                      other than Skill (tool and target) with no absolute path
                      at, under or above the plugin's directory, since the
                      environment then denied it with or without the plugin,
                      such as a user-scope read of ~/.claude. A denial of a
                      named call other than Skill aimed only under the run's
                      own plugin-data directory (<sandbox>/config/plugins/data,
                      CLAUDE_PLUGIN_DATA), which the sandbox denies to any
                      skill that persists state, is always a warning and is
                      set aside before the rules here judge the run's other
                      denials, so it never counts toward a FAIL; so is a Read,
                      Grep or Glob aimed only under the session's own
                      <sandbox>/config/projects/*/*/tool-results/, where Claude
                      Code persists a large tool result the session already
                      received. The run's score was taken under such a denial,
                      so compare it only with runs denied the same way. Otherwise a
                      with-arm denial aimed at or under the plugin's
                      directory (suite.root or a
                      suite.plugins path), at a directory above it, or with
                      no absolute path or no known plugin directory, is
                      a FAIL; in an invocation-probe case a denial of a named
                      call other than Skill is a warning when it comes after
                      the graded Skill call, or the run is a should-not-fire
                      run that held while every denial-free run of its case
                      held; a should-fire miss with a denial takes the rules
                      above
    skill fired       every with-arm run of a should-trigger case fired the skill;
                      in an invocation-probe case, or one named by
                      --measured-fire, a miss is the trigger rate it measures,
                      reported per case and overall as a warning
    probe tools       no invocation-probe run's session could call Read, Glob,
                      Grep or Agent, which the emitted README removes with
                      --disallow-tools; one that could is a warning naming that
                      run line. A probe run whose init tools list cannot be read
                      is a warning; none readable is UNCHECKED
    models           the model and judge model, where the result or traces
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
aimed at the plugin's own skills) and no grader requiring a call. A case is an
invocation probe when its prompt.md tags include `invocation-probe`, as
skill-quality's `measure-invocation.sh emit-plugin-eval` writes them.

Exit codes:

    0  VALID
    1  INVALID
    2  usage error, or the result file is missing, unreadable, or not JSON
"""

import argparse
import json
import os
import posixpath
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
CASE_YAML = "case.yaml"  # <suite.root>/<dir>/case.yaml, absent for most cases
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
RUN_TURNS = "turns"  # 0 when the session never took a turn
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
TRACE_ASSISTANT = "assistant"  # type of a model message line, a forked session's too
TRACE_RESULT_ERROR = "is_error"
TRACE_DENIALS = "permission_denials"  # on the result line
# A run's plugin-data directory (CLAUDE_PLUGIN_DATA), under its sandbox, beside out/.
SANDBOX_PLUGIN_DATA = ("config", "plugins", "data")
# Where a run's session persists a large tool result it already received:
# <sandbox>/config/projects/<project>/<session>/tool-results/.
SANDBOX_PROJECTS, TOOL_RESULTS_DIR = ("config", "projects"), "tool-results"
TOOL_RESULTS_READERS = ("Read", "Grep", "Glob")
DENIAL_TOOL, DENIAL_ID, DENIAL_INPUT = "tool_name", "tool_use_id", "tool_input"
MESSAGE, CONTENT, BLOCK_TYPE = "message", "content", "type"  # message.content[].type
TOOL_USE, USE_ID, USE_NAME, USE_INPUT = "tool_use", "id", "name", "input"
TOOL_RESULT, RESULT_USE_ID, RESULT_ERROR = "tool_result", "tool_use_id", "is_error"
DENIAL_TEXT = "denied by your permission settings"  # in an is_error tool_result
# Anywhere in a trace line when the shell sandbox never started (Claude Code 2.1.310).
SANDBOX_FAILURE_TEXT = "Sandbox is required but failed to initialize"
# A run with at least this many Bash calls, every one failed with no output, had no
# working shell. Two, not one, so one silent failure does not flag a healthy run.
MIN_BASH_CALLS = 2
EXIT_LINE = re.compile(r"\AExit code -?\d+\s*")  # heads a failed Bash result's text
# The input a denial line prints: Read's file, or Grep's and Glob's search root,
# else the call's first input value.
TARGET_KEYS = ("file_path", "path")
BASH_TOOL, BASH_COMMAND = "Bash", "command"
# A Glob with no path searches where its pattern points: the guard checks the
# directory the pattern's literal part names, cut at its first glob character.
GLOB_TOOL, GLOB_PATTERN = "Glob", "pattern"
GLOB_CHAR = re.compile(r"[*?\[{]")
SHELL_SPLIT = re.compile(r"[<>|;&()'\"=]")  # where one shell word holds several
# A word the shell would expand, or a path packed after another character (/a,/b).
UNRESOLVED = re.compile(r"[$`*?\[{]|^~|[^\w./-]/")
# A path that resolves against the validator's own process, matched normalized.
OWN_PROCESS = re.compile(r"^/+(proc/(self|thread-self)|dev/fd)(/|$)")
# Same-command shell variables (shell_words): an unquoted NAME= opening a word,
# and a $NAME or ${NAME}.
SHELL_NAME = r"[A-Za-z_][A-Za-z0-9_]*"
ASSIGNMENT = re.compile(r"(%s)=" % SHELL_NAME)
EXPANSION = re.compile(r"\$(?:(%s)|\{(%s)\})" % (SHELL_NAME, SHELL_NAME))
# A value a later $NAME cannot stand for as one literal word: empty, or holding
# whitespace, an expansion, a glob or brace, a redirect, or a tilde the shell
# would expand.
UNRECORDED_VALUE = re.compile(r"\A\Z|[\s$`*?\[{<>]|\A~|:~")
# A command holding one of these can set or split a variable in a way not traced.
NO_RESOLVE = ("`", "<<", "IFS")
# Names the shell sets, ignores assignments to or holds readonly, so an earlier
# assignment does not fix their value.
SHELL_SET = frozenset(
    "_ PWD OLDPWD RANDOM SRANDOM SECONDS LINENO REPLY OPTARG OPTIND HISTCMD"
    " EPOCHSECONDS EPOCHREALTIME BASHPID PPID UID EUID GROUPS FUNCNAME"
    " SHELLOPTS MAPFILE PIPESTATUS DIRSTACK COPROC".split()
)
RESETS = ("eval", "source", ".")  # run other shell code, which may set any name
# Words opening or closing a compound command: an assignment inside one may not run.
COMPOUND = frozenset(
    "if then else elif fi while until for select do done case esac function { }".split()
)
# The operators after which an assignment that ran stays set in the shell.
KEEPS_ASSIGNMENT = (None, ";", "\n", "&&")
# A redirect word that names no file the command reads or writes: an fd
# duplication or close (2>&1, >&2, 2>&-) or a redirect to /dev/null, with or
# without its fd (>/dev/null, 2>/dev/null, &>/dev/null). A bare operator (2>)
# takes the next word as its operand, dropped only when it is /dev/null.
REDIRECT = re.compile(r"(?:\d*|&)(?:>>?|<)(&(?:\d+|-)|/dev/null)?")
DEV_NULL = "/dev/null"

# The suite's skill-fired convention and the no-trigger control markers.
SKILL_TOOL = "Skill"
FIRE_GRADER_TYPE = "tool_used"
CONTROL_TAGS = ("control", "no-trigger", "negative-control")
CONTROL_DESCRIPTION = re.compile(
    r"\bno[- ]trigger\b|\bwithout invoking\b|\bmust not (?:fire|trigger|invoke)\b",
    re.IGNORECASE,
)
# A trigger-measurement case (skill-quality's measure-invocation.sh
# emit-plugin-eval): a miss is the rate it measures, and a run that hit its turn
# cap after the Skill call was already graded.
PROBE_TAG = "invocation-probe"
# The whole error text, optionally after the runner's "exit N: " prefix.
MAX_TURNS_ERROR = re.compile(
    r"(?:exit \d+: )?Reached maximum number of turns \(\d+\)\.?"
)
TRACE_ERRORS = "errors"  # on the result line
TRACE_TOOLS = "tools"  # on the init line: the tools the session could call
# Tools emit-plugin-eval's README removes from a probe run with --disallow-tools.
# The init line names the Agent tool Task.
PROBE_REMOVED_TOOLS = ("Read", "Glob", "Grep", "Agent", "Task")

# A case.yaml context key (scaffold_script, history_file), in block or flow
# form, read without a YAML parser. Any uncommented mention of the key outside
# these shapes, a quoted key or an empty value continued on the next line among
# them, leaves the case UNCHECKED.
SCAFFOLD_SCRIPT, HISTORY_FILE = "scaffold_script", "history_file"
CONTEXT_BLOCK = re.compile(r"context:\s*(?:#.*)?")
CONTEXT_FLOW = re.compile(r"context:\s*\{(.*)\}\s*(?:#.*)?")
NO_VALUE = ("", "null", "~")

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


def prompt_fields(case, root):
    """The case's prompt.md frontmatter, tags lowercased, or {}."""
    case_dir = case.get(CASE_DIR)
    if not root or not isinstance(case_dir, str):
        return {}
    fields = frontmatter(os.path.join(root, case_dir, CASE_PROMPT))
    fields["tags"] = [t.lower() for t in fields.get("tags", [])]
    return fields


def is_probe(case, root):
    return PROBE_TAG in prompt_fields(case, root).get("tags", [])


def is_control(case, root):
    """Control: tagged or described as one, else it forbids own-skill calls and
    requires none (a should-trigger case may also carry a max-0 guard)."""
    fields = prompt_fields(case, root)
    if any(t in CONTROL_TAGS for t in fields.get("tags", [])) or (
        CONTROL_DESCRIPTION.search(fields.get("description", ""))
    ):
        return True
    requiring, forbids = skill_graders(case, root)
    return forbids and not requiring


def script_value(text):
    value = text.strip().strip("'\"")
    return None if value in NO_VALUE else value


def indent(line):
    return len(line) - len(line.lstrip())


def continues(lines, index):
    """True when the next line with content is indented past lines[index], so
    the key there holds a value this scanner does not read."""
    for line in lines[index + 1 :]:
        if line.strip() and not line.lstrip().startswith("#"):
            return indent(line) > indent(lines[index])
    return False


def scaffold_script(case, root):
    """(the case's context.scaffold_script or None, why its case.yaml could not
    be read or None)."""
    return context_value(case, root, SCAFFOLD_SCRIPT)


def context_value(case, root, key):
    """(the case's context.<key> or None, why its case.yaml could not be read or
    None). An existing case dir with no case.yaml has no value; a missing suite
    root or case dir leaves the case.yaml unread."""
    case_dir = case.get(CASE_DIR)
    if not root or not isinstance(case_dir, str) or not case_dir:
        return None, (
            "the result records no suite root or case dir, so its case.yaml"
            " cannot be located"
        )
    path = os.path.join(root, case_dir, CASE_YAML)
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except FileNotFoundError:
        if os.path.isdir(os.path.dirname(path)):
            return None, None
        return None, "case dir %s does not exist" % os.path.dirname(path)
    except (OSError, ValueError) as error:
        return None, "cannot read %s (%s)" % (path, error)
    if not re.search(r"^[^#\n]*" + key, text, re.MULTILINE):
        return None, None
    block_key = re.compile(r"\s+%s:\s*(.*?)\s*(?:#.*)?" % key)
    flow_key = re.compile(r"\b%s:\s*([^,}]*)" % key)
    lines = text.splitlines()
    in_context = False
    for index, line in enumerate(lines):
        flow = CONTEXT_FLOW.fullmatch(line)
        if flow:
            found = flow_key.search(flow.group(1))
            if found:
                return script_value(found.group(1)), None
            in_context = False
        elif CONTEXT_BLOCK.fullmatch(line):
            in_context = True
        elif line[:1] not in ("", " ", "\t", "#"):
            in_context = False
        elif in_context:
            found = block_key.fullmatch(line)
            if found:
                value = script_value(found.group(1))
                if value is None and continues(lines, index):
                    break
                return value, None
    return None, "%s names %s outside a context block this check reads" % (path, key)


def check_scaffold(cases, root, scaffolded):
    """A case whose case.yaml sets context.scaffold_script ran both arms in an
    empty workspace unless the eval ran with --scaffold, and the result file does
    not record whether it did, so --scaffolded is the operator's record of it."""
    declared, unread = {}, []
    for case in cases:
        script, problem = scaffold_script(case, root)
        if problem:
            unread.append("case %s: %s" % (case.get(CASE_NAME), problem))
        elif script:
            declared[str(case.get(CASE_NAME))] = script
    if declared and not scaffolded:
        return (
            FAIL,
            "%s set context.scaffold_script and --scaffolded is not passed, so both"
            " arms ran in an empty workspace; rerun with --scaffold, or pass"
            " --scaffolded if the eval had it" % plural(len(declared), "case"),
            ["case %s: scaffold_script %s" % item for item in declared.items()]
            + unread,
            "case %s never scaffolded: the pass records no --scaffold"
            % ", ".join(declared),
        )
    if unread:
        return (
            UNCHECKED,
            "%s whose case.yaml could not be read" % plural(len(unread), "case"),
            unread,
            "scaffold scripts unchecked in %s" % plural(len(unread), "case"),
        )
    if declared:
        return (
            PASS,
            "%s set context.scaffold_script, and --scaffolded records the pass ran"
            " with --scaffold" % plural(len(declared), "case"),
            [],
            None,
        )
    return PASS, "no case sets context.scaffold_script", [], None


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


def trace_errored(run):
    return bool(run.trace) and any(
        line.get(LINE_TYPE) == TRACE_RESULT and line.get(TRACE_RESULT_ERROR) is True
        for line in run.trace
    )


def is_denial(block):
    """True when a tool_result is the permission settings refusing the call."""
    return block.get(RESULT_ERROR) is True and DENIAL_TEXT in json.dumps(
        block.get(CONTENT)
    )


def has_output(content):
    """True when a tool_result's content holds text past a leading exit-code line,
    or a block other than text."""
    if isinstance(content, list):
        return any(
            has_output(b)
            if isinstance(b, str)
            else b.get(BLOCK_TYPE) != "text" or has_output(b.get("text"))
            for b in content
            if isinstance(b, (str, dict))
        )
    return isinstance(content, str) and bool(EXIT_LINE.sub("", content.strip()))


def shell_failure(run):
    """Why the run had no working shell, or None: a failed Bash result reporting the
    sandbox not starting, or every one of at least MIN_BASH_CALLS Bash calls failing
    with no output. A failed call that printed output ran, so the shell worked. A
    denied call never reached the shell, so it counts toward neither; check_denials
    judges it."""
    bash_ids, failed_ids = set(), set()
    for line in run.trace or []:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) == TOOL_USE and block.get(USE_NAME) == BASH_TOOL:
                bash_ids.add(block.get(USE_ID))
            elif (
                block.get(BLOCK_TYPE) == TOOL_RESULT
                and block.get(RESULT_ERROR) is True
                and block.get(RESULT_USE_ID) in bash_ids
            ):
                if is_denial(block):
                    bash_ids.discard(block.get(RESULT_USE_ID))
                    continue
                if SANDBOX_FAILURE_TEXT in json.dumps(block.get(CONTENT)):
                    return "the shell sandbox failed to start"
                if not has_output(block.get(CONTENT)):
                    failed_ids.add(block.get(RESULT_USE_ID))
    if len(bash_ids) >= MIN_BASH_CALLS and failed_ids == bash_ids:
        return "all %d Bash calls failed" % len(bash_ids)
    return None


def graded_call_made(run, root):
    """True when the case's own Skill grader registered the skill under test as
    called in this run: a grader requiring the call passed, or a max-0 grader
    forbidding it failed."""
    results = {g.get(GRADER_NAME): g for g in as_list(run.row.get(RUN_GRADERS))}
    for grader in as_list(run.case.get(CASE_GRADER_DEFS)):
        config = as_dict(grader.get(GRADER_CONFIG))
        if (
            grader.get(GRADER_TYPE) != FIRE_GRADER_TYPE
            or config.get(CONFIG_TOOL) != SKILL_TOOL
        ):
            continue
        passed = as_dict(results.get(grader.get(GRADER_NAME))).get(GRADER_PASSED)
        if config.get(CONFIG_MAX) == 0:
            if passed is False:
                return True
        elif passed is True:
            return True
    return False


def trace_errors(run):
    """Each error the trace's erroring result lines carry, as text."""
    out = []
    for line in run.trace or []:
        if line.get(LINE_TYPE) == TRACE_RESULT and line.get(TRACE_RESULT_ERROR) is True:
            errors = line.get(TRACE_ERRORS)
            for e in errors if isinstance(errors, list) else [errors]:
                out.append(e if isinstance(e, str) else json.dumps(e))
    return out


def check_errors(runs, root):
    """Every run error FAILs, except in an invocation-probe case whose run hit
    its turn cap after a Skill call: the graded call happened, so it warns."""
    details, failed = [], 0
    for r in runs:
        errors = []
        if r.row.get(RUN_ERROR) is not None:
            text = str(r.row.get(RUN_ERROR))
            errors.append(("%s: error %s" % (r.where, text), [text]))
        if r.row.get(RUN_ABORTED):
            errors.append(
                ("%s: aborted %s" % (r.where, json.dumps(r.row.get(RUN_ABORTED))), [])
            )
        if trace_errored(r):
            errors.append(
                (
                    "%s: its trace ends in an error (%s)" % (r.where, r.trace_path),
                    trace_errors(r),
                )
            )
        capped = bool(errors) and is_probe(r.case, root) and graded_call_made(r, root)
        for detail, texts in errors:
            # Exempt only when every error this detail carries is the turn cap.
            if (
                capped
                and texts
                and all(MAX_TURNS_ERROR.fullmatch(t.strip()) for t in texts)
            ):
                details.append(
                    detail + "; an invocation probe capped after its Skill call"
                )
            else:
                details.append(detail)
                failed += 1
    if failed:
        count = plural(failed, "run error")
        return FAIL, count, details, count
    if details:
        return (
            WARN,
            "%s, each an invocation probe hitting its turn cap after the Skill call"
            % plural(len(details), "run error"),
            details,
            "invocation probes capped at max turns after the Skill call",
        )
    return PASS, "no run errored or aborted", [], None


def assistant_messages(run):
    """How many assistant messages the run's trace holds, 0 with no trace."""
    return sum(1 for line in run.trace or [] if line.get(LINE_TYPE) == TRACE_ASSISTANT)


def check_started(runs):
    """A run at 0 turns that check_errors passes, or one whose trace shows the
    sandbox failing to start, scored a session that never ran or had no shell.
    A 0-turn run whose trace holds assistant messages ran in a forked session
    (a slash-invoked `context: fork` skill), which the turn count leaves out."""
    details, failed, forked = [], set(), []
    for r in runs:
        if (
            is_number(r.row.get(RUN_TURNS))
            and r.row[RUN_TURNS] == 0
            and r.row.get(RUN_ERROR) is None
            and not r.row.get(RUN_ABORTED)
            and not trace_errored(r)
        ):
            messages = assistant_messages(r)
            if messages:
                forked.append(
                    "%s: 0 turns, and its trace holds %s (%s)"
                    % (r.where, plural(messages, "assistant message"), r.trace_path)
                )
            else:
                details.append("%s: 0 turns and no run error" % r.where)
                failed.add(r)
        reason = shell_failure(r)
        if reason:
            details.append("%s: %s (%s)" % (r.where, reason, r.trace_path))
            failed.add(r)
    if details:
        count = plural(len(failed), "run")
        return (
            FAIL,
            "%s never started or had no sandbox" % count,
            details + forked,
            "harness failure: %s never started or had no sandbox, so the score"
            " measures the harness, not the skill" % count,
        )
    summary = "every run took a turn and no trace shows a sandbox failure"
    if forked:
        summary = (
            "every run ran and no trace shows a sandbox failure; %s at 0 turns ran"
            " in a forked session its trace holds" % plural(len(forked), "run")
        )
    return PASS, summary, forked, None


def single_arm(case, root):
    """True when the result records no without-arm for the case at all and its
    case.yaml sets context.history_file: claude plugin eval runs such a case
    with-arm only from a path target, whatever --ablation says."""
    if "without" in as_dict(case.get(CASE_ARMS)):
        return False
    return context_value(case, root, HISTORY_FILE)[0] is not None


def check_rows(cases, runs_wanted, arms, root):
    details, per_case, one_arm = [], set(), []
    for case in cases:
        for arm in arms:
            if arm == "without" and single_arm(case, root):
                one_arm.append(case.get(CASE_NAME))
                continue
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
    if one_arm:
        ignored += (
            "; single-arm by design (context.history_file, no without-arm recorded),"
            " so no delta: %s" % ", ".join(one_arm)
        )
    if details:
        return (
            FAIL,
            "%s off the requested count%s" % (plural(len(details), "arm"), ignored),
            details,
            "%s hold a row count other than --runs %d"
            % (plural(len(details), "arm"), runs_wanted),
        )
    if one_arm:
        return (
            WARN,
            "%s per arm as --runs %d asked%s"
            % (plural(runs_wanted, "row"), runs_wanted, ignored),
            [],
            "%s single-arm by design, with no delta" % plural(len(one_arm), "case"),
        )
    return (
        PASS,
        "%s per arm in every case, as --runs %d asked%s"
        % (plural(runs_wanted, "row"), runs_wanted, ignored),
        [],
        None,
    )


def rooted(path):
    """True when path starts at a root. Not isabs: on Windows /tmp/x has no
    drive, so Python 3.13+ isabs calls it relative, yet it names one place on the
    current drive."""
    return os.path.splitdrive(path or "")[1][:1] in (os.sep, os.altsep)


def shell_tokens(command):
    """A Bash command as tokens: ("op", text) for an unquoted ;, &, &&, |, ||, (,
    ) or newline, else ("word", parts), each part (text, quote), quote None for
    unquoted text, '"' for double-quoted text and "'" for text the shell takes as
    written (single quotes or a backslash escape). A & or | right after < or >,
    or a & before >, stays in its redirect's word. None when a quote is left open
    or a backslash ends the command."""
    tokens, parts, i, n = [], [], 0, len(command)

    def add(text, quote):
        if parts and parts[-1][1] == quote:
            parts[-1] = (parts[-1][0] + text, quote)
        else:
            parts.append((text, quote))

    def end_word():
        if parts:
            tokens.append(("word", parts[:]))
            parts.clear()

    while i < n:
        char = command[i]
        if char == "\\":
            if i + 1 == n:
                return None
            if command[i + 1] != "\n":
                add(command[i + 1], "'")
            i += 2
        elif char == "'":
            close = command.find("'", i + 1)
            if close < 0:
                return None
            add(command[i + 1 : close], "'")
            i = close + 1
        elif char == '"':
            i += 1
            add("", '"')
            while i < n and command[i] != '"':
                escaped = command[i + 1 : i + 2]
                if command[i] == "\\" and escaped in ("$", "`", '"', "\\", "\n"):
                    if escaped != "\n":
                        add(escaped, "'")
                    i += 2
                else:
                    add(command[i], '"')
                    i += 1
            if i >= n:
                return None
            i += 1
        elif char in " \t":
            end_word()
            i += 1
        elif char in "\n;&|()" and not (
            (
                char in "&|"
                and parts
                and parts[-1][1] is None
                and parts[-1][0].endswith(("<", ">"))
            )
            or command.startswith("&>", i)
        ):
            end_word()
            op = command[i : i + 2] if command[i : i + 2] in ("&&", "||") else char
            tokens.append(("op", op))
            i += len(op)
        else:
            add(char, None)
            i += 1
    end_word()
    return tokens


def assignment(parts):
    """The match of a word's opening unquoted NAME=, else None."""
    return ASSIGNMENT.match(parts[0][0]) if parts[0][1] is None else None


def expand(parts, names):
    """A word's text, each $NAME or ${NAME} outside single quotes replaced by
    names[NAME], one with no entry left as written."""
    return "".join(
        text
        if quote == "'"
        else EXPANSION.sub(lambda m: names.get(m.group(1) or m.group(2), m.group(0)), text)
        for text, quote in parts
    )


def shell_words(command):
    """A Bash command's words as (text, lead) pairs, quotes removed. A $NAME or
    ${NAME} outside single quotes takes the value of an earlier NAME=value in the
    same command when that assignment stands alone as a command the shell is sure
    to run in its own process (at the top level, first or after ;, a newline or
    an && whose left side was such an assignment, before any compound command or
    # comment) and its value is one literal word (UNRECORDED_VALUE). A later
    word that holds the name other than as $NAME or ${NAME}, an eval, source or
    ., or any assignment to it not recorded so drops the name, as in read NAME,
    printf -vNAME or ((NAME=1)). Every other expansion stays as written. lead marks each
    command's first word and each assignment, whose first piece names a command
    or a variable, not a path. None when the command does not parse."""
    tokens = shell_tokens(command)
    if tokens is None:
        return None
    names, words, simple = {}, [], []
    recording = not any(mark in command for mark in NO_RESOLVE)
    depth, certain, at_command = 0, True, True
    for kind, value in tokens + [("op", None)]:
        if kind == "word":
            simple.append(value)
            continue
        lead = at_command
        alone = bool(simple) and at_command and all(assignment(p) for p in simple)
        sure = alone and recording and depth == 0 and certain and value in KEEPS_ASSIGNMENT
        for parts in simple:
            match = assignment(parts) if lead else None
            if match:
                name = match.group(1)
                text = expand([(parts[0][0][match.end() :], None)] + parts[1:], names)
                words.append((name + "=" + text, True))
                names.pop(name, None)
                if (
                    sure
                    and name not in SHELL_SET
                    and not name.startswith("BASH")
                    and not UNRECORDED_VALUE.search(text)
                ):
                    names[name] = text
                continue
            raw = "".join(text for text, _ in parts)
            if lead and raw in RESETS:
                names.clear()
            if (lead and raw in COMPOUND) or (parts[0][1] is None and raw[:1] == "#"):
                recording = False
            mentions = EXPANSION.sub("", raw)
            for name in [name for name in names if name in mentions]:
                del names[name]
            words.append((expand(parts, names), lead))
            lead = False
        simple = []
        certain = value in (";", "\n", None) or (value == "&&" and certain and sure)
        if value == "(":
            depth += 1
        elif value == ")":
            depth = max(depth - 1, 0)
        at_command = value != ")"
    return words


def bash_paths(command):
    """The paths a Bash command names: each rooted word, split at quotes,
    redirects, pipes, parentheses and `=` so --flag=/x, >/x and '/x' count, after
    shell_words puts each same-command variable it resolves in place. A REDIRECT
    word naming no file (2>&1, 2>/dev/null) is dropped first. A word UNRESOLVED
    matches, a relative path with a slash or any word that is neither rooted, a
    flag nor the command or variable name opening a lead word (cwd-relative, so
    possibly the plugin), a path OWN_PROCESS matches, no rooted word, or a
    command that does not parse adds None, which inside() counts as inside."""
    words = shell_words(command) if isinstance(command, str) else None
    if not words:
        return (None,)
    kept, skip = [], False
    for index, (text, lead) in enumerate(words):
        if skip:
            skip = False
            continue
        redirect = REDIRECT.fullmatch(text)
        if redirect and redirect.group(1):
            continue
        if redirect and [w for w, _ in words[index + 1 : index + 2]] == [DEV_NULL]:
            skip = True
            continue
        kept.append((text, lead))
    words = kept
    if not words:
        return (None,)
    values = []
    for text, lead in words:
        first = lead and not SHELL_SPLIT.match(text)
        pieces = [v for v in SHELL_SPLIT.split(text) if v]
        values += [(v, first and k == 0) for k, v in enumerate(pieces)]
    paths = tuple(v for v, _ in values if rooted(v))
    unresolved = (
        any(UNRESOLVED.search(v) or (not rooted(v) and "/" in v) for v, _ in values)
        or any(not (lead or rooted(v) or v.startswith("-")) for v, lead in values)
        or any(OWN_PROCESS.search(posixpath.normpath(v)) for v in paths)
    )
    return paths + (None,) if unresolved or not paths else paths


def glob_root(pattern):
    """The directory a Glob pattern names before its first glob character: the
    pattern itself when it holds none, else the directory its literal part ends
    in, so /p/plug* gives /p, an ancestor of /p/plugin. None for a non-string."""
    if not isinstance(pattern, str):
        return None
    match = GLOB_CHAR.search(pattern)
    return pattern if match is None else os.path.dirname(pattern[: match.start()])


def denials(run):
    """Every denied tool call in one trace, keyed by tool_use_id, as (detail line,
    the paths it targets: a Bash call's rooted arguments, else the target path, a
    path-less Glob's pattern root (glob_root) or None, the tool's name, the
    tool_use_id, the (tool, target) pair that names the same call in another run)."""
    calls, found = {}, {}
    for line in run.trace:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) == TOOL_USE:
                calls[block.get(USE_ID)] = (
                    block.get(USE_NAME),
                    as_dict(block.get(USE_INPUT)),
                )
            elif block.get(BLOCK_TYPE) == TOOL_RESULT and is_denial(block):
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
        if name == BASH_TOOL:
            paths = bash_paths(tool_input.get(BASH_COMMAND))
        elif path is None and name == GLOB_TOOL:
            paths = (glob_root(tool_input.get(GLOB_PATTERN)),)
        else:
            paths = (path if isinstance(path, str) else None,)
        out.append(
            (
                "%s: %s %s (%s)" % (run.where, name or "tool", target, run.trace_path),
                paths,
                name,
                use_id,
                (name, json.dumps(target)),
            )
        )
    return out


def graded_call_at(run, root):
    """(tool_use_id -> position of each tool_use in the trace, position of the first
    Skill call a Skill grader's input_match accepts, or None)."""
    patterns = [
        grader_input_match(run.case, g, root)
        for g in as_list(run.case.get(CASE_GRADER_DEFS))
        if g.get(GRADER_TYPE) == FIRE_GRADER_TYPE
        and as_dict(g.get(GRADER_CONFIG)).get(CONFIG_TOOL) == SKILL_TOOL
    ]
    at, first = {}, None
    for line in run.trace:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) != TOOL_USE:
                continue
            at[block.get(USE_ID)] = len(at)
            text = json.dumps(as_dict(block.get(USE_INPUT)))
            if first is None and block.get(USE_NAME) == SKILL_TOOL:
                try:
                    if any(p is None or re.search(p, text) for p in patterns):
                        first = at[block.get(USE_ID)]
                except re.error:
                    pass
    return at, first


def inside(path, roots):
    """True unless path is rooted and neither under nor above any plugin root.
    An ancestor of a root covers the plugin's files, so it counts as inside; so
    do no path, a relative path, a path holding a NUL byte and no known root. A root on another drive
    cannot hold path. Symlinks resolve on both sides."""
    if not rooted(path) or not roots or "\0" in path:
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
    if run.arm == "with" and any(
        inside(path, roots) for _, paths, _, _, _ in found[run] for path in paths
    ):
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


def in_every_run(run, found, runs, roots):
    """True when every denial in run names a call that every run of its case, in
    both arms, was also denied, and none is aimed at, under or above the plugin's
    directory. The without-arm runs lack the plugin, so a call denied in every
    run of both arms is the environment's, such as a user-scope read a skill's
    contract asks for, and cannot move the delta. Each run of the case needs a
    readable trace. A Skill denial, or one naming no tool, never qualifies: in
    the with-arm it may have kept the plugin's own skill from loading."""
    case_runs = [r for r in runs if r.case is run.case]
    both_arms = {r.arm for r in case_runs} == set(ARMS)
    if not both_arms or any(r not in found for r in case_runs):
        return False
    if any(
        name in (None, SKILL_TOOL) or any(rooted(p) and inside(p, roots) for p in paths)
        for _, paths, name, _, _ in found[run]
    ):
        return False
    held = [{key for _, _, _, _, key in found[r]} for r in case_runs]
    return all(all(key in keys for keys in held) for _, _, _, _, key in found[run])


def sandbox_dir(run):
    """The run's sandbox, <sandbox> for a trace at <sandbox>/out/trace.jsonl; None
    for a trace anywhere else."""
    if not run.trace_path:
        return None
    out = os.path.dirname(os.path.realpath(run.trace_path))
    return os.path.dirname(out) if os.path.basename(out) == "out" else None


def own_data_dir(run):
    """The run's own plugin-data directory, <sandbox>/config/plugins/data, or None."""
    sandbox = sandbox_dir(run)
    return os.path.join(sandbox, *SANDBOX_PLUGIN_DATA) if sandbox else None


def in_tool_results(path, projects):
    """True when path is at or under <projects>/<project>/<session>/tool-results."""
    if not under(path, projects):
        return False
    rel = os.path.relpath(os.path.realpath(path), os.path.realpath(projects))
    parts = rel.split(os.sep)
    return len(parts) >= 3 and parts[2] == TOOL_RESULTS_DIR


def under(path, directory):
    """True when path is rooted and at or under directory, symlinks resolved."""
    if not rooted(path) or "\0" in path:
        return False
    path, directory = os.path.realpath(path), os.path.realpath(directory)
    try:
        return os.path.commonpath([path, directory]) == directory
    except ValueError:
        return False


def own_data_denial(run, denial):
    """True when the denial names a call other than Skill whose every target path
    is under the run's own plugin-data directory. The eval sandbox keeps that
    directory, where CLAUDE_PLUGIN_DATA points, out of reach, so a skill that
    persists state is denied there in every run whatever it does; no case or
    skill change can avoid it. A denial elsewhere in the run's config directory,
    or with no rooted path, never qualifies."""
    _, paths, name, _, _ = denial
    data = own_data_dir(run)
    return (
        bool(data)
        and name not in (None, SKILL_TOOL)
        and bool(paths)
        and all(under(p, data) for p in paths)
    )


def own_results_denial(run, denial):
    """True when the denial is a Read, Grep or Glob whose every target path is
    under the run's own config/projects/<project>/<session>/tool-results/. Claude
    Code writes a large tool result there and the model reads it back; the run's
    permission settings deny its config directory, so the read is denied whatever
    the case does. It reads only output the session already received, so it
    cannot add to what the model knows. Bash, a write, or any other path never
    qualifies."""
    _, paths, name, _, _ = denial
    sandbox = sandbox_dir(run)
    if not sandbox or name not in TOOL_RESULTS_READERS or not paths:
        return False
    projects = os.path.join(sandbox, *SANDBOX_PROJECTS)
    return all(in_tool_results(p, projects) for p in paths)


def probe_denial(run, found, runs, root):
    """True when a run of an invocation-probe case was denied only named calls other
    than Skill, none of which could have steered the graded decision. The probe
    grades only whether the Skill call fired, which loads the skill without Read,
    Glob or Grep. In a run where it fired, every denial must come after that call in
    the trace; a denial with no tool_use line has no position, so it does not
    qualify. In a should-fire run that missed, a denial may have caused the miss.
    A should-not-fire run that never fired decided over the whole run, so order
    cannot show the denial did not cause the hold; it qualifies only when its case
    has denial-free with-arm runs and every one of them held too. A denial naming
    no tool may have been the Skill call."""
    if not is_probe(run.case, root) or not all(
        name is not None and name != SKILL_TOOL for _, _, name, _, _ in found[run]
    ):
        return False
    if graded_call_made(run, root):
        at, first = graded_call_at(run, root)
        return first is not None and all(
            at.get(use_id, -1) > first for _, _, _, use_id, _ in found[run]
        )
    if skill_graders(run.case, root)[0]:
        return False
    clean = [
        r
        for r in runs
        if r.case is run.case and r.arm == run.arm and r in found and not found[r]
    ]
    return bool(clean) and not any(graded_call_made(r, root) for r in clean)


def probe_split(case, runs, found, root):
    """A detail line: how often a probe case's with-arm runs fired, denied versus
    denial-free, so a reader comparing two descriptions sees denials' effect."""
    arm = [r for r in runs if r.case is case and r.arm == "with" and r in found]
    denied = [r for r in arm if found[r]]
    clean = [r for r in arm if not found[r]]
    return "  probe case %s: fired in %d of %d denied with-arm runs, %d of %d clean" % (
        case.get(CASE_NAME),
        sum(graded_call_made(r, root) for r in denied),
        len(denied),
        sum(graded_call_made(r, root) for r in clean),
        len(clean),
    )


def check_denials(runs, roots, root):
    traced = [r for r in runs if r.trace is not None]
    every = {r: denials(r) for r in traced}
    # Plugin-data denials and reads of the session's own tool results are
    # environment: they warn and never count toward a FAIL, so every other rule
    # judges a run on the denials left.
    data = {r: [d for d in every[r] if own_data_denial(r, d)] for r in traced}
    results = {
        r: [d for d in every[r] if d not in data[r] and own_results_denial(r, d)]
        for r in traced
    }
    found = {
        r: [d for d in every[r] if d not in data[r] and d not in results[r]]
        for r in traced
    }
    denied = [r for r in traced if every[r]]
    warned = [
        r
        for r in denied
        if not found[r]
        or probe_denial(r, found, runs, root)
        or same_as_clean(r, found, runs, roots)
        or in_every_run(r, found, runs, roots)
    ]
    failed = [r for r in denied if r not in warned]
    details = [line for r in denied for line, _, _, _, _ in every[r]]
    summary = "%s in %s" % (plural(len(details), "denial"), plural(len(denied), "run"))
    set_aside = sum(len(data[r]) for r in denied)
    if set_aside:
        summary += "; %s under the run's own plugin-data directory, not counted" % plural(
            set_aside, "denial"
        )
    read_back = sum(len(results[r]) for r in denied)
    if read_back:
        summary += "; %s of the session's own tool results, not counted" % plural(
            read_back, "denied read"
        )
    warned_cases = sorted({r.case.get(CASE_NAME) for r in warned}, key=str)
    probe_cases = []
    for r in denied:
        if is_probe(r.case, root) and r.case not in probe_cases:
            probe_cases.append(r.case)
    details += [probe_split(c, runs, found, root) for c in probe_cases]
    if warned:
        summary += (
            "; warnings (an invocation probe denied only calls other than Skill, after"
            " its graded Skill call, or holding as every denial-free run of its"
            " should-not-fire case held; or a run scoring the same as its case's"
            " denial-free runs in the same arm with no with-arm denial inside the"
            " plugin; or a run denied only named calls other than Skill that every"
            " run of its case was denied in both arms, none inside the plugin; and"
            " any named call other than Skill aimed only under the run's own"
            " plugin-data directory, or a Read, Grep or Glob aimed only at the"
            " session's own tool-results directory, which never counts toward a"
            " FAIL; a run's score was taken under such a denial, so compare it only"
            " with runs denied the same way): %s"
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


def check_fired(cases, runs, root, measured_fire=frozenset()):
    unfired, unread, controls, unknown, checked = [], [], [], [], 0
    measured = {}  # invocation-probe or --measured-fire case name -> [fired, with-arm runs]
    for case in cases:
        requiring, _ = skill_graders(case, root)
        if is_control(case, root):
            controls.append(case.get(CASE_NAME))
            continue
        if not requiring:
            unknown.append(case.get(CASE_NAME))
            continue
        probe = is_probe(case, root) or case.get(CASE_NAME) in measured_fire
        for r in runs:
            if r.case is not case or r.arm != "with":
                continue
            results = {g.get(GRADER_NAME): g for g in as_list(r.row.get(RUN_GRADERS))}
            verdicts = [
                results[n].get(GRADER_PASSED) for n in requiring if n in results
            ]
            if not verdicts:
                unread.append("%s: no skill-fired grader result" % r.where)
            elif probe:
                tally = measured.setdefault(case.get(CASE_NAME), [0, 0])
                tally[0] += all(v is True for v in verdicts)
                tally[1] += 1
            elif all(v is True for v in verdicts):
                checked += 1
            else:
                unfired.append("%s (%s)" % (r.where, r.trace_path or "no trace"))
    notes = []
    if controls:
        notes.append("exempt as no-trigger controls: %s" % ", ".join(controls))
    if unknown:
        notes.append("no skill-fired grader, so not checked: %s" % ", ".join(unknown))
    fired = sum(f for f, _ in measured.values())
    probed = sum(n for _, n in measured.values())
    label = "measured cases" if set(measured) & measured_fire else "invocation probes"
    if measured:
        notes.append(
            "%s fired in %d of %s, the measured rate, not gated"
            % (label, fired, plural(probed, "with-arm run"))
        )
    rates = [
        "measured: case %s fired in %d of %s" % (name, f, plural(n, "with-arm run"))
        for name, (f, n) in measured.items()
        if f < n
    ]
    tail = ("; " + "; ".join(notes)) if notes else ""
    fired_in = "fired in %s" % plural(checked, "with-arm run")
    if measured and not checked:
        fired_in = "no should-trigger case outside the %s" % label
    if unfired:
        return (
            FAIL,
            "%d of %d with-arm runs of should-trigger cases did not fire%s"
            % (len(unfired), len(unfired) + checked + len(unread), tail),
            ["unfired: " + u for u in unfired] + unread + rates,
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
    if unknown or rates:
        return (
            WARN,
            fired_in + tail,
            rates,
            (
                "%s fired in %d of %s" % (label, fired, plural(probed, "run"))
                if rates
                else None
            ),
        )
    if measured and not checked:
        return PASS, fired_in + tail, [], None
    return (
        PASS,
        "fired in all %s of should-trigger cases%s"
        % (plural(checked, "with-arm run"), tail),
        [],
        None,
    )


def check_probe_tools(runs, root):
    """An invocation-probe run whose session could call a tool the emitted README
    removes ran without that run line: in its empty workspace those calls are
    denied, and a subagent it dispatches outlives the run's timeout. Warns, and
    names the fix, since the denial and error checks already judge the runs. A
    probe run with no trace, no init line or no tools list on it is unread: none
    read is UNCHECKED, some unread a warning."""
    found = {}  # the removable tools a run could call -> the runs that could
    probes, unread = 0, []
    for r in runs:
        if not is_probe(r.case, root):
            continue
        probes += 1
        tools = next(
            (
                line.get(TRACE_TOOLS)
                for line in r.trace or []
                if (line.get(LINE_TYPE), line.get(LINE_SUBTYPE)) == TRACE_INIT
            ),
            None,
        )
        if not isinstance(tools, list):
            unread.append(r)
            continue
        extra = ", ".join(t for t in tools if t in PROBE_REMOVED_TOOLS)
        if extra:
            found.setdefault(extra, []).append(r)
    if not probes:
        return PASS, "no invocation-probe case", [], None
    unread_details = [
        "%s: no init tools list (%s)" % (r.where, r.trace_path or "no trace")
        for r in unread
    ]
    if len(unread) == probes:
        return (
            UNCHECKED,
            "no invocation-probe run's init tools list could be read",
            unread_details,
            "probe tools unchecked in %s with no readable init tools list"
            % plural(len(unread), "run"),
        )
    summary, reasons = [], []
    if found:
        summary.append(
            "%s of invocation-probe cases could call %s; run the emitted README's"
            " line, --disallow-tools Read Glob Grep Agent, so a probe run cannot be"
            " denied a search or outlive its timeout in a subagent"
            % (
                plural(sum(len(rs) for rs in found.values()), "run"),
                "/".join(PROBE_REMOVED_TOOLS),
            )
        )
        reasons.append(
            "invocation probes ran without --disallow-tools Read Glob Grep Agent"
        )
    if unread:
        summary.append(
            "%s with no readable init tools list" % plural(len(unread), "probe run")
        )
        reasons.append("probe tools unread in %s" % plural(len(unread), "run"))
    if summary:
        return (
            WARN,
            "; ".join(summary),
            [
                "%s: %s, first %s" % (tools, plural(len(rs), "run"), rs[0].where)
                for tools, rs in found.items()
            ]
            + unread_details,
            "; ".join(reasons),
        )
    return (
        PASS,
        "no invocation-probe run could call Read, Glob, Grep or Agent",
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
    parser.add_argument(
        "--scaffolded",
        action="store_true",
        help="the eval was invoked with --scaffold",
    )
    parser.add_argument(
        "--measured-fire",
        action="append",
        default=[],
        metavar="CASE",
        help="a should-trigger case whose firing is the quantity compared (repeatable)",
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
        ("run errors", check_errors(runs, root)),
        ("row count", check_rows(cases, args.runs, arms, root)),
        ("scaffold", check_scaffold(cases, root, args.scaffolded)),
    ]
    lines = []
    for name, (status, summary, details, _) in checks:
        lines.append("check %s: %s (%s)" % (name, status, summary))
        lines += ["  " + d for d in details]
    if unresolved:
        lines.append(
            "traces: %d of %d tracePaths do not resolve (the run needs --keep-temp, and its"
            " directories must still exist); permission denials, probe tools and the"
            " trace model are unchecked for those runs" % (len(unresolved), len(runs))
        )
        lines += [
            "  %s: %s" % (r.where, r.trace_path or "no tracePath") for r in unresolved
        ]
    else:
        lines.append("traces: %d of %d tracePaths resolve" % (len(runs), len(runs)))
    later = [
        ("session started", check_started(runs)),
        ("permission denials", check_denials(runs, plugin_roots, root)),
        ("skill fired", check_fired(cases, runs, root, frozenset(args.measured_fire))),
        ("probe tools", check_probe_tools(runs, root)),
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
