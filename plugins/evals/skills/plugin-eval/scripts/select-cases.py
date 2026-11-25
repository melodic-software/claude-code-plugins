#!/usr/bin/env python3
"""select-cases - select affected eval cases for a git diff.

    select-cases.py <diff-base> [--json] [--repo <dir>]

Reads `git diff --name-status -M -z <diff-base>...HEAD --`, classifies each
changed file against the eval run policy, maps files to skills and cases
through the shared `case_skills.py` rule, and prints one block per affected
plugin (or `no affected cases`). When the repository has
`.github/scripts/plugin-eval/select-plugins.mjs`, each block also names the
changed paths that script refuses, which a compare run will not take.

Exit codes:

    0  success
    2  usage error, uncommitted changes under plugins/, or unreadable git state

Python 3.8+, standard library only.
"""

import argparse
import collections
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 8)
DEFAULT_RUNS = 3
ARMS = 2

EVAL_DIR_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
PAID_RE = re.compile(r"""\btype["']?\s*:\s*["']?(?:llm|baseline)\b""", re.IGNORECASE)
GRADERS_HEADER_RE = re.compile(r"^graders[ \t]*:[ \t]*(?:#.*)?\r?$")

TRIGGER_TAGS = frozenset(["triggering", "no-trigger", "no-fire"])
PLUGIN_SCRIPT_DIRS = frozenset(["scripts", "lib", "tests"])
PLUGIN_DOC_FILES = frozenset(["README.md", "CHANGELOG.md"])

HERE = os.path.dirname(os.path.abspath(__file__))
CASE_SKILLS_PY = os.path.normpath(
    os.path.join(HERE, os.pardir, os.pardir, os.pardir, "scripts", "case_skills.py")
)
VALIDATE_CASES_PY = os.path.normpath(
    os.path.join(HERE, os.pardir, os.pardir, "validate", "scripts", "validate-cases.py")
)
SELECT_MAPPING_PY = os.path.join(HERE, "select_mapping.py")
SELECT_PLUGINS_MJS = (".github", "scripts", "plugin-eval", "select-plugins.mjs")
SELECT_PLUGINS_HEADER = "a selected plugin changes more than"
REFUSED_PLUGIN_RE = re.compile(r'^"?plugins/([^/:"\\]+)[/:]')
COMPARE_REFUSED_ADVICE = (
    "a compare run refuses these, so run the cases in a suite run"
    " on the default branch after merge"
)
NO_RUN_EXEMPT_REASON = (
    "the description or when_to_use edit changes only routing clauses, skill tokens"
    " or glossary-decided terms, so it runs no case"
)


def _load_module(name, path):
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


case_skills = _load_module("evals_case_skills", CASE_SKILLS_PY)
validate_cases = _load_module("evals_validate_cases", VALIDATE_CASES_PY)
select_mapping = _load_module("evals_select_mapping", SELECT_MAPPING_PY)

CaseInfo = collections.namedtuple(
    "CaseInfo",
    (
        "plugin",
        "name",
        "rel_dir",
        "abs_dir",
        "runs",
        "judged_only",
        "skills",
        "skill_prefixes",
        "agents",
        "agent_prefixes",
        "is_trigger_or_no_fire",
        "unread_graders",
    ),
)


def eval_dir_of(plugin_dir):
    """Return the eval directory name declared by plugin.json, else `evals`."""
    for rel in (os.path.join(".claude-plugin", "plugin.json"), "plugin.json"):
        manifest_path = os.path.join(plugin_dir, rel)
        if not os.path.isfile(manifest_path):
            continue
        try:
            with open(manifest_path, "r", encoding="utf-8") as handle:
                manifest = json.load(handle)
        except (OSError, ValueError):
            continue
        experimental = manifest.get("experimental") if isinstance(manifest, dict) else None
        named = experimental.get("evals") if isinstance(experimental, dict) else None
        if isinstance(named, str) and EVAL_DIR_NAME.match(named):
            return named
    return "evals"


