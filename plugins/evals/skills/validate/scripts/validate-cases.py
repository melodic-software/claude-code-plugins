#!/usr/bin/env python3
"""validate-cases - check a `claude plugin eval` suite without spending a cent.

    validate-cases <eval-dir> [--json]

Reads every case under <eval-dir> (a directory holding `prompt.md`, `case.yaml`,
or both, with one grader per file under `graders/`) and reports two tiers:

    FAIL  what the binary itself rejects, so the suite cannot load
    WARN  an authoring mistake the suite loads with and scores badly on

It also runs every deterministic grader (regex, tool_used, tool_order,
file_exists) offline against the case's sample answers, one JSON file per grader
at `<case>/samples/<grader-name>.json`:

    {"pass": [{"answer": ..., "why": "..."}], "fail": [{"answer": ...}]}

`answer` is what the grader reads: the target text for regex (the final reply
by default), a list of `{"tool": ..., "input": {...}}` calls for tool_used and
tool_order, and a list of created paths for file_exists. A must-pass answer the
grader rejects, or a must-fail answer it accepts, is a FAIL. A deterministic
grader with no samples is a WARN, and so is an llm or baseline grader that has
samples, since judging them needs a paid calibration run this script never
makes.

Output is one finding per line, `<FAIL|WARN> <case>/<file>: <message>`, sorted by
case then file. A finding about the suite as a whole carries the eval dir in
place of `<case>/<file>`. `--json` prints the same findings as a JSON array of
`{level, case, file, message}` objects instead.

Exit codes:

    0  no FAIL finding (WARN findings are allowed and still printed)
    1  at least one FAIL finding
    2  usage error, or the eval dir is missing or unreadable

The YAML this reads is a bounded subset: scalars, quoted scalars, flow lists and
flow mappings, block lists including lists of mappings, and block mappings three
levels deep. Anything outside it is reported as `frontmatter not parsed
(<construct>)` at FAIL, never waved through at exit 0: a validator must not
green-light input it did not read. Simplify the file, or run the CLI, which
carries the full parser.

Drift record. CLAIM: the FAIL tier mirrors what the binary rejects - the
thirteen `prompt.md` frontmatter keys, the six grader types whose option sets are
strict, the bounds on `runs`, `max_turns`, `timeout_seconds`, `weight`, and
`env` key names, the supported `schema_version` major (1), and every field the
schema marks required: `schema_version` (a string with a leading major) and
`name`, which the binary defaults only when the case has no `case.yaml`; a
prompt, from the `prompt.md` body or `execution.prompt`; and each grader type's
required options (regex `pattern`, tool_used `tool`, tool_order `before` and
`after`, file_exists `path`, llm `criteria`, baseline `baseline_file` and
`criteria`), where a `graders/*.md` body stands in for `pattern` or `criteria`.
BASIS: the case schema and its loader read out of Claude Code 2.1.296 (the
zod object behind `invalid case.yaml: <path>: Required`, and the merge that
defaults `schema_version` and `name` only when `case.yaml` is absent), each
required-field rejection reproduced with `claude plugin eval --case`, together
with the eval-suite reference page; recheck on the next Claude Code release,
which can add a key or move a bound, and re-derive the lists from the schema
rather than patching one value. AS OF: 2026-10-09. Page:
https://code.claude.com/docs/en/plugin-evals

Drift record. CLAIM: two more `prompt.md` keys, `artifact_publish` and
`growthbook_overrides`, load but are not on the page's field table, so they are
a WARN rather than a FAIL. BASIS: the case schema read out of Claude Code
2.1.287 against the page's prompt.md field table. AS OF: 2026-10-02. Recheck
when the page lists either key, or a release drops either from the schema.

Drift record. CLAIM: the sample check grades the way the binary does - a regex
is a JavaScript RegExp built from `pattern` and `flags` (default none) and
tested against the target; `match` defaults to contains, and `count:N` counts
global matches; `input_match` is a flagless regex over each call's compact
JSON input; `min` defaults to 1 and `max` to unbounded; `tool_order` compares
the first matching call of each side; a `file_exists` glob is anchored, with
`*` inside one path segment and `**` across them. Python's `re` stands in for
the JavaScript engine: named groups are translated, the `y` and `v` flags and
any pattern `re` cannot compile are reported as not checkable (WARN), and the
two engines still differ at the edges (`\\w` and `\\b` on non-ASCII letters,
`$` before a final newline). BASIS: the grader code in Claude Code 2.1.287
read together with the grader-types table of the eval-suite reference page.
AS OF: 2026-10-01. Recheck on the next Claude Code release.

Python 3.8+, standard library only: these scripts run from a consumer checkout
where no third-party package is provisioned.
"""

import argparse
import json
import os
import re
import sys

MIN_PYTHON = (3, 8)

# The complete `prompt.md` frontmatter key set. An unknown key is an error in the
# binary ("prompt.md: unknown frontmatter key"), which is why this is a FAIL.
PROMPT_KEYS = frozenset(
    [
        "schema_version",
        "name",
        "description",
        "tags",
        "plugins",
        "runs",
        "expected_outcome",
        "model",
        "max_turns",
        "timeout_seconds",
        "allowed_tools",
        "append_system_prompt",
        "env",
    ]
)

# Keys the binary accepts in `prompt.md` that the reference page does not list.
# They load, so they are no FAIL; undocumented, they can change without notice,
# which is a WARN.
UNDOCUMENTED_PROMPT_KEYS = frozenset(["artifact_publish", "growthbook_overrides"])

