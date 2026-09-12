#!/usr/bin/env python3
"""validate-cases - check a `claude plugin eval` suite without spending a cent.

    validate-cases <eval-dir> [--json]

Reads every case under <eval-dir> (a directory holding `prompt.md`, `case.yaml`,
or both, with one grader per file under `graders/`) and reports two tiers:

    FAIL  what the binary itself rejects, so the suite cannot load
    WARN  an authoring mistake the suite loads with and scores badly on

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
strict, and the bounds on `runs`, `max_turns`, `timeout_seconds`, `weight`, and
`env` key names. BASIS: the case schema read out of Claude Code 2.1.269 together
with the eval-suite reference page; recheck on the next Claude Code release,
which can add a key or move a bound, and re-derive both lists from the schema
rather than patching one value. AS OF: 2026-09-12. Page:
https://code.claude.com/docs/en/plugin-evals

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
# without the tool it was written around.
READ_ONLY_TOOLS = frozenset(
    [
        "Read",
        "Glob",
        "Grep",
        "NotebookRead",
        "Skill",
        "Agent",
        "TodoWrite",
        "TaskCreate",
        "TaskGet",
        "TaskList",
        "TaskUpdate",
        "TaskStop",
        "TaskOutput",
    ]
)

# (field, minimum, maximum) for the run fields the schema bounds.
BOUNDS = (("runs", 1, 50), ("max_turns", 1, 200), ("timeout_seconds", 1, 3600))

ENV_KEY = re.compile(r"^EVAL_[A-Z0-9_]*$")
KEY_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.\-]*)[ \t]*:(?:[ \t]+(.*))?$")
INT_SCALAR = re.compile(r"^[-+]?[0-9]+$")
FLOAT_SCALAR = re.compile(r"^[-+]?[0-9]*\.[0-9]+$")

# Never a case, whatever they contain: results are run output and mocks answer
# tool calls. Anything else inside a case directory belongs to that case.
SKIP_DIRS = frozenset(["results", "mocks", "graders", "node_modules", "__pycache__"])


class ParseError(Exception):
    """A construct outside the supported YAML subset."""

    def __init__(self, construct):
        Exception.__init__(self, construct)
        self.construct = construct


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
            chars.append({"n": "\n", "t": "\t", "r": "\r"}.get(following, following))
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
        if char == ":" and opener == "{":
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


def split_frontmatter(text):
    """Return the frontmatter block of a markdown file, or None when it has none."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "\n".join(lines[1:index])
    raise ParseError("unterminated frontmatter")


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


def check_tools(fields, case, findings):
    """Report tools the operator must grant, and say whether the case can write."""
    if "allowed_tools" not in fields:
        return False
    value, path = fields["allowed_tools"]
    if not isinstance(value, list):
        findings.append(Finding("FAIL", case, path, "allowed_tools must be a list"))
        return False
    gated = [str(tool) for tool in value if str(tool) not in READ_ONLY_TOOLS]
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
                block = split_frontmatter(read_text(os.path.join(grader_dir, filename)))
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
            graders.append((filename[:-3], options, path))
    return graders


def analyze_case(case_dir, case, findings):
    """Validate one case; returns (suite_can_write, file_exists grader sites)."""
    fields = {}
    yaml_data = None
    yaml_path = os.path.join(case_dir, "case.yaml")
    prompt_path = os.path.join(case_dir, "prompt.md")

    if os.path.isfile(yaml_path):
        try:
            text = read_text(yaml_path)
            if text.lstrip().startswith("---"):
                text = text.lstrip()[3:]
            yaml_data = parse_yaml(text)
        except ParseError as error:
            findings.append(unparsed(case, "case.yaml", error))
        except OSError as error:
            findings.append(
                Finding("FAIL", case, "case.yaml", "could not read (%s)" % error)
            )
        if isinstance(yaml_data, dict):
            if "runs" in yaml_data:
                fields["runs"] = (yaml_data["runs"], "case.yaml")
            execution = yaml_data.get("execution")
            if isinstance(execution, dict):
                for key in EXECUTION_KEYS:
                    if key in execution:
                        fields[key] = (execution[key], "case.yaml")

    if os.path.isfile(prompt_path):
        block = None
        try:
            block = split_frontmatter(read_text(prompt_path))
        except ParseError as error:
            findings.append(unparsed(case, "prompt.md", error))
        except OSError as error:
            findings.append(
                Finding("FAIL", case, "prompt.md", "could not read (%s)" % error)
            )
        if block is not None:
            try:
                prompt_fm = parse_yaml(block)
            except ParseError as error:
                findings.append(unparsed(case, "prompt.md", error))
                prompt_fm = None
            if prompt_fm is not None:
                for key in sorted(prompt_fm):
                    if key not in PROMPT_KEYS:
                        findings.append(
                            Finding(
                                "FAIL",
                                case,
                                "prompt.md",
                                'unknown frontmatter key "%s"' % key,
                            )
                        )
                # prompt.md frontmatter overrides the matching case.yaml field,
                # so the bounds check reads the effective value and reports the
                # file the value actually came from.
                for key in ("runs",) + EXECUTION_KEYS:
                    if key in prompt_fm:
                        fields[key] = (prompt_fm[key], "prompt.md")

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
            file_exists_sites.append((case, path))

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
    return can_write, file_exists_sites


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

    suite_can_write = False
    file_exists_sites = []
    for case_dir in cases:
        case = os.path.relpath(case_dir, eval_dir).replace(os.sep, "/")
        can_write, sites = analyze_case(case_dir, case, findings)
        suite_can_write = suite_can_write or can_write
        file_exists_sites.extend(sites)

    # A file_exists grader passes only on a file Claude CREATED during the run.
    # In a suite where no case asks for a write-capable tool, nothing is ever
    # created, so every such grader is unsatisfiable.
    if not suite_can_write:
        for case, path in file_exists_sites:
            findings.append(
                Finding(
                    "WARN",
                    case,
                    path,
                    "file_exists in a read-only suite: only files created during "
                    "the run count, and no case here requests a write tool",
                )
            )

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
