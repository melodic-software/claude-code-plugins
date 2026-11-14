#!/usr/bin/env python3
"""run-validity - decide whether a `claude plugin eval` run's score may count.

    run-validity <aggregate-result.json> --runs N [--scaffolded] [--measured-fire CASE]...
                 [--own-copy-search-warns]

--runs is the run count the eval was invoked with (its --runs, else the case
default). --scaffolded records that the eval was invoked with --scaffold, which
the result file does not record. --measured-fire names a should-trigger case
whose firing is the quantity a comparison measures, such as the base side of a
change that makes a skill fire; the skill-fired check reports its misses as a
measured rate, as for an invocation probe, and every other check is unchanged.
--own-copy-search-warns is for the broken side of a negative control, whose
gutted skill searches its own plugin copy for the text it lost; without it such
a denial fails, since in a normal run it usually means the skill references a
file it cannot read. Reads the result file, each case's case.yaml,
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
                      slash-invoked `context: fork` skill) and passes. Any run
                      fails whose failed Bash result reports a read-only file
                      system at a relative path or under the run's sandbox (its
                      workspace and TMPDIR), a relative path only when the call
                      does more than read (a grep of a saved tool result prints
                      the text it read)
    skill loaded      no run's skill load aborted on its pre-computed command:
                      `Shell command failed for pattern` or `Shell command
                      permission check failed for pattern` in a user line's
                      local-command-stderr (a slash-invoked skill) or in the
                      result of a Skill call. Such a run scored the model
                      without the skill, even when its Skill grader passed, so
                      it is a FAIL naming the case and run; in an
                      invocation-probe or --measured-fire case a failed Skill
                      call is still the call measured, so it is a warning. skill
                      fired notes how many fired runs failed to load
    plugins loaded    every suite.plugins plugin, named by its
                      .claude-plugin/plugin.json (else its directory), is in
                      each with-arm run's init plugins list with no
                      plugin_errors entry; a with-arm run that lacks one, or
                      reports a load error for one, ran without the plugin
                      under test and is a FAIL naming the plugin and the
                      error. A plugin inside a case's dir is that case's own
                      helper and is checked only in that case's runs. A
                      with-arm run with no trace, no init line or no
                      plugins list on it is a warning
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
                      denials, so it never counts toward a FAIL (a compound
                      Bash call qualifies when one command names only paths
                      there and each other one is an echo with no redirect or
                      command substitution, or names only paths an allowed
                      Bash call of the run also named); so is a Read,
                      Grep or Glob aimed only under the session's own
                      <sandbox>/config/projects/*/*/tool-results/, where Claude
                      Code persists a large tool result the session already
                      received, and a Bash pipeline of cat, head, wc, grep and
                      sed -n reading only there, with no redirect, other
                      operator or unquoted expansion, after any opening
                      NAME=value commands whose names it expands (a value
                      with a / must be a path there, any other a plain
                      literal), and one opening cd there; several such
                      pipelines may be joined by ; or &&; with
                      --own-copy-search-warns, so is a Read, Grep or
                      Glob aimed only at or under the plugin copy the run's
                      init line lists as loaded (a suite.root or suite.plugins
                      path), in a run that finished, when no tool_used grader
                      of its case names that tool, such as the broken side of
                      a negative control searching for the text it lacks; a
                      Glob pattern that is rooted or holds `..` never
                      qualifies; so is, in a without-arm run that finished,
                      a search whose every term names only a suite.plugins
                      plugin, which that arm lacks by design: one find whose
                      only tests are -name, -iname, -path or -ipath (plus
                      their negations, -type, -maxdepth, -mindepth, -a and
                      -print, no -o), or one grep, egrep or fgrep with plain flags, either
                      piped only into head or tail with no file, a Grep
                      pattern, or a Glob whose
                      every segment but * and ** names it; a term matches
                      once its *, ., ^, $ and / ends are stripped, case
                      ignored (find / -ipath '*markdown-format*'). A
                      with-arm denied compound Bash call whose plugin part
                      a later Bash call in the same trace ran alone and was
                      not denied is set aside the same way:
                      split at ;, &&, || and
                      newlines, its assignment-only and cd commands dropped
                      and, after that part, ls, echo or cat (piped only into
                      head or tail), unless a word of the dropped command
                      holds a < or > anywhere, even quoted, other than 2>&1,
                      >&2, 2>&- or a /dev/null target; exactly one command
                      must remain, naming a path at or under the plugin's
                      directory, and the later call's words must equal it,
                      quotes removed and same-command variables resolved, a
                      word holding a glob, brace, tilde or $ compared with
                      its quoting. A command holding an unquoted &, ( or ),
                      or a $( or backtick outside single quotes anywhere,
                      never qualifies, nor does a part left holding an
                      unquoted glob, brace or tilde or an unresolved $. The
                      run's score was
                      taken under such a denial, so compare it only with
                      runs denied the same way. Otherwise a
                      with-arm denial aimed at or under the plugin's
                      directory (suite.root or a
                      suite.plugins path), at a directory above it, or with
                      no absolute path or no known plugin directory, is
                      a FAIL; in an invocation-probe case a denial of a named
                      call other than Skill is a warning when it comes after
                      the graded Skill call, or the run is a should-not-fire
                      run that held while every denial-free run of its case
                      held; a should-fire miss with a denial takes the rules
                      above. In a with-arm run, a Bash tool result whose
                      sandbox report denies an outbound host (SANDBOX_VIOLATIONS)
                      is a denial too, its hosts named in the summary: in an
                      invocation-probe, control or no-network-tagged case it
                      is set aside as a warning, otherwise a FAIL. A
                      without-arm run's network denials are not read
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
does not. The line before it counts the runs that ran Bash, decides nothing,
and names no case, command or trace text, so it may be published:
`bash ran: with <a> of <b>, without <c> of <d>[, unknown <n>]`. A run ran Bash
when a Bash call got a tool_result that is neither a permission denial nor a
failed result reporting the sandbox failing to start. A run with no readable trace is counted in its arm's
total and as unknown. A run whose init tools list leaves Bash out, with no Bash
call, is left out of its arm; an arm of only such runs is `<arm> n/a`, and a
suite of them `bash ran: n/a`. A case's allowed_tools cannot grant Bash, so the
init tools list is the record read.

A should-trigger case has a `tool_used` grader on the Skill tool that requires a
call. A case is a no-trigger control, and exempt, when its tags (prompt.md or
case.yaml) or description mark it one, or it has a max-0 Skill grader with no input_match (or one
aimed at the plugin's own skills) and no grader requiring a call. A case is an
invocation probe when its tags include `invocation-probe`, as
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
import shlex
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
PLUGIN_MANIFEST = (".claude-plugin", "plugin.json")  # under a suite.plugins path
MANIFEST_NAME = "name"
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
# A Bash pipeline the same reads may take, joined only by `|`: per command, the
# short flags it may cluster, the flags that take a number (glued, -A40, or the
# next word), and whether its first operand is a pattern or script, not a path.
# Any other command, flag, operator or word keeps the call a denial.
BASH_READERS = {
    "cat": ("nbsvetAET", "", False),
    "head": ("qv", "nc", False),
    "wc": ("lcwmL", "", False),
    "grep": ("nicvwxoqszHhlLEFGPaI", "ABCm", True),
    "egrep": ("nicvwxoqszHhlLEFGPaI", "ABCm", True),
    "fgrep": ("nicvwxoqszHhlLEFGPaI", "ABCm", True),
    "sed": ("nEr", "", True),
}
# A grep's -e pattern or -f pattern file, glued or the next word; either one means
# no operand is a pattern. -- ends its flags.
GREP_VALUE_FLAGS = {"e": False, "f": True}  # flag -> its value is a path
GREP_LONG_FLAGS = {"--regexp": "e", "--file": "f"}
END_OF_FLAGS = "--"
PIPE = "|"
# A tool-results read may run as reads joined by these, after one opening `cd`.
SEQUENCE_OPS, CD = (";", "&&"), "cd"
# Opening assignments a tool-results read may not make: each changes how the shell
# or a reader finds files or programs, or what it prints.
ENV_SENSITIVE = frozenset(
    "PATH IFS CDPATH HOME ENV PWD OLDPWD SHELLOPTS GLOBIGNORE PS4 POSIXLY_CORRECT"
    " TMPDIR LANG LANGUAGE NLSPATH TZ".split()
)
ENV_SENSITIVE_PREFIXES = ("LD_", "LC_", "GREP_", "BASH", "DYLD_")
# An opening value with neither / nor a leading ~ that a tool-results read may
# expand: a pattern, count or name, never a path.
SAFE_LITERAL = re.compile(r"\A[A-Za-z0-9._:,+=@%-]+\Z")
NUMBER = re.compile(r"\A[-+]?\d+\Z")
# The only sed scripts that qualify: print a line, a range or a /regex/ match.
SED_ADDRESS = r"(?:\d+|\$|/[^/\\]*/)"
SED_PRINT = re.compile(r"\A%s(?:,%s)?p\Z" % (SED_ADDRESS, SED_ADDRESS))
# Command substitution or a second line runs something other than the pipeline.
BASH_EXEC = re.compile(r"`|\$\(|[\r\n]")
# Outside quotes, a brace, glob or $ can expand into more operands, and $'...' or
# a backslash quotes the command differently for bash than for shlex.
QUOTED_SPAN = re.compile(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"")
UNQUOTED_EXPANSION = re.compile(r"[{*?\[$\\]")
QUOTED_EXPANSION = re.compile(r"[$`]")  # inside double quotes
DENIAL_TOOL, DENIAL_ID, DENIAL_INPUT = "tool_name", "tool_use_id", "tool_input"
MESSAGE, CONTENT, BLOCK_TYPE = "message", "content", "type"  # message.content[].type
TOOL_USE, USE_ID, USE_NAME, USE_INPUT = "tool_use", "id", "name", "input"
TOOL_RESULT, RESULT_USE_ID, RESULT_ERROR = "tool_result", "tool_use_id", "is_error"
DENIAL_TEXT = "denied by your permission settings"  # in an is_error tool_result
# A Bash tool_result's sandbox report, is_error or not, and its network denial
# lines. Upstream documents no format: observed in a with-arm trace of the x
# plugin's suite on Claude Code 2.1.317, 2026-11-03; network-denied.jsonl in the
# test fixtures keeps its shape. Pointer and recheck trigger: SKILL.md, Sources,
# "Sandbox network denial report".
SANDBOX_VIOLATIONS = re.compile(r"<sandbox_violations>(.*?)</sandbox_violations>", re.S)
NETWORK_DENIAL = re.compile(r"^deny network-outbound (\S+)", re.M)
# Anywhere in a trace line when the shell sandbox never started (Claude Code 2.1.310).
SANDBOX_FAILURE_TEXT = "Sandbox is required but failed to initialize"
# A skill's pre-computed (!`command`) line that fails, or that its permission
# check refuses, aborts the skill's load with one of these texts: in a user
# line's local-command-stderr when the skill was slash-invoked (Claude Code
# 2.1.316, #12422), and in the result of the Skill call that loaded it (the
# 2026-11-14 skill-authoring compare on #15707, #16146).
# - Pointer: https://code.claude.com/docs/en/skills#inject-dynamic-context
# - As of: 2026-11-14
# - Recheck trigger: that section rewords either abort message.
TRACE_USER = "user"
PRE_COMMAND_STDERR = "local-command-stderr"
PRE_COMMAND_FAILURE = re.compile(r"Shell command (?:permission check )?failed for pattern")
SLASH_LOAD_FAILED = "a slash-invoked skill's pre-computed command failed"
SKILL_CALL_LOAD_FAILED = "its Skill call returned a failed pre-computed command"
# A path a failed write reports as read-only, before the phrase ("cannot touch
# '<p>': Read-only file system", "line 1: <p>: Read-only file system") or after it
# ("[Errno 30] Read-only file system: '<p>'", Node's "EROFS: read-only file
# system, mkdir '<p>'"). An unquoted word before the phrase is a path only when
# it is whole and not an errno name or "Error". In a Bash result it means the
# run's workspace or TMPDIR is not writable when the path is relative or under the
# run's sandbox (Claude Code 2.1.316 with TMPDIR under /tmp or /var/tmp, #12422);
# the sandbox mounts other paths read-only by design.
_QUOTED = r"[\"'\u2018]([^\"'\u2019\n]+)[\"'\u2019]"
READ_ONLY_TARGET = re.compile(
    r"(?:%s|(?<![^\s:])(?!(?-i:E[A-Z0-9]+):|errno:|error:)([^\s:\"'\u2018\u2019]+))"
    r":\s*read-only file system"
    r"|read-only file system:\s*(?:%s|(\S+))"
    r"|read-only file system,\s*\w+\s+%s" % (_QUOTED, _QUOTED, _QUOTED),
    re.IGNORECASE,
)
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
# would expand; or a bare name, which a later read "$X" or declare "$X=..."
# would write through, so $X stays unresolved.
UNRECORDED_VALUE = re.compile(r"\A\Z|[\s$`*?\[{<>]|\A~|:~|\A%s\Z" % SHELL_NAME)
BARE_NAME = re.compile(r"\A%s\Z" % SHELL_NAME)
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
# An argument word with no slash, glob or operator (release, 30): a subcommand or
# value, not a path, when no redirect operator precedes it.
BARE_WORD = re.compile(r"\A\w[\w.,:@%+-]*\Z")
# A denied compound Bash call whose plugin part a later call ran alone: the
# operators that separate its commands, the ones that keep it from qualifying,
# and the commands dropped around that part (cd anywhere; after it, ls, echo or
# cat, piped only into head or tail).
SEPARATORS = (";", "&&", "||", "\n")
NOT_SPLIT = ("&", "(", ")")
CD = "cd"
TRAILING, TRAILING_PIPED = ("ls", "echo", "cat"), ("head", "tail")
# A character the shell may expand: GLOBBING only outside quotes, $ inside too.
GLOBBING = re.compile(r"[*?\[\]{}~]")
EXPANDING = re.compile(r"[*?\[\]{}~$]")
# Command substitution, outside single quotes.
SUBSTITUTION = re.compile(r"\$\(|`")
# A plugin-data compound's command that names no path (own_data_compound).
ECHO = "echo"
# A without-arm search for the plugin it lacks (absent_plugin_search): the
# commands, find words and grep flags it may use, and the wildcard and anchor
# characters stripped from a term's ends before it is compared with a name.
SEARCH_COMMANDS = ("find", "grep", "egrep", "fgrep")
FIND_NAME_TESTS = ("-name", "-iname", "-path", "-ipath", "-wholename", "-iwholename")
FIND_VALUE_TESTS = ("-type", "-maxdepth", "-mindepth")
FIND_NEGATIONS = ("!", "-not")
# No -o: it widens the match past the plugin's name. A negation (FIND_NEGATIONS)
# is accepted only before a name or path test, where it narrows the search.
FIND_CONNECTIVES = ("-a", "-and", "-print", "-xdev")
GREP_SEARCH_FLAGS = "rRIilLnsHhwFEcoqx"
SEARCH_TERM_ENDS = "*.^$/"

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
# A case that declares it needs no network: a sandbox network denial there warns.
NO_NETWORK_TAG = "no-network"
# The whole error text, optionally after the runner's "exit N: " prefix.
MAX_TURNS_ERROR = re.compile(
    r"(?:exit \d+: )?Reached maximum number of turns \(\d+\)\.?"
)
TRACE_ERRORS = "errors"  # on the result line
TRACE_TOOLS = "tools"  # on the init line: the tools the session could call
# The init line lists the plugins the session loaded and the ones that failed
# to load; the check reads both by these keys, takes a missing failure list as
# none failed, and matches a loaded name with or without an @marketplace suffix.
# - Pointer: when the init line's plugin fields may have changed, fetch
#   https://code.claude.com/docs/en/agent-sdk/typescript#sdksystemmessage live.
# - As of: 2026-11-01
# - Recheck trigger: the init message renames or drops plugins or
#   plugin_errors, or renames a field these keys read from their entries.
TRACE_PLUGINS, LOADED_NAME, LOADED_PATH = "plugins", "name", "path"
TRACE_PLUGIN_ERRORS = "plugin_errors"
ERROR_PLUGIN, ERROR_TYPE, ERROR_MESSAGE, ERROR_PATH = "plugin", "type", "message", "path"
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
RAN, NOT_RAN, UNKNOWN, EXEMPT = "ran", "not run", "unknown", "exempt"  # bash_state


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


def read_text(path):
    """The file's text, or None when it cannot be read."""
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except (OSError, TypeError):
        return None