def _effective_runs(yaml_data, prompt_fm):
    for source in (prompt_fm, yaml_data):
        if isinstance(source, dict) and "runs" in source:
            val = source["runs"]
            if isinstance(val, int) and not isinstance(val, bool) and val > 0:
                return val
    return DEFAULT_RUNS


def _grader_items(lines):
    header = -1
    for idx, line in enumerate(lines):
        if GRADERS_HEADER_RE.match(line):
            header = idx
            break
    if header == -1:
        return None

    def is_body(line):
        stripped = line.strip()
        return stripped != "" and not stripped.startswith("#")

    def indent_of(line):
        return len(line) - len(line.lstrip())

    first = -1
    for idx in range(header + 1, len(lines)):
        if is_body(lines[idx]):
            first = idx
            break
    if first == -1 or not lines[first].lstrip().startswith("-"):
        return None

    dash = indent_of(lines[first])
    items = []
    for idx in range(first, len(lines)):
        line = lines[idx]
        if not is_body(line):
            continue
        ind = indent_of(line)
        if ind < dash or (ind == dash and not line[dash:].startswith("-")):
            break
        if ind == dash:
            items.append([idx, idx + 1])
        else:
            items[-1][1] = idx + 1
    return header, items


def _strip_case_yaml(text):
    lines = text.split("\n")
    shape = _grader_items(lines)
    if shape is not None:
        header, items = shape
        paid = [
            bool(PAID_RE.search("\n".join(lines[start:end])))
            for start, end in items
        ]
    else:
        header, items, paid = -1, [], []

    if not any(paid):
        if PAID_RE.search(text):
            raise ValueError("a paid grader outside a block graders list")
        return len(items) if shape is not None else None

    if all(paid):
        cuts = [(header, items[-1][1])]
    else:
        cuts = [item for item, is_paid in zip(items, paid) if is_paid]

    stripped = "\n".join(
        line
        for idx, line in enumerate(lines)
        if not any(start <= idx < end for start, end in cuts)
    )
    if PAID_RE.search(stripped):
        raise ValueError("a paid line is left after the cut")

    before = validate_cases.parse_yaml(text)
    after = validate_cases.parse_yaml(stripped)
    graders = before.get("graders") if isinstance(before, dict) else None
    if not isinstance(graders, list) or len(graders) != len(items):
        raise ValueError("the graders list does not match its lines")

    expected = dict(before)
    remaining_graders = [g for g, is_paid in zip(graders, paid) if not is_paid]
    if remaining_graders:
        expected["graders"] = remaining_graders
    else:
        expected.pop("graders", None)
    if after != expected:
        raise ValueError("the cut changed more than the paid graders")

    for grader, is_paid in zip(graders, paid):
        if not is_paid:
            continue
        gname = grader.get("name") if isinstance(grader, dict) else None
        name_text = "undefined" if gname is None else str(gname)
        if not EVAL_DIR_NAME.match(name_text):
            raise ValueError("paid grader name is not a plain file name")

    return len(remaining_graders)


def _case_is_judged_only(case_dir):
    grader_dir = os.path.join(case_dir, "graders")
    md_files = (
        sorted(f for f in os.listdir(grader_dir) if f.endswith(".md"))
        if os.path.isdir(grader_dir)
        else []
    )
    paid_files = []
    for filename in md_files:
        try:
            text = validate_cases.read_text(os.path.join(grader_dir, filename))
        except OSError:
            continue
        if PAID_RE.search(text):
            paid_files.append(filename)

    yaml_path = os.path.join(case_dir, "case.yaml")
    original = None
    if os.path.isfile(yaml_path):
        try:
            original = validate_cases.read_text(yaml_path)
        except OSError:
            original = None

    if not paid_files and (original is None or not PAID_RE.search(original)):
        return False

    try:
        if original is None:
            yaml_left = 0
        else:
            yaml_left = _strip_case_yaml(original)
            if yaml_left is None:
                parsed = validate_cases.parse_yaml(original)
                graders = parsed.get("graders") if isinstance(parsed, dict) else None
                yaml_left = len(graders) if isinstance(graders, list) else 0
    except (ValueError, validate_cases.ParseError):
        return True

    return (yaml_left + len(md_files) - len(paid_files)) == 0


