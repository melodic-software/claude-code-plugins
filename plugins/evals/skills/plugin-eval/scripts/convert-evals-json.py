"""convert-evals-json - turn one plugin's skill-creator evals.json cases into a
`claude plugin eval` suite.

    convert-evals-json <plugin-dir> [--dry-run]

Reads every `<plugin-dir>/skills/*/evals/evals.json` and writes one case
directory per case under `<plugin-dir>/evals/`:

    <case>/prompt.md                  frontmatter, then the case's prompt as the body
    <case>/case.yaml                  schema_version, name and the graders
    <case>/samples/<grader>.json      sample answers for a grader that has any

The case directory is `<skill>-<name>`, or `<name>` when the name already starts
with the skill's own name; a case with no `name` uses its `id`. Each item of
`expectations` (or `assertions`) becomes an `llm` grader with that item as its
criteria, judged over the trace, unless its whole wording is one of these
mechanical checks, which become a deterministic grader with pass and fail
samples instead:

    Invokes|Loads|Triggers|Calls the <skill> skill   tool_used on Skill, for
                                                     the case's own skill when
                                                     the prompt is not a slash
                                                     command
    Does not invoke /<plugin>:<skill>, No Skill call reaches <plugin>:<skill>,
    The <skill> skill is not invoked                 tool_used on Skill,
                                                     min 0, max 0, arm both,
                                                     for one of the plugin's
                                                     skills
    Runs `<command>` [through Bash]                  tool_used on Bash for the
                                                     command run as one (at the
                                                     start or after a separator,
                                                     maybe via an interpreter),
                                                     not echoed or read, when
                                                     the case grants Bash
    Does not run `<command>` [itself]                tool_used on Bash, min 0,
                                                     max 0, arm both, catching
                                                     the command anywhere a run
                                                     could hide it (sudo, env,
                                                     bash -c, xargs) but not
                                                     after echo, cat, grep or
                                                     rg, unless the guarded
                                                     command is one of them
    Names|Prints|Reports [the line] `<literal>`,
    Names|Points at /<plugin>:<skill>                regex over the final reply
    Writes|Creates the <thing> at|to|under <path>    file_exists on **/<path>,
                                                     when the case can create
                                                     files and lists no fixtures

A qualifier after the wording ("for the why part", "and reports the result"),
a placeholder such as `<id>`, a slash command passed to Run, or another
plugin's skill keeps the item an `llm` judgment. A case with neither list gets
one `llm` grader from `expected_output`, which otherwise goes to
`expected_outcome`.

A case whose prompt does not start with a slash command also gets a
`skill-fired` `tool_used` grader on the Skill tool, with sample answers it must
pass and reject. A slash command loads the skill without a Skill call, so a
slash-invoked case gets none, and neither does a case whose expectations say
the skill must not trigger or be invoked: the converter cannot tell which way
such a case points, and run-validity.py marks a run INVALID when a required
Skill call is missing. Only `expected_output` and the expectations left to an
`llm` judge are read for that wording; a mapped must-not-fire grader names its
skill, and one on the case's own skill settles the direction, so that case
gets neither the grader nor a note.

Every case's `allowed_tools` is Read, Glob, Grep and Skill, plus the tools its
skill needs to run, read from the skill's SKILL.md: Bash when the body holds a
pre-computed context line (!`command`), which runs at load so the slash command
fails to load without it, or tells Claude to run something through Bash; then
each tool in the frontmatter's `allowed-tools`, with a `Bash(git *)`-style
pattern reduced to its tool name. The list keeps that order with no repeats.

A case with expectations and an `expected_output` gets a sample file per
`llm` expectation grader, holding `expected_output` as the one answer it must pass.
The source describes the intended reply rather than recording one, so the
sample's `why` asks for the label to be confirmed before calibrate-judge.py
measures the judge on it, and validate-cases.py warns that these samples need
judge calibration. A case with expectations and no `expected_output` gets a
note instead. The `expected-output` grader gets no sample: its criteria is
that same text.

`difficulty: hard`, `why_hard` and `source` go to `description` and the `hard`
tag. `narration: true`, which marks a case that names fictional or
consumer-repo paths no fixture provides, goes to `description` and the
`narration` tag. A case that lists `files` keeps them in place under the
skill; the converter names them in `description` and in a note, since a run
starts in an empty workspace and they need `context.add_dirs` or a
`scaffold_script`.

After every case is written, each converted evals.json is removed, and its
`evals/` directory too when nothing else is left in it.

The converter writes nothing, and removes nothing, when a target case
directory already exists, two cases map to one directory, a source file is
not an evals.json it can read, or a case lacks a prompt or a criterion or
holds a value it cannot write. Each reason prints as `error: <message>`.

Output, on stdout: one line with the plugin's case count, one line per
evals.json with its count, then one `note <case>: <message>` line per case that
needs a person's attention. `--dry-run` prints the same and writes nothing.

Exit codes:

    0  converted, or nothing to convert (a count of 0)
    1  refused (nothing was written or removed), or a write or removal
       failed; the error names what was left behind
    2  usage error, or the plugin dir is missing

Python 3.8+, standard library only, like validate-cases.py.
"""