def frontmatter(path):
    """description and tags from a prompt.md, or {} when it cannot be read."""
    text = read_text(path)
    if text is None:
        return {}
    parts = text.split("---", 2)
    if not text.startswith("---") or len(parts) < 3:
        return {}
    return top_level_fields(parts[1])


def top_level_fields(text):
    """description and tags from the top-level keys of a YAML block."""
    fields, key = {"tags": []}, None
    for line in text.splitlines():
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
    """The case's prompt.md frontmatter with its case.yaml top-level tags
    added, tags lowercased, or {}."""
    case_dir = case.get(CASE_DIR)
    if not root or not isinstance(case_dir, str):
        return {}
    fields = frontmatter(os.path.join(root, case_dir, CASE_PROMPT))
    case_yaml = read_text(os.path.join(root, case_dir, CASE_YAML))
    yaml_tags = top_level_fields(case_yaml)["tags"] if case_yaml else []
    fields["tags"] = [t.lower() for t in fields.get("tags", []) + yaml_tags]
    return fields


def is_probe(case, root):
    return PROBE_TAG in prompt_fields(case, root).get("tags", [])


def is_no_network(case, root):
    return NO_NETWORK_TAG in prompt_fields(case, root).get("tags", [])


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


def sandbox_failed(block):
    """True when a failed tool_result reports the shell sandbox failing to start;
    a call that succeeded and printed the text only quoted it."""
    return block.get(RESULT_ERROR) is True and SANDBOX_FAILURE_TEXT in json.dumps(
        block.get(CONTENT)
    )