def load_case(repo_root, plugin, eval_dir, case_dir):
    """Load one eval case into a CaseInfo record."""
    rel_from_eval = os.path.relpath(case_dir, eval_dir).replace(os.sep, "/")
    rel_dir = os.path.relpath(case_dir, repo_root).replace(os.sep, "/")
    yaml_path = os.path.join(case_dir, "case.yaml")
    prompt_path = os.path.join(case_dir, "prompt.md")

    yaml_data = None
    prompt_fm = None
    prompt = ""
    tag_sources = []
    all_tags = []

    if os.path.isfile(yaml_path):
        try:
            yaml_data = select_mapping._parse_case_yaml_text(
                validate_cases.read_text(yaml_path)
            )
        except (OSError, validate_cases.ParseError):
            yaml_data = None
        if isinstance(yaml_data, dict):
            tags = yaml_data.get("tags")
            if isinstance(tags, list):
                tag_sources.append((tags, "case.yaml"))
                all_tags.extend(str(t) for t in tags)
            execution = yaml_data.get("execution")
            if isinstance(execution, dict) and isinstance(execution.get("prompt"), str):
                prompt = execution["prompt"].strip()

    if os.path.isfile(prompt_path):
        try:
            block, body = select_mapping._split_frontmatter_loose(
                validate_cases.read_text(prompt_path)
            )
            prompt = body.strip() or prompt
            if block is not None:
                prompt_fm = validate_cases.parse_yaml(block)
        except (OSError, validate_cases.ParseError):
            pass
        if isinstance(prompt_fm, dict):
            tags = prompt_fm.get("tags")
            if isinstance(tags, list):
                tag_sources.append((tags, "prompt.md"))
                all_tags.extend(str(t) for t in tags)

    name = None
    if isinstance(yaml_data, dict):
        candidate = yaml_data.get("name")
        if isinstance(candidate, str) and candidate:
            name = candidate
    if not name:
        name = os.path.basename(case_dir)

    graders = validate_cases.collect_graders(case_dir, rel_from_eval, yaml_data, [])
    prompt_file = "prompt.md" if os.path.isfile(prompt_path) else "case.yaml"
    refs = case_skills.references(prompt, prompt_file, tag_sources, graders)
    skills = case_skills.skills_under_test(
        prompt, prompt_file, tag_sources, graders, plugin
    )
    skill_prefixes = {
        case_skills.resolve(ref, plugin)
        for ref in refs
        if ref.kind == "skill" and ref.prefix
    }
    agents = {
        case_skills.resolve(ref, plugin) for ref in refs if ref.kind == "agent"
    }
    agent_prefixes = {
        case_skills.resolve(ref, plugin)
        for ref in refs
        if ref.kind == "agent" and ref.prefix
    }

    has_skill_grader = False
    unread_graders = []
    for grader in graders:
        gname, options, _ = grader
        if not isinstance(options, dict) or options.get("type") != "tool_used":
            continue
        tool = options.get("tool")
        if tool == "Skill":
            has_skill_grader = True
        if tool not in case_skills.TOOL_KINDS:
            continue
        pattern = options.get("input_match")
        if isinstance(pattern, str) and pattern.strip():
            if not case_skills.references("", prompt_file, (), (grader,)):
                unread_graders.append("%s/%s" % (name, gname))

    slash_invoked = bool(validate_cases.SLASH_SKILL.match(prompt or ""))
    is_trigger_or_no_fire = (has_skill_grader and not slash_invoked) or any(
        tag.lower() in TRIGGER_TAGS for tag in all_tags
    )
    return CaseInfo(
        plugin=plugin,
        name=name,
        rel_dir=rel_dir,
        abs_dir=case_dir,
        runs=_effective_runs(yaml_data, prompt_fm),
        judged_only=_case_is_judged_only(case_dir),
        skills=frozenset(skills),
        skill_prefixes=frozenset(skill_prefixes),
        agents=frozenset(agents),
        agent_prefixes=frozenset(agent_prefixes),
        is_trigger_or_no_fire=is_trigger_or_no_fire,
        unread_graders=tuple(unread_graders),
    )