import argparse
import json
import os
import re
import shutil
import sys

MIN_PYTHON = (3, 8)

EVALS_DIR = "evals"
NOT_SLUG = re.compile(r"[^a-z0-9]+")

# The source keys this converter carries into the case. Any other key is named
# in a note, so nothing is dropped without a person seeing it.
KNOWN_KEYS = frozenset(
    [
        "id",
        "name",
        "prompt",
        "expected_output",
        "expectations",
        "assertions",
        "files",
        "narration",
        "difficulty",
        "why_hard",
        "source",
    ]
)

# Read-only tools, granted without --allow-tools: the validator's
# READ_ONLY_TOOLS. Skill must be listed, or no skill can load.
ALLOWED_TOOLS = ("Read", "Glob", "Grep", "Skill")

# A pre-computed context line (!`command`) runs through Bash when the skill
# loads; without Bash the slash command fails to load and the run ends at 0
# turns. So does a body that tells Claude to run something through Bash.
# - Pointer: when what loads a pre-computed line may have changed, fetch
#   https://code.claude.com/docs/en/skills#inject-dynamic-context live; the
#   observed basis is the #8635 rate-limit-guard run, INVALID at 0 turns.
# - As of: 2026-11-01
# - Recheck trigger: that section names a tool other than Bash for the line.
PRECOMPUTED = re.compile(r"!`[^`\n]+`")
BASH_IN_BODY = re.compile(r"\b(?:through|via|with|using|the) Bash\b|\bBash tool\b")
# A clause that tells the skill to stay off Bash grants nothing. Only the
# clause holding the Bash phrase counts, so "lines do not run, so run X through
# Bash" still grants it.
NEGATION = re.compile(r"\b(?:not|never|don['’]t|do not|avoid|without)\b", re.IGNORECASE)
# A hard-wrapped line joins the next unless that line starts a block (blank
# line, list item, heading, quote or table row).
WRAP = re.compile(r"[ \t]*\n(?![ \t]*(?:[\n\-*#>|]|\d+\.))[ \t]*")


def body_needs_bash(text):
    for sentence in re.split(r"(?<=[.!?;])\s+|\n", WRAP.sub(" ", text)):
        for match in BASH_IN_BODY.finditer(sentence):
            clause = re.split(r"[,:]", sentence[: match.start()])[-1]
            if not NEGATION.search(clause):
                return True
    return False

# One tool in an allowed-tools value; a permission pattern in parentheses after
# the name is consumed with it, so the words inside are not read as tools.
TOOL_TOKEN = re.compile(r"([A-Za-z][\w.:-]*)\s*(?:\([^)]*\))?")

# Wording that says the skill must stay quiet. Such a case gets no Skill grader.
NO_TRIGGER = re.compile(
    r"(?:\b(?:not|never|no|without)\b|n't\b)[^.;\n]{0,60}?"
    r"\b(?:trigger\w*|invok\w*|fir(?:e|es|ed|ing)\b|activat\w*|load\w*"
    r"|us(?:e|es|ed|ing)\b|call\w*|rout\w*)",
    re.IGNORECASE,
)

# A slash command at the start of the prompt, which loads a skill with no Skill
# call. A path such as /srv/app is not one.
SLASH_COMMAND = re.compile(r"^\s*/[\w.-]+(?::[\w.-]+)?(?=[\s:,.;]|$)")