def init_tools(run):
    """The tools the run's init line lists, or None when it lists none."""
    tools = next(
        (
            line.get(TRACE_TOOLS)
            for line in run.trace or []
            if (line.get(LINE_TYPE), line.get(LINE_SUBTYPE)) == TRACE_INIT
        ),
        None,
    )
    return tools if isinstance(tools, list) else None


def bash_state(run):
    """RAN, NOT_RAN, UNKNOWN (no readable trace) or EXEMPT (no Bash offered or called)."""
    if run.trace is None:
        return UNKNOWN
    bash = set()
    for line in run.trace:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) == TOOL_USE and block.get(USE_NAME) == BASH_TOOL:
                bash.add(block.get(USE_ID))
            elif (
                block.get(BLOCK_TYPE) == TOOL_RESULT
                and block.get(RESULT_USE_ID) in bash
                and not is_denial(block)
                and not sandbox_failed(block)
            ):
                return RAN
    tools = init_tools(run)
    return EXEMPT if not bash and tools is not None and BASH_TOOL not in tools else NOT_RAN


def bash_line(runs, arms):
    """The `bash ran:` line the module docstring describes."""
    states = [(r.arm, bash_state(r)) for r in runs if r.arm in arms]
    parts = []
    for arm in arms:
        got = [s for a, s in states if a == arm]
        counted = [s for s in got if s != EXEMPT]
        if got and not counted:
            parts.append("%s n/a" % arm)
        else:
            parts.append("%s %d of %d" % (arm, counted.count(RAN), len(counted)))
    if all(p.endswith(" n/a") for p in parts):
        return "bash ran: n/a"
    unknown = sum(1 for _, s in states if s == UNKNOWN)
    return "bash ran: %s%s" % (", ".join(parts), ", unknown %d" % unknown if unknown else "")


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


def read_only_targets(content):
    """Each path a tool_result's text reports as on a read-only file system."""
    if isinstance(content, list):
        return [
            p
            for b in content
            for p in read_only_targets(b if isinstance(b, str) else as_dict(b).get("text"))
        ]
    if not isinstance(content, str):
        return []
    return [next(g for g in m.groups() if g) for m in READ_ONLY_TARGET.finditer(content)]


def in_run_sandbox(path, sandbox):
    """True when a path is relative, so under the run's cwd (its workspace), or
    under its sandbox, which holds the workspace and TMPDIR. A relative path after
    a cd elsewhere is misread as the workspace."""
    return not rooted(path) or (sandbox is not None and under(path, sandbox))


def shell_failure(run):
    """Why the run had no working shell, or None: a failed Bash result reporting
    a read-only file system in the run's workspace or TMPDIR, or the sandbox not
    starting, or every one of at least MIN_BASH_CALLS Bash calls failing with no
    output. A failed call that printed output ran, so the shell worked. A denied
    call never reached the shell, so it counts toward none; check_denials judges
    it. A relative read-only path in a call that only reads (only_reads), such
    as a grep of a saved tool result, is text it read; a path under the run's
    sandbox, fresh per run, is always this run's, as when Bash cannot write its
    cwd file to TMPDIR whatever the command."""
    sandbox = sandbox_dir(run)
    bash_ids, failed_ids, commands = set(), set(), {}
    for line in run.trace or []:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) == TOOL_USE and block.get(USE_NAME) == BASH_TOOL:
                bash_ids.add(block.get(USE_ID))
                commands[block.get(USE_ID)] = as_dict(block.get(USE_INPUT)).get(BASH_COMMAND)
            elif (
                block.get(BLOCK_TYPE) == TOOL_RESULT
                and block.get(RESULT_USE_ID) in bash_ids
            ):
                if is_denial(block):
                    bash_ids.discard(block.get(RESULT_USE_ID))
                    continue
                if block.get(RESULT_ERROR) is not True:
                    continue
                reads = only_reads(commands.get(block.get(RESULT_USE_ID)))
                if any(
                    in_run_sandbox(p, sandbox) and (rooted(p) or not reads)
                    for p in read_only_targets(block.get(CONTENT))
                ):
                    return (
                        "a Bash call hit a read-only file system in the run's"
                        " workspace or TMPDIR"
                    )
                if sandbox_failed(block):
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


def user_texts(line):
    """A user line's own text: its string content or its text blocks, never a
    tool_result, which may quote a file the session read."""
    if line.get(LINE_TYPE) != TRACE_USER:
        return []
    content = as_dict(line.get(MESSAGE)).get(CONTENT)
    if isinstance(content, str):
        return [content]
    return [
        b.get("text")
        for b in as_list(content)
        if b.get(BLOCK_TYPE) == "text" and isinstance(b.get("text"), str)
    ]


def load_failure(run):
    """Where the run's trace shows a skill's load aborted by its pre-computed
    command (SLASH_LOAD_FAILED or SKILL_CALL_LOAD_FAILED), or None. A
    tool_result answering any call but a Skill call only quotes the text."""
    skill_calls = set()
    for line in run.trace or []:
        if any(
            PRE_COMMAND_STDERR in text and PRE_COMMAND_FAILURE.search(text)
            for text in user_texts(line)
        ):
            return SLASH_LOAD_FAILED
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) == TOOL_USE and block.get(USE_NAME) == SKILL_TOOL:
                skill_calls.add(block.get(USE_ID))
            elif (
                block.get(BLOCK_TYPE) == TOOL_RESULT
                and block.get(RESULT_USE_ID) in skill_calls
                and PRE_COMMAND_FAILURE.search(json.dumps(block.get(CONTENT)))
            ):
                return SKILL_CALL_LOAD_FAILED
    return None


def check_loaded(runs, root, measured_fire=frozenset()):
    """A run whose skill load aborted on its pre-computed command scored the
    model without the skill, even when its Skill grader saw the call. In an
    invocation probe or a --measured-fire case a failed Skill call is still the
    call measured, so it warns there; a failed slash command made no call."""
    failed, measured = [], []
    for r in runs:
        reason = load_failure(r)
        if not reason:
            continue
        detail = "%s: %s (%s)" % (r.where, reason, r.trace_path)
        if reason == SKILL_CALL_LOAD_FAILED and (
            is_probe(r.case, root) or r.case.get(CASE_NAME) in measured_fire
        ):
            measured.append(detail + "; the call it measures was made")
        else:
            failed.append((r, detail))
    if failed:
        cases = ", ".join(dict.fromkeys(str(r.case.get(CASE_NAME)) for r, _ in failed))
        count = plural(len(failed), "run")
        return (
            FAIL,
            "the skill failed to load in %s" % count,
            [d for _, d in failed] + measured,
            "the skill failed to load in %s, its pre-computed command failed (case %s)"
            % (count, cases),
        )
    if measured:
        return (
            WARN,
            "the skill failed to load in %s of invocation-probe or measured cases"
            % plural(len(measured), "run"),
            measured,
            "skill failed to load in %s whose call is the measure"
            % plural(len(measured), "run"),
        )
    return PASS, "no trace shows a skill's pre-computed command failing", [], None