# `case.yaml` nests the run fields under `execution`, where `prompt.md` keeps
# them flat. Both spellings feed the same bounds check below.
EXECUTION_KEYS = ("max_turns", "timeout_seconds", "allowed_tools", "env")

GRADER_TYPES = ("regex", "tool_order", "tool_used", "file_exists", "llm", "baseline")
TYPE_MESSAGE = 'frontmatter must include "type:" (%s)' % " | ".join(
    ["regex", "tool_order", "tool_used", "file_exists", "llm", "baseline"]
)

# Per-type option sets. `name` is common here rather than yaml-only: the
# `case.yaml` grader list requires it, and no source records the `.md` layout
# rejecting it, so accepting it invents no rejection the binary does not make.
GRADER_COMMON = frozenset(["type", "weight", "arm", "name"])
GRADER_FIELDS = {
    "regex": frozenset(["pattern", "flags", "match", "target"]),
    "tool_used": frozenset(["tool", "input_match", "min", "max"]),
    "tool_order": frozenset(["before", "after"]),
    "file_exists": frozenset(["path", "exists"]),
    "llm": frozenset(["criteria", "focus"]),
    "baseline": frozenset(["baseline_file", "criteria"]),
}
JUDGE_TYPES = frozenset(["llm", "baseline"])
ARMS = ("with-only", "both")

# Tools a case may list without an operator grant. Everything else is removed
# from the session and reported on stderr as `not granted`, so the case runs
# without the tool it was written around. We mirror the page's no-grant list.
# - Pointer: when this set may be stale, fetch
#   https://code.claude.com/docs/en/plugin-evals#grant-tools live.
# - As of: 2026-10-10
# - Recheck trigger: that section's allowed-tools sentence changes.
READ_ONLY_TOOLS = frozenset(
    [
        "Read",
        "Glob",
        "Grep",
        "NotebookRead",
        "Skill",
        "AskUserQuestion",
        "Agent",
        "TodoWrite",
        "TaskCreate",
        "TaskGet",
        "TaskList",
        "TaskUpdate",
        "TaskStop",
    ]
)

# Tools Claude Code removed. No grant restores one, so suggesting
# --allow-tools would send the case to a paid run without it.
# - Pointer: when a tool here may be back, or another was removed, fetch
#   https://code.claude.com/docs/en/changelog live (TaskOutput: 2.1.277).
# - As of: 2026-10-10
# - Recheck trigger: a release note removes or restores a tool a case can list.
REMOVED_TOOLS = frozenset(["TaskOutput"])

# (field, minimum, maximum) for the run fields the schema bounds.
BOUNDS = (("runs", 1, 50), ("max_turns", 1, 200), ("timeout_seconds", 1, 3600))

# The `schema_version` major the binary supports; a newer major is refused, and
# so is a value with no leading major. A case with no `case.yaml` gets a default
# `schema_version` and takes its directory name as `name`; once a `case.yaml`
# exists, the two come from it or from `prompt.md` frontmatter, or the case
# fails to load.
SCHEMA_MAJOR = 1
SCHEMA_MAJOR_PREFIX = re.compile(r"^\s*([+-]?[0-9]+)")

# The options each grader type marks required. A `graders/*.md` body stands in
# for the option named in BODY_FIELD when the frontmatter leaves it out.
GRADER_REQUIRED = {
    "regex": ("pattern",),
    "tool_used": ("tool",),
    "tool_order": ("before", "after"),
    "file_exists": ("path",),
    "llm": ("criteria",),
    "baseline": ("baseline_file", "criteria"),
}
BODY_FIELD = {"regex": "pattern", "llm": "criteria", "baseline": "criteria"}

# The double-quoted escapes this subset translates. Anything else is a ParseError
# rather than a silent drop: YAML rejects an unknown escape too, so translating
# `\d` to `d` would green-light input the binary refuses.
ESCAPES = {"\\": "\\", '"': '"', "/": "/", "n": "\n", "t": "\t", "r": "\r"}

ENV_KEY = re.compile(r"^EVAL_[A-Z0-9_]*$")
KEY_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.\-]*)[ \t]*:(?:[ \t]+(.*))?$")
INT_SCALAR = re.compile(r"^[-+]?[0-9]+$")
FLOAT_SCALAR = re.compile(r"^[-+]?[0-9]*\.[0-9]+$")

# Never a case, whatever they contain: results are run output and mocks answer
# tool calls. Anything else inside a case directory belongs to that case.
SKIP_DIRS = frozenset(["results", "mocks", "graders", "node_modules", "__pycache__"])

# Sample answers live beside graders/, never inside it, so the binary never
# loads one as a grader, and a run cannot read the eval directory, so the agent
# never sees them.
SAMPLES_DIR = "samples"
SAMPLE_KEYS = ("pass", "fail")
DETERMINISTIC_TYPES = frozenset(["regex", "tool_used", "tool_order", "file_exists"])

# JavaScript RegExp flags that change matching, and their `re` equivalents.
# `g` and `d` do not change whether a fresh regex matches; `u` is the default
# for a Python str pattern.
JS_FLAGS = {"i": re.IGNORECASE, "m": re.MULTILINE, "s": re.DOTALL}
NEUTRAL_FLAGS = frozenset("gdu")
COUNT_MATCH = re.compile(r"^count:([0-9]+)$")
JS_NAMED_GROUP = re.compile(r"\(\?<(?![=!])")
JS_NAMED_BACKREF = re.compile(r"\\k<([A-Za-z_][A-Za-z0-9_]*)>")
GLOB_SPECIAL = frozenset(".+^${}()|[]\\")