# Characters a one-line YAML scalar cannot carry here: control characters, the
# ones Python's splitlines() breaks a line on, which the validator uses, and the
# non-printable ones a YAML loader rejects.
UNWRITABLE = re.compile(
    "[%s]"
    % "".join(
        re.escape(chr(code))
        for code in list(range(0x00, 0x09))
        + [0x0B, 0x0C]
        + list(range(0x0E, 0x20))
        + list(range(0x7F, 0xA0))
        + [0x2028, 0x2029, 0xFFFE, 0xFFFF]
    )
)
REGEX_SPECIAL = frozenset(".^$*+?()[]{}|\\/")

# Expectation wording that maps to a deterministic grader. Each pattern must
# match the whole expectation, so a qualifier ("for the why part", "and reports
# the result") keeps it an llm judgment. Grader fields are the Grader types
# table's.
# - Pointer: when a field or its default may have changed, fetch
#   https://code.claude.com/docs/en/plugin-evals#grader-types live.
# - As of: 2026-11-01
# - Recheck trigger: that table renames a field of regex, tool_used or
#   file_exists, or changes how tool_used matches input_match.
SKILL_REF = r"(the `?[\w-]+`? skill|`?/?[\w-]+:[\w-]+`?)"
SKILL_INVOKED = re.compile(
    r"^(?:Invokes|Loads|Triggers|Calls) %s(?: (?:via|through) the Skill tool)?\.?$"
    % SKILL_REF
)
SKILL_NOT_INVOKED = re.compile(
    r"^(?:(?:Does not|Does NOT|Never) (?:invoke|load|trigger|call)s? %s"
    r"|No Skill call reaches %s"
    r"|(The `?[\w-]+`? skill) is (?:not|NOT|never) invoked)\.?$" % (SKILL_REF, SKILL_REF)
)
COMMAND_RAN = re.compile(
    r"^(?:Runs|Executes) `([^`\n]+)`"
    r"(?: (?:through|via|with|using) (?:the )?Bash(?: tool)?)?\.?$"
)
COMMAND_NOT_RAN = re.compile(
    r"^(?:Does not|Does NOT|Never) runs? `([^`\n]+)`(?: itself)?\.?$"
)
NAMES_LITERAL = re.compile(
    r"^(?:(?:The (?:response|reply|output|answer)|It) )?"
    r"(?:names|prints|mentions|quotes|reports|outputs|contains|includes|states)"
    r"(?: the)?(?: (?:literal|exact))?(?: (?:line|string|token|text|command|path))?"
    r" `([^`\n]+)`\.?$",
    re.IGNORECASE,
)
NAMES_SKILL = re.compile(
    r"^(?:(?:The (?:response|reply|output|answer)|It) )?"
    r"(?:names|mentions|points (?:at|to)) /([\w-]+:[\w-]+)\.?$",
    re.IGNORECASE,
)
FILE_CREATED = re.compile(
    r"^(?:Writes|Creates) (?:(?:the|a|an) [\w -]+? )?(?:at|to|under) "
    r"`?([\w.](?:[\w./-]*[\w/])?)`?\.?$"
)
# A token holding a placeholder or a quote is not a literal the run can echo.
NOT_LITERAL = re.compile(r"[<>…\"\\]|\.\.\.")
# Must-fail replies for a regex grader; the first that cannot match is used.
STOCK_REPLIES = ("The reply names nothing in particular.", "Done.", "0", "-")
# Tools that let a run create a file; Edit only changes one.
CREATES_FILES = frozenset(["Write", "Bash"])


class Refusal(Exception):
    """A reason the whole plugin is not converted."""


def slug(text):
    return NOT_SLUG.sub("-", str(text).lower()).strip("-")


def yaml_str(value, where):
    """One-line YAML scalar the validator's subset parser reads back unchanged."""
    if UNWRITABLE.search(value):
        raise Refusal("%s holds a control or line-separator character" % where)
    if any(char in value for char in "\n\r\t"):
        for old, new in (
            ("\\", "\\\\"),
            ('"', '\\"'),
            ("\n", "\\n"),
            ("\r", "\\r"),
            ("\t", "\\t"),
        ):
            value = value.replace(old, new)
        return '"%s"' % value
    return "'%s'" % value.replace("'", "''")