def check_started(runs):
    """A run at 0 turns that check_errors passes, or one whose trace shows the
    sandbox failing to start, scored a session that never ran or had no shell.
    A 0-turn run whose trace holds assistant messages ran in a forked session
    (a slash-invoked `context: fork` skill), which the turn count leaves out.
    A run whose skill failed to load is check_loaded's."""
    details, failed, forked = [], set(), []
    for r in runs:
        if (
            not load_failure(r)
            and is_number(r.row.get(RUN_TURNS))
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


def suite_plugins(suite, base):
    """(name, path) of each suite.plugins entry, the name read from its
    .claude-plugin/plugin.json, else the directory's own name."""
    plugins = []
    for plugin in as_list(suite.get(SUITE_PLUGINS)):
        path = resolve(plugin.get(PLUGIN_PATH), base)
        if not path:
            continue
        path, name = os.path.normpath(path), None
        try:
            with open(os.path.join(path, *PLUGIN_MANIFEST), encoding="utf-8") as handle:
                name = as_dict(json.load(handle)).get(MANIFEST_NAME)
        except (OSError, ValueError):
            pass
        if not isinstance(name, str) or not name:
            name = os.path.basename(path)
        plugins.append((name, path))
    return plugins


def init_line(run):
    """The run's (system, init) trace line, or {}."""
    return next(
        (
            line
            for line in run.trace or []
            if (line.get(LINE_TYPE), line.get(LINE_SUBTYPE)) == TRACE_INIT
        ),
        {},
    )


def names_plugin(entry, name_key, path_key, plugin):
    """True when a trace entry's name (bare or name@marketplace) or path is plugin's."""
    name, path = plugin
    label, entry_path = entry.get(name_key), entry.get(path_key)
    return (isinstance(label, str) and (label == name or label.startswith(name + "@"))) or (
        isinstance(entry_path, str)
        and bool(entry_path)
        and os.path.normpath(entry_path) == path
    )


def load_error(error):
    return "%s: %s" % (error.get(ERROR_TYPE) or "error", error.get(ERROR_MESSAGE) or "no message")


def case_dir_of(run, root):
    """<suite root>/<case dir> of the run's case, or None."""
    case_dir = run.case.get(CASE_DIR)
    if not root or not isinstance(case_dir, str) or not case_dir:
        return None
    return os.path.normpath(os.path.join(root, case_dir))


def check_plugins_loaded(runs, plugins, root=None):
    """A with-arm run whose init line reports a plugin_errors entry for a suite
    plugin, or leaves one out of its loaded plugins, ran without the plugin
    under test, so its score measures the bare model. A suite plugin inside a
    case's dir counts as that case's own helper and is required only in that
    case's runs (reading-results.md, plugins loaded, records why). A with-arm run
    whose init plugins list cannot be read is a warning."""
    if not plugins:
        return PASS, "no suite.plugins entry to check", [], None
    case_dirs = {d for d in (case_dir_of(r, root) for r in runs) if d}
    plugins = [
        (name, path, next((d for d in case_dirs if under(path, d)), None))
        for name, path in plugins
    ]
    details, failed, causes, unread = [], 0, set(), []
    for r in (r for r in runs if r.arm == "with"):
        init = init_line(r)
        if not isinstance(init.get(TRACE_PLUGINS), list):
            unread.append(r)
            continue
        loaded, errors = as_list(init[TRACE_PLUGINS]), as_list(init.get(TRACE_PLUGIN_ERRORS))
        problems = []
        case_dir = case_dir_of(r, root)
        for plugin in [(n, p) for n, p, d in plugins if d is None or d == case_dir]:
            name = plugin[0]
            own = [e for e in errors if names_plugin(e, ERROR_PLUGIN, ERROR_PATH, plugin)]
            for error in own:
                problems.append("plugin %s failed to load: %s" % (name, load_error(error)))
                causes.add("%s (%s)" % (name, error.get(ERROR_TYPE) or "error"))
            if not any(names_plugin(p, LOADED_NAME, LOADED_PATH, plugin) for p in loaded):
                # A load error filed under another name, such as a missing
                # dependency's, may be why this plugin is absent.
                others = [e for e in errors if e not in own]
                listed = "; ".join(
                    "%s %s" % (e.get(ERROR_PLUGIN), load_error(e)) for e in others
                )
                problems.append(
                    "plugin %s is not among the loaded plugins%s"
                    % (name, "; plugin_errors: " + listed if others else "")
                )
                if not own:
                    types = ", ".join(
                        "%s %s" % (e.get(ERROR_PLUGIN), e.get(ERROR_TYPE) or "error")
                        for e in others
                    )
                    causes.add(
                        "%s (not loaded%s)"
                        % (name, "; plugin_errors: " + types if others else "")
                    )
        if problems:
            failed += 1
            details += ["%s: %s (%s)" % (r.where, p, r.trace_path) for p in problems]
    unread_details = [
        "%s: no init plugins list (%s)" % (r.where, r.trace_path or "no trace")
        for r in unread
    ]
    if failed:
        count = plural(failed, "with-arm run")
        unread_note = (
            "; %s with no readable init plugins list" % plural(len(unread), "with-arm run")
            if unread
            else ""
        )
        return (
            FAIL,
            "the plugin under test did not load in %s%s" % (count, unread_note),
            details + unread_details,
            "the plugin under test did not load in %s: %s"
            % (count, ", ".join(sorted(causes))),
        )
    if unread:
        return (
            WARN,
            "%s with no readable init plugins list" % plural(len(unread), "with-arm run"),
            unread_details,
            "plugins loaded unread in %s" % plural(len(unread), "run"),
        )
    names = ", ".join(dict.fromkeys(n for n, _, _ in plugins))
    return PASS, "every with-arm run loaded %s" % names, [], None


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
    """A Bash command's words as (text, lead, simple) triples, quotes removed. A $NAME or
    ${NAME} outside single quotes takes the value of an earlier NAME=value in the
    same command when that assignment stands alone as a command the shell is sure
    to run in its own process (at the top level, first or after ;, a newline or
    an && whose left side was such an assignment, before any compound command or
    # comment) and its value is one literal word (UNRECORDED_VALUE). A later
    word or assignment value that holds the name other than as $NAME or ${NAME},
    an eval, source or ., or any assignment to it not recorded so drops the name,
    as in read NAME, printf -vNAME, ((NAME=1)) or E="$((NAME=1))". Every other
    expansion stays as written. lead marks each command's first word and each
    assignment, whose first piece names a command or a variable, not a path.
    simple numbers the simple command a word belongs to, None for a BASH_READERS
    command reading a pipe (after |) or one that follows a ), whose words are the
    compound's redirects.
    None when the command does not parse."""
    tokens = shell_tokens(command)
    if tokens is None:
        return None
    names, words, simple = {}, [], []
    recording = not any(mark in command for mark in NO_RESOLVE)
    depth, certain, at_command, piped, count = 0, True, True, False, 0
    for kind, value in tokens + [("op", None)]:
        if kind == "word":
            simple.append(value)
            continue
        lead = at_command
        verb = next(("".join(t for t, _ in p) for p in simple if not assignment(p)), None)
        number = count if at_command and not (piped and verb in BASH_READERS) else None
        alone = bool(simple) and at_command and all(assignment(p) for p in simple)
        sure = alone and recording and depth == 0 and certain and value in KEEPS_ASSIGNMENT
        for parts in simple:
            match = assignment(parts) if lead else None
            if match:
                name = match.group(1)
                raw = "".join(text for text, _ in parts)
                mentions = EXPANSION.sub("", raw[match.end() :])
                for other in [other for other in names if other in mentions]:
                    del names[other]
                text = expand([(parts[0][0][match.end() :], None)] + parts[1:], names)
                words.append((name + "=" + text, True, number))
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
            words.append((expand(parts, names), lead, number))
            lead = False
        simple = []
        certain = value in (";", "\n", None) or (value == "&&" and certain and sure)
        if value == "(":
            depth += 1
        elif value == ")":
            depth = max(depth - 1, 0)
        at_command = value != ")"
        piped = value == "|"
        count += 1
    return words


def bash_paths(command):
    """The paths a Bash command names: each rooted word, split at quotes,
    redirects, pipes, parentheses and `=` so --flag=/x, >/x and '/x' count, after
    shell_words puts each same-command variable it resolves in place. A REDIRECT
    word naming no file (2>&1, 2>/dev/null) is dropped first. A word UNRESOLVED
    matches, a relative path with a slash or any word that is neither rooted, a
    flag nor the command or variable name opening a lead word (cwd-relative, so
    possibly the plugin), a simple command other than a BASH_READERS one reading a
    pipe that names
    no rooted argument outside a redirect (ls, make: it works in the working
    directory, so possibly the plugin), a path OWN_PROCESS matches, no rooted
    word, or a command that does not parse adds None, which inside() counts as
    inside. A plain read bash_read_paths accepts with no opening assignment names
    only its path operands, so a grep or sed pattern is no path."""
    resolved = inline_assignments(command) if isinstance(command, str) else None
    read = bash_read_paths(command) if resolved and not resolved[0] else None
    if read is not None:
        own = any(OWN_PROCESS.search(posixpath.normpath(v)) for v in read)
        return read + (None,) if own else read
    words = shell_words(command) if isinstance(command, str) else None
    if not words:
        return (None,)
    kept, skip = [], False
    for index, (text, lead, simple) in enumerate(words):
        if skip:
            skip = False
            continue
        redirect = REDIRECT.fullmatch(text)
        if redirect and redirect.group(1):
            continue
        if redirect and [w for w, _, _ in words[index + 1 : index + 2]] == [DEV_NULL]:
            skip = True
            continue
        kept.append((text, lead, simple))
    words = kept
    if not words:
        return (None,)
    values, named, target = [], {}, False
    for text, lead, simple in words:
        first = lead and not SHELL_SPLIT.match(text)
        pieces = [v for v in SHELL_SPLIT.split(text) if v]
        values += [(v, first and k == 0) for k, v in enumerate(pieces)]
        # A redirect's file (>/x, or the word after a bare >) is no argument,
        # nor is a prefix assignment's value (PYTHONPATH=/x pytest).
        argument = not (target or REDIRECT.match(text))
        target = REDIRECT.fullmatch(text) is not None
        if simple is not None and not (lead and ASSIGNMENT.match(text)):
            named[simple] = named.get(simple, False) or (
                argument
                and any(rooted(v) for k, v in enumerate(pieces) if k or not first)
            )
    paths = tuple(v for v, _ in values if rooted(v))
    unresolved = (
        any(UNRESOLVED.search(v) or (not rooted(v) and "/" in v) for v, _ in values)
        or any(not (lead or rooted(v) or v.startswith("-")) for v, lead in values)
        or any(OWN_PROCESS.search(posixpath.normpath(v)) for v in paths)
        or not all(named.values())
    )
    return paths + (None,) if unresolved or not paths else paths


def inline_assignments(command, bare_names=False):
    """(names, items) for a Bash command: names maps each NAME=value command that
    opens it, standing alone before a ;, newline or &&, to its value; items is the
    rest as ("op", text) and ("word", literal text) pairs, each $NAME or ${NAME}
    outside single quotes replaced by its value. None when the command does not
    parse, an opening value is not one literal word (UNRECORDED_VALUE, though a
    bare name passes with bare_names, for a caller whose later commands cannot
    write through one) or names a shell-set variable, names were recorded and the
    command holds a NO_RESOLVE mark, a word holds an unquoted < or > (a
    redirect), or a word keeps an expansion, glob or brace outside single quotes."""
    tokens = shell_tokens(command)
    if tokens is None:
        return None
    names, start = {}, 0
    while True:
        end = next((k for k in range(start, len(tokens)) if tokens[k][0] == "op"), None)
        words = [parts for _, parts in tokens[start:end]]
        if (
            end is None
            or not words
            or tokens[end][1] not in (";", "\n", "&&")
            or not all(assignment(parts) for parts in words)
        ):
            break
        for parts in words:
            match = assignment(parts)
            name = match.group(1)
            value = parts[0][0][match.end() :] + "".join(t for t, _ in parts[1:])
            unrecorded = UNRECORDED_VALUE.search(value) and not (
                bare_names and BARE_NAME.match(value)
            )
            if unrecorded or name in SHELL_SET or name.startswith("BASH"):
                return None
            names[name] = value
        start = end + 1
    if names and any(mark in command for mark in NO_RESOLVE):
        return None
    items = []
    for kind, value in tokens[start:]:
        if kind == "op":
            items.append((kind, value))
            continue
        text = ""
        for part, quote in value:
            if quote is None and ("<" in part or ">" in part):
                return None
            if quote != "'":
                part = EXPANSION.sub(
                    lambda m: names.get(m.group(1) or m.group(2), m.group(0)), part
                )
                if (UNQUOTED_EXPANSION if quote is None else QUOTED_EXPANSION).search(part):
                    return None
            text += part
        items.append((kind, text))
    return names, items


def joined(items):
    """inline_assignments items as one command, each word quoted as a literal."""
    return " ".join(text if kind == "op" else shlex.quote(text) for kind, text in items)


def only_reads(command):
    """True when every command of a Bash command, after its opening assignments
    (inline_assignments), is a read bash_read_paths accepts, joined only by ;,
    newlines, && or ||. Such a command writes nothing, so a read-only file system
    its output reports is text it read, not its own failure."""
    resolved = inline_assignments(command) if isinstance(command, str) else None
    if resolved is None:
        return False
    segments, current = [], []
    for kind, text in resolved[1] + [("op", None)]:
        if kind == "op" and text in (";", "\n", "&&", "||", None):
            if current:
                segments.append(current)
            current = []
        else:
            current.append((kind, text))
    return bool(segments) and all(bash_read_paths(joined(s)) is not None for s in segments)


def bash_sequence_reads(command):
    """The paths a Bash command reads, for own_results_denial: after opening
    assignments (inline_assignments) and at most one `cd <rooted dir>`, one or more
    bash_read_paths pipelines joined only by ; or &&, a relative operand resolved
    against the cd directory. The tuple also holds every assignment value with a
    / and the cd target, so each must lie where the reads do; any other value is
    a SAFE_LITERAL, checked only where it expands. None for an ENV_SENSITIVE
    name, a value with a / or leading ~ that is not a plain rooted path, any
    other value, any other operator, a cd with a flag or more than one operand,
    a cd not first, or no read after it. The commands after the opening
    assignments only read, so a bare-name value cannot be written through."""
    if isinstance(command, str):
        resolved = inline_assignments(command, bare_names=True)
    else:
        resolved = None
    if resolved is None:
        return bash_read_paths(command)
    names, items = resolved
    if any(n in ENV_SENSITIVE or n.startswith(ENV_SENSITIVE_PREFIXES) for n in names):
        return None
    paths = [v for v in names.values() if "/" in v or v.startswith("~")]
    if not all(plain(v) for v in paths) or not all(
        SAFE_LITERAL.match(v) for v in names.values() if v not in paths
    ):
        return None
    segments, current = [], []
    for kind, text in items + [("op", None)]:
        if kind == "op" and text != PIPE:
            if text not in SEQUENCE_OPS + (None,) or not current:
                return None
            segments.append(current)
            current = []
        else:
            current.append((kind, text))
    if len(segments) == 1 and not names:
        return bash_read_paths(command)
    cwd, first = None, segments[0]
    if first[0] == ("word", CD):
        if len(first) != 2 or first[1][0] != "word" or not plain(first[1][1]):
            return None
        cwd = posixpath.normpath(first[1][1])
        paths += [first[1][1], cwd]
        segments = segments[1:]
    if not segments:
        return None
    for segment in segments:
        found = bash_read_paths(joined(segment), cwd=cwd)
        if found is None:
            return None
        paths += found
    return tuple(paths)


def bash_read_paths(command, cwd=None):
    """The path operands of a Bash command that only reads: a pipeline of
    BASH_READERS commands, each with only its listed flags (a grep also with
    GREP_VALUE_FLAGS, GREP_LONG_FLAGS and --), sed with -n and a
    SED_PRINT script, after any opening assignments it then expands
    (inline_assignments). A relative path joins cwd when one is given. None for
    any other command, a redirect or other operator, command substitution, an
    UNQUOTED_EXPANSION character outside quotes, a path UNRESOLVED matches, or no
    path at all."""
    resolved = inline_assignments(command) if isinstance(command, str) else None
    if resolved and resolved[0]:
        command = joined(resolved[1])
    if (
        not isinstance(command, str)
        or BASH_EXEC.search(command)
        or UNQUOTED_EXPANSION.search(QUOTED_SPAN.sub("", command))
    ):
        return None
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split, lexer.commenters = True, ""
    try:
        words = list(lexer)
    except ValueError:
        return None
    paths, segment = [], []
    for word in words + [PIPE]:
        if word != PIPE:
            if not word.strip(lexer.punctuation_chars):
                return None
            segment.append(word)
            continue
        found = segment_read_paths(segment, cwd=cwd)
        if found is None:
            return None
        paths += found
        segment = []
    return tuple(paths) if paths else None


def segment_read_paths(words, cwd=None):
    """The path operands of one pipeline segment, per bash_read_paths, or None."""
    if not words or words[0] not in BASH_READERS:
        return None
    flags, numeric, takes_script = BASH_READERS[words[0]]
    grep = words[0] != "sed" and takes_script
    seen, operands, paths = set(), [], []
    rest = iter(words[1:])

    def resolve(word):
        """word as a plain rooted path, a relative one joined to cwd, else None.
        A tilde or - word is never joined: the shell expands one, a reader takes
        the other as its input."""
        if cwd and word and not rooted(word) and word != "-" and not word.startswith("~"):
            word = posixpath.join(cwd, word)
        return word if plain(word) else None

    def take(flag, value):
        """Record a -e or -f value; False when it is missing or an unplain file."""
        seen.add(flag)
        if GREP_VALUE_FLAGS[flag] and value is not None:
            value = resolve(value)
        if value is None:
            return False
        if GREP_VALUE_FLAGS[flag]:
            paths.append(value)
        return True

    for word in rest:
        name, glued, value = word.partition("=")
        if grep and word == END_OF_FLAGS:
            operands += rest
        elif grep and name in GREP_LONG_FLAGS:
            if not take(GREP_LONG_FLAGS[name], value if glued else next(rest, None)):
                return None
        elif word.startswith("-") and len(word) > 1:
            cluster = word[1:]
            if numeric and cluster.isdigit():
                continue
            for i, flag in enumerate(cluster):
                if flag in numeric:
                    value = cluster[i + 1 :] or next(rest, "")
                    if not NUMBER.match(value):
                        return None
                    break
                if grep and flag in GREP_VALUE_FLAGS:
                    if not take(flag, cluster[i + 1 :] or next(rest, None)):
                        return None
                    break
                if flag not in flags:
                    return None
                seen.add(flag)
        else:
            operands.append(word)
    if takes_script and not (grep and seen & set(GREP_VALUE_FLAGS)):
        if not operands:
            return None
        script, operands = operands[0], operands[1:]
    operands = [resolve(word) for word in operands]
    if None in operands:
        return None
    if words[0] == "sed" and ("n" not in seen or not SED_PRINT.match(script)):
        return None
    return paths + operands


def plain(word):
    """True when word is a rooted path UNRESOLVED does not match."""
    return rooted(word) and not UNRESOLVED.search(word)


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
    tool_use_id, the (tool, target) pair that names the same call in another run,
    the paths it only reads: a Read, Grep or Glob's paths, a read-only Bash
    command's paths (bash_sequence_reads), else None)."""
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
        if name == BASH_TOOL:
            reads = bash_sequence_reads(tool_input.get(BASH_COMMAND))
        else:
            reads = paths if name in TOOL_RESULTS_READERS else None
        out.append(
            (
                "%s: %s %s (%s)" % (run.where, name or "tool", target, run.trace_path),
                paths,
                name,
                use_id,
                (name, json.dumps(target)),
                reads,
            )
        )
    return out


def result_text(content):
    """A tool_result's text: its string content, else its text blocks joined."""
    if isinstance(content, str):
        return content
    return "\n".join(
        b if isinstance(b, str) else str(as_dict(b).get("text") or "")
        for b in content if isinstance(b, (str, dict))
    ) if isinstance(content, list) else ""


def network_denials(run, skip=()):
    """In a with-arm run, every Bash call, its id not in skip, whose tool_result
    reports a sandbox network denial (SANDBOX_VIOLATIONS, NETWORK_DENIAL), shaped
    as denials gives them: no path, so no rule reads it as aimed outside the
    plugin, and the denied hosts as its target. Text quoting the report anywhere
    but a Bash tool_result is not a denial; a without-arm run has none."""
    if run.arm != "with":
        return []
    bash, out = set(), []
    for line in run.trace:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            use_id = block.get(RESULT_USE_ID)
            if block.get(BLOCK_TYPE) == TOOL_USE and block.get(USE_NAME) == BASH_TOOL:
                bash.add(block.get(USE_ID))
            elif block.get(BLOCK_TYPE) == TOOL_RESULT and use_id in bash and use_id not in skip:
                hosts = tuple(dict.fromkeys(
                    host
                    for report in SANDBOX_VIOLATIONS.findall(result_text(block.get(CONTENT)))
                    for host in NETWORK_DENIAL.findall(report)
                ))
                if hosts:
                    out.append((
                        "%s: Bash network-outbound %s (%s)"
                        % (run.where, ", ".join(hosts), run.trace_path),
                        (None,), BASH_TOOL, use_id, ("network-outbound", hosts), None,
                    ))
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
        inside(path, roots) for _, paths, _, _, _, _ in found[run] for path in paths
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
        for _, paths, name, _, _, _ in found[run]
    ):
        return False
    held = [{key for _, _, _, _, key, _ in found[r]} for r in case_runs]
    return all(all(key in keys for keys in held) for _, _, _, _, key, _ in found[run])


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
    _, paths, name, _, _, _ = denial
    data = own_data_dir(run)
    return (
        bool(data)
        and name not in (None, SKILL_TOOL)
        and bool(paths)
        and all(under(p, data) for p in paths)
    ) or own_data_compound(run, denial, data)