class ParseError(Exception):
    """A construct outside the supported YAML subset."""

    def __init__(self, construct):
        Exception.__init__(self, construct)
        self.construct = construct


class Unmirrored(Exception):
    """A grader setting this script cannot reproduce offline."""


# --------------------------------------------------------------------------
# YAML subset parser
# --------------------------------------------------------------------------


def _prepare(text):
    """Strip comments and blank lines, returning (indent, content) pairs."""
    prepared = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        body = raw.lstrip(" ")
        if body[:1] == "\t" or "\t" in raw[: len(raw) - len(body)]:
            raise ParseError("tab indentation")
        if stripped in ("---", "..."):
            raise ParseError("document marker")
        if stripped.startswith("<<:"):
            raise ParseError("merge key")
        prepared.append((len(raw) - len(body), stripped))
    return prepared


def _scalar(text):
    """Convert a plain scalar to int, float, bool, None, or str."""
    if text in ("null", "~", ""):
        return None
    if text in ("true", "True"):
        return True
    if text in ("false", "False"):
        return False
    if INT_SCALAR.match(text):
        return int(text)
    if FLOAT_SCALAR.match(text):
        return float(text)
    return text


def _read_quoted(text, start):
    """Read one quoted scalar, returning (value, index after the closing quote)."""
    quote = text[start]
    index = start + 1
    chars = []
    while index < len(text):
        char = text[index]
        if quote == '"' and char == "\\":
            if index + 1 >= len(text):
                break
            following = text[index + 1]
            if following not in ESCAPES:
                raise ParseError("unsupported escape")
            chars.append(ESCAPES[following])
            index += 2
            continue
        if char == quote:
            # A single-quoted scalar escapes its quote by doubling it.
            if quote == "'" and text[index + 1 : index + 2] == "'":
                chars.append("'")
                index += 2
                continue
            return "".join(chars), index + 1
        chars.append(char)
        index += 1
    raise ParseError("quoted scalar spanning lines")


def _is_key_separator(text, index):
    """True when the colon at `index` ends a flow-mapping key.

    A colon inside a plain scalar is content, not a delimiter: YAML makes it a
    separator only where what follows ends the scalar, which is what keeps
    `{ EVAL_URL: https://example.com }` and `{ EVAL_AT: 12:30 }` intact.
    """
    return text[index + 1 : index + 2] in ("", " ", "\t", ",", "]", "}")


def _read_flow(text, start):
    """Read one flow collection, returning (value, index after its closer)."""
    opener = text[start]
    closer = "]" if opener == "[" else "}"
    container = [] if opener == "[" else {}
    index = start + 1
    pending_key = None
    buffer = []

    def flush():
        raw = "".join(buffer).strip()
        buffer[:] = []
        return raw

    def place(value, raw_was_quoted):
        if opener == "[":
            container.append(value)
        else:
            if pending_key is None:
                raise ParseError("flow mapping entry without a key")
            container[pending_key] = value
        return raw_was_quoted

    while index < len(text):
        char = text[index]
        if char in "\"'":
            value, index = _read_quoted(text, index)
            buffer.append("\0Q")  # marker: the buffer holds a parsed string
            buffer.append(value)
            continue
        if char in "[{":
            value, index = _read_flow(text, index)
            place(value, True)
            pending_key = None
            buffer[:] = []
            continue
        if char == ":" and opener == "{" and _is_key_separator(text, index):
            if pending_key is not None:
                raise ParseError("flow mapping entry with two key separators")
            pending_key = _unmark(flush())
            index += 1
            continue
        if char == ",":
            raw = flush()
            if raw != "":
                place(_unmark_scalar(raw), True)
            pending_key = None
            index += 1
            continue
        if char == closer:
            raw = flush()
            if raw != "":
                place(_unmark_scalar(raw), True)
            return container, index + 1
        if char in "]}":
            raise ParseError("mismatched flow collection")
        if char in "&*!":
            raise ParseError(_construct_for(char))
        buffer.append(char)
        index += 1
    raise ParseError("flow collection spanning lines")


def _unmark(raw):
    return raw[2:] if raw.startswith("\0Q") else raw


def _unmark_scalar(raw):
    if raw.startswith("\0Q"):
        return raw[2:]
    return _scalar(raw)


def _construct_for(char):
    return {"&": "anchor", "*": "alias", "!": "tag"}[char]


def _parse_value(text):
    """Parse the value half of a `key: value` line."""
    text = text.strip()
    if text == "":
        return None
    first = text[0]
    if first in "&*!":
        raise ParseError(_construct_for(first))
    if first in "|>":
        raise ParseError("block scalar")
    if first in "[{":
        value, index = _read_flow(text, 0)
        trailing = text[index:].strip()
        if trailing and not trailing.startswith("#"):
            raise ParseError("trailing content after a flow collection")
        return value
    if first in "\"'":
        value, index = _read_quoted(text, 0)
        trailing = text[index:].strip()
        if trailing and not trailing.startswith("#"):
            raise ParseError("trailing content after a quoted scalar")
        return value
    comment = text.find(" #")
    if comment != -1:
        text = text[:comment].rstrip()
    return _scalar(text)


def _parse_block(lines, index, indent, depth):
    """Parse the block collection starting at lines[index].

    `depth` counts MAPPING levels only. A sequence is not a level of its own:
    the `graders:` list's items are mappings at the same depth the list sits at,
    which is what lets a grader carry a block `target:` inside a case.yaml.
    """
    if lines[index][1].startswith("-"):
        return _parse_sequence(lines, index, indent, depth)
    return _parse_mapping(lines, index, indent, depth)