def regex_escape(text):
    return "".join("\\" + char if char in REGEX_SPECIAL else char for char in text)


def plugin_name(plugin_dir):
    manifest = os.path.join(plugin_dir, ".claude-plugin", "plugin.json")
    try:
        with open(manifest, "r", encoding="utf-8") as handle:
            name = json.load(handle).get("name")
    except (OSError, ValueError, AttributeError):
        name = None
    return name if isinstance(name, str) and name else os.path.basename(plugin_dir)


def skill_dirs(plugin_dir):
    skills = os.path.join(plugin_dir, "skills")
    if not os.path.isdir(skills):
        return []
    return sorted(
        name for name in os.listdir(skills) if os.path.isdir(os.path.join(skills, name))
    )


def source_files(plugin_dir):
    found = []
    for skill in skill_dirs(plugin_dir):
        path = os.path.join(plugin_dir, "skills", skill, EVALS_DIR, "evals.json")
        if os.path.isfile(path):
            found.append((skill, path))
    return found


def frontmatter_tools(lines):
    """Tool names from a SKILL.md frontmatter's allowed-tools, inline or block."""
    raw = []
    for index, line in enumerate(lines):
        if not line.startswith("allowed-tools:"):
            continue
        raw.append(line.split(":", 1)[1])
        for item in lines[index + 1 :]:
            if not item.lstrip().startswith("- "):
                break
            raw.append(item.lstrip()[2:])
        break
    return [match.group(1) for match in TOOL_TOKEN.finditer(" ".join(raw))]


def skill_tools(plugin_dir, skill):
    """The case's allowed_tools: the base list plus what the skill needs to run."""
    try:
        with open(
            os.path.join(plugin_dir, "skills", skill, "SKILL.md"), "r", encoding="utf-8"
        ) as handle:
            text = handle.read()
    except (OSError, UnicodeDecodeError):
        return list(ALLOWED_TOOLS)
    lines = text.splitlines()
    front = []
    if lines and lines[0].strip() == "---":
        for number, line in enumerate(lines[1:], start=1):
            if line.strip() == "---":
                front, text = lines[1:number], "\n".join(lines[number + 1 :])
                break
    tools = list(ALLOWED_TOOLS)
    if PRECOMPUTED.search(text) or body_needs_bash(text):
        tools.append("Bash")
    tools += frontmatter_tools(front)
    return list(dict.fromkeys(tools))


def read_cases(path, rel):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as error:
        raise Refusal("%s: not readable JSON (%s)" % (rel, error))
    cases = data.get("evals") if isinstance(data, dict) else None
    if not isinstance(cases, list) or not all(isinstance(c, dict) for c in cases):
        raise Refusal("%s: no evals list of case objects" % rel)
    return cases


def case_dir_name(skill, case, where):
    raw = case.get("name")
    if not isinstance(raw, str) or not raw.strip():
        raw = case.get("id")
    name = slug(raw) if raw is not None else ""
    if not name:
        raise Refusal("%s has no name or id to name its directory" % where)
    prefix = slug(skill)
    if name != prefix and not name.startswith(prefix + "-"):
        name = prefix + "-" + name
    return name


def criteria_list(case, where, notes):
    """The case's expectation strings, in order; blank items are skipped."""
    items = []
    for key in ("expectations", "assertions"):
        listed = case.get(key)
        if listed is None:
            continue
        if not isinstance(listed, list):
            raise Refusal("%s: %s is not a list" % (where, key))
        for number, item in enumerate(listed, start=1):
            if not isinstance(item, str):
                raise Refusal(
                    "%s: %s item %d is not a string; convert it by hand"
                    % (where, key, number)
                )
            if item.strip():
                items.append(item.strip())
            else:
                notes.append("%s item %d is blank and was skipped" % (key, number))
    return items


def skill_samples(plugin, skill):
    def call(name):
        return [{"tool": "Skill", "input": {"skill": name}}]

    return {
        "pass": [
            {"answer": call(plugin + ":" + skill), "why": "qualified name"},
            {"answer": call(skill), "why": "bare name"},
        ],
        "fail": [
            {"answer": [], "why": "no Skill call"},
            {"answer": call("other-plugin:other-skill"), "why": "another skill"},
            {
                "answer": call(plugin + ":" + skill + "-other"),
                "why": "a skill whose name only starts the same",
            },
        ],
    }