def own_data_compound(run, denial, data):
    """True when a denied Bash command is a compound one of whose simple commands
    names only rooted paths under the run's own plugin-data directory, which is
    denied whatever the case does, and every rooted path its other commands name
    was also named by a Bash call of the same run that was not denied, so none of
    them caused the denial; a BARE_WORD argument in another command, not a
    redirect's file, is an argument, not a path. An echo command with no < or >
    in any word names nothing and is passed over, whatever its arguments hold,
    unless the command holds a $( or backtick anywhere. Any other part bash_paths cannot place (a
    relative path with a slash, a command with no rooted argument such as make)
    never qualifies, except a BASH_READERS command after a pipe with no file
    operand, which reads only the pipe. A command that does not parse, or a
    word UNRESOLVED matches outside a file-less redirect, never qualifies."""
    if not data or denial[2] != BASH_TOOL:
        return False
    try:
        command = json.loads(denial[4][1])
    except (TypeError, ValueError):
        return False
    words = shell_words(command) if isinstance(command, str) else None
    if not words:
        return False
    groups = {}
    for text, lead, simple in words:
        groups.setdefault(simple, []).append((text, lead))
    if len(groups) < 2:
        return False
    substitutes = SUBSTITUTION.search(command) is not None
    parts = {}
    for key, items in groups.items():
        texts = [text for text, _ in items]
        verb = texts[0] if key is not None and items[0][1] else None
        if verb == ECHO and not substitutes and not any(c in t for t in texts for c in "<>"):
            continue
        every, kept, target = [], [], False
        for text, lead in items:
            if not REDIRECT.fullmatch(text) and any(
                UNRESOLVED.search(v) for v in SHELL_SPLIT.split(text) if v
            ):
                return False
            every.append(text)
            if lead or target or not BARE_WORD.match(text):
                kept.append(text)
            target = REDIRECT.fullmatch(text) is not None
        parts[key] = (every, kept)
    paths = {key: bash_paths(shlex.join(every)) for key, (every, _) in parts.items()}
    own = {
        key for key, p in paths.items() if None not in p and all(under(x, data) for x in p)
    }
    if not own:
        return False
    for key, (every, kept) in parts.items():
        if (
            key not in own
            and None in bash_paths(shlex.join(kept))
            and not (key is None and segment_read_paths(every) == [])
        ):
            return False
    others = {x for p in paths.values() for x in p if x and not under(x, data)}
    return others <= allowed_bash_paths(run, denial[3])