def _parse_mapping(lines, index, indent, depth):
    if depth > 3:
        raise ParseError("nesting deeper than three levels")
    mapping = {}
    while index < len(lines):
        line_indent, content = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent:
            raise ParseError("inconsistent indentation")
        if content.startswith("- "):
            raise ParseError("sequence item where a mapping key was expected")
        match = KEY_LINE.match(content)
        if not match:
            raise ParseError("unsupported line")
        key, inline = match.group(1), match.group(2)
        index += 1
        if inline is None or inline.strip() == "":
            nested = index < len(lines) and lines[index][0] > line_indent
            if nested:
                mapping[key], index = _parse_block(
                    lines, index, lines[index][0], depth + 1
                )
            else:
                mapping[key] = None
        else:
            mapping[key] = _parse_value(inline)
    return mapping, index


def _parse_sequence(lines, index, indent, depth):
    items = []
    while index < len(lines):
        line_indent, content = lines[index]
        if line_indent < indent or not content.startswith("-"):
            break
        if line_indent > indent:
            raise ParseError("inconsistent indentation")
        body = content[1:]
        offset = 1 + (len(body) - len(body.lstrip(" ")))
        body = body.strip()
        if body.startswith("-"):
            raise ParseError("nested sequence")
        index += 1
        if body == "":
            if index < len(lines) and lines[index][0] > line_indent:
                if lines[index][1].startswith("-"):
                    raise ParseError("nested sequence")
                item, index = _parse_block(lines, index, lines[index][0], depth)
                items.append(item)
                continue
            items.append(None)
            continue
        if KEY_LINE.match(body):
            item_indent = line_indent + offset
            spliced = [(item_indent, body)] + lines[index:]
            item, consumed = _parse_mapping(spliced, 0, item_indent, depth)
            items.append(item)
            index += consumed - 1
            continue
        items.append(_parse_value(body))
    return items, index


def parse_yaml(text):
    """Parse a YAML-subset document into a dict. Raises ParseError otherwise."""
    lines = _prepare(text)
    if not lines:
        return {}
    if lines[0][0] != 0:
        raise ParseError("inconsistent indentation")
    value, index = _parse_block(lines, 0, 0, 1)
    if index != len(lines):
        raise ParseError("unsupported line")
    if not isinstance(value, dict):
        raise ParseError("top-level sequence")
    return value


