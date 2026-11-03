#!/usr/bin/env python3
"""check-matchers - prove the shared grader matchers and every grader built from them.

    check-matchers [--write] [--fragments <file>] <eval-dir>...

A case grader's regex is static text in case.yaml: the binary cannot call code
when it grades. So the shared sub-patterns live in one file,
`plugins/evals/matchers/fragments.json`, and a case that builds a grader from
them says how in `<case>/matchers.json`:

    {"no-token-shell": [{"use": "command_position"}, "curl\\\\b",
                        {"use": "token_argument"}, "AbCdEf"]}

Each value is a list of parts, joined in order: a string is literal regex, and
`{"use": <fragment>, "with": {<param>: <regex>}}` inserts a fragment, its
`{{param}}` slots filled. The joined text must equal the grader's `pattern`
(regex) or `input_match` (tool_used) in case.yaml; `--write` rewrites the
case.yaml line when it does not.

The check, every finding a FAIL:

- each fragment has a summary, its text, a probe grader built from it, and
  must-pass and must-fail samples, and every sample sorts the way its label says
  under Python's `re` and under node's `RegExp`;
- each matchers.json grader exists in case.yaml as a regex or tool_used grader,
  names only known fragments and parameters, and matches its rendered text;
- each such grader has `samples/<grader>.json` with must-pass and must-fail
  answers;
- every deterministic grader with samples, in every case that has a
  matchers.json, sorts its samples correctly under both engines.

node is required: the binary grades with JavaScript's RegExp, and a check that
skipped it would prove only the Python half.

Exit codes: 0 clean; 1 at least one FAIL; 2 usage error, node missing, or an
eval dir missing.

Python 3.8+, standard library only.
"""

import argparse
import importlib.util
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FRAGMENTS = os.path.normpath(
    os.path.join(HERE, "..", "..", "..", "matchers", "fragments.json")
)
MATCHERS = "matchers.json"
SLOT = re.compile(r"\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}")
FIELD = {"regex": "pattern", "tool_used": "input_match"}
FRAGMENT_KEYS = frozenset(["summary", "params", "text", "probe", "samples"])