def skill_match(plugin, skill):
    return '"skill"\\s*:\\s*"(?:%s:)?%s"' % (regex_escape(plugin), regex_escape(skill))


def own_skill(ref, plugin, skills):
    """The skill a SKILL_REF names when it is one of this plugin's, else None."""
    ref = ref.strip("`")
    if ref.lower().startswith("the "):
        name = ref[4:-6].strip("`")
    else:
        owner, _, name = ref.lstrip("/").partition(":")
        if owner != plugin:
            return None
    return name if name in skills else None


# The two directions err opposite ways. A must-run grader credits only a
# command that starts the value or follows a separator, after an optional
# interpreter and a quoted or absolute directory, so a mention never passes it.
# A must-not-run guard counts the words anywhere a run could hide them (sudo,
# env, time, bash -c, a subshell, xargs), unless the segment since the last
# separator starts with a command that only shows text, such as echo or grep,
# and is not the guarded command itself. TEXT_ONLY lists commands that print
# or search and never run their arguments; sed, awk and find can run or write
# (sed's e command and -i, awk's system(), find -exec), so a guard counts them.
TEXT_ONLY = (
    "echo", "printf", "cat", "grep", "rg", "git grep", "head", "tail", "less", "more"
)
COMMAND_START = (
    r'"command"\s*:\s*"(?:(?:[^"\\]|\\.)*?(?:&&|\|\||;|\||\\n)\s*)?'
    r"(?:(?:python3?|bash|sh|node|npx|uv run)\s+)?(?:\\\"|')?(?:[^\s\"'\\]*/)?"
)
COMMAND_SEGMENT = r'"command"\s*:\s*"(?:(?:[^"\\]|\\.)*?(?:&&|\|\||;|\||\\n))?'
COMMAND_ANYWHERE = r'(?:[^"\\;&|]|\\[^n])*?(?<![\w.-])'
# Between two words: whitespace, with an optional closing and opening quote.
COMMAND_GAP = r"(?:\\\"|')?\s+(?:\\\"|')?"


def command_match(command, ran):
    """input_match for a Bash call that runs these words as one command:
    strict for a must-run grader, broad for a must-not-run guard."""
    words = [regex_escape(word) for word in command.split()]
    if ran:
        start = COMMAND_START
    else:
        shown = [
            r"\s+".join(regex_escape(w) for w in name.split())
            for name in TEXT_ONLY
            if command != name and not command.startswith(name + " ")
        ]
        start = COMMAND_SEGMENT + r"(?!\s*(?:%s)\b)" % "|".join(shown) + COMMAND_ANYWHERE
    return start + COMMAND_GAP.join(words) + r"(?![^\s\"'\\;&|)])"


def bash(command):
    return [{"tool": "Bash", "input": {"command": command}}]


def command_samples(command, ran):
    words = command.split()
    quoted = 'cd /work && python3 "/work/%s" %s' % (words[0], " ".join(words[1:]))
    present = [
        {"answer": bash(command), "why": "the command as written"},
        {"answer": bash(quoted.rstrip()), "why": "a quoted absolute path"},
    ]
    if not ran:
        present += [
            {"answer": bash("sudo " + command), "why": "run under sudo"},
            {"answer": bash("bash -c '%s'" % command), "why": "run through bash -c"},
        ]
    absent = [
        {"answer": [], "why": "no Bash call"},
        {"answer": bash("echo unrelated"), "why": "another command"},
        {"answer": bash("echo '%s'" % command), "why": "the command only echoed"},
        {
            "answer": [{"tool": "Read", "input": {"file_path": command}}],
            "why": "the text in another tool's input",
        },
    ]
    if len(set(words)) == len(words) > 1:
        absent.append(
            {"answer": bash(" ".join(reversed(words))), "why": "the words out of order"}
        )
    return {"pass": present, "fail": absent} if ran else {"pass": absent, "fail": present}