def split_markdown(text):
    """Return (frontmatter block or None, body) of a markdown file."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "\n".join(lines[1:index]), "\n".join(lines[index + 1 :])
    raise ParseError("unterminated frontmatter")


def split_frontmatter(text):
    """Return the frontmatter block of a markdown file, or None when it has none."""
    return split_markdown(text)[0]


# --------------------------------------------------------------------------
# Findings
# --------------------------------------------------------------------------


class Finding(object):
    def __init__(self, level, case, path, message):
        self.level = level
        self.case = case
        self.path = path
        self.message = message

    def location(self):
        if self.case and self.path:
            return self.case + "/" + self.path
        return self.case or self.path

    def line(self):
        return "%s %s: %s" % (self.level, self.location(), self.message)

    def as_dict(self):
        return {
            "level": self.level,
            "case": self.case,
            "file": self.path,
            "message": self.message,
        }

    def sort_key(self):
        return (self.case, self.path, self.level, self.message)


def unparsed(case, path, error):
    return Finding(
        "FAIL",
        case,
        path,
        "frontmatter not parsed (%s); simplify or run the CLI" % error.construct,
    )


# --------------------------------------------------------------------------
# Case discovery and validation
# --------------------------------------------------------------------------


def discover_cases(eval_dir):
    """Every directory under eval_dir holding a prompt.md or a case.yaml."""
    cases = []
    for dirpath, dirnames, filenames in os.walk(eval_dir):
        dirnames[:] = sorted(
            name
            for name in dirnames
            if name not in SKIP_DIRS and not name.startswith(".")
        )
        if dirpath == eval_dir:
            continue
        if "prompt.md" in filenames or "case.yaml" in filenames:
            cases.append(dirpath)
            dirnames[:] = []
    return sorted(cases)


def read_text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def check_bounds(fields, case, findings):
    """Bounds the binary enforces on the effective (merged) run fields."""
    for key, low, high in BOUNDS:
        if key not in fields:
            continue
        value, path = fields[key]
        if not isinstance(value, int) or isinstance(value, bool):
            message = '%s "%s" is not a number' % (key, value)
        elif value > high:
            message = "%s %d over the maximum %d" % (key, value, high)
        elif value < low:
            message = "%s %d below the minimum %d" % (key, value, low)
        else:
            continue
        findings.append(Finding("FAIL", case, path, message))

    if "env" not in fields:
        return
    value, path = fields["env"]
    if not isinstance(value, dict):
        findings.append(Finding("FAIL", case, path, "env must be a mapping"))
        return
    for key in sorted(value):
        if not ENV_KEY.match(str(key)):
            findings.append(
                Finding(
                    "FAIL",
                    case,
                    path,
                    'env key "%s" must match EVAL_[A-Z0-9_]* or the case\'s '
                    "runs fail" % key,
                )
            )


def check_schema_version(value, case, path, findings):
    """FAIL a schema_version that is not a string, has no leading major, or has
    a major newer than the binary supports."""
    if not isinstance(value, str):
        findings.append(
            Finding(
                "FAIL",
                case,
                path,
                'schema_version must be a quoted string such as "1.1"',
            )
        )
        return
    match = SCHEMA_MAJOR_PREFIX.match(value.split(".")[0])
    if not match:
        findings.append(
            Finding(
                "FAIL",
                case,
                path,
                'schema_version "%s" is not a valid version string' % value,
            )
        )
    elif int(match.group(1)) > SCHEMA_MAJOR:
        findings.append(
            Finding(
                "FAIL",
                case,
                path,
                'schema_version "%s" is a major newer than %d, which the binary '
                "refuses" % (value, SCHEMA_MAJOR),
            )
        )


def check_identity(identity, prompt, prompt_file, case, findings):
    """FAIL a case missing a field the binary requires once the files merge."""
    for key in ("schema_version", "name"):
        if key not in identity:
            findings.append(
                Finding(
                    "FAIL",
                    case,
                    "case.yaml",
                    '"%s" is required; set it in case.yaml or in prompt.md '
                    "frontmatter" % key,
                )
            )
    if "schema_version" in identity:
        value, path = identity["schema_version"]
        check_schema_version(value, case, path, findings)
    if "name" in identity:
        value, path = identity["name"]
        if not isinstance(value, str) or not value:
            findings.append(
                Finding("FAIL", case, path, "name must be a non-empty string")
            )
    if not prompt:
        findings.append(
            Finding(
                "FAIL",
                case,
                prompt_file,
                "no prompt; write it as the prompt.md body or as execution.prompt "
                "in case.yaml",
            )
        )


def check_tools(fields, case, findings):
    """Report tools the operator must grant, and say whether the case can write."""
    if "allowed_tools" not in fields:
        return False
    value, path = fields["allowed_tools"]
    if not isinstance(value, list):
        findings.append(Finding("FAIL", case, path, "allowed_tools must be a list"))
        return False
    tools = [str(tool) for tool in value if str(tool) not in READ_ONLY_TOOLS]
    gated = [tool for tool in tools if tool not in REMOVED_TOOLS]
    for tool in tools:
        if tool in REMOVED_TOOLS:
            findings.append(
                Finding(
                    "WARN",
                    case,
                    path,
                    "allowed_tools lists %s, which Claude Code removed; no grant "
                    "restores it, so drop it or rewrite the case" % tool,
                )
            )
    for tool in gated:
        findings.append(
            Finding(
                "WARN",
                case,
                path,
                "allowed_tools lists %s, which a case cannot grant itself; pass "
                "--allow-tools or the tool is removed from the session" % tool,
            )
        )
    return bool(gated)


def check_grader(case, path, options, findings):
    """One grader's type, option set, weight, arm, and documented mistakes."""
    kind = options.get("type")
    if kind not in GRADER_TYPES:
        findings.append(Finding("FAIL", case, path, TYPE_MESSAGE))
        return
    allowed = GRADER_COMMON | GRADER_FIELDS[kind]
    for key in sorted(options):
        if key not in allowed:
            findings.append(
                Finding(
                    "FAIL",
                    case,
                    path,
                    'unknown grader option "%s" for type %s' % (key, kind),
                )
            )
    for key in GRADER_REQUIRED[kind]:
        if key not in options:
            findings.append(
                Finding(
                    "FAIL",
                    case,
                    path,
                    'grader type %s requires "%s"' % (kind, key),
                )
            )
    if "weight" in options:
        weight = options["weight"]
        if not isinstance(weight, (int, float)) or isinstance(weight, bool):
            findings.append(
                Finding("FAIL", case, path, 'weight "%s" is not a number' % weight)
            )
        elif weight <= 0:
            findings.append(
                Finding("FAIL", case, path, "weight %s is not positive" % weight)
            )
    if "arm" in options and options["arm"] not in ARMS:
        findings.append(
            Finding(
                "FAIL",
                case,
                path,
                'arm "%s" must be with-only or both' % options["arm"],
            )
        )
    looks_at = options.get("target") if kind == "regex" else options.get("focus")
    if looks_at == "files":
        findings.append(
            Finding(
                "WARN",
                case,
                path,
                "target: files reads the list of paths Claude created, not their "
                "contents; use { source: file, path: <p> } for contents",
            )
        )
    pattern = options.get("pattern")
    if kind == "regex" and isinstance(pattern, str) and "(?i)" in pattern:
        findings.append(
            Finding(
                "WARN",
                case,
                path,
                "inline (?i) is not supported by the grader's regex engine; put "
                "the flag in flags: i",
            )
        )


def collect_graders(case_dir, case, yaml_data, findings):
    """The union of the case.yaml grader list and graders/*.md, in that order."""
    graders = []
    listed = (yaml_data or {}).get("graders")
    if listed is not None:
        if not isinstance(listed, list):
            findings.append(
                Finding("FAIL", case, "case.yaml", "graders must be a list")
            )
        else:
            for position, entry in enumerate(listed, start=1):
                if not isinstance(entry, dict):
                    findings.append(
                        Finding(
                            "FAIL",
                            case,
                            "case.yaml",
                            "grader entry %d is not a mapping" % position,
                        )
                    )
                    continue
                name = entry.get("name")
                if not name:
                    findings.append(
                        Finding(
                            "FAIL",
                            case,
                            "case.yaml",
                            "grader entry %d has no name" % position,
                        )
                    )
                    name = "entry-%d" % position
                graders.append((str(name), entry, "case.yaml"))

    grader_dir = os.path.join(case_dir, "graders")
    if os.path.isdir(grader_dir):
        for filename in sorted(os.listdir(grader_dir)):
            if not filename.endswith(".md"):
                continue
            path = "graders/" + filename
            try:
                block, body = split_markdown(
                    read_text(os.path.join(grader_dir, filename))
                )
            except ParseError as error:
                findings.append(unparsed(case, path, error))
                continue
            except OSError as error:
                findings.append(
                    Finding("FAIL", case, path, "could not read (%s)" % error)
                )
                continue
            if block is None:
                findings.append(Finding("FAIL", case, path, TYPE_MESSAGE))
                continue
            try:
                options = parse_yaml(block)
            except ParseError as error:
                findings.append(unparsed(case, path, error))
                continue
            kind = options.get("type") if isinstance(options, dict) else None
            field = BODY_FIELD.get(kind) if isinstance(kind, str) else None
            if field and field not in options and body.strip():
                options[field] = body.strip()
            graders.append((filename[:-3], options, path))
    return graders


