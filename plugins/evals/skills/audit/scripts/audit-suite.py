#!/usr/bin/env python3
"""audit-suite - static health audit for a `claude plugin eval` suite.

    audit-suite <plugin-dir|suite-dir> [--json]

Reports coverage and calibration gaps without calling a model or editing files:
  - skills with no case
  - skills with no deterministic triggering case
  - judged (llm or baseline) graders without labeled samples/<grader>.json,
    and PASS/FAIL label counts for judged graders that have samples
  - legacy-only skills (only skills/<skill>/evals/evals.json)
  - skills with no should-not-fire case (advisory)

Exit codes:
    0  target read and audited
    2  usage error, or target missing or unreadable
"""

import argparse
import importlib.util
import json
import os
import re
import sys

MIN_PYTHON = (3, 8)

HERE = os.path.dirname(os.path.abspath(__file__))
CASE_SKILLS_PY = os.path.normpath(
    os.path.join(HERE, os.pardir, os.pardir, os.pardir, "scripts", "case_skills.py")
)
VALIDATE_CASES_PY = os.path.normpath(
    os.path.join(HERE, os.pardir, os.pardir, "validate", "scripts", "validate-cases.py")
)

EVAL_DIR_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ROUTE_DESIGN = "/evals:design"
ROUTE_CALIBRATE = "/evals:plugin-eval"


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


case_skills = _load_module("evals_case_skills", CASE_SKILLS_PY)
validate_cases = _load_module("evals_validate_cases", VALIDATE_CASES_PY)


def _read_manifest(plugin_dir):
    for parts in ((".claude-plugin", "plugin.json"), ("plugin.json",)):
        path = os.path.join(plugin_dir, *parts)
        if not os.path.isfile(path):
            continue
        try:
            data = json.loads(validate_cases.read_text(path))
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}
    return None


def _is_plugin_dir(path):
    return _read_manifest(path) is not None or os.path.isdir(
        os.path.join(path, "skills")
    )


def _eval_dir_name(manifest):
    experimental = manifest.get("experimental") if isinstance(manifest, dict) else None
    named = experimental.get("evals") if isinstance(experimental, dict) else None
    if isinstance(named, str) and EVAL_DIR_NAME.match(named):
        return named
    return "evals"


def resolve_target(target):
    """Resolve a plugin or suite directory to (plugin_name, plugin_dir, eval_dir)."""
    target = os.path.abspath(target)
    if _is_plugin_dir(target):
        manifest = _read_manifest(target) or {}
        name = manifest.get("name")
        plugin = name if isinstance(name, str) and name else os.path.basename(target)
        eval_dir = os.path.join(target, _eval_dir_name(manifest))
        return plugin, target, eval_dir if os.path.isdir(eval_dir) else None

    root = validate_cases.containment_root(target)
    if root and root != target and _is_plugin_dir(root):
        manifest = _read_manifest(root) or {}
        name = manifest.get("name")
        plugin = name if isinstance(name, str) and name else os.path.basename(root)
        return plugin, root, target

    return os.path.basename(target), None, target


def discover_skills(plugin_dir):
    """Sorted skill directory names under plugin_dir/skills/ containing SKILL.md."""
    if not plugin_dir:
        return []
    skills_dir = os.path.join(plugin_dir, "skills")
    if not os.path.isdir(skills_dir):
        return []
    return sorted(
        entry
        for entry in os.listdir(skills_dir)
        if os.path.isfile(os.path.join(skills_dir, entry, "SKILL.md"))
    )


def read_case(case_dir, case_rel):
    """Read a case's prompt, prompt_file, tag_sources, and graders via validate-cases."""
    yaml_data = None
    tag_sources = []
    prompt = ""
    yaml_path = os.path.join(case_dir, "case.yaml")
    prompt_path = os.path.join(case_dir, "prompt.md")

    if os.path.isfile(yaml_path):
        try:
            text = validate_cases.read_text(yaml_path)
            if text.lstrip().startswith("---"):
                text = text.lstrip()[3:]
            yaml_data = validate_cases.parse_yaml(text)
        except (validate_cases.ParseError, OSError):
            yaml_data = None
        if isinstance(yaml_data, dict):
            tags = yaml_data.get("tags")
            if isinstance(tags, list):
                tag_sources.append((tags, "case.yaml"))
            execution = yaml_data.get("execution")
            if isinstance(execution, dict) and isinstance(execution.get("prompt"), str):
                prompt = execution["prompt"].strip()

    if os.path.isfile(prompt_path):
        try:
            block, body = validate_cases.split_markdown(
                validate_cases.read_text(prompt_path)
            )
            prompt = body.strip() or prompt
        except (validate_cases.ParseError, OSError):
            block = None
        if block is not None:
            try:
                prompt_fm = validate_cases.parse_yaml(block)
            except validate_cases.ParseError:
                prompt_fm = None
            if isinstance(prompt_fm, dict):
                prompt_tags = prompt_fm.get("tags")
                if isinstance(prompt_tags, list):
                    tag_sources.append((prompt_tags, "prompt.md"))

    prompt_file = "prompt.md" if os.path.isfile(prompt_path) else "case.yaml"
    graders = validate_cases.collect_graders(case_dir, case_rel, yaml_data, [])
    return prompt, prompt_file, tag_sources, graders


