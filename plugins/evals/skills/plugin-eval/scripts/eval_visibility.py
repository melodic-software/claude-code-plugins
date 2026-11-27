"""Whether the agent under test can see an eval file, for select-cases' comment-deletion rule.
Python 3.8+, standard library only.
"""

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_module(name, path):
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


select_mapping = _load_module("evals_select_mapping", os.path.join(HERE, "select_mapping.py"))
suite_refs = select_mapping.suite_refs
no_run_text = select_mapping.no_run_text

WILD_PATH_RE = re.compile(r"[*?[$`{]")
QUOTED_TOKEN_RE = re.compile(r"""(['"])([^'"\n]+)\1""")
SELF_REF_RE = re.compile(r"BASH_SOURCE|\$\{?0(?![0-9])")
PRINT_ONLY_RE = re.compile(
    r"""^(?:[^\s()]*\)\s*)?(?:echo|printf(?!\s+-v))\s[^;&|<>`]*?(?:\s*[12]?>&[12])?"""
    r"""\s*(?:;\s*exit(?:\s+\d+)?\s*)?(?:;;)?\s*$"""
)
SELF_LOCATE_RE = re.compile(
    r"__file__|__dirname|__filename|import\.meta|PSScriptRoot|PSCommandPath|MyInvocation"
    r"|\$0|BASH_SOURCE|os\.Executable|runtime\.Caller"
)
UNSET_MESSAGE_RE = re.compile(r"\$\{(\w+):?\?[^}$`]*\}")
TEXT_TOOL_RE = re.compile(r"\b(?:awk|gawk|mawk|sed|grep|jq)\b(?:[^;&|()`$]|\$(?!\())*$")


def _printed_text_cut(line):
    """`line` without what it only prints: nothing for an `echo` or `printf` line with no command
    substitution or redirect into a file, and no `${name:?message}` message. A script naming
    itself there prints its name, never its source."""
    stripped = UNSET_MESSAGE_RE.sub(r"${\1}", line.strip())
    shape = re.sub(r"""'[^']*'|"(?:[^"\\$`]|\\.)*\"""", "''", stripped)
    printed = PRINT_ONLY_RE.match(shape) and "$(" not in stripped and "`" not in stripped
    return "" if printed else stripped


def _code_lines(text):
    """Per line of a shell `text`: the line with each single-quoted program of a text tool (`awk`,
    `sed`, `grep`, `jq`) blanked, since `$0` there is that tool's record, never the script. The
    whole text reads unblanked when it runs code from a string (`suite_refs.runs_strings`) or its
    quoting does not read cleanly."""
    lines = text.splitlines()
    inside = no_run_text._string_block_lines(".sh", text)
    if inside is None or suite_refs.runs_strings(lines, inside):
        return list(lines)
    out, quote = [], None
    for number, line in enumerate(lines):
        if quote is None and number + 1 in inside:
            out.append(line)
            continue
        kept = []
        index = 0
        while index < len(line):
            char = line[index]
            if quote in ("'", "'kept"):
                kept.append(char if quote == "'kept" or char == "'" else " ")
                quote = None if char == "'" else quote
            elif char == "'" and quote is None:
                quote = "'" if TEXT_TOOL_RE.search("".join(kept)) else "'kept"
                kept.append(char)
            elif char == "\\":
                kept.append(line[index : index + 2])
                index += 1
            elif quote in ('"', "$'"):
                quote = None if char == quote[-1] else quote
                kept.append(char)
            elif char == "#" and (index == 0 or line[index - 1] in " \t"):
                break
            elif line.startswith("$'", index):
                quote = "$'"
                kept.append("$'")
                index += 1
            else:
                quote = '"' if char == '"' else None
                kept.append(char)
            index += 1
        out.append("".join(kept))
    return out


def _names_in_code(text, name_re=None):
    """Some code line of a shell `text` uses `$0` or `BASH_SOURCE` outside `$(dirname ...)`, a
    text tool's program and a print-only line, or matches `name_re` outside a print-only line."""
    for raw, code in zip(text.splitlines(), _code_lines(text)):
        if code is None or not raw.strip() or raw.strip().startswith("#"):
            continue
        if SELF_REF_RE.search(_printed_text_cut(select_mapping.DIRNAME_INNER_RE.sub("", code))):
            return True
        if name_re is not None and name_re.search(_printed_text_cut(raw)):
            return True
    return False


def _reads_own_source(path, text):
    return _names_in_code(text, _name_re(os.path.basename(path)))


def _locates_itself(fpath, text):
    """A case file that finds its own folder in a form the reference reading does not resolve:
    a shell `$0` or `BASH_SOURCE` other than `$(dirname ...)`, or another script's own-path
    variable."""
    ext = os.path.splitext(fpath)[1].lower()
    if ext in select_mapping.HIDDEN_SCRIPT_EXTS:
        return _names_in_code(text)
    return ext in select_mapping.SCRIPT_EXTENSIONS and bool(SELF_LOCATE_RE.search(text))


def _name_re(name):
    return re.compile(r"(?<![\w.-])" + re.escape(name) + r"(?![\w.-])")


def _covers(ref, target):
    """`ref` is `target`, a folder holding it, or a glob or unresolved expansion whose literal
    folder prefix could match it."""
    if ref == target or target.startswith(ref + os.sep):
        return True
    parts = ref.split(os.sep)
    wild = next((i for i, part in enumerate(parts) if WILD_PATH_RE.search(part)), None)
    prefix = os.sep.join(parts[:wild]) if wild else ""
    return bool(prefix) and target.startswith(prefix + os.sep)