# --------------------------------------------------------------------------
# Sample answers: deterministic graders run offline
# --------------------------------------------------------------------------


def js_regex(pattern, flags=""):
    """Compile a JavaScript regex with Python's re, or raise Unmirrored."""
    if not isinstance(pattern, str) or not isinstance(flags, str):
        raise Unmirrored("pattern and flags must be strings")
    compiled_flags = 0
    for flag in flags:
        if flag in JS_FLAGS:
            compiled_flags |= JS_FLAGS[flag]
        elif flag not in NEUTRAL_FLAGS:
            raise Unmirrored("flag %s has no offline equivalent" % flag)
    source = JS_NAMED_GROUP.sub("(?P<", pattern)
    source = JS_NAMED_BACKREF.sub(r"(?P=\1)", source)
    try:
        return re.compile(source, compiled_flags)
    except re.error as error:
        raise Unmirrored("pattern does not compile offline (%s)" % error)


def grade_regex(options, text):
    regex = js_regex(options.get("pattern"), options.get("flags") or "")
    mode = options.get("match", "contains")
    if mode in ("contains", "not_contains"):
        found = regex.search(text) is not None
        if mode == "contains":
            return found, "pattern found" if found else "pattern not found"
        return not found, "pattern found, expected absent" if found else "absent"
    count = COUNT_MATCH.match(str(mode))
    if not count:
        raise Unmirrored('match mode "%s"' % mode)
    found = sum(1 for _ in regex.finditer(text))
    return (
        found == int(count.group(1)),
        "found %d matches, expected %s" % (found, count.group(1)),
    )


def call_matches(call, spec):
    """One call against a tool name or a {tool, input_match} mapping."""
    if isinstance(spec, str):
        spec = {"tool": spec}
    if not isinstance(spec, dict):
        raise Unmirrored("a tool spec must be a name or a mapping")
    if call["tool"] != spec.get("tool"):
        return False
    if not spec.get("input_match"):
        return True
    # The binary matches the compact JSON encoding of the call's input.
    text = json.dumps(call.get("input", {}), separators=(",", ":"), ensure_ascii=False)
    return js_regex(spec["input_match"]).search(text) is not None


def grade_tool_used(options, calls):
    spec = {"tool": options.get("tool"), "input_match": options.get("input_match")}
    count = sum(1 for call in calls if call_matches(call, spec))
    low = options.get("min")
    low = 1 if low is None else low
    high = options.get("max")
    for bound in (low, high):
        if bound is not None and (
            not isinstance(bound, int) or isinstance(bound, bool)
        ):
            raise Unmirrored("min and max must be whole numbers")
    passed = count >= low and (high is None or count <= high)
    return passed, "%s called %dx, expected %s..%s" % (
        spec["tool"],
        count,
        low,
        "unbounded" if high is None else high,
    )


def grade_tool_order(options, calls):
    def first(spec):
        for index, call in enumerate(calls):
            if call_matches(call, spec):
                return index
        return -1

    before, after = first(options.get("before")), first(options.get("after"))
    if before == -1 or after == -1:
        return False, '"%s" tool never called' % ("before" if before == -1 else "after")
    return before < after, "before@%d, after@%d" % (before, after)


def glob_regex(glob):
    """The binary's glob: anchored, `*` within a segment, `**/` any depth."""
    if not isinstance(glob, str):
        raise Unmirrored("path must be a string")
    out, index = "^", 0
    while index < len(glob):
        char = glob[index]
        if glob.startswith("**/", index):
            out, index = out + "(?:.*/)?", index + 3
            continue
        if glob.startswith("**", index):
            out, index = out + ".*", index + 2
            continue
        if char == "*":
            out += "[^/]*"
        elif char == "?":
            out += "."
        else:
            out += "\\" + char if char in GLOB_SPECIAL else char
        index += 1
    return re.compile(out + "$")


def grade_file_exists(options, paths):
    regex = glob_regex(options.get("path"))
    found = any(regex.search(path.strip()) for path in paths if path.strip())
    expected = options.get("exists", True)
    if not isinstance(expected, bool):
        raise Unmirrored("exists must be true or false")
    return found == expected, "%s %s" % (
        options.get("path"),
        "created" if found else "not created",
    )


GRADE = {
    "regex": grade_regex,
    "tool_used": grade_tool_used,
    "tool_order": grade_tool_order,
    "file_exists": grade_file_exists,
}