def allowed_bash_paths(run, denied_id):
    """The rooted paths named by every Bash call in the run other than denied_id
    that no tool result or permission_denials entry denied."""
    denied = {d[3] for d in denials(run)} | {denied_id}
    paths = set()
    for line in run.trace:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if (
                block.get(BLOCK_TYPE) == TOOL_USE
                and block.get(USE_NAME) == BASH_TOOL
                and block.get(USE_ID) not in denied
            ):
                command = as_dict(block.get(USE_INPUT)).get(BASH_COMMAND)
                paths |= {p for p in bash_paths(command) if p}
    return paths


def own_results_denial(run, denial):
    """True when the denial is a Read, Grep or Glob, or a read-only Bash command
    (bash_sequence_reads), whose every target path is under the run's own
    config/projects/<project>/<session>/tool-results/. Claude Code writes a large
    tool result there and the model reads it back; the run's permission settings
    deny its config directory, so the read is denied whatever the case does. It
    reads only output the session already received, so it cannot add to what the
    model knows. Any other Bash command, a write, or any other path never
    qualifies."""
    reads = denial[5]
    sandbox = sandbox_dir(run)
    if not sandbox or not reads:
        return False
    projects = os.path.join(sandbox, *SANDBOX_PROJECTS)
    return all(in_tool_results(p, projects) for p in reads)


def own_copies(run, roots):
    """The plugin directories the run's init line lists as loaded whose path is
    the suite root or a suite.plugins path: the copy of the plugin this run
    loaded. [] when the init line lists none of them, as in a without-arm run."""
    wanted = {os.path.realpath(root) for root in roots}
    return [
        p[LOADED_PATH]
        for p in as_list(init_line(run).get(TRACE_PLUGINS))
        if isinstance(p.get(LOADED_PATH), str)
        and rooted(p[LOADED_PATH])
        and os.path.realpath(p[LOADED_PATH]) in wanted
    ]


def finished(run):
    """True when the run ended normally: no row error, not aborted, and its trace
    holds a result line and none that is an error."""
    return (
        run.row.get(RUN_ERROR) is None
        and not run.row.get(RUN_ABORTED)
        and not trace_errored(run)
        and any(
            line.get(LINE_TYPE) == TRACE_RESULT and line.get(TRACE_RESULT_ERROR) is False
            for line in run.trace or []
        )
    )


def graded_tools(case):
    """The tools the case's tool_used graders name."""
    return {
        as_dict(g.get(GRADER_CONFIG)).get(CONFIG_TOOL)
        for g in as_list(case.get(CASE_GRADER_DEFS))
        if g.get(GRADER_TYPE) == FIRE_GRADER_TYPE
    }


