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

WILD_PATH_RE = re.compile(r"[*?[$`{]")
QUOTED_TOKEN_RE = re.compile(r"""(['"])([^'"\n]+)\1""")
SELF_REF_RE = re.compile(r"BASH_SOURCE|\$\{?0(?![0-9])")


def _reads_own_source(path, text):
    name_re = _name_re(os.path.basename(path))
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        rest = select_mapping.DIRNAME_INNER_RE.sub("", stripped)
        if SELF_REF_RE.search(rest) or name_re.search(rest):
            return True
    return False


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
    matches the deleted line."""
    comments = [line.strip() for line in deleted if line.strip().startswith("#")]
    bodies = [line.lstrip("#").strip() for line in comments]
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
            if any(pattern.search(line) for line in comments):
                return True
    return False


def _case_yaml_hidden(target, cases, eval_norm, deleted):
    if deleted is None:
        return False
    files = {}
    for case in cases:
        files.update(select_mapping._case_suite_files(case, eval_norm))
    for _, sites in files.values():
        for _, refs, _, _, _, wide in sites:
            if wide or any(_covers(ref, target) for ref in refs):
                return False
    return not _reads_deleted_comment(_comment_reader_texts(eval_norm, files.values()), deleted)


def hidden_from_agent(eval_abs, target_abs, cases, owning_case=None, deleted=()):
    """Whether the agent under test can never see `target_abs`. The owning case's `case.yaml`
    is hidden when no case file names its folder, the evals folder or one above, and no script
    naming `case.yaml` reads a `deleted` comment. A shell script is hidden when some case's
    scaffold runs it, no case's files copy, print, read, pass on or name it, or a folder holding
    it, in any other form, and it never reads its own source. Unsure is visible."""
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
        for fpath, (text, sites) in select_mapping._case_suite_files(case, eval_norm).items():
            run_lines = set()
            for line, refs, runs, rest, rest_refs, wide in sites:
                if wide:
                    return False
                if not any(_covers(ref, target) for ref in refs):
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
                if name_re.search(line):
                    return False
    return run