def answer_error(kind, answer):
    """What `answer` must be for this grader type, or None when it fits."""
    if kind == "regex":
        return None if isinstance(answer, str) else "a string"
    if kind == "file_exists":
        fits = isinstance(answer, list) and all(isinstance(p, str) for p in answer)
        return None if fits else "a list of created paths"
    fits = isinstance(answer, list) and all(
        isinstance(call, dict)
        and isinstance(call.get("tool"), str)
        and set(call) <= {"tool", "input"}
        for call in answer
    )
    return None if fits else 'a list of {"tool", "input"} calls'


def sample_shape_error(data):
    if not isinstance(data, dict):
        return "the file must hold a JSON object"
    for key in sorted(data):
        if key not in SAMPLE_KEYS:
            return 'unknown key "%s"; use pass and fail' % key
        if not isinstance(data[key], list):
            return "%s must be a list" % key
        for number, item in enumerate(data[key], start=1):
            if (
                not isinstance(item, dict)
                or "answer" not in item
                or not set(item) <= {"answer", "why"}
            ):
                return '%s entry %d must be {"answer": ..., "why": ...}' % (key, number)
    return None


def load_samples(case_dir, case, findings):
    """Every samples/<grader>.json in the case, as {name: (path, data)}."""
    directory = os.path.join(case_dir, SAMPLES_DIR)
    loaded = {}
    if not os.path.isdir(directory):
        return loaded
    for filename in sorted(os.listdir(directory)):
        if not filename.endswith(".json"):
            continue
        path = SAMPLES_DIR + "/" + filename
        try:
            data = json.loads(read_text(os.path.join(directory, filename)))
            problem = sample_shape_error(data)
        except (OSError, ValueError) as error:
            problem = str(error)
        if problem:
            findings.append(
                Finding("FAIL", case, path, "samples not parsed (%s)" % problem)
            )
            continue
        loaded[filename[:-5]] = (path, data)
    return loaded


def run_samples(case, path, kind, options, data, findings):
    """Grade every sample; a mismatch with its expected verdict is a FAIL."""
    for key in SAMPLE_KEYS:
        if not data.get(key):
            findings.append(
                Finding(
                    "WARN",
                    case,
                    path,
                    "no must-%s answers, so the check cannot catch a grader that "
                    "%s everything" % (key, "rejects" if key == "pass" else "accepts"),
                )
            )
    for key in SAMPLE_KEYS:
        for number, item in enumerate(data.get(key) or [], start=1):
            label = "must-%s sample %d" % (key, number)
            if item.get("why"):
                label += ' ("%s")' % item["why"]
            problem = answer_error(kind, item["answer"])
            if problem:
                findings.append(
                    Finding(
                        "FAIL",
                        case,
                        path,
                        "%s: answer must be %s for a %s grader"
                        % (label, problem, kind),
                    )
                )
                continue
            try:
                passed, explanation = GRADE[kind](options, item["answer"])
            except Unmirrored as error:
                findings.append(
                    Finding("WARN", case, path, "samples not checked: %s" % error)
                )
                return
            if passed != (key == "pass"):
                findings.append(
                    Finding(
                        "FAIL",
                        case,
                        path,
                        "%s %s the grader (%s)"
                        % (label, "fails" if key == "pass" else "passes", explanation),
                    )
                )


def check_samples(case, graders, samples, findings):
    """Run deterministic graders over their samples; flag what goes unchecked."""
    names = set()
    for name, options, grader_path in graders:
        names.add(name)
        if not isinstance(options, dict) or options.get("type") not in GRADER_TYPES:
            continue
        kind = options["type"]
        if name not in samples:
            if kind in DETERMINISTIC_TYPES:
                findings.append(
                    Finding(
                        "WARN",
                        case,
                        grader_path,
                        "no sample answers; add %s/%s.json with answers this "
                        "grader must pass and must reject" % (SAMPLES_DIR, name),
                    )
                )
            continue
        path, data = samples[name]
        if kind in JUDGE_TYPES:
            count = sum(len(data.get(key) or []) for key in SAMPLE_KEYS)
            findings.append(
                Finding(
                    "WARN",
                    case,
                    path,
                    "%d sample answers need judge calibration; this check never "
                    "calls a model" % count,
                )
            )
            continue
        run_samples(case, path, kind, options, data, findings)
    for name in sorted(set(samples) - names):
        findings.append(
            Finding(
                "WARN",
                case,
                samples[name][0],
                'no grader named "%s" in this case, so these samples check nothing'
                % name,
            )
        )