def own_input(run, denial):
    """The denied call's input: its permission_denials entry's, else its tool_use's."""
    use_id, found = denial[3], {}
    for line in run.trace or []:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) == TOOL_USE and block.get(USE_ID) == use_id:
                found = as_dict(block.get(USE_INPUT))
        if line.get(LINE_TYPE) == TRACE_RESULT:
            for entry in as_list(line.get(TRACE_DENIALS)):
                if entry.get(DENIAL_ID) == use_id:
                    return as_dict(entry.get(DENIAL_INPUT))
    return found


def own_copy_denial(run, denial, roots):
    """True when the denial is a Read, Grep or Glob whose every target path is at
    or under the plugin copy this run loaded (own_copies), the run finished, and
    no tool_used grader of its case names the denied tool. A session whose skill
    lacks the text it needs, as the broken side of a negative control does,
    searches its own plugin copy for it; the denial leaves the score to what the
    run then did. A Glob pattern that is rooted or holds a `..` segment may search
    elsewhere, so it never qualifies; nor does any other tool or path."""
    _, paths, name, _, _, _ = denial
    if name not in TOOL_RESULTS_READERS or not paths or name in graded_tools(run.case):
        return False
    pattern = own_input(run, denial).get(GLOB_PATTERN)
    if name == GLOB_TOOL and isinstance(pattern, str) and (
        rooted(pattern) or ".." in re.split(r"[\\/]", pattern)
    ):
        return False
    copies = own_copies(run, roots)
    return (
        bool(copies)
        and finished(run)
        and all(any(under(p, c) for c in copies) for p in paths)
    )


def names_absent(term, absent):
    """True when a search term, its wildcard and anchor ends stripped, is one of
    the absent plugins' names, case ignored (*markdown-format*, .*x.*, ^x$)."""
    return isinstance(term, str) and term.strip(SEARCH_TERM_ENDS).lower() in absent


def search_words(command):
    """A Bash command's words when it is one find or grep-family command, piped
    only into head or tail, its file-less redirects dropped; else None. A
    command that does not parse, holds an operator other than | or a redirect
    into a file, or a word with an unquoted glob, brace, tilde or $, never
    qualifies."""
    segments = command_segments(command)
    if not segments or len(segments) != 1 or segments[0][2] or writes_file(segments[0][0]):
        return None
    words = [
        "".join(part for part, _ in w) if isinstance(w, tuple) else w
        for w in segments[0][0]
    ]
    stages = [[]]
    for word in words:
        if word is None:
            stages.append([])
        else:
            stages[-1].append(word)
    if words[0] not in SEARCH_COMMANDS or any(
        not stage
        or stage[0] not in TRAILING_PIPED
        or not all(NUMBER.match(w) or w.startswith("-") for w in stage[1:])
        for stage in stages[1:]
    ):
        return None
    out, drop = [], False
    for word in stages[0]:
        if drop:
            drop = False
            continue
        full = REDIRECT.fullmatch(word)
        if full:
            drop = not full.group(1)
            continue
        out.append(word)
    return out


def find_terms(words):
    """The name and path patterns of a find command whose every word is a start
    path, a name or path test, a negated one, which only narrows the search and
    adds no term, -type, -maxdepth or -mindepth with a bare value, or a
    connective; else None."""
    rest = iter(words[1:])
    terms, started = [], False
    for word in rest:
        if not started and not word.startswith("-") and word != "!":
            continue
        started = True
        if word in FIND_NEGATIONS:
            if next(rest, None) not in FIND_NAME_TESTS or next(rest, None) is None:
                return None
        elif word in FIND_NAME_TESTS:
            terms.append(next(rest, None))
        elif word in FIND_VALUE_TESTS:
            if not BARE_WORD.match(next(rest, "") or ""):
                return None
        elif word not in FIND_CONNECTIVES:
            return None
    return terms or None


def grep_terms(words):
    """The patterns of a grep, egrep or fgrep command whose flags are only
    GREP_SEARCH_FLAGS clusters and -e values, its first operand the pattern
    when no -e gives one; else None."""
    rest = iter(words[1:])
    terms, operands, flags = [], [], True
    for word in rest:
        if flags and word == END_OF_FLAGS:
            flags = False
        elif flags and word.startswith("-") and word != "-":
            cluster = word[1:]
            for i, flag in enumerate(cluster):
                if flag == "e":
                    terms.append(cluster[i + 1 :] or next(rest, None))
                    break
                if flag not in GREP_SEARCH_FLAGS:
                    return None
        else:
            operands.append(word)
    if not terms:
        terms = operands[:1]
    return terms or None


def absent_plugin_search(run, denial, absent):
    """True when a finished without-arm run's denied call is a search whose every
    term names only a plugin under test (absent, its names lowercased), which
    that arm lacks by design: a find whose name and path tests, or a grep whose
    patterns, name only it (search_words), a Grep tool's pattern, or a Glob
    pattern whose every segment other than * or ** names it. The arm searches
    for the skill it was asked to run and is denied; the denial cannot raise its
    score. Any other tool, term, flag or path never qualifies."""
    name = denial[2]
    if run.arm != "without" or not absent or not finished(run):
        return False
    tool_input = own_input(run, denial)
    if name == BASH_TOOL:
        words = search_words(tool_input.get(BASH_COMMAND))
        if not words:
            return False
        terms = find_terms(words) if words[0] == "find" else grep_terms(words)
        return bool(terms) and all(names_absent(t, absent) for t in terms)
    if name == "Grep":
        return names_absent(tool_input.get("pattern"), absent)
    if name == GLOB_TOOL:
        pattern = tool_input.get(GLOB_PATTERN)
        if not isinstance(pattern, str):
            return False
        parts = [p for p in pattern.split("/") if p not in ("", "*", "**")]
        return bool(parts) and all(names_absent(p, absent) for p in parts)
    return False


def command_segments(command):
    """A Bash command's commands, split at SEPARATORS, each a (words, assignments,
    expands) triple: its words as shell_words gives them (quotes removed, same-
    command variables resolved) with None between pipeline stages, a word that
    holds an EXPANDING character kept as its quoted parts so quoting still tells
    a pattern from a literal; True when every word is a NAME=value; and True when
    a word still holds a $ or an unquoted glob, brace or tilde, which the shell
    would expand. None when it does not parse, is empty, or holds a NOT_SPLIT
    operator."""
    tokens = shell_tokens(command) if isinstance(command, str) else None
    words = shell_words(command) if tokens is not None else None
    if not words or any(
        value in NOT_SPLIT
        if kind == "op"
        else any(quote != "'" and SUBSTITUTION.search(part) for part, quote in value)
        for kind, value in tokens
    ):
        return None
    segments, current, assigns, expands, texts = [], [], True, False, iter(words)
    for kind, value in tokens + [("op", None)]:
        if kind == "word":
            text = next(texts)[0]
            current.append(tuple(value) if EXPANDING.search(text) else text)
            assigns = assigns and assignment(value) is not None
            expands = expands or "$" in text or any(
                quote is None and GLOBBING.search(part) for part, quote in value
            )
        elif value == PIPE:
            current.append(None)
            assigns = False
        elif current:
            segments.append((tuple(current), assigns, expands))
            current, assigns, expands = [], True, False
    return segments


def writes_file(words):
    """True when a command's words may redirect into a file: any word holding a <
    or >, wherever in the word and even quoted, but an fd duplication or close or
    a /dev/null target (2>&1, >&2, 2>&-, >/dev/null, 2> /dev/null), as bash_paths
    drops them."""
    words = tuple(
        "".join(part for part, _ in w) if isinstance(w, tuple) else w for w in words
    )
    for index, word in enumerate(words):
        if not isinstance(word, str) or not ("<" in word or ">" in word):
            continue
        full = REDIRECT.fullmatch(word)
        if full and full.group(1):
            continue
        if full and words[index + 1 : index + 2] == (DEV_NULL,):
            continue
        return True
    return False


def plugin_part(command, roots):
    """The words of the one command left in a compound Bash command once its
    assignment-only and cd commands, and the ls, echo or cat pipelines (into head
    or tail only) after it, are dropped, when that command names a rooted path at
    or under a plugin root; else None."""
    segments = command_segments(command)
    if not segments or len(segments) < 2:
        return None
    kept = []
    for words, assigns, expands in segments:
        heads = [words[0]] + [w for w, prior in zip(words[1:], words) if prior is None]
        if (assigns or (words[0] == CD and None not in words)) and not writes_file(words):
            continue
        if (
            kept
            and heads[0] in TRAILING
            and all(h in TRAILING_PIPED for h in heads[1:])
            and not writes_file(words)
        ):
            continue
        kept.append((words, expands))
    if len(kept) != 1 or kept[0][1] or not any(
        rooted(piece) and under(piece, root)
        for word in kept[0][0]
        if isinstance(word, str)
        for piece in SHELL_SPLIT.split(word)
        for root in roots
    ):
        return None
    return kept[0][0]


