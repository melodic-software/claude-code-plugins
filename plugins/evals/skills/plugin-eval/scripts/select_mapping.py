"""Git helpers, diff classifiers, and file-to-skill/case mapping for select-cases.

Shared by `select-cases.py` to inspect `diff_base...HEAD`, classify markdown and
frontmatter edits, and resolve plugin files, workflows, agents, and suite
fixtures to the skills and eval cases that depend on them. Python 3.8+,
standard library only.
"""

import collections
import functools
import importlib.util
import json
import os
import re
import subprocess
import sys

MIN_PYTHON = (3, 8)

DESC_TOKEN_RE = re.compile(r"\w+|[^\w\s]")
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
DESCRIPTION_KEYS = ("description", "when_to_use")

GLOSSARY_PATHS = ("docs/glossary.md", "GLOSSARY.md")

HERE = os.path.dirname(os.path.abspath(__file__))
VALIDATE_CASES_PY = os.path.normpath(
    os.path.join(HERE, os.pardir, os.pardir, "validate", "scripts", "validate-cases.py")
)


def _load_module(name, path):
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


validate_cases = _load_module("evals_validate_cases", VALIDATE_CASES_PY)
no_run_text = _load_module("evals_no_run_text", os.path.join(HERE, "no_run_text.py"))


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


def _diff_has_cut_hunks(
    diff_text,
    skip_old_lines_upto=0,
    skip_old_ranges=(),
    allow_heading_renames=False,
    pairs=(),
    comment_style=None,
):
    """A hunk that edits an existing line is a cut unless every old word survives, in order, in
    its new lines and no inserted word flips their meaning: a re-wrap or a pure insertion. A hunk
    whose old lines all sit inside one of `skip_old_ranges` (inclusive line pairs) is not a cut,
    nor one that only swaps glossary-decided terms (`pairs`) or only deletes whole comment lines
    (`comment_style`), nor, with `allow_heading_renames`, one that only renames routing headings."""
    hunks = []
    for line in diff_text.splitlines():
        if line.startswith("Binary files "):
            return True
        match = no_run_text.HUNK_HEADER_RE.match(line)
        if match:
            old_start = int(match.group(1))
            old_count = 1 if match.group(2) is None else int(match.group(2))
            old_end = old_start + old_count - 1
            skipped = any(lo <= old_start and old_end <= hi for lo, hi in skip_old_ranges)
            keep = old_count > 0 and old_end > skip_old_lines_upto and not skipped
            hunks.append([keep, [], [], [], [], old_start])
        elif hunks and line.startswith("-") and not line.startswith("---"):
            hunks[-1][1].extend(line[1:].split())
            hunks[-1][3].append(line[1:])
        elif hunks and line.startswith("+") and not line.startswith("+++"):
            hunks[-1][2].append(line[1:].split())
            hunks[-1][4].append(line[1:])
    for hunk in hunks:
        if hunk[0] and (
            (allow_heading_renames and no_run_text._is_routing_heading_rename(hunk[3], hunk[4]))
            or no_run_text._hunk_is_no_run(hunk[3], hunk[4], pairs, comment_style, hunk[5])
        ):
            hunk[0] = False

    def is_cut(old, new_lines):
        """Old words must survive in order; a flip word inserted into a line that keeps old words
        is a cut, while a wholly new line stays additive."""
        index = 0
        for words in new_lines:
            added = []
            kept_here = False
            for word in words:
                if index < len(old) and word == old[index]:
                    index += 1
                    kept_here = True
                else:
                    added.append(word)
            if kept_here and any(no_run_text.flips_meaning(word) for word in added):
                return True
        return index != len(old)

    return any(edits and is_cut(old, new) for edits, old, new, *_ in hunks)


