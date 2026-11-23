#!/usr/bin/env python3
"""select-cases - select affected eval cases for a git diff.

    select-cases.py <diff-base> [--json] [--repo <dir>]

Reads `git diff --name-status -M -z <diff-base>...HEAD --`, classifies each
changed file against the eval run policy, maps files to skills and cases
through the shared `case_skills.py` rule, and prints one block per affected
plugin (or `no affected cases`).

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
import subprocess
import sys

MIN_PYTHON = (3, 8)
DEFAULT_RUNS = 3
ARMS = 2

EVAL_DIR_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
PAID_RE = re.compile(r"""\btype["']?\s*:\s*["']?(?:llm|baseline)\b""", re.IGNORECASE)
DESC_TOKEN_RE = re.compile(r"\w+|[^\w\s]")
HUNK_HEADER_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
GRADERS_HEADER_RE = re.compile(r"^graders[ \t]*:[ \t]*(?:#.*)?\r?$")
DELIM_REL_PATH_RES = (
    re.compile(r"<((?:\.\.?/)+[^<>#\r\n]+)(?:#[^<>\r\n]*)?>"),
    re.compile(r'"((?:\.\.?/)+[^"#\r\n]+)(?:#[^"\r\n]*)?"'),
    re.compile(r"'((?:\.\.?/)+[^'#\r\n]+)(?:#[^'\r\n]*)?'"),
    re.compile(r"`((?:\.\.?/)+[^`#\r\n]+)(?:#[^`\r\n]*)?`"),
)
UNQUOTED_REL_PATH_RE = re.compile(r"(?:\.\.?/)+[^\s)\]`\"'>#;]+")
SHELL_ASSIGN_RE = re.compile(
    r"^[ \t]*(?:(?:local|readonly|export)[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)=(.+)$"
)
DIRNAME_INNER_RE = re.compile(
    r"""\$\(\s*dirname\s+["']?(?:\$\{?BASH_SOURCE(?:\[0\])?\}?|\$0)["']?\s*\)"""
)
PWD_TAIL_RE = re.compile(r"""["']?\s*&&\s*pwd(?:\s+-[PL])?\s*\)""")
YAML_TOP_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.\-]*)[ \t]*:(?:[ \t]+(.*))?$")

SCRIPT_EXTENSIONS = frozenset(
    [
        ".py",
        ".sh",
        ".bash",
        ".zsh",
        ".mjs",
        ".js",
        ".cjs",
        ".ts",
        ".mts",
        ".cts",
        ".ps1",
        ".psm1",
        ".bat",
        ".cmd",
        ".rb",
        ".pl",
        ".go",
    ]
)
TRIGGER_TAGS = frozenset(["triggering", "no-trigger", "no-fire"])
PLUGIN_WIDE_FILES = frozenset(
    [
        ".mcp.json",
        "plugin.json",
        ".claude-plugin/plugin.json",
        ".claude-plugin/marketplace.json",
        "settings.json",
        ".claude/settings.json",
    ]
)
PLUGIN_WIDE_DIRS = frozenset(["hooks"])
PLUGIN_SCRIPT_DIRS = frozenset(["scripts", "lib", "tests"])
PLUGIN_DOC_FILES = frozenset(["README.md", "CHANGELOG.md"])
DESCRIPTION_KEYS = ("description", "when_to_use")

HERE = os.path.dirname(os.path.abspath(__file__))
CASE_SKILLS_PY = os.path.normpath(
    os.path.join(HERE, os.pardir, os.pardir, os.pardir, "scripts", "case_skills.py")
)
VALIDATE_CASES_PY = os.path.normpath(
    os.path.join(HERE, os.pardir, os.pardir, "validate", "scripts", "validate-cases.py")
)


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


case_skills = _load_module("evals_case_skills", CASE_SKILLS_PY)
validate_cases = _load_module("evals_validate_cases", VALIDATE_CASES_PY)

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