def deterministic(text, where, plugin, skill, skills, tools, slash_invoked, has_files):
    """(grader option lines, samples, skill it forbids or None) for an
    expectation whose whole wording maps to a deterministic check, or None to
    keep it an llm judgment."""
    found = SKILL_INVOKED.match(text)
    if found and not slash_invoked:
        name = own_skill(found.group(1), plugin, skills)
        if name == skill:
            return (
                ["type: 'tool_used'", "tool: 'Skill'", "input_match: "
                 + yaml_str(skill_match(plugin, name), where)],
                skill_samples(plugin, name),
                None,
            )
    found = SKILL_NOT_INVOKED.match(text)
    if found:
        name = own_skill(next(g for g in found.groups() if g), plugin, skills)
        if name:
            calls = skill_samples(plugin, name)
            return (
                ["type: 'tool_used'", "tool: 'Skill'", "input_match: "
                 + yaml_str(skill_match(plugin, name), where), "min: 0", "max: 0",
                 "arm: 'both'"],
                {"pass": calls["fail"], "fail": calls["pass"]},
                name,
            )
    for pattern, ran in ((COMMAND_RAN, True), (COMMAND_NOT_RAN, False)):
        found = pattern.match(text)
        if not found:
            continue
        command = found.group(1).strip()
        if command.startswith("/") or NOT_LITERAL.search(command):
            return None
        if ran and "Bash" not in tools:
            return None
        lines = ["type: 'tool_used'", "tool: 'Bash'",
                 "input_match: " + yaml_str(command_match(command, ran), where)]
        if not ran:
            lines += ["min: 0", "max: 0", "arm: 'both'"]
        return lines, command_samples(command, ran), None
    found = NAMES_LITERAL.match(text) or NAMES_SKILL.match(text)
    if found:
        token = found.group(1)
        if NOT_LITERAL.search(token) or not token.strip():
            return None
        if found.re is NAMES_SKILL:
            pattern = "\\/?" + regex_escape(token) + "(?![\\w:-])"
            present = ["Use /%s next." % token, "Use %s next." % token]
            absent = ["Use /%s-other next." % token]
        else:
            pattern = regex_escape(token)
            present = ["The answer names %s here." % token]
            absent = []
        # A must-fail reply that cannot hold the literal; none fits, stay llm.
        compiled = re.compile(pattern)
        absent += [r for r in STOCK_REPLIES if not compiled.search(r)][:1]
        if not absent:
            return None
        return (
            ["type: 'regex'", "pattern: " + yaml_str(pattern, where),
             "target: 'last_message'"],
            {
                "pass": [{"answer": a, "why": "names it"} for a in present],
                "fail": [{"answer": a, "why": "does not name it"} for a in absent],
            },
            None,
        )
    found = FILE_CREATED.match(text)
    if found and not has_files and CREATES_FILES & set(tools):
        path = found.group(1)
        if ".." in path.split("/") or "/" not in path.rstrip("/") and "." not in path:
            return None
        glob = "**/" + path + ("**" if path.endswith("/") else "")
        made = path + ("SKILL.md" if path.endswith("/") else "")
        return (
            ["type: 'file_exists'", "path: " + yaml_str(glob, where)],
            {
                "pass": [
                    {"answer": [made], "why": "created, relative path"},
                    {"answer": ["/work/" + made], "why": "created, absolute path"},
                ],
                "fail": [
                    {"answer": [], "why": "nothing created"},
                    {"answer": ["unrelated/notes.txt"], "why": "another file"},
                ],
            },
            None,
        )
    return None


def expected_samples(expected):
    return {
        "pass": [
            {
                "answer": expected,
                "why": "the source's expected_output, which describes the reply "
                "rather than recording one; confirm the label before calibrating",
            }
        ]
    }