def _is_whole(value):
    return isinstance(value, int) and not isinstance(value, bool)


def _is_positive_skill_grader(options):
    if not isinstance(options, dict):
        return False
    if options.get("type") != "tool_used" or options.get("tool") != "Skill":
        return False
    low = options.get("min")
    low = 1 if low is None else low
    high = options.get("max")
    if not _is_whole(low) or low < 1:
        return False
    return high is None or (_is_whole(high) and high >= low)


def _is_negated_skill_grader(options):
    if not isinstance(options, dict):
        return False
    if options.get("type") != "tool_used" or options.get("tool") != "Skill":
        return False
    return _is_whole(options.get("min")) and options.get("min") == 0 and (
        _is_whole(options.get("max")) and options.get("max") == 0
    )


def _grader_targets_skill(grader, plugin, skill, prompt_file, suite_plugin):
    direct = case_skills.skills_under_test("", prompt_file, (), [grader], suite_plugin)
    if (plugin, skill) in direct:
        return True
    if direct:
        return False
    _, options, _ = grader
    for call_name in ("%s:%s" % (plugin, skill), skill):
        try:
            if validate_cases.call_matches(
                {"tool": "Skill", "input": {"skill": call_name}}, options
            ):
                return True
        except validate_cases.Unmirrored:
            return False
    return False


def _read_sample_counts(case_dir, grader_name):
    rel = "%s/%s.json" % (validate_cases.SAMPLES_DIR, grader_name)
    path = os.path.join(case_dir, validate_cases.SAMPLES_DIR, grader_name + ".json")
    if not os.path.isfile(path):
        return None, "no %s" % rel
    try:
        data = json.loads(validate_cases.read_text(path))
    except (OSError, ValueError):
        return None, "%s not readable" % rel
    if not isinstance(data, dict):
        return None, "%s not readable" % rel
    pass_items = data.get("pass")
    fail_items = data.get("fail")
    pass_count = len(pass_items) if isinstance(pass_items, list) else 0
    fail_count = len(fail_items) if isinstance(fail_items, list) else 0
    if pass_count + fail_count == 0:
        return None, "%s has no labeled samples" % rel
    return (pass_count, fail_count), None