def _git(repo_dir, *args):
    return subprocess.run(
        ["git", "-C", repo_dir, "-c", "core.quotepath=false"] + list(args),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def resolve_repo_root(repo_dir):
    """Return the git repository top-level directory, or None if unreadable."""
    done = _git(repo_dir, "rev-parse", "--show-toplevel")
    if done.returncode != 0:
        return None
    root = done.stdout.rstrip("\r\n")
    return os.path.abspath(root) if root else None


def resolve_merge_base(repo_root, diff_base):
    """Verify diff_base is readable and return the merge-base commit SHA."""
    verify = _git(repo_root, "rev-parse", "--verify", "--quiet", diff_base + "^{commit}")
    if verify.returncode != 0:
        return None
    base = _git(repo_root, "merge-base", diff_base, "HEAD")
    if base.returncode != 0:
        return None
    sha = base.stdout.strip()
    return sha or None


def has_uncommitted_plugin_changes(repo_root):
    """True when `git status --porcelain` shows changes under `plugins/`, None on error."""
    done = _git(repo_root, "status", "--porcelain", "-z", "--", "plugins")
    if done.returncode != 0:
        return None
    return bool(done.stdout)


def changed_entries(repo_root, diff_base):
    """Return (status_code, path, new_path_or_none) entries for diff_base...HEAD."""
    done = _git(
        repo_root,
        "diff",
        "--name-status",
        "-M",
        "-z",
        diff_base + "...HEAD",
        "--",
    )
    if done.returncode != 0:
        return None
    tokens = done.stdout.split("\0")
    if tokens and tokens[-1] == "":
        tokens.pop()
    entries = []
    index = 0
    while index < len(tokens):
        status = tokens[index]
        index += 1
        if not status:
            continue
        code = status[0]
        if code in ("R", "C"):
            if index + 1 < len(tokens):
                entries.append((code, tokens[index], tokens[index + 1]))
                index += 2
        elif index < len(tokens):
            entries.append((code, tokens[index], None))
            index += 1
    return entries


def git_show(repo_root, rev, rel_path):
    """Return file text at rev:rel_path, or None if absent at that commit."""
    done = _git(repo_root, "show", "%s:%s" % (rev, rel_path))
    if done.returncode != 0:
        return None
    return done.stdout


def _diff_has_cut_hunks(diff_text, skip_old_lines_upto=0):
    """A hunk that edits an existing line is a cut unless its old and new lines hold the same
    words, which is a re-wrap."""
    hunks = []
    for line in diff_text.splitlines():
        if line.startswith("Binary files "):
            return True
        match = HUNK_HEADER_RE.match(line)
        if match:
            old_start = int(match.group(1))
            old_count = 1 if match.group(2) is None else int(match.group(2))
            hunks.append([old_count > 0 and old_start + old_count - 1 > skip_old_lines_upto, [], []])
        elif hunks and line.startswith("-") and not line.startswith("---"):
            hunks[-1][1].extend(line[1:].split())
        elif hunks and line.startswith("+") and not line.startswith("+++"):
            hunks[-1][2].extend(line[1:].split())
    return any(edits and old != new for edits, old, new in hunks)


def diff_has_cut(repo_root, diff_base, rel_path, skip_old_lines_upto=0):
    """True when any `-U0` hunk modifies or removes an existing line past the skipped prefix."""
    done = _git(
        repo_root,
        "diff",
        "-U0",
        "--no-renames",
        diff_base + "...HEAD",
        "--",
        rel_path,
    )
    if done.returncode != 0:
        return True
    return _diff_has_cut_hunks(done.stdout, skip_old_lines_upto=skip_old_lines_upto)


def diff_blobs_has_cut(repo_root, merge_base, old_path, new_path):
    """True when `-U0` diff between `merge_base:old_path` and `HEAD:new_path` removes/edits a line."""
    done = _git(
        repo_root,
        "diff",
        "-U0",
        "%s:%s" % (merge_base, old_path),
        "HEAD:%s" % new_path,
    )
    if done.returncode != 0:
        return True
    return _diff_has_cut_hunks(done.stdout)


def _frontmatter_end_line(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return 0
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return index + 1
    return 0


def _split_frontmatter_loose(text):
    try:
        return validate_cases.split_markdown(text)
    except validate_cases.ParseError:
        lines = text.splitlines()
        if not lines or lines[0].strip() != "---":
            return None, text
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                return "\n".join(lines[1:index]), "\n".join(lines[index + 1 :])
        return None, text


def _unquote_scalar(raw):
    text = raw.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in ("'", '"'):
        return text[1:-1]
    return text


def _parse_frontmatter_loose(block):
    if block is None:
        return {}
    try:
        parsed = validate_cases.parse_yaml(block)
        if isinstance(parsed, dict):
            return parsed
    except validate_cases.ParseError:
        pass
    data = {}
    lines = block.splitlines()
    index = 0
    while index < len(lines):
        raw = lines[index]
        if not raw.strip() or raw.lstrip().startswith("#") or raw.startswith(" "):
            index += 1
            continue
        match = YAML_TOP_KEY_RE.match(raw)
        if not match:
            index += 1
            continue
        key = match.group(1)
        inline = (match.group(2) or "").strip()
        index += 1
        if inline in ("", ">", ">-", "|", "|-"):
            collected = []
            while index < len(lines) and (
                not lines[index].strip() or lines[index].startswith(" ")
            ):
                if lines[index].strip():
                    collected.append(lines[index].strip())
                index += 1
            data[key] = " ".join(collected)
        else:
            data[key] = _unquote_scalar(inline)
    return data


def _is_subsequence(old_tokens, new_tokens):
    it = iter(new_tokens)
    return all(token in it for token in old_tokens)


def _classify_description_change(base_fm, head_fm):
    status = None
    for key in DESCRIPTION_KEYS:
        old_val = base_fm.get(key)
        new_val = head_fm.get(key)
        if old_val == new_val:
            continue
        if old_val is None and new_val is not None:
            key_status = "additive"
        elif new_val is None:
            key_status = "cut"
        else:
            old_tokens = DESC_TOKEN_RE.findall(str(old_val))
            new_tokens = DESC_TOKEN_RE.findall(str(new_val))
            key_status = (
                "additive" if _is_subsequence(old_tokens, new_tokens) else "cut"
            )
        if key_status == "cut":
            return "cut"
        status = "additive"
    return status


def _classify_other_frontmatter(base_fm, head_fm):
    base_other = {k: v for k, v in base_fm.items() if k not in DESCRIPTION_KEYS}
    head_other = {k: v for k, v in head_fm.items() if k not in DESCRIPTION_KEYS}
    if base_other == head_other:
        return None
    for key, old_val in base_other.items():
        if key not in head_other or head_other[key] != old_val:
            return "cut"
    return "additive"


def classify_skill_md(repo_root, diff_base, merge_base, rel_path):
    """Return (body_class, desc_class) for a changed SKILL.md."""
    base_text = git_show(repo_root, merge_base, rel_path)
    head_text = git_show(repo_root, "HEAD", rel_path)
    if head_text is None:
        base_fm = _parse_frontmatter_loose(_split_frontmatter_loose(base_text or "")[0])
        desc = "cut" if any(k in base_fm for k in DESCRIPTION_KEYS) else None
        return "cut", desc
    if base_text is None:
        head_fm = _parse_frontmatter_loose(_split_frontmatter_loose(head_text)[0])
        desc = "additive" if any(k in head_fm for k in DESCRIPTION_KEYS) else None
        return "additive", desc

    base_fm_raw, base_body = _split_frontmatter_loose(base_text)
    head_fm_raw, head_body = _split_frontmatter_loose(head_text)
    base_fm = _parse_frontmatter_loose(base_fm_raw)
    head_fm = _parse_frontmatter_loose(head_fm_raw)

    desc_class = _classify_description_change(base_fm, head_fm)
    other_fm_class = _classify_other_frontmatter(base_fm, head_fm)

    body_class = None
    if base_body != head_body:
        fm_end = _frontmatter_end_line(base_text)
        body_class = (
            "cut"
            if diff_has_cut(repo_root, diff_base, rel_path, skip_old_lines_upto=fm_end)
            else "additive"
        )

    if "cut" in (body_class, other_fm_class):
        combined_body = "cut"
    elif "additive" in (body_class, other_fm_class):
        combined_body = "additive"
    else:
        combined_body = None
    return combined_body, desc_class


def _parse_case_yaml_text(text):
    stripped = text.lstrip()
    if stripped.startswith("---"):
        stripped = stripped[3:]
    return validate_cases.parse_yaml(stripped)


def is_description_only_case_edit(repo_root, merge_base, rel_path, filename):
    """True when a modified case.yaml or prompt.md changes only its description."""
    base_text = git_show(repo_root, merge_base, rel_path)
    head_text = git_show(repo_root, "HEAD", rel_path)
    if base_text is None or head_text is None:
        return False
    try:
        if filename == "case.yaml":
            base_doc = _parse_case_yaml_text(base_text)
            head_doc = _parse_case_yaml_text(head_text)
            if not isinstance(base_doc, dict) or not isinstance(head_doc, dict):
                return False
            base_rest = {k: v for k, v in base_doc.items() if k != "description"}
            head_rest = {k: v for k, v in head_doc.items() if k != "description"}
            return base_rest == head_rest
        if filename == "prompt.md":
            base_fm_raw, base_body = validate_cases.split_markdown(base_text)
            head_fm_raw, head_body = validate_cases.split_markdown(head_text)
            if base_body != head_body or base_fm_raw is None or head_fm_raw is None:
                return False
            base_fm = validate_cases.parse_yaml(base_fm_raw)
            head_fm = validate_cases.parse_yaml(head_fm_raw)
            base_rest = {k: v for k, v in base_fm.items() if k != "description"}
            head_rest = {k: v for k, v in head_fm.items() if k != "description"}
            return base_rest == head_rest
    except validate_cases.ParseError:
        return False
    return False


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
            yaml_data = _parse_case_yaml_text(validate_cases.read_text(yaml_path))
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
            block, body = _split_frontmatter_loose(validate_cases.read_text(prompt_path))
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

    is_trigger_or_no_fire = has_skill_grader or any(
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


def _read_text_safe(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            return handle.read()
    except OSError:
        return ""


def _iter_skill_files(repo_root, plugin_filter=None):
    plugins_dir = os.path.join(repo_root, "plugins")
    if not os.path.isdir(plugins_dir):
        return
    plugins = [plugin_filter] if plugin_filter else sorted(os.listdir(plugins_dir))
    for plugin in plugins:
        skills_dir = os.path.join(plugins_dir, plugin, "skills")
        if not os.path.isdir(skills_dir):
            continue
        for skill in sorted(os.listdir(skills_dir)):
            skill_dir = os.path.join(skills_dir, skill)
            if not os.path.isdir(skill_dir) or skill.startswith("."):
                continue
            for dirpath, dirnames, filenames in os.walk(skill_dir):
                dirnames[:] = sorted(
                    d
                    for d in dirnames
                    if d not in ("evals", "node_modules", "__pycache__")
                    and not d.startswith(".")
                )
                for filename in sorted(filenames):
                    if filename.startswith("."):
                        continue
                    yield plugin, skill, skill_dir, os.path.join(dirpath, filename)


def _extract_relative_paths(text):
    paths = []
    seen = set()
    for pat in DELIM_REL_PATH_RES:
        for match in pat.finditer(text):
            token = match.group(1)
            if token not in seen:
                seen.add(token)
                paths.append(token)
    for token in UNQUOTED_REL_PATH_RE.findall(text):
        for candidate in (token, token.rstrip(".,:")):
            if candidate and candidate not in seen:
                seen.add(candidate)
                paths.append(candidate)
    return paths


def _build_file_citation_patterns(plugin, rel_in_plugin):
    plugin_root_re = re.compile(
        r"\$\{CLAUDE_PLUGIN_ROOT\}/" + re.escape(rel_in_plugin) + r"(?![\w./-])"
    )
    repo_path_re = re.compile(
        r"(?<![\w/-])plugins/"
        + re.escape(plugin)
        + r"/"
        + re.escape(rel_in_plugin)
        + r"(?![\w./-])"
    )
    bare_re = re.compile(
        r"(?<![\w/.-])" + re.escape(rel_in_plugin) + r"(?![\w./-])"
    )
    return plugin_root_re, repo_path_re, bare_re


def _text_cites_plugin_file(
    text,
    fpath,
    p_name,
    skill_dir,
    target_plugin,
    rel_in_plugin,
    target_abs,
    patterns,
):
    plugin_root_re, repo_path_re, bare_re = patterns
    if repo_path_re.search(text):
        return True
    if p_name == target_plugin and plugin_root_re.search(text):
        return True
    base_dir = os.path.dirname(fpath)
    for token in _extract_relative_paths(text):
        if os.path.normpath(os.path.join(base_dir, token)) == target_abs:
            return True
    if p_name == target_plugin and bare_re.search(text):
        local_shadow = os.path.join(skill_dir, *rel_in_plugin.split("/"))
        if not os.path.exists(local_shadow):
            return True
    return False


def skills_citing_plugin_file(repo_root, plugin, rel_in_plugin):
    """Skills across all plugins whose files cite `plugins/<plugin>/<rel_in_plugin>`."""
    target_abs = os.path.normpath(
        os.path.join(repo_root, "plugins", plugin, *rel_in_plugin.split("/"))
    )
    patterns = _build_file_citation_patterns(plugin, rel_in_plugin)
    matched = set()
    for p_name, skill, skill_dir, fpath in _iter_skill_files(repo_root):
        if (p_name, skill) in matched:
            continue
        text = _read_text_safe(fpath)
        if not text:
            continue
        if _text_cites_plugin_file(
            text,
            fpath,
            p_name,
            skill_dir,
            plugin,
            rel_in_plugin,
            target_abs,
            patterns,
        ):
            matched.add((p_name, skill))
    return matched


def skills_for_workflow(repo_root, wf_plugin, wf_stem):
    """Skills across all plugins naming `<wf_plugin>:<wf_stem>` or citing its script."""
    token_re = re.compile(
        r"(?<![\w:-])" + re.escape("%s:%s" % (wf_plugin, wf_stem)) + r"(?![\w-])"
    )
    rel_in_plugin = "workflows/%s.js" % wf_stem
    target_abs = os.path.normpath(
        os.path.join(repo_root, "plugins", wf_plugin, "workflows", wf_stem + ".js")
    )
    patterns = _build_file_citation_patterns(wf_plugin, rel_in_plugin)
    matched = set()
    for p_name, skill, skill_dir, fpath in _iter_skill_files(repo_root):
        if (p_name, skill) in matched:
            continue
        text = _read_text_safe(fpath)
        if not text:
            continue
        if token_re.search(text) or _text_cites_plugin_file(
            text,
            fpath,
            p_name,
            skill_dir,
            wf_plugin,
            rel_in_plugin,
            target_abs,
            patterns,
        ):
            matched.add((p_name, skill))
    return matched


def skills_for_agent(repo_root, plugin, agent_name):
    """Skills referencing `plugin:agent` directly or through `workflows/*.js`."""
    token_re = re.compile(
        r"(?<![\w:-])" + re.escape("%s:%s" % (plugin, agent_name)) + r"(?![\w-])"
    )
    matched = set()
    for p_name, skill, _, fpath in _iter_skill_files(repo_root):
        if (p_name, skill) in matched:
            continue
        if token_re.search(_read_text_safe(fpath)):
            matched.add((p_name, skill))

    plugins_dir = os.path.join(repo_root, "plugins")
    if os.path.isdir(plugins_dir):
        for wf_plugin in sorted(os.listdir(plugins_dir)):
            wf_dir = os.path.join(plugins_dir, wf_plugin, "workflows")
            if not os.path.isdir(wf_dir):
                continue
            for filename in sorted(os.listdir(wf_dir)):
                if not filename.endswith(".js"):
                    continue
                wf_path = os.path.join(wf_dir, filename)
                if token_re.search(_read_text_safe(wf_path)):
                    matched.update(
                        skills_for_workflow(repo_root, wf_plugin, filename[:-3])
                    )
    return matched


def _suffix_after(text, start, end):
    if end >= len(text) or text[end] != "/":
        return ""
    quote = text[start - 1] if start > 0 and text[start - 1] in ('"', "'") else None
    stop_chars = (quote, "\r", "\n") if quote else tuple(" \t\r\n\"'`)&|;<>#")
    pos = end
    while pos < len(text) and text[pos] not in stop_chars:
        pos += 1
    return text[end:pos]


def _resolve_shell_subpath(base_dir, suffix):
    if not suffix:
        return os.path.normpath(base_dir)
    parts = [seg for seg in suffix.split("/") if seg]
    static = []
    for seg in parts:
        if "$" in seg:
            break
        static.append(seg)
    if not static:
        return os.path.normpath(base_dir)
    return os.path.normpath(os.path.join(base_dir, *static))


def _dirname_resolved(text, dn_match, base_dir):
    suffix = _suffix_after(text, dn_match.start(), dn_match.end())
    resolved = _resolve_shell_subpath(base_dir, suffix)
    tail_pos = dn_match.end() + len(suffix)
    pwd_tail = PWD_TAIL_RE.match(text, tail_pos)
    if pwd_tail:
        outer_start = text.rfind("$(", 0, dn_match.start())
        outer_suffix = _suffix_after(
            text, outer_start if outer_start >= 0 else 0, pwd_tail.end()
        )
        if outer_suffix:
            resolved = _resolve_shell_subpath(resolved, outer_suffix)
    return resolved


def _in_eval_suite(path, eval_norm):
    return path != eval_norm and path.startswith(eval_norm + os.sep)


def _extract_suite_refs(fpath, text, eval_norm):
    base_dir = os.path.dirname(fpath)
    refs = set()
    var_dirs = {}
    assign_lines = set()
    lines = text.splitlines()

    for line_no, line in enumerate(lines):
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        assign = SHELL_ASSIGN_RE.match(line)
        if not assign:
            continue
        var_name, rhs = assign.group(1), assign.group(2).strip()
        dn_match = DIRNAME_INNER_RE.search(rhs)
        if dn_match:
            var_dirs[var_name] = _dirname_resolved(rhs, dn_match, base_dir)
            assign_lines.add(line_no)
            continue
        for known_var, known_dir in list(var_dirs.items()):
            var_use = re.match(
                r"""^["']?(?:\$\{"""
                + re.escape(known_var)
                + r"""\}|\$"""
                + re.escape(known_var)
                + r"""(?![A-Za-z0-9_]))""",
                rhs,
            )
            if var_use:
                start_offset = 1 if rhs[0] in ('"', "'") else 0
                suffix = _suffix_after(rhs, start_offset, var_use.end())
                var_dirs[var_name] = _resolve_shell_subpath(known_dir, suffix)
                assign_lines.add(line_no)
                break

    for line_no, line in enumerate(lines):
        if line_no in assign_lines:
            continue
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        for dn_match in DIRNAME_INNER_RE.finditer(line):
            resolved = _dirname_resolved(line, dn_match, base_dir)
            if _in_eval_suite(resolved, eval_norm):
                refs.add(resolved)
        for token in _extract_relative_paths(line):
            resolved = os.path.normpath(os.path.join(base_dir, token))
            if _in_eval_suite(resolved, eval_norm):
                refs.add(resolved)
        for var_name, var_dir in var_dirs.items():
            var_re = re.compile(
                r"\$\{"
                + re.escape(var_name)
                + r"\}|\$"
                + re.escape(var_name)
                + r"(?![A-Za-z0-9_])"
            )
            for match in var_re.finditer(line):
                suffix = _suffix_after(line, match.start(), match.end())
                resolved = _resolve_shell_subpath(var_dir, suffix)
                if _in_eval_suite(resolved, eval_norm):
                    refs.add(resolved)

    if os.path.basename(fpath) == "case.yaml":
        try:
            doc = _parse_case_yaml_text(text)
        except validate_cases.ParseError:
            doc = None
        context = doc.get("context") if isinstance(doc, dict) else None
        if isinstance(context, dict):
            for field in ("scaffold_script", "history_file", "add_dirs"):
                value = context.get(field)
                entries = value if isinstance(value, list) else [value]
                for entry in entries:
                    if isinstance(entry, str) and entry:
                        resolved = os.path.normpath(os.path.join(base_dir, entry))
                        if _in_eval_suite(resolved, eval_norm):
                            refs.add(resolved)

    return refs


def _case_suite_references(case, eval_norm):
    queue = collections.deque()
    for dirpath, dirnames, filenames in os.walk(case.abs_dir):
        dirnames[:] = sorted(
            d
            for d in dirnames
            if d not in ("samples", "node_modules", "__pycache__")
            and not d.startswith(".")
        )
        for filename in sorted(filenames):
            if filename.startswith("."):
                continue
            queue.append(os.path.normpath(os.path.join(dirpath, filename)))

    visited = set()
    referenced = set()
    while queue:
        fpath = queue.popleft()
        if fpath in visited:
            continue
        visited.add(fpath)
        text = _read_text_safe(fpath)
        if not text:
            continue
        for ref_path in _extract_suite_refs(fpath, text, eval_norm):
            referenced.add(ref_path)
            if os.path.isfile(ref_path) and ref_path not in visited:
                queue.append(ref_path)
    return referenced


def cases_citing_suite_file(eval_abs, target_abs, suite_cases, ref_cache=None):
    """Cases in `suite_cases` whose files or helper scripts cite `target_abs`."""
    eval_norm = os.path.normpath(eval_abs)
    target_norm = os.path.normpath(target_abs)
    matched = []
    for case in suite_cases:
        if ref_cache is not None and case.abs_dir in ref_cache:
            referenced = ref_cache[case.abs_dir]
        else:
            referenced = _case_suite_references(case, eval_norm)
            if ref_cache is not None:
                ref_cache[case.abs_dir] = referenced
        hit = target_norm in referenced or any(
            not os.path.isfile(ref_path) and target_norm.startswith(ref_path + os.sep)
            for ref_path in referenced
        )
        if hit:
            matched.append(case)
    return matched


def _is_script_path(parts):
    if "scripts" in parts[:-1]:
        return True
    _, ext = os.path.splitext(parts[-1].lower())
    return ext in SCRIPT_EXTENSIONS


def _is_plugin_wide(rel_in_plugin):
    if rel_in_plugin in PLUGIN_WIDE_FILES:
        return True
    parts = rel_in_plugin.split("/")
    if parts[0] in PLUGIN_WIDE_DIRS:
        return True
    if parts[0].startswith("settings.") or (
        len(parts) == 2
        and parts[0] in (".claude", ".claude-plugin")
        and parts[1].startswith("settings.")
    ):
        return True
    return False


def _is_test_script(filename):
    lower = filename.lower()
    return (
        ".test." in lower
        or lower.startswith("test_")
        and lower.endswith(".py")
    )


def _case_covers_skill(case, skill_key):
    plugin, name = skill_key
    return skill_key in case.skills or any(
        rp == plugin and name.startswith(prefix)
        for rp, prefix in case.skill_prefixes
    )


def _case_covers_agent(case, agent_key):
    plugin, name = agent_key
    return agent_key in case.agents or any(
        rp == plugin and name.startswith(prefix)
        for rp, prefix in case.agent_prefixes
    )


def _agent_key_from_path(rel_path):
    parts = rel_path.split("/")
    if (
        len(parts) == 4
        and parts[0] == "plugins"
        and parts[2] == "agents"
        and parts[3].endswith(".md")
    ):
        return parts[1], parts[3][:-3]
    return None


def _agent_token_re(plugin, agent_name):
    return re.compile(
        r"(?<![\w:-])" + re.escape("%s:%s" % (plugin, agent_name)) + r"(?![\w-])"
    )


def _pair_unmatched_agent_renames(
    repo_root, merge_base, deleted_agents, added_agents, modified_dispatchers, changed_agents
):
    if not deleted_agents or not added_agents or not modified_dispatchers:
        return
    paired_old = set()
    for rel_path in modified_dispatchers:
        base_text = git_show(repo_root, merge_base, rel_path)
        head_text = git_show(repo_root, "HEAD", rel_path)
        if base_text is None or head_text is None:
            continue
        removed_here = [
            item
            for item in deleted_agents
            if item[0] not in paired_old
            and _agent_token_re(*item[0]).search(base_text)
            and not _agent_token_re(*item[0]).search(head_text)
        ]
        added_here = [
            item
            for item in added_agents
            if _agent_token_re(*item[0]).search(head_text)
            and not _agent_token_re(*item[0]).search(base_text)
        ]
        for old_key, old_path in removed_here:
            for new_key, new_path in added_here:
                kind = (
                    "cut"
                    if diff_blobs_has_cut(repo_root, merge_base, old_path, new_path)
                    else "additive"
                )
                if changed_agents.get(new_key) != "cut":
                    changed_agents[new_key] = kind
                paired_old.add(old_key)
    for old_key in paired_old:
        changed_agents.pop(old_key, None)


def select_cases(repo_root, diff_base, merge_base):
    """Compute affected cases per plugin for `diff_base...HEAD`."""
    entries = changed_entries(repo_root, diff_base)
    if entries is None:
        return None
    eval_dirs, cases_by_plugin = load_all_suites(repo_root)
    all_cases = [c for cases in cases_by_plugin.values() for c in cases]
    fixture_ref_cache = {}

    run_cases = collections.defaultdict(set)
    after_merge_cases = collections.defaultdict(set)
    no_run_cases = collections.defaultdict(set)
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

    expanded = []
    for code, path_a, path_b in entries:
        if code == "R" and path_b is not None:
            old_agent = _agent_key_from_path(path_a)
            new_agent = _agent_key_from_path(path_b)
            if old_agent and new_agent:
                kind = (
                    "cut"
                    if diff_blobs_has_cut(repo_root, merge_base, path_a, path_b)
                    else "additive"
                )
                if changed_agents.get(new_agent) != "cut":
                    changed_agents[new_agent] = kind
                skill_or_agent_plugins.add(new_agent[0])
                if skills_for_agent(repo_root, *old_agent) or any(
                    _case_covers_agent(c, old_agent) for c in all_cases
                ):
                    changed_agents[old_agent] = "cut"
                    skill_or_agent_plugins.add(old_agent[0])
                continue
            expanded.append(("D", path_a))
            expanded.append(("A", path_b))
        elif code == "C" and path_b is not None:
            expanded.append(("A", path_b))
        else:
            expanded.append((code, path_a))

    for code, rel_path in expanded:
        parts = rel_path.split("/")
        if len(parts) < 3 or parts[0] != "plugins":
            continue
        plugin = parts[1]
        rel_in_plugin = "/".join(parts[2:])
        ed_name = eval_dirs.get(plugin, "evals")

        if _is_plugin_wide(rel_in_plugin):
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
                body_cls, desc_cls = classify_skill_md(
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
                skill_or_agent_plugins.add(plugin)
            elif _is_script_path(inner_parts):
                script_only_skills.add((plugin, skill))
            else:
                reason = (
                    "body_cut"
                    if diff_has_cut(repo_root, diff_base, rel_path)
                    else "body_additive"
                )
                changed_skills[(plugin, skill)].add(reason)
                skill_or_agent_plugins.add(plugin)
            continue

        if parts[2] in ("reference", "context") and len(parts) >= 4:
            citing = skills_citing_plugin_file(repo_root, plugin, rel_in_plugin)
            if not citing:
                unmapped[plugin].add(rel_path)
            else:
                reason = (
                    "body_cut"
                    if diff_has_cut(repo_root, diff_base, rel_path)
                    else "body_additive"
                )
                for skill_key in citing:
                    changed_skills[skill_key].add(reason)
                    skill_or_agent_plugins.add(skill_key[0])
            continue

        if parts[2] == "agents" and len(parts) == 4 and parts[3].endswith(".md"):
            agent_name = parts[3][:-3]
            agent_key = (plugin, agent_name)
            kind = "cut" if diff_has_cut(repo_root, diff_base, rel_path) else "additive"
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
            for skill_key in skills_for_workflow(repo_root, plugin, parts[3][:-3]):
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
                if inner.startswith("samples/"):
                    no_run_cases[plugin].add(owning_case)
                elif inner in ("case.yaml", "prompt.md") and is_description_only_case_edit(
                    repo_root, merge_base, rel_path, inner
                ):
                    no_run_cases[plugin].add(owning_case)
                else:
                    run_cases[plugin].add(owning_case)
                unread_graders[plugin].update(owning_case.unread_graders)
            else:
                if parts[3] == "results" or _is_test_script(parts[-1]):
                    continue
                eval_abs = os.path.join(repo_root, "plugins", plugin, ed_name)
                target_abs = os.path.join(repo_root, *parts)
                cited_cases = cases_citing_suite_file(
                    eval_abs, target_abs, suite_cases, ref_cache=fixture_ref_cache
                )
                if cited_cases:
                    for case in cited_cases:
                        run_cases[plugin].add(case)
                elif os.path.exists(target_abs):
                    unmapped[plugin].add(rel_path)
            continue

        if parts[2] in PLUGIN_SCRIPT_DIRS or rel_in_plugin in PLUGIN_DOC_FILES:
            continue

        unmapped[plugin].add(rel_path)

    _pair_unmatched_agent_renames(
        repo_root,
        merge_base,
        deleted_agents,
        added_agents,
        modified_dispatchers,
        changed_agents,
    )

    for skill_key in script_only_skills:
        for case in all_cases:
            if _case_covers_skill(case, skill_key):
                no_run_cases[case.plugin].add(case)

    for (plugin, skill), reasons in sorted(changed_skills.items()):
        skill_key = (plugin, skill)
        skill_cases = [c for c in all_cases if _case_covers_skill(c, skill_key)]
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

        desc_only = reasons <= {"desc_cut", "desc_additive"}
        if not skill_cases or (desc_only and not trigger_cases):
            uncovered[plugin].add("%s:%s" % (plugin, skill))

    for (plugin, agent_name), kind in sorted(changed_agents.items()):
        agent_key = (plugin, agent_name)
        dispatched_by = skills_for_agent(repo_root, plugin, agent_name)
        for skill_key in dispatched_by:
            skill_or_agent_plugins.add(skill_key[0])
        agent_cases = [
            c
            for c in all_cases
            if any(_case_covers_skill(c, sk) for sk in dispatched_by)
            or _case_covers_agent(c, agent_key)
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
        | set(uncovered)
        | set(plugin_wide)
        | set(unmapped)
        | set(unread_graders)
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
        uncovered_list = sorted(uncovered.get(plugin, set()))
        plugin_wide_list = sorted(plugin_wide.get(plugin, set()))
        unmapped_list = sorted(unmapped.get(plugin, set()))
        unread_list = sorted(unread_graders.get(plugin, set()))

        if not any(
            (
                det_cases,
                judged,
                no_run_names,
                uncovered_list,
                ram_names,
                plugin_wide_list,
                unmapped_list,
                unread_list,
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
            "uncovered": uncovered_list,
            "run-after-merge": ram_names,
            "plugin-wide": plugin_wide_list,
            "unmapped": unmapped_list,
            "unread-graders": unread_list,
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
    repo_root = resolve_repo_root(repo_arg)
    if repo_root is None:
        sys.stderr.write("error: not a git repository: %s\n" % args.repo)
        return 2
    merge_base = resolve_merge_base(repo_root, args.diff_base)
    if merge_base is None:
        sys.stderr.write("error: unreadable diff base: %s\n" % args.diff_base)
        return 2
    dirty = has_uncommitted_plugin_changes(repo_root)
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