def sample_text(data):
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def plan_case(plugin, skill, case, where, tools=ALLOWED_TOOLS, skills=()):
    """Return (directory name, {relative path: text}, notes) for one case."""
    notes = []
    name = case_dir_name(skill, case, where)
    prompt = case.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise Refusal("%s has no prompt" % where)
    expected = case.get("expected_output")
    expected = expected.strip() if isinstance(expected, str) else ""
    criteria = criteria_list(case, where, notes)
    graders = [("expectation-%d" % n, text) for n, text in enumerate(criteria, 1)]
    if not graders:
        if not expected:
            raise Refusal("%s has no expectations and no expected_output" % where)
        graders = [("expected-output", expected)]

    tags = [slug(skill)]
    described = []
    if case.get("difficulty") == "hard":
        tags.append("hard")
        why = case.get("why_hard")
        described.append(
            "Hard case. Why hard: %s" % why.strip()
            if isinstance(why, str) and why.strip()
            else "Hard case."
        )
    if isinstance(case.get("source"), str) and case["source"].strip():
        described.append("Source: %s." % case["source"].strip().rstrip("."))
    narration = case.get("narration")
    if narration is True:
        tags.append("narration")
        described.append(
            "Narration case: it names fictional or consumer-repo paths that no "
            "fixture provides."
        )
    elif narration is not None and narration is not False:
        notes.append("narration is not true or false, so it was not carried over")
    files = case.get("files") or []
    files = [files] if isinstance(files, str) else files
    if not isinstance(files, list) or not all(isinstance(f, str) for f in files):
        raise Refusal("%s: files is not a list of paths" % where)
    files = [f for f in files if f]
    if files:
        shown = ", ".join("skills/%s/%s" % (skill, f) for f in files)
        described.append("Fixtures not yet routed into the run: %s." % shown)
        notes.append(
            "lists fixtures (%s); route them in with context.add_dirs or a "
            "scaffold_script" % shown
        )
    unknown = sorted(set(case) - KNOWN_KEYS)
    if unknown:
        notes.append("source keys not carried over: %s" % ", ".join(unknown))

    front = []
    if described:
        front.append("description: " + yaml_str(" ".join(described), where))
    front.append("tags: [%s]" % ", ".join(yaml_str(t, where) for t in tags))
    front.append("allowed_tools: [%s]" % ", ".join(tools))
    if expected:
        front.append("expected_outcome: " + yaml_str(expected, where))
    files_out = {
        "prompt.md": "---\n%s\n---\n\n%s\n" % ("\n".join(front), prompt.strip("\n"))
    }

    slash_invoked = SLASH_COMMAND.match(prompt) is not None
    yaml_lines = ['schema_version: "1.1"', "name: " + yaml_str(name, where), "graders:"]
    judged, judged_text, forbidden = [], [], set()
    for grader, text in graders:
        mapped = None
        if criteria:
            mapped = deterministic(
                text, where, plugin, skill, skills, tools, slash_invoked, bool(files)
            )
        yaml_lines.append("  - name: '%s'" % grader)
        if mapped:
            options, samples, forbids = mapped
            yaml_lines += ["    " + line for line in options]
            files_out["samples/%s.json" % grader] = sample_text(samples)
            forbidden.add(forbids)
            continue
        judged.append(grader)
        judged_text.append(text)
        yaml_lines += [
            "    type: 'llm'",
            "    criteria: " + yaml_str(text, where),
            "    focus: 'trace'",
        ]
    if criteria and expected:
        for grader in judged:
            files_out["samples/%s.json" % grader] = sample_text(
                expected_samples(expected)
            )
    elif criteria and judged:
        notes.append(
            "has expectations but no expected_output, so its llm graders have no "
            "sample answers; add samples/<grader>.json by hand"
        )
    # A mapped expectation says which skill it is about, so only the wording
    # left to the judge can leave the direction unknown.
    if slash_invoked or skill in forbidden:
        pass
    elif any(NO_TRIGGER.search(t) for t in [expected] + judged_text):
        notes.append(
            "its expectations may say the skill must not fire, so it has no Skill "
            "grader; add one by hand once the direction is known"
        )
    else:
        pattern = skill_match(plugin, skill)
        yaml_lines += [
            "  - name: 'skill-fired'",
            "    type: 'tool_used'",
            "    tool: 'Skill'",
            "    input_match: " + yaml_str(pattern, where),
        ]
        files_out["samples/skill-fired.json"] = sample_text(
            skill_samples(plugin, skill)
        )
    files_out["case.yaml"] = "\n".join(yaml_lines) + "\n"
    for text in files_out.values():
        try:
            text.encode("utf-8")
        except UnicodeEncodeError:
            raise Refusal("%s holds text that cannot be written as UTF-8" % where)
    return name, files_out, notes