def load_all_suites(repo_root):
    """Discover every plugin's eval directory and CaseInfo list."""
    plugins_dir = os.path.join(repo_root, "plugins")
    eval_dirs = {}
    cases_by_plugin = collections.defaultdict(list)
    if not os.path.isdir(plugins_dir):
        return eval_dirs, cases_by_plugin
    for plugin in sorted(os.listdir(plugins_dir)):
        plugin_dir = os.path.join(plugins_dir, plugin)
        if not os.path.isdir(plugin_dir) or plugin.startswith("."):
            continue
        ed_name = eval_dir_of(plugin_dir)
        eval_dirs[plugin] = ed_name
        eval_abs = os.path.join(plugin_dir, ed_name)
        if not os.path.isdir(eval_abs):
            continue
        for case_dir in validate_cases.discover_cases(eval_abs):
            cases_by_plugin[plugin].append(
                load_case(repo_root, plugin, eval_abs, case_dir)
            )
    return eval_dirs, cases_by_plugin


def compare_refusals(repo_root, merge_base):
    """Map each plugin name to the `<path>: <reason>` lines compare mode refuses.

    Runs the repository's own select-plugins.mjs on the plugin paths changed
    since merge_base, listed as compare-arms.sh lists them (git's default path
    quoting, so a quoted path is refused the same way) and without each
    plugin's tests/, which compare-arms.sh leaves out.
    Returns {} when the repository has no such script, None when it cannot run.
    """
    script = os.path.join(repo_root, *SELECT_PLUGINS_MJS)
    if not os.path.isfile(script):
        return {}
    diff = subprocess.run(
        ["git", "-C", repo_root, "diff", "--no-renames", "--name-only", merge_base, "HEAD", "--", "plugins"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if diff.returncode != 0:
        return None
    paths = [
        path
        for path in diff.stdout.split("\n")
        if path and path.split("/")[2:3] != ["tests"]
    ]
    if not paths:
        return {}
    node = shutil.which("node")
    if node is None:
        return None
    done = subprocess.run(
        [node, script, "--repo", repo_root, "--base", merge_base, "--head", "HEAD"],
        input="\n".join(paths) + "\n",
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if done.returncode == 0:
        return {}
    lines = done.stderr.splitlines()
    if done.returncode != 1 or not lines or not lines[0].startswith(SELECT_PLUGINS_HEADER):
        return None
    refused = collections.defaultdict(list)
    for line in lines[1:]:
        match = REFUSED_PLUGIN_RE.match(line)
        if match:
            refused[match.group(1)].append(line)
    return refused


def select_cases(repo_root, diff_base, merge_base):
    """Compute affected cases per plugin for `diff_base...HEAD`."""
    entries = select_mapping.changed_entries(repo_root, diff_base)
    if entries is None:
        return None
    refused = compare_refusals(repo_root, merge_base)
    if refused is None:
        sys.stderr.write(
            "warning: select-plugins.mjs gave no readable result; compare-mode refusals are unchecked\n"
        )
        refused = {}
    eval_dirs, cases_by_plugin = load_all_suites(repo_root)
    all_cases = [c for cases in cases_by_plugin.values() for c in cases]
    fixture_ref_cache = {}

    run_cases = collections.defaultdict(set)
    after_merge_cases = collections.defaultdict(set)
    no_run_cases = collections.defaultdict(set)
    no_run_exempt = collections.defaultdict(set)
    uncovered = collections.defaultdict(set)
    plugin_wide = collections.defaultdict(set)
    unmapped = collections.defaultdict(set)
    unread_graders = collections.defaultdict(set)

    changed_skills = collections.defaultdict(set)
    script_only_skills = set()
    changed_agents = {}
    deleted_agents = []
    added_agents = []
    modified_dispatchers = []
    skill_or_agent_plugins = set()

    no_run_paths = set()

    def no_run_edit(code, rel_path):
        return rel_path in no_run_paths or (
            code == "M"
            and select_mapping.is_no_run_file_change(
                repo_root, merge_base, rel_path, rel_path
            )
        )

    expanded = []
    for code, path_a, path_b in entries:
        if code == "R" and path_b is not None:
            old_agent = select_mapping._agent_key_from_path(path_a)
            new_agent = select_mapping._agent_key_from_path(path_b)
            if old_agent and new_agent:
                kind = (
                    "cut"
                    if select_mapping.diff_blobs_has_cut(
                        repo_root, merge_base, path_a, path_b
                    )
                    else "additive"
                )
                if changed_agents.get(new_agent) != "cut":
                    changed_agents[new_agent] = kind
                skill_or_agent_plugins.add(new_agent[0])
                if select_mapping.skills_for_agent(repo_root, *old_agent) or any(
                    select_mapping._case_covers_agent(c, old_agent) for c in all_cases
                ):
                    changed_agents[old_agent] = "cut"
                    skill_or_agent_plugins.add(old_agent[0])
                continue
            if select_mapping.is_no_run_file_change(repo_root, merge_base, path_a, path_b):
                no_run_paths.add(path_b)
                expanded.append(("M", path_b))
                continue
            expanded.append(("D", path_a))
            expanded.append(("A", path_b))
        elif code == "C" and path_b is not None:
            expanded.append(("A", path_b))
        else:
            expanded.append((code, path_a))

    for old_path, new_path in select_mapping.swap_rename_pairs(
        repo_root,
        merge_base,
        [p for c, p in expanded if c == "D" and p.startswith("plugins/")],
        [p for c, p in expanded if c == "A" and p.startswith("plugins/")],
    ):
        expanded.remove(("D", old_path))
        expanded[expanded.index(("A", new_path))] = ("M", new_path)
        no_run_paths.add(new_path)

    for code, rel_path in expanded:
        parts = rel_path.split("/")
        if len(parts) < 3 or parts[0] != "plugins":
            continue
        plugin = parts[1]
        rel_in_plugin = "/".join(parts[2:])
        ed_name = eval_dirs.get(plugin, "evals")

        if select_mapping._is_plugin_wide(rel_in_plugin):
            if not no_run_edit(code, rel_path):
                plugin_wide[plugin].add(rel_path)
            continue

        if parts[2] == "skills" and len(parts) >= 4:
            if code == "M":
                modified_dispatchers.append(rel_path)
            skill = parts[3]
            inner_parts = parts[4:]
            if not inner_parts:
                unmapped[plugin].add(rel_path)
                continue
            if inner_parts == ["SKILL.md"]:
                body_cls, desc_cls = select_mapping.classify_skill_md(
                    repo_root, diff_base, merge_base, rel_path
                )
                if body_cls == "cut":
                    changed_skills[(plugin, skill)].add("body_cut")
                elif body_cls == "additive":
                    changed_skills[(plugin, skill)].add("body_additive")
                if desc_cls == "cut":
                    changed_skills[(plugin, skill)].add("desc_cut")
                elif desc_cls == "additive":
                    changed_skills[(plugin, skill)].add("desc_additive")
                elif desc_cls == "exempt":
                    changed_skills[(plugin, skill)].add("desc_exempt")
                skill_or_agent_plugins.add(plugin)
            elif select_mapping._is_script_path(inner_parts):
                script_only_skills.add((plugin, skill))
            else:
                reason = (
                    "body_cut"
                    if select_mapping.diff_has_cut(repo_root, diff_base, rel_path)
                    else "body_additive"
                )
                changed_skills[(plugin, skill)].add(reason)
                skill_or_agent_plugins.add(plugin)
            continue

        if parts[2] in ("reference", "context") and len(parts) >= 4:
            citing = select_mapping.skills_citing_plugin_file(
                repo_root, plugin, rel_in_plugin
            )
            if not citing:
                unmapped[plugin].add(rel_path)
            else:
                reason = (
                    "body_cut"
                    if select_mapping.diff_has_cut(repo_root, diff_base, rel_path)
                    else "body_additive"
                )
                for skill_key in citing:
                    changed_skills[skill_key].add(reason)
                    skill_or_agent_plugins.add(skill_key[0])
            continue

        if parts[2] == "agents" and len(parts) == 4 and parts[3].endswith(".md"):
            agent_name = parts[3][:-3]
            agent_key = (plugin, agent_name)
            kind = (
                "cut"
                if select_mapping.diff_has_cut(repo_root, diff_base, rel_path)
                else "additive"
            )
            if changed_agents.get(agent_key) != "cut":
                changed_agents[agent_key] = kind
            if code == "D":
                deleted_agents.append((agent_key, rel_path))
            elif code == "A":
                added_agents.append((agent_key, rel_path))
            skill_or_agent_plugins.add(plugin)
            continue

        if parts[2] == "workflows" and len(parts) == 4 and parts[3].endswith(".js"):
            if code == "M":
                modified_dispatchers.append(rel_path)
            for skill_key in select_mapping.skills_for_workflow(
                repo_root, plugin, parts[3][:-3]
            ):
                script_only_skills.add(skill_key)
            continue

        if parts[2] == ed_name and len(parts) >= 4:
            suite_cases = cases_by_plugin.get(plugin, [])
            owning_case = None
            for case in suite_cases:
                if rel_path.startswith(case.rel_dir + "/"):
                    owning_case = case
                    break
            if owning_case is not None:
                inner = rel_path[len(owning_case.rel_dir) + 1 :]
                if inner.startswith("samples/") or no_run_edit(code, rel_path):
                    no_run_cases[plugin].add(owning_case)
                elif (
                    inner in ("case.yaml", "prompt.md")
                    and select_mapping.is_description_only_case_edit(
                        repo_root, merge_base, rel_path, inner
                    )
                ):
                    no_run_cases[plugin].add(owning_case)
                else:
                    run_cases[plugin].add(owning_case)
                    run_cases[plugin].update(
                        select_mapping.cases_citing_suite_file(
                            os.path.join(repo_root, "plugins", plugin, ed_name),
                            os.path.join(repo_root, *parts),
                            suite_cases,
                            ref_cache=fixture_ref_cache,
                        )
                    )
                unread_graders[plugin].update(owning_case.unread_graders)
            else:
                if parts[3] == "results" or select_mapping._is_test_script(parts[-1]):
                    continue
                eval_abs = os.path.join(repo_root, "plugins", plugin, ed_name)
                target_abs = os.path.join(repo_root, *parts)
                cited_cases = select_mapping.cases_citing_suite_file(
                    eval_abs, target_abs, suite_cases, ref_cache=fixture_ref_cache
                )
                if cited_cases:
                    target = no_run_cases if no_run_edit(code, rel_path) else run_cases
                    for case in cited_cases:
                        target[plugin].add(case)
                elif os.path.exists(target_abs):
                    unmapped[plugin].add(rel_path)
            continue

        if parts[2] in PLUGIN_SCRIPT_DIRS or rel_in_plugin in PLUGIN_DOC_FILES:
            continue

        unmapped[plugin].add(rel_path)

    select_mapping._pair_unmatched_agent_renames(
        repo_root,
        merge_base,
        deleted_agents,
        added_agents,
        modified_dispatchers,
        changed_agents,
    )

    for skill_key in script_only_skills:
        for case in all_cases:
            if select_mapping._case_covers_skill(case, skill_key):
                no_run_cases[case.plugin].add(case)

    for (plugin, skill), reasons in sorted(changed_skills.items()):
        skill_key = (plugin, skill)
        skill_cases = [
            c for c in all_cases if select_mapping._case_covers_skill(c, skill_key)
        ]
        trigger_cases = [
            c for c in cases_by_plugin.get(plugin, []) if c.is_trigger_or_no_fire
        ]
        if "body_cut" in reasons:
            for case in skill_cases:
                run_cases[case.plugin].add(case)
        elif "body_additive" in reasons:
            for case in skill_cases:
                no_run_cases[case.plugin].add(case)

        if "desc_cut" in reasons:
            for case in trigger_cases:
                run_cases[case.plugin].add(case)
            for case in skill_cases:
                run_cases[case.plugin].add(case)
        elif "desc_additive" in reasons:
            for case in trigger_cases:
                after_merge_cases[case.plugin].add(case)
        elif "desc_exempt" in reasons:
            no_run_exempt[plugin].add("%s:%s" % (plugin, skill))
            for case in trigger_cases:
                no_run_cases[case.plugin].add(case)

        desc_only = reasons <= {"desc_cut", "desc_additive"}
        if not skill_cases or (desc_only and not trigger_cases):
            uncovered[plugin].add("%s:%s" % (plugin, skill))

    for (plugin, agent_name), kind in sorted(changed_agents.items()):
        agent_key = (plugin, agent_name)
        dispatched_by = select_mapping.skills_for_agent(repo_root, plugin, agent_name)
        for skill_key in dispatched_by:
            skill_or_agent_plugins.add(skill_key[0])
        agent_cases = [
            c
            for c in all_cases
            if any(select_mapping._case_covers_skill(c, sk) for sk in dispatched_by)
            or select_mapping._case_covers_agent(c, agent_key)
        ]
        if not agent_cases:
            uncovered[plugin].add("%s:%s" % (plugin, agent_name))
        elif kind == "cut":
            for case in agent_cases:
                run_cases[case.plugin].add(case)
        else:
            for case in agent_cases:
                no_run_cases[case.plugin].add(case)

    for plugin in skill_or_agent_plugins:
        for case in cases_by_plugin.get(plugin, []):
            unread_graders[plugin].update(case.unread_graders)

    affected_plugins = sorted(
        set(run_cases)
        | set(after_merge_cases)
        | set(no_run_cases)
        | set(no_run_exempt)
        | set(uncovered)
        | set(plugin_wide)
        | set(unmapped)
        | set(unread_graders)
        | set(refused)
    )

    result = {}
    for plugin in affected_plugins:
        run_set = run_cases.get(plugin, set())
        det_cases = sorted({c.name for c in run_set if not c.judged_only})
        judged = sorted({c.name for c in run_set if c.judged_only})
        run_names = set(det_cases) | set(judged)

        ram_set = {
            c for c in after_merge_cases.get(plugin, set()) if c.name not in run_names
        }
        ram_names = sorted({c.name for c in ram_set})
        scheduled_names = run_names | set(ram_names)

        no_run_names = sorted(
            {
                c.name
                for c in no_run_cases.get(plugin, set())
                if c.name not in scheduled_names
            }
        )
        exempt_list = sorted(no_run_exempt.get(plugin, set()))
        uncovered_list = sorted(uncovered.get(plugin, set()))
        plugin_wide_list = sorted(plugin_wide.get(plugin, set()))
        unmapped_list = sorted(unmapped.get(plugin, set()))
        unread_list = sorted(unread_graders.get(plugin, set()))
        refused_list = refused.get(plugin, [])

        if not any(
            (
                det_cases,
                judged,
                no_run_names,
                exempt_list,
                uncovered_list,
                ram_names,
                plugin_wide_list,
                unmapped_list,
                unread_list,
                refused_list,
            )
        ):
            continue

        scheduled_cases = [
            c for c in cases_by_plugin.get(plugin, []) if c.name in scheduled_names
        ]
        agent_runs = sum(case.runs * ARMS for case in scheduled_cases)

        result["plugins/" + plugin] = {
            "cases": det_cases,
            "judged": judged,
            "affected-no-run": no_run_names,
            "no-run-exempt": exempt_list,
            "uncovered": uncovered_list,
            "run-after-merge": ram_names,
            "plugin-wide": plugin_wide_list,
            "unmapped": unmapped_list,
            "unread-graders": unread_list,
            "compare-refused": refused_list,
            "agent-runs": agent_runs,
        }
    return result


def format_text(result):
    """Format the per-plugin selection dictionary as Contracts text blocks."""
    if not result:
        return "no affected cases"
    blocks = []
    list_keys = (
        "cases",
        "judged",
        "affected-no-run",
        "uncovered",
        "run-after-merge",
        "plugin-wide",
        "unmapped",
        "unread-graders",
    )
    for plugin_key in sorted(result):
        data = result[plugin_key]
        lines = ["plugin: " + plugin_key]
        for key in list_keys:
            values = data[key]
            if values:
                lines.append("%s: %s" % (key, " ".join(values)))
            if key == "affected-no-run" and data["no-run-exempt"]:
                lines.append(
                    "no-run-exempt: %s; %s"
                    % (" ".join(data["no-run-exempt"]), NO_RUN_EXEMPT_REASON)
                )
        if data.get("compare-refused"):
            lines.append(
                "compare-refused: %s; %s"
                % ("; ".join(data["compare-refused"]), COMPARE_REFUSED_ADVICE)
            )
        lines.append("agent-runs: %d" % data["agent-runs"])
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks)


def main(argv=None):
    """CLI entry point for select-cases."""
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write(
            "error: select-cases needs Python %d.%d or newer\n" % MIN_PYTHON
        )
        return 2
    parser = argparse.ArgumentParser(
        prog="select-cases",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("diff_base", help="git diff base ref or commit")
    parser.add_argument(
        "--json",
        action="store_true",
        help="print the result as a JSON object keyed by plugin",
    )
    parser.add_argument(
        "--repo",
        default=os.getcwd(),
        help="path to the git repository (default: current directory)",
    )
    args = parser.parse_args(argv)

    repo_arg = os.path.abspath(args.repo)
    if not os.path.isdir(repo_arg):
        sys.stderr.write("error: not a directory: %s\n" % args.repo)
        return 2
    repo_root = select_mapping.resolve_repo_root(repo_arg)
    if repo_root is None:
        sys.stderr.write("error: not a git repository: %s\n" % args.repo)
        return 2
    merge_base = select_mapping.resolve_merge_base(repo_root, args.diff_base)
    if merge_base is None:
        sys.stderr.write("error: unreadable diff base: %s\n" % args.diff_base)
        return 2
    dirty = select_mapping.has_uncommitted_plugin_changes(repo_root)
    if dirty is None:
        sys.stderr.write("error: failed to read git status\n")
        return 2
    if dirty:
        sys.stderr.write(
            "error: uncommitted changes under plugins/; select-cases reads committed state only\n"
        )
        return 2

    result = select_cases(repo_root, args.diff_base, merge_base)
    if result is None:
        sys.stderr.write("error: failed to read git diff against %s\n" % args.diff_base)
        return 2

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(format_text(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