def _site_covers(refs, narrow, target):
    """Some ref covers `target`, a ref in `narrow` only when `target` or a folder holding it below
    the ref ends with one of its tails."""

    def tail_hits(ref):
        parts = os.path.relpath(target, ref).split(os.sep)
        return any(part.endswith(tail) for part in parts for tail in narrow[ref])

    return any(_covers(ref, target) and (ref not in narrow or tail_hits(ref)) for ref in refs)


def deleted_lines(repo_root, merge_base, rel_path):
    """The lines `merge_base...HEAD` removes from `rel_path`, or None when git cannot say."""
    done = select_mapping._git(repo_root, "diff", "-U0", merge_base, "HEAD", "--", rel_path)
    if done.returncode != 0:
        return None
    return [
        line[1:]
        for line in done.stdout.splitlines()
        if line.startswith("-") and not line.startswith("---")
    ]


def _comment_reader_texts(eval_norm, files):
    for dirpath, dirnames, filenames in os.walk(eval_norm):
        dirnames[:] = [d for d in dirnames if d not in ("node_modules", "__pycache__")]
        for filename in filenames:
            if os.path.splitext(filename)[1].lower() in select_mapping.SCRIPT_EXTENSIONS:
                yield select_mapping._read_text_safe(os.path.join(dirpath, filename)) or ""
    for text, _ in files:
        yield text or ""


def _reads_deleted_comment(texts, deleted):
    """Some text naming `case.yaml` holds a deleted comment's words, or a quoted pattern that
    matches a deleted line; a comment after code counts from its first blank-led `#`."""
    bodies = []
    for line in deleted:
        mark = re.search(r"(?:^|[ \t])#", line)
        bodies.append(line[mark.end() :].lstrip("#").strip() if mark else "")
    for text in texts:
        if "case.yaml" not in text:
            continue
        if any(body and body in text for body in bodies):
            return True
        for _, token in QUOTED_TOKEN_RE.findall(text):
            if not re.search(r"[A-Za-z]{3}", token):
                continue
            try:
                pattern = re.compile(token)
            except re.error:
                continue
            if any(pattern.search(line) or pattern.search(line.strip()) for line in deleted):
                return True
    return False


def _case_files(case, eval_norm):
    return select_mapping._case_suite_files(case, eval_norm, visibility=True)


def _case_yaml_hidden(target, cases, eval_norm, deleted):
    if deleted is None:
        return False
    files = {}
    for case in cases:
        files.update(_case_files(case, eval_norm))
    case_yaml_re = _name_re("case.yaml")
    for fpath, (text, sites) in files.items():
        for _, refs, _, _, _, wide, narrow in sites:
            if wide or _site_covers(refs, narrow, target):
                return False
        if fpath != target and _locates_itself(fpath, text or ""):
            return False
        if os.path.splitext(fpath)[1].lower() in select_mapping.SCRIPT_EXTENSIONS and any(
            case_yaml_re.search(_printed_text_cut(line))
            for line in (text or "").splitlines()
            if not line.lstrip().startswith("#")
        ):
            return False
    return not _reads_deleted_comment(_comment_reader_texts(eval_norm, files.values()), deleted)


def hidden_from_agent(eval_abs, target_abs, cases, owning_case=None, deleted=()):
    """Whether the agent under test can never see `target_abs`. The owning case's `case.yaml`
    is hidden when no case file names its folder, the evals folder or one above, and no script
    naming `case.yaml` reads a `deleted` comment. A shell script is hidden when some case's
    scaffold runs it, no case's files copy, print, read, pass on or name it, or a folder holding
    it, in any other form, and it never reads its own source. A print-only line, a binding of a variable to the script's exact path, and a `plugins` entry
    naming the suite's own plugin are not such forms. Unsure is visible."""
    target = os.path.normpath(target_abs)
    eval_norm = os.path.normpath(eval_abs)
    if owning_case is not None and target == os.path.normpath(
        os.path.join(owning_case.abs_dir, "case.yaml")
    ):
        return _case_yaml_hidden(target, cases, eval_norm, deleted)
    if os.path.splitext(target)[1].lower() not in select_mapping.HIDDEN_SCRIPT_EXTS:
        return False
    own_text = select_mapping._read_text_safe(target)
    if own_text is None or _reads_own_source(target, own_text):
        return False
    name_re = _name_re(os.path.basename(target))
    run = False
    for case in cases:
        files = _case_files(case, eval_norm)
        for fpath, (text, sites) in files.items():
            if fpath != target and _locates_itself(fpath, text or ""):
                return False
            run_lines = suite_refs.binding_lines(fpath, text or "", target)
            for line, refs, runs, rest, rest_refs, wide, narrow in sites:
                if wide:
                    return False
                if not _site_covers(refs, narrow, target):
                    continue
                if runs != target or any(_covers(ref, target) for ref in rest_refs):
                    return False
                if name_re.search(rest):
                    return False
                run = True
                run_lines.add(line)
            if os.path.basename(fpath) == "case.yaml":
                run_lines.update(
                    line for line in (text or "").splitlines()
                    if line.strip().startswith("scaffold_script:")
                )
            for line in (text or "").splitlines():
                stripped = line.strip()
                if line in run_lines or not stripped or stripped.startswith("#"):
                    continue
                if name_re.search(_printed_text_cut(line)):
                    return False
    return run