def plan(plugin_dir):
    """Every case to write, per source file, or raise Refusal with all reasons."""
    plugin = plugin_name(plugin_dir)
    eval_dir = os.path.join(plugin_dir, EVALS_DIR)
    if os.path.lexists(eval_dir) and not os.path.isdir(eval_dir):
        raise Refusal("%s exists and is not a directory" % EVALS_DIR)
    sources, errors, owners = [], [], {}
    skills = frozenset(skill_dirs(plugin_dir))
    for skill, path in source_files(plugin_dir):
        rel = os.path.relpath(path, plugin_dir).replace(os.sep, "/")
        try:
            cases = read_cases(path, rel)
        except Refusal as error:
            errors.append(str(error))
            continue
        planned = []
        tools = skill_tools(plugin_dir, skill)
        for number, case in enumerate(cases, start=1):
            where = "%s case %d" % (rel, number)
            try:
                name, files, notes = plan_case(
                    plugin, skill, case, where, tools, skills
                )
            except Refusal as error:
                errors.append(str(error))
                continue
            if name in owners:
                errors.append(
                    "%s and %s both map to %s/%s" % (owners[name], where, EVALS_DIR, name)
                )
                continue
            owners[name] = where
            if os.path.lexists(os.path.join(eval_dir, name)):
                errors.append(
                    "%s/%s already exists; refusing to overwrite it" % (EVALS_DIR, name)
                )
                continue
            planned.append((name, files, notes))
        sources.append((rel, path, planned))
    if errors:
        raise Refusal("\n".join(errors))
    return plugin, eval_dir, sources


def write_cases(eval_dir, sources):
    created = []
    try:
        for _, _, planned in sources:
            for name, files, _ in planned:
                case_dir = os.path.join(eval_dir, name)
                os.makedirs(case_dir)
                created.append(case_dir)
                for rel, text in sorted(files.items()):
                    target = os.path.join(case_dir, *rel.split("/"))
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    with open(target, "w", encoding="utf-8", newline="\n") as handle:
                        handle.write(text)
    except OSError as error:
        for case_dir in created:
            shutil.rmtree(case_dir, ignore_errors=True)
        raise OSError("%s; no case was kept and no evals.json removed" % error)
    left = []
    for rel, path, _ in sources:
        try:
            os.remove(path)
        except OSError as error:
            left.append("%s (%s)" % (rel, error))
            continue
        try:
            os.rmdir(os.path.dirname(path))
        except OSError:
            pass  # fixtures or other files remain beside it
    if left:
        raise OSError("the cases were written, but not removed: %s" % ", ".join(left))


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            "error: convert-evals-json needs Python %d.%d or newer\n" % MIN_PYTHON
        )
        return 2
    parser = argparse.ArgumentParser(
        prog="convert-evals-json",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("plugin_dir", help="the plugin root holding skills/")
    parser.add_argument(
        "--dry-run", action="store_true", help="print the counts and write nothing"
    )
    args = parser.parse_args(argv)
    plugin_dir = os.path.abspath(args.plugin_dir)
    if not os.path.isdir(plugin_dir):
        sys.stderr.write("error: not a directory: %s\n" % args.plugin_dir)
        return 2
    try:
        plugin, eval_dir, sources = plan(plugin_dir)
        if not args.dry_run:
            write_cases(eval_dir, sources)
    except Refusal as error:
        for line in str(error).splitlines():
            sys.stderr.write("error: %s\n" % line)
        sys.stderr.write("nothing was written or removed\n")
        return 1
    except OSError as error:
        sys.stderr.write("error: %s\n" % error)
        return 1
    total = sum(len(planned) for _, _, planned in sources)
    print(
        "%s: %d cases from %d evals.json files%s"
        % (plugin, total, len(sources), " (dry run, nothing written)" if args.dry_run else "")
    )
    for rel, _, planned in sources:
        print("  %s: %d case%s" % (rel, len(planned), "" if len(planned) == 1 else "s"))
    for _, _, planned in sources:
        for name, _, notes in planned:
            for note in notes:
                print("note %s: %s" % (name, note))
    return 0


if __name__ == "__main__":
    sys.exit(main())