def diff_has_cut(
    repo_root,
    diff_base,
    rel_path,
    skip_old_lines_upto=0,
    skip_old_ranges=(),
    allow_heading_renames=False,
):
    """True when any `-U0` hunk modifies or removes an existing line past the skipped prefix and
    outside the skipped ranges."""
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
    base = git_show(repo_root, resolve_merge_base(repo_root, diff_base), rel_path) or ""
    return _diff_has_cut_hunks(
        done.stdout,
        skip_old_lines_upto=skip_old_lines_upto,
        skip_old_ranges=skip_old_ranges,
        allow_heading_renames=allow_heading_renames,
        pairs=decided_term_pairs(repo_root),
        comment_style=no_run_text.comment_style(rel_path, base),
    )


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
    base = git_show(repo_root, merge_base, old_path) or ""
    return _diff_has_cut_hunks(
        done.stdout,
        pairs=decided_term_pairs(repo_root),
        comment_style=no_run_text.comment_style(new_path, base),
    )


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


@functools.lru_cache(maxsize=None)
def decided_term_pairs(repo_root, rev="HEAD"):
    """The glossary's rejected-to-decided term pairs at `rev`, empty when no glossary exists."""
    for path in GLOSSARY_PATHS:
        text = git_show(repo_root, rev, path)
        if text is not None:
            return no_run_text._parse_rejected_terms(text)
    return ()


def swap_rename_pairs(repo_root, merge_base, deleted, added):
    """(deleted, added) path pairs git did not pair as a rename whose path and content differ only
    by decided-term swaps."""
    pairs = []
    unused = list(added)
    for old_path in deleted:
        for new_path in unused:
            if is_no_run_file_change(repo_root, merge_base, old_path, new_path):
                pairs.append((old_path, new_path))
                unused.remove(new_path)
                break
    return pairs


def is_no_run_file_change(repo_root, merge_base, old_path, new_path):
    """True when `old_path` at merge_base and `new_path` at HEAD differ only by decided-term swaps
    (path and content) and whole-comment-line deletions."""
    pairs = decided_term_pairs(repo_root)
    if old_path != new_path and not no_run_text.is_term_swap_only(old_path, new_path, pairs):
        return False
    done = _git(
        repo_root, "diff", "-U0", "%s:%s" % (merge_base, old_path), "HEAD:%s" % new_path
    )
    if done.returncode != 0:
        return False
    hunks = no_run_text._raw_hunks(done.stdout)
    style = no_run_text.comment_style(new_path, git_show(repo_root, merge_base, old_path) or "")
    return hunks is not None and all(
        no_run_text._hunk_is_no_run(old, new, pairs, style, start) for start, old, new in hunks
    )


def _value_text(value):
    return value if isinstance(value, str) else json.dumps(value, sort_keys=True)


def _classify_description_change(base_fm, head_fm, pairs=()):
    """`cut`, `additive`, `exempt` (routing clauses, skill tokens or decided terms only) or
    None; a cut in either key wins, then an additive edit."""
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
        elif no_run_text.is_routing_only_change(str(old_val), str(new_val), pairs):
            key_status = "exempt"
        else:
            old_tokens = DESC_TOKEN_RE.findall(str(old_val))
            new_tokens = DESC_TOKEN_RE.findall(str(new_val))
            key_status = (
                "additive" if _is_subsequence(old_tokens, new_tokens) else "cut"
            )
        if key_status == "cut":
            return "cut"
        if status != "additive":
            status = key_status
    return status


def _classify_other_frontmatter(base_fm, head_fm, pairs=()):
    """An added key, or a value changed only by decided-term swaps, is additive."""
    base_other = {k: v for k, v in base_fm.items() if k not in DESCRIPTION_KEYS}
    head_other = {k: v for k, v in head_fm.items() if k not in DESCRIPTION_KEYS}
    if base_other == head_other:
        return None
    for key, old_val in base_other.items():
        new_val = head_other.get(key)
        if new_val != old_val and (
            new_val is None
            or not no_run_text.is_term_swap_only(_value_text(old_val), _value_text(new_val), pairs)
        ):
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

    pairs = decided_term_pairs(repo_root)
    desc_class = _classify_description_change(base_fm, head_fm, pairs)
    other_fm_class = _classify_other_frontmatter(base_fm, head_fm, pairs)

    body_class = None
    if base_body != head_body:
        body_class = (
            "cut"
            if diff_has_cut(
                repo_root,
                diff_base,
                rel_path,
                skip_old_lines_upto=_frontmatter_end_line(base_text),
                skip_old_ranges=no_run_text._no_run_section_lines(base_text),
                allow_heading_renames=True,
            )
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