def recovered_denial(run, denial, roots, denied_ids):
    """True when a with-arm denied compound Bash call's plugin part (plugin_part)
    is the whole of a later Bash call in the same trace that was not denied: the
    run shows the plugin call itself allowed, so the denial was the wrappers'. A
    denial with no tool_use line has no position, so it never qualifies."""
    use_id, name = denial[3], denial[2]
    if run.arm != "with" or name != BASH_TOOL:
        return False
    part = plugin_part(own_input(run, denial).get(BASH_COMMAND), roots)
    if part is None:
        return False
    seen = False
    for line in run.trace:
        for block in as_list(as_dict(line.get(MESSAGE)).get(CONTENT)):
            if block.get(BLOCK_TYPE) != TOOL_USE:
                continue
            if block.get(USE_ID) == use_id:
                seen = True
                continue
            if seen and block.get(USE_NAME) == BASH_TOOL and block.get(USE_ID) not in denied_ids:
                alone = command_segments(as_dict(block.get(USE_INPUT)).get(BASH_COMMAND))
                if alone and len(alone) == 1 and alone[0][0] == part:
                    return True
    return False


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
        name is not None and name != SKILL_TOOL for _, _, name, _, _, _ in found[run]
    ):
        return False
    if graded_call_made(run, root):
        at, first = graded_call_at(run, root)
        return first is not None and all(
            at.get(use_id, -1) > first for _, _, _, use_id, _, _ in found[run]
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


def check_denials(runs, roots, root, own_copy_search_warns=False, plugin_names=()):
    traced = [r for r in runs if r.trace is not None]
    every = {r: denials(r) for r in traced}
    absent = {n.lower() for n in plugin_names if isinstance(n, str) and n}
    # Plugin-data denials, reads of the session's own tool results, a finished
    # without-arm run's searches for the plugin it lacks and, under
    # --own-copy-search-warns, a finished run's ungraded searches of its own plugin
    # copy warn and never count toward a FAIL, so every other rule judges a run on
    # the denials left.
    data = {r: [d for d in every[r] if own_data_denial(r, d)] for r in traced}
    results = {
        r: [d for d in every[r] if d not in data[r] and own_results_denial(r, d)]
        for r in traced
    }
    searched = {
        r: [
            d
            for d in every[r]
            if own_copy_search_warns
            and d not in data[r]
            and d not in results[r]
            and own_copy_denial(r, d, roots)
        ]
        for r in traced
    }
    lacked = {
        r: [
            d
            for d in every[r]
            if d not in data[r]
            and d not in results[r]
            and d not in searched[r]
            and absent_plugin_search(r, d, absent)
        ]
        for r in traced
    }
    # A denied compound call whose plugin part a later call ran alone, allowed.
    recovered = {
        r: [
            d
            for d in every[r]
            if d not in data[r]
            and d not in results[r]
            and d not in searched[r]
            and d not in lacked[r]
            and recovered_denial(r, d, roots, {e[3] for e in every[r]})
        ]
        for r in traced
    }
    # With-arm sandbox network denials: set aside in an invocation-probe, control
    # or no-network case, else a FAIL whatever the rules below say.
    network = {r: network_denials(r, {d[3] for d in every[r]}) for r in traced}
    offline = {
        r: network[r]
        if is_probe(r.case, root) or is_control(r.case, root) or is_no_network(r.case, root)
        else []
        for r in traced
    }
    found = {
        r: [
            d
            for d in every[r]
            if d not in data[r]
            and d not in results[r]
            and d not in searched[r]
            and d not in lacked[r]
            and d not in recovered[r]
        ]
        + [d for d in network[r] if d not in offline[r]]
        for r in traced
    }
    denied = [r for r in traced if every[r] or network[r]]
    warned = [
        r
        for r in denied
        if len(network[r]) == len(offline[r])
        and (
            not found[r]
            or probe_denial(r, found, runs, root)
            or same_as_clean(r, found, runs, roots)
            or in_every_run(r, found, runs, roots)
        )
    ]
    failed = [r for r in denied if r not in warned]
    details = [line for r in denied for line, _, _, _, _, _ in every[r] + network[r]]
    summary = "%s in %s" % (plural(len(details), "denial"), plural(len(denied), "run"))
    blocked = sum(len(network[r]) for r in denied)
    if blocked:
        summary += "; %s, outbound to %s" % (
            plural(blocked, "sandbox network denial"),
            ", ".join(sorted({h for r in denied for d in network[r] for h in d[4][1]})),
        )
    unplugged = sum(len(offline[r]) for r in denied)
    if unplugged:
        summary += "; %s in an invocation-probe, control or no-network case, not counted" % plural(
            unplugged, "sandbox network denial"
        )
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
    self_search = sum(len(searched[r]) for r in denied)
    if self_search:
        summary += "; %d %s of the run's own plugin copy in a finished run, not counted" % (
            self_search,
            "denied read or search" if self_search == 1 else "denied reads or searches",
        )
    missing_search = sum(len(lacked[r]) for r in denied)
    if missing_search:
        summary += (
            "; %d %s for the plugin a finished without-arm run lacks, not counted"
            % (
                missing_search,
                "denied search" if missing_search == 1 else "denied searches",
            )
        )
    rerun = sum(len(recovered[r]) for r in denied)
    if rerun:
        summary += (
            "; %s whose plugin part a later call ran alone and was allowed, not counted"
            % plural(rerun, "denied compound Bash call")
        )
    warned_cases = sorted({r.case.get(CASE_NAME) for r in warned}, key=str)
    probe_cases = []
    for r in denied:
        if is_probe(r.case, root) and r.case not in probe_cases:
            probe_cases.append(r.case)
    split = {r: found[r] + offline[r] for r in traced}
    details += [probe_split(c, runs, split, root) for c in probe_cases]
    if warned:
        summary += (
            "; warnings (an invocation probe denied only calls other than Skill, after"
            " its graded Skill call, or holding as every denial-free run of its"
            " should-not-fire case held; or a run scoring the same as its case's"
            " denial-free runs in the same arm with no with-arm denial inside the"
            " plugin; or a run denied only named calls other than Skill that every"
            " run of its case was denied in both arms, none inside the plugin; and"
            " any named call other than Skill aimed only under the run's own"
            " plugin-data directory, or a Read, Grep, Glob or read-only Bash pipeline"
            " aimed only at the session's own tool-results directory,%s%s%s%s which never"
            " counts toward a"
            " FAIL; a run's score was taken under such a denial, so compare it only"
            " with runs denied the same way): %s"
            % (
                " or, under --own-copy-search-warns, a Read, Grep or Glob aimed only"
                " at the plugin copy a finished run loaded that no tool_used grader of"
                " its case names," if own_copy_search_warns else "",
                " or a finished without-arm run's search naming only the plugin it"
                " lacks," if missing_search else "",
                " or a with-arm denied compound Bash call whose plugin part a later"
                " call in its run ran alone and was allowed," if rerun else "",
                " or a with-arm sandbox network denial in an invocation-probe, control"
                " or no-network case,"
                if unplugged
                else "",
                ", ".join(warned_cases),
            )
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
    unfired, unread, controls, unknown, checked, unloaded = [], [], [], [], 0, 0
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
                unloaded += bool(load_failure(r))
            else:
                unfired.append("%s (%s)" % (r.where, r.trace_path or "no trace"))
    notes = []
    if unloaded:
        notes.append(
            "%d of the fired runs failed to load the skill (check skill loaded)" % unloaded
        )
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
        tools = init_tools(r)
        if tools is None:
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
    parser.add_argument(
        "--own-copy-search-warns",
        action="store_true",
        help="a negative control's broken copy: a finished run's ungraded denied"
        " Read, Grep or Glob of its own plugin copy warns",
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
            " trace model are unchecked for those runs, and plugins loaded warns for"
            " each with-arm run among them" % (len(unresolved), len(runs))
        )
        lines += [
            "  %s: %s" % (r.where, r.trace_path or "no tracePath") for r in unresolved
        ]
    else:
        lines.append("traces: %d of %d tracePaths resolve" % (len(runs), len(runs)))
    later = [
        ("session started", check_started(runs)),
        ("skill loaded", check_loaded(runs, root, frozenset(args.measured_fire))),
        ("plugins loaded", check_plugins_loaded(runs, suite_plugins(suite, base), root)),
        (
            "permission denials",
            check_denials(
                runs,
                plugin_roots,
                root,
                args.own_copy_search_warns,
                [name for name, _ in suite_plugins(suite, base)],
            ),
        ),
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
    print(bash_line(runs, arms))
    if reasons:
        print("verdict: INVALID (%s)" % "; ".join(reasons))
        return 1
    print("verdict: VALID" + (" (warnings: %s)" % ", ".join(warned) if warned else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