def audit(target):
    """Audit a plugin or suite directory and return the structured report dict."""
    plugin, plugin_dir, eval_dir = resolve_target(target)
    skills = discover_skills(plugin_dir)
    skill_set = set(skills)

    has_case = set()
    has_det_trigger = set()
    has_should_not_fire = set()
    judged_without_samples = []
    judged_with_samples = []

    case_dirs = validate_cases.discover_cases(eval_dir) if eval_dir else []
    for case_dir in case_dirs:
        case_rel = os.path.relpath(case_dir, eval_dir).replace(os.sep, "/")
        prompt, prompt_file, tag_sources, graders = read_case(case_dir, case_rel)
        named = case_skills.skills_under_test(
            prompt, prompt_file, tag_sources, graders, plugin
        )

        for ref_plugin, ref_skill in named:
            if ref_plugin != plugin or ref_skill not in skill_set:
                continue
            has_case.add(ref_skill)
            for grader in graders:
                _, options, _ = grader
                if _is_positive_skill_grader(options) and _grader_targets_skill(
                    grader, plugin, ref_skill, prompt_file, plugin
                ):
                    has_det_trigger.add(ref_skill)
                if _is_negated_skill_grader(options) and _grader_targets_skill(
                    grader, plugin, ref_skill, prompt_file, plugin
                ):
                    has_should_not_fire.add(ref_skill)

        for grader_name, options, _ in graders:
            if not isinstance(options, dict):
                continue
            kind = options.get("type")
            if kind not in validate_cases.JUDGE_TYPES:
                continue
            counts, reason = _read_sample_counts(case_dir, grader_name)
            if counts is None:
                judged_without_samples.append(
                    {
                        "case": case_rel,
                        "grader": grader_name,
                        "type": kind,
                        "reason": reason,
                        "route": ROUTE_CALIBRATE,
                    }
                )
            else:
                judged_with_samples.append(
                    {
                        "case": case_rel,
                        "grader": grader_name,
                        "type": kind,
                        "pass": counts[0],
                        "fail": counts[1],
                    }
                )

    legacy_skills = set()
    if plugin_dir:
        for skill in skills:
            legacy_path = os.path.join(
                plugin_dir, "skills", skill, "evals", "evals.json"
            )
            if os.path.isfile(legacy_path):
                legacy_skills.add(skill)

    no_case = [
        {"skill": "%s:%s" % (plugin, skill), "route": ROUTE_DESIGN}
        for skill in skills
        if skill not in has_case and skill not in legacy_skills
    ]
    legacy_only = [
        {
            "skill": "%s:%s" % (plugin, skill),
            "path": "skills/%s/evals/evals.json" % skill,
            "route": ROUTE_DESIGN,
        }
        for skill in skills
        if skill not in has_case and skill in legacy_skills
    ]
    no_deterministic_trigger = [
        {"skill": "%s:%s" % (plugin, skill), "route": ROUTE_DESIGN}
        for skill in skills
        if skill in has_case and skill not in has_det_trigger
    ]
    no_should_not_fire = [
        {"skill": "%s:%s" % (plugin, skill), "advisory": True, "route": ROUTE_DESIGN}
        for skill in skills
        if skill in has_case and skill not in has_should_not_fire
    ]

    judged_without_samples.sort(key=lambda item: (item["case"], item["grader"]))
    judged_with_samples.sort(key=lambda item: (item["case"], item["grader"]))

    return {
        "plugin": plugin,
        "plugin_dir": plugin_dir,
        "eval_dir": eval_dir,
        "skills": skills,
        "case_count": len(case_dirs),
        "counts": {
            "no_case": len(no_case),
            "no_deterministic_trigger": len(no_deterministic_trigger),
            "judged_without_samples": len(judged_without_samples),
            "judged_with_samples": len(judged_with_samples),
            "legacy_only": len(legacy_only),
            "no_should_not_fire": len(no_should_not_fire),
        },
        "no_case": no_case,
        "no_deterministic_trigger": no_deterministic_trigger,
        "judged_without_samples": judged_without_samples,
        "judged_with_samples": judged_with_samples,
        "legacy_only": legacy_only,
        "no_should_not_fire": no_should_not_fire,
    }


def format_text(report):
    """Format an audit report dict as human-readable lines."""
    lines = []

    lines.append("skills with no case: %d" % report["counts"]["no_case"])
    for item in report["no_case"]:
        lines.append("  %s [%s]" % (item["skill"], item["route"]))

    lines.append(
        "skills with no deterministic triggering case: %d"
        % report["counts"]["no_deterministic_trigger"]
    )
    for item in report["no_deterministic_trigger"]:
        lines.append("  %s [%s]" % (item["skill"], item["route"]))

    lines.append(
        "judged graders without samples: %d"
        % report["counts"]["judged_without_samples"]
    )
    for item in report["judged_without_samples"]:
        lines.append(
            "  %s/%s (%s): %s [%s]"
            % (item["case"], item["grader"], item["type"], item["reason"], item["route"])
        )

    lines.append(
        "judged graders with samples: %d" % report["counts"]["judged_with_samples"]
    )
    for item in report["judged_with_samples"]:
        lines.append(
            "  %s/%s (%s): %d PASS, %d FAIL"
            % (item["case"], item["grader"], item["type"], item["pass"], item["fail"])
        )

    lines.append("legacy-only skills: %d" % report["counts"]["legacy_only"])
    for item in report["legacy_only"]:
        lines.append("  %s (%s) [%s]" % (item["skill"], item["path"], item["route"]))

    lines.append(
        "skills with no should-not-fire case (advisory): %d"
        % report["counts"]["no_should_not_fire"]
    )
    for item in report["no_should_not_fire"]:
        lines.append("  %s [%s]" % (item["skill"], item["route"]))

    return "\n".join(lines)


def main(argv=None):
    """CLI entry point for audit-suite."""
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            "error: audit-suite needs Python %d.%d or newer\n" % MIN_PYTHON
        )
        return 2
    parser = argparse.ArgumentParser(
        prog="audit-suite",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("target", help="plugin directory or eval suite directory")
    parser.add_argument(
        "--json", action="store_true", help="print the audit report as JSON"
    )
    args = parser.parse_args(argv)

    target = os.path.abspath(args.target)
    if not os.path.isdir(target):
        sys.stderr.write("error: not a directory: %s\n" % args.target)
        return 2
    try:
        os.listdir(target)
    except OSError as error:
        sys.stderr.write("error: cannot read %s (%s)\n" % (args.target, error))
        return 2

    report = audit(target)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(format_text(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