def load_validator():
    spec = importlib.util.spec_from_file_location(
        "validate_cases", os.path.join(HERE, "validate-cases.py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


vc = load_validator()


class RenderError(Exception):
    pass


def render(parts, fragments):
    """Join a parts list into one regex string, or raise RenderError."""
    if not isinstance(parts, list) or not parts:
        raise RenderError("parts must be a non-empty list")
    out = []
    for part in parts:
        if isinstance(part, str):
            out.append(part)
            continue
        if not isinstance(part, dict) or not set(part) <= {"use", "with"}:
            raise RenderError('a part is a string or {"use": ..., "with": {...}}')
        name = part.get("use")
        if name not in fragments:
            raise RenderError('unknown fragment "%s"' % name)
        values = part.get("with") or {}
        params = fragments[name].get("params") or []
        if not isinstance(values, dict) or sorted(values) != sorted(params):
            raise RenderError(
                'fragment "%s" takes %s' % (name, ", ".join(params) or "no parameters")
            )
        text = fragments[name]["text"]
        for key, value in values.items():
            if not isinstance(value, str):
                raise RenderError(
                    'fragment "%s" parameter %s must be a string' % (name, key)
                )
            text = text.replace("{{%s}}" % key, value)
        out.append(text)
    return "".join(out)


def fragment_problem(name, fragment):
    if not isinstance(fragment, dict):
        return "must be an object"
    missing = sorted({"summary", "text", "probe", "samples"} - set(fragment))
    if missing:
        return "missing %s" % ", ".join(missing)
    extra = sorted(set(fragment) - FRAGMENT_KEYS)
    if extra:
        return "unknown key %s" % ", ".join(extra)
    if not isinstance(fragment["text"], str) or not fragment["text"]:
        return "text must be a non-empty string"
    slots = sorted(set(SLOT.findall(fragment["text"])))
    if slots != sorted(fragment.get("params") or []):
        return "params must list exactly the text's slots (%s)" % (
            ", ".join(slots) or "none"
        )
    probe = fragment["probe"]
    if not isinstance(probe, dict) or probe.get("type") not in FIELD:
        return "probe must be a regex or tool_used grader"
    if FIELD[probe["type"]] not in probe:
        return "probe needs %s parts" % FIELD[probe["type"]]
    shape = vc.sample_shape_error(fragment["samples"])
    if shape:
        return "samples: %s" % shape
    for key in vc.SAMPLE_KEYS:
        if not fragment["samples"].get(key):
            return "needs must-%s samples" % key
    return None


def grade_python(case, path, name, options, data, findings):
    """The Python half, keeping only FAILs: validate-cases owns the WARN tier."""
    found = []
    vc.run_samples(case, path, options["type"], options, data, found)
    for finding in found:
        if finding.level == "FAIL":
            findings.append(finding)
        elif "samples not checked" in finding.message:
            findings.append(
                vc.Finding(
                    "FAIL", case, path, '%s for grader "%s"' % (finding.message, name)
                )
            )


def check_fragments(fragments, findings, jobs):
    label = "matchers"
    for name in sorted(fragments):
        fragment = fragments[name]
        problem = fragment_problem(name, fragment)
        if problem:
            findings.append(
                vc.Finding(
                    "FAIL",
                    label,
                    "fragments.json",
                    'fragment "%s" %s' % (name, problem),
                )
            )
            continue
        options = dict(fragment["probe"])
        field = FIELD[options["type"]]
        try:
            options[field] = render(options[field], fragments)
        except RenderError as error:
            findings.append(
                vc.Finding(
                    "FAIL",
                    label,
                    "fragments.json",
                    'fragment "%s" probe: %s' % (name, error),
                )
            )
            continue
        path = "fragments.json#" + name
        grade_python(label, path, name, options, fragment["samples"], findings)
        jobs.extend(
            vc.js_jobs(
                label, [(name, options, path)], {name: (path, fragment["samples"])}
            )
        )


def write_field(case_yaml, name, field, value):
    """Rewrite one grader's field line in case.yaml as a single-quoted scalar."""
    if "\n" in value:
        raise RenderError("a rendered value cannot span lines")
    with open(case_yaml, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    head = re.compile(r"^(\s*)-\s+name:\s*['\"]?%s['\"]?\s*$" % re.escape(name))
    for start, line in enumerate(lines):
        match = head.match(line)
        if not match:
            continue
        indent = len(match.group(1))
        for index in range(start + 1, len(lines)):
            current = lines[index]
            stripped = current.lstrip()
            depth = len(current) - len(stripped)
            if stripped.startswith("- ") and depth <= indent:
                break
            if stripped.startswith(field + ":"):
                lines[index] = "%s%s: '%s'" % (
                    " " * depth,
                    field,
                    value.replace("'", "''"),
                )
                with open(case_yaml, "w", encoding="utf-8", newline="\n") as handle:
                    handle.write("\n".join(lines))
                return
    raise RenderError('no %s line for grader "%s" in case.yaml' % (field, name))


def check_case(case_dir, case, fragments, write, findings, jobs):
    try:
        with open(os.path.join(case_dir, MATCHERS), encoding="utf-8") as handle:
            matchers = json.load(handle)
    except (OSError, ValueError) as error:
        findings.append(vc.Finding("FAIL", case, MATCHERS, "not parsed (%s)" % error))
        return
    if not isinstance(matchers, dict) or not matchers:
        findings.append(
            vc.Finding("FAIL", case, MATCHERS, "must map grader names to parts")
        )
        return
    case_yaml = os.path.join(case_dir, "case.yaml")
    for attempt in (1, 2):
        try:
            with open(case_yaml, encoding="utf-8") as handle:
                data = vc.parse_yaml(handle.read()) or {}
        except (OSError, vc.ParseError) as error:
            findings.append(
                vc.Finding("FAIL", case, "case.yaml", "not parsed (%s)" % error)
            )
            return
        graders = {
            str(entry.get("name")): entry
            for entry in data.get("graders") or []
            if isinstance(entry, dict)
        }
        rewrote = False
        drift = []
        for name in sorted(matchers):
            options = graders.get(name)
            if not isinstance(options, dict) or options.get("type") not in FIELD:
                drift.append(
                    vc.Finding(
                        "FAIL",
                        case,
                        MATCHERS,
                        'no regex or tool_used grader "%s" in case.yaml' % name,
                    )
                )
                continue
            field = FIELD[options["type"]]
            try:
                rendered = render(matchers[name], fragments)
            except RenderError as error:
                drift.append(
                    vc.Finding(
                        "FAIL", case, MATCHERS, 'grader "%s": %s' % (name, error)
                    )
                )
                continue
            if options.get(field) == rendered:
                continue
            if write and attempt == 1:
                try:
                    write_field(case_yaml, name, field, rendered)
                    rewrote = True
                    continue
                except RenderError as error:
                    drift.append(vc.Finding("FAIL", case, "case.yaml", str(error)))
                    continue
            drift.append(
                vc.Finding(
                    "FAIL",
                    case,
                    "case.yaml",
                    'grader "%s" %s differs from its matchers.json build; '
                    "run check-matchers --write" % (name, field),
                )
            )
        if not rewrote:
            break
    findings.extend(drift)

    samples_found = []
    samples = vc.load_samples(case_dir, case, samples_found)
    findings.extend(f for f in samples_found if f.level == "FAIL")
    for name in sorted(matchers):
        entry = samples.get(name)
        if entry is None or not all(entry[1].get(key) for key in vc.SAMPLE_KEYS):
            findings.append(
                vc.Finding(
                    "FAIL",
                    case,
                    "%s/%s.json" % (vc.SAMPLES_DIR, name),
                    'grader "%s" is built from matchers, so it needs must-pass and '
                    "must-fail samples" % name,
                )
            )
    listed = [(name, options, "case.yaml") for name, options in sorted(graders.items())]
    for name, options, path in listed:
        if name in samples and options.get("type") in FIELD:
            grade_python(
                case, samples[name][0], name, options, samples[name][1], findings
            )
    jobs.extend(vc.js_jobs(case, listed, samples))


def discover(eval_dir):
    for root, dirs, files in os.walk(eval_dir):
        dirs[:] = sorted(d for d in dirs if d not in vc.SKIP_DIRS)
        if MATCHERS in files and "case.yaml" in files:
            yield root


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="check-matchers",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "eval_dirs", nargs="+", help="eval directories to scan for matchers.json"
    )
    parser.add_argument(
        "--write", action="store_true", help="rewrite drifted case.yaml lines"
    )
    parser.add_argument(
        "--fragments",
        default=FRAGMENTS,
        help="the fragments file (default: the plugin's)",
    )
    args = parser.parse_args(argv)

    if shutil.which("node") is None:
        sys.stderr.write(
            "error: node is not on PATH; the JavaScript half of the check cannot run\n"
        )
        return 2
    for eval_dir in args.eval_dirs:
        if not os.path.isdir(eval_dir):
            sys.stderr.write("error: not a directory: %s\n" % eval_dir)
            return 2
    try:
        with open(args.fragments, encoding="utf-8") as handle:
            fragments = json.load(handle)
    except (OSError, ValueError) as error:
        sys.stderr.write("error: cannot read %s (%s)\n" % (args.fragments, error))
        return 2

    findings, jobs = [], []
    check_fragments(fragments, findings, jobs)
    checked = 0
    for eval_dir in args.eval_dirs:
        for case_dir in discover(os.path.abspath(eval_dir)):
            case = os.path.relpath(
                case_dir, os.path.dirname(os.path.dirname(os.path.abspath(eval_dir)))
            )
            check_case(
                case_dir,
                case.replace(os.sep, "/"),
                fragments,
                args.write,
                findings,
                jobs,
            )
            checked += 1
    results, problem = vc.run_js_jobs(jobs)
    if results is None:
        findings.append(
            vc.Finding(
                "FAIL", "matchers", "node", "JavaScript check failed (%s)" % problem
            )
        )
    else:
        vc.judge_js_jobs(jobs, results, findings)

    findings.sort(key=vc.Finding.sort_key)
    for finding in findings:
        print(finding.line())
    failed = any(finding.level == "FAIL" for finding in findings)
    print(
        "check-matchers: %d fragments, %d cases with matchers, %d graders under JavaScript: %s"
        % (len(fragments), checked, len(jobs), "FAIL" if failed else "ok")
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