def analyze_case(case_dir, case, findings):
    """Validate one case, appending its findings."""
    fields = {}
    yaml_data = None
    yaml_path = os.path.join(case_dir, "case.yaml")
    prompt_path = os.path.join(case_dir, "prompt.md")
    # The case identity and prompt, each as (value, file it came from). Without
    # a case.yaml the binary supplies the identity; with one it supplies none.
    identity = {}
    prompt = ""
    unread = False

    if os.path.isfile(yaml_path):
        try:
            text = read_text(yaml_path)
            if text.lstrip().startswith("---"):
                text = text.lstrip()[3:]
            yaml_data = parse_yaml(text)
        except ParseError as error:
            unread = True
            findings.append(unparsed(case, "case.yaml", error))
        except OSError as error:
            unread = True
            findings.append(
                Finding("FAIL", case, "case.yaml", "could not read (%s)" % error)
            )
        if isinstance(yaml_data, dict):
            for key in ("schema_version", "name"):
                if key in yaml_data:
                    identity[key] = (yaml_data[key], "case.yaml")
            if "runs" in yaml_data:
                fields["runs"] = (yaml_data["runs"], "case.yaml")
            execution = yaml_data.get("execution")
            if isinstance(execution, dict):
                if isinstance(execution.get("prompt"), str):
                    prompt = execution["prompt"].strip()
                for key in EXECUTION_KEYS:
                    if key in execution:
                        fields[key] = (execution[key], "case.yaml")
    if not yaml_data:
        identity = {
            "schema_version": ("1.1", "case.yaml"),
            "name": (os.path.basename(case_dir), "case.yaml"),
        }

    if os.path.isfile(prompt_path):
        block = None
        try:
            block, body = split_markdown(read_text(prompt_path))
            prompt = body.strip() or prompt
        except ParseError as error:
            unread = True
            findings.append(unparsed(case, "prompt.md", error))
        except OSError as error:
            unread = True
            findings.append(
                Finding("FAIL", case, "prompt.md", "could not read (%s)" % error)
            )
        if block is not None:
            try:
                prompt_fm = parse_yaml(block)
            except ParseError as error:
                unread = True
                findings.append(unparsed(case, "prompt.md", error))
                prompt_fm = None
            if prompt_fm is not None:
                for key in sorted(prompt_fm):
                    if key in UNDOCUMENTED_PROMPT_KEYS:
                        findings.append(
                            Finding(
                                "WARN",
                                case,
                                "prompt.md",
                                'frontmatter key "%s" loads but is undocumented, so '
                                "it can change without notice" % key,
                            )
                        )
                    elif key not in PROMPT_KEYS:
                        findings.append(
                            Finding(
                                "FAIL",
                                case,
                                "prompt.md",
                                'unknown frontmatter key "%s"' % key,
                            )
                        )
                # prompt.md frontmatter overrides the matching case.yaml field,
                # so each check reads the effective value and reports the file
                # the value actually came from.
                for key in ("schema_version", "name"):
                    if key in prompt_fm:
                        identity[key] = (prompt_fm[key], "prompt.md")
                for key in ("runs",) + EXECUTION_KEYS:
                    if key in prompt_fm:
                        fields[key] = (prompt_fm[key], "prompt.md")

    if not unread:
        prompt_file = "prompt.md" if os.path.isfile(prompt_path) else "case.yaml"
        check_identity(identity, prompt, prompt_file, case, findings)
    check_bounds(fields, case, findings)
    can_write = check_tools(fields, case, findings)

    graders = collect_graders(case_dir, case, yaml_data, findings)
    if not graders:
        findings.append(
            Finding(
                "FAIL",
                case,
                "graders/",
                "no grader defined; a case needs at least one",
            )
        )
    seen = {}
    file_exists_sites = []
    kinds = []
    for name, options, path in graders:
        if name in seen:
            findings.append(
                Finding("FAIL", case, path, 'duplicate grader name "%s"' % name)
            )
        seen[name] = path
        if not isinstance(options, dict):
            findings.append(Finding("FAIL", case, path, TYPE_MESSAGE))
            continue
        check_grader(case, path, options, findings)
        kinds.append(options.get("type"))
        if options.get("type") == "file_exists":
            file_exists_sites.append(path)

    # A file_exists grader passes only on a file Claude CREATED during the run,
    # and every case runs in its own throwaway workspace, so it is this case's
    # own tool grant that decides whether anything can be created. Another
    # case's write tool cannot make this assertion satisfiable.
    if not can_write:
        for path in file_exists_sites:
            findings.append(
                Finding(
                    "WARN",
                    case,
                    path,
                    "file_exists in a read-only case: only files created during "
                    "the run count, and this case requests no write tool",
                )
            )

    check_samples(case, graders, load_samples(case_dir, case, findings), findings)

    if kinds and all(kind in JUDGE_TYPES for kind in kinds):
        findings.append(
            Finding(
                "WARN",
                case,
                "graders/",
                "every grader is a judge grader, the two types that cost money; "
                "pair one deterministic grader (regex, tool_used, tool_order, "
                "file_exists) with it",
            )
        )


def validate(eval_dir):
    """Validate a whole suite. Returns the findings, sorted."""
    findings = []
    cases = discover_cases(eval_dir)
    if not cases:
        findings.append(
            Finding(
                "FAIL",
                "",
                eval_dir,
                "no eval cases found; a case is a directory holding prompt.md "
                "or case.yaml",
            )
        )
        return findings

    for case_dir in cases:
        case = os.path.relpath(case_dir, eval_dir).replace(os.sep, "/")
        analyze_case(case_dir, case, findings)

    findings.sort(key=Finding.sort_key)
    return findings


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            "error: validate-cases needs Python %d.%d or newer\n" % MIN_PYTHON
        )
        return 2
    parser = argparse.ArgumentParser(
        prog="validate-cases",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        add_help=True,
    )
    parser.add_argument("eval_dir", help="the eval directory holding the cases")
    parser.add_argument(
        "--json", action="store_true", help="print the findings as JSON"
    )
    args = parser.parse_args(argv)

    eval_dir = os.path.abspath(args.eval_dir)
    if not os.path.isdir(eval_dir):
        sys.stderr.write("error: not a directory: %s\n" % args.eval_dir)
        return 2
    try:
        os.listdir(eval_dir)
    except OSError as error:
        sys.stderr.write("error: cannot read %s (%s)\n" % (args.eval_dir, error))
        return 2

    findings = validate(eval_dir)
    if args.json:
        print(json.dumps([finding.as_dict() for finding in findings], indent=2))
    else:
        for finding in findings:
            print(finding.line())
    return 1 if any(finding.level == "FAIL" for finding in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
