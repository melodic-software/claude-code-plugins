"""Whether the agent under test can see an eval file, for select-cases' comment-deletion rule.
Python 3.8+, standard library only.
"""

import functools
import importlib.util
import os
import re
import shlex
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
    r"""^(?:[^\s()]*\)\s*)?(?:echo|printf)\s[^;&|<>`]*?(?:\s*[12]?>&[12])?"""
    r"""\s*(?:;\s*exit(?:\s+\d+)?\s*)?(?:;;)?\s*$"""
)
SELF_LOCATE_RE = re.compile(
    r"__file__|__dirname|__filename|import\.meta|PSScriptRoot|PSCommandPath|MyInvocation"
    r"|\$0|BASH_SOURCE|os\.Executable|runtime\.Caller"
)
POSITIONAL_COPY_RE = re.compile(
    r"""^cp\s+(?:-[A-Za-z]+\s+)*"\$\{?(?P<dir>\w+)\}?/\$\{?(?P<var>[A-Za-z_]\w*)\}?"\s+"[^"$`]*(?:\$\{?\w+\}?[^"$`]*)*"\s*$"""
)
RUNNER_RE = re.compile(
    suite_refs.COMMAND_START
    + r"""["'\\]?(?:\$\{\w+:-)?(?:make|gmake|cmake|ninja|meson|scons|bazel|gradle|gradlew|mvn"""
    r"|ant|rake|dotnet|pre-commit|direnv|npm|npx|yarn|pnpm|bun|deno|node|python3?|pytest|tox|uv"
    r"|ruby|perl|php|go|cargo|just|task|bats|find|xargs|run-parts|parallel|watch)\b"
)
INDIRECT_NAME_RE = re.compile(r"\$\{!|(?<![$\\:])[*?]|\$\w+[.-]|\$\{\w+\}[\w.-]|[\w.-]\$\{?\w")
HOOKS_RE = re.compile(r"\.git\b|(?<![\w.-])hooks(?![\w.-])")
CAT_HEREDOC_RE = re.compile(
    r"""^\s*(?:cat|tee)(?:\s+(?:>>?\s*)?[^\s<>|;&]+)*\s*<<-?\s*([A-Za-z_]\w*)"""
    r"""\s*(?:>>?\s*[^\s<>|;&]+\s*)?$"""
)
GIT_RECORD_RE = re.compile(
    r"^\s*git\s+(?:-c\s+(?:core\.hooksPath=/dev/null|user\.\w+=\S*)\s+)*"
    r"(?:add|rm|commit|diff|status|ls-files)\b[^;&|`$()<>]*$"
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
    `sed`, `grep`, `jq`) blanked, since `$0` there is that tool's record, never the script, or None
    for a line a literal heredoc writes out. The whole text reads unblanked when it runs code from
    a string (`suite_refs.runs_strings`) or its quoting does not read cleanly."""
    lines = text.splitlines()
    skipped = suite_refs.literal_heredoc_lines(lines)
    inside = no_run_text._string_block_lines(".sh", text)
    if inside is None or suite_refs.runs_strings(lines, inside):
        return [None if n in skipped else line for n, line in enumerate(lines)]
    out, quote = [], None
    for number, line in enumerate(lines):
        if number in skipped:
            out.append(None)
            continue
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


def _written_files_run(files):
    """The names of the files literal heredocs write that a case shell file may run (it names one
    on any code line but the heredoc's own opener and a plain `git add`, `rm`, `commit`, `diff`,
    `status` or `ls-files`, which covers running, sourcing, renaming, linking and making it
    executable), or True when it may run any of them: it runs a tool that executes files it finds
    (`make`, `npm`, `python`, `find`, ...), points git at a hooks folder, redefines `PATH` or a
    child shell's startup, or writes a heredoc with no literal target name. A literal heredoc body
    is text, read as code only once its own file is found to run."""
    shell = [
        (text or "").splitlines()
        for fpath, (text, _) in files.items()
        if os.path.splitext(fpath)[1].lower() in select_mapping.HIDDEN_SCRIPT_EXTS
    ]
    names = set()
    for lines in shell:
        found = suite_refs.literal_heredoc_targets(lines)
        texts = _cat_heredoc_targets(lines)
        if found is None or texts is None:
            return True
        names |= found | texts
    run, grew = set(), bool(names)
    written = re.compile(r"(?<![\w.-])(%s)(?![\w.-])" % "|".join(re.escape(n) for n in names))
    every = frozenset(names)
    for fpath, (text, _) in files.items():
        ext = os.path.splitext(fpath)[1].lower()
        if ext in select_mapping.SCRIPT_EXTENSIONS and ext not in select_mapping.HIDDEN_SCRIPT_EXTS:
            if names and written.search(text or ""):
                return True
    aliases = {}
    for lines in shell:
        for line in lines:
            _names_run(line, written, aliases, every)
    while grew:
        grew = False
        for lines in shell:
            bodies = suite_refs.literal_heredoc_lines(lines, frozenset(run))
            texts = set() if run else _cat_heredoc_text_lines(lines)
            for number, line in enumerate(lines):
                stripped = line.strip()
                if number in bodies or number in texts or not stripped or stripped.startswith("#"):
                    continue
                hooks_path = re.search(r"hooksPath[=\s]+(\S+)", line)
                if hooks_path and hooks_path.group(1).strip("\"'") != "/dev/null":
                    return True
                if RUNNER_RE.search(line) or HOOKS_RE.search(line):
                    return True
                if suite_refs.LITERAL_HEREDOC_RE.match(line):
                    continue
                if suite_refs.SHADOWS_WRITER_RE.search(line):
                    return True
                hit = _names_run(line, written, aliases, every)
                if hit - run:
                    run |= hit
                    grew = True
    return frozenset(run)


def _cat_heredoc_text_lines(lines):
    """0-based body lines of `cat` or `tee` heredocs with an unquoted delimiter that hold no `$(`
    or backtick: text written out, whose only expansions are variables, so nothing on them runs.
    None count in a file that redefines `cat`, `tee` or `PATH` or sources a file, or whose
    strings do not read cleanly; an opener inside a string opens none, and a line continued with a
    backslash and the line after it count only when the joined text holds neither."""
    inside = no_run_text._string_block_lines(".sh", "\n".join(lines))
    if inside is None or suite_refs.shadows_writers(lines):
        return set()
    found, closer, joined = set(), None, []
    for number, line in enumerate(lines):
        if closer is not None:
            if line.lstrip("\t") == closer:
                closer, joined = None, []
                continue
            joined.append(number)
            if line.endswith("\\"):
                continue
            text = "".join(lines[n][:-1] if n != number else lines[n] for n in joined)
            if "$(" not in text and "`" not in text:
                found.update(joined)
            joined = []
            continue
        if number + 1 in inside:
            continue
        opener = CAT_HEREDOC_RE.match(line)
        if opener:
            closer = opener.group(1)
    return found


def _cat_heredoc_targets(lines):
    """The file names each `cat` or `tee` heredoc with an unquoted delimiter writes to, or None
    when one has a target whose name is not literal. One that only prints writes none."""
    names = set()
    for line in lines:
        opener = CAT_HEREDOC_RE.match(line)
        if opener and (">" in line or line.lstrip().startswith("tee")):
            found = suite_refs._heredoc_names(line, opener.end(1))
            if found is None:
                return None
            names |= found
    return names


def _names_run(line, written, aliases, every):
    """The written-file names `line` may run: every one it names, or names through a variable in
    `aliases` (bound, by a line that does only that, to a written path, and recorded here), or all
    of `every` when it builds a name (a glob, `${!name}`, or an expansion joined to text), except
    on a plain `git add`/`rm`/`commit`/`diff`/`status`/`ls-files` line or as an output redirection
    target (`>file`, `>>"$f"`)."""
    if GIT_RECORD_RE.match(line):
        return set()
    bound = suite_refs.SHELL_ASSIGN_RE.match(line)
    if bound and suite_refs._is_lone_assignment(line) and not re.search(r"\$\(|`", line):
        found = set(written.findall(bound.group(2)))
        if found:
            aliases[bound.group(1)] = found
            return set()
    rest = re.sub(r"""[0-9&]?(?<!<)>>?\s*(?:"[^"]*"|'[^']*'|[^\s;&|]+)""", " ", line)
    if INDIRECT_NAME_RE.search(_printed_text_cut(rest)):
        return set(every)
    hit = set(written.findall(rest))
    for name, targets in aliases.items():
        if re.search(r"\$\{?%s(?![\w])" % re.escape(name), rest):
            hit |= targets
    return hit


@functools.lru_cache(maxsize=None)
def _scripts_under(root):
    """((path, text, is_shell), ...) for every text file under `root`: a `Makefile`, an
    extensionless script or a prompt may call a helper as well as a script can."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in ("node_modules", "__pycache__", ".git")]
        for name in filenames:
            path = os.path.join(dirpath, name)
            text = select_mapping._read_text_safe(path)
            if text is not None:
                ext = os.path.splitext(name)[1].lower()
                found.append((path, text, ext in select_mapping.HIDDEN_SCRIPT_EXTS))
    return tuple(found)


@functools.lru_cache(maxsize=None)
def _call_site_args(helper, eval_norm):
    """The literal words every call of the shell script `helper` passes it, from every script
    under the repository's `plugins/`, or None when a script in another language names it, or a
    shell line names it other than as a plain `bash`/`sh`/path run or passes anything but literal
    words."""
    plugins_dir = os.path.dirname(os.path.dirname(eval_norm))
    name_re = _name_re(os.path.basename(helper))
    words = []
    for fpath, text, is_shell in _scripts_under(plugins_dir):
        if not is_shell:
            if name_re.search(text):
                return None
            continue
        if not name_re.search(text):
            continue
        lines = text.splitlines()
        var_dirs, _ = suite_refs._shell_var_dirs(lines, os.path.dirname(fpath))
        for number, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("#") or not name_re.search(_printed_text_cut(line)):
                continue
            shape = suite_refs.SCRIPT_RUN_RE.match(stripped)
            if fpath == helper or not shape or stripped.startswith(("source", ". ")) or shape.group("cd"):
                return None
            path_refs = suite_refs._line_refs(shape.group("path"), os.path.dirname(fpath), var_dirs, eval_norm)
            if path_refs != {helper}:
                return None
            raw, index = shape.group("rest"), number
            while raw.rstrip().endswith("\\") and index + 1 < len(lines):
                index += 1
                raw = raw.rstrip()[:-1] + " " + lines[index]
            if re.search(r"[$`*?\[\]{}<>|;&()~#\\]", raw):
                return None
            words.extend(shlex.split(raw))
    return tuple(words)


def _sets_positional_args(code):
    """Some `set` command in `code` sets the positional arguments: a `--`, or a word that is not
    an option or the name after `-o`/`+o`; unsure (a quote or expansion, or a quoted or escaped
    `set`) counts as setting them."""
    if re.search(r"""[\\"']set\b|(?<![\w$.-])set["']""", code):
        return True
    for match in re.finditer(r"(?<![\w$./-])set\b(?!-)([^;&|\n]*)", code):
        words, index = match.group(1).split(), 0
        while index < len(words):
            word = words[index]
            if word == "--" or not word.startswith(("-", "+")) or re.search(r"[\"'$`]", word):
                return True
            index += 2 if word.endswith("o") else 1
    return False


def _positional_copy_is_safe(fpath, text, line, target, eval_norm):
    """`line` of the shell script `fpath` is `cp "$dir/$var" "<dest>"` with `$dir` a resolved
    folder and `$var` set only from positional arguments, and no literal argument any call of the
    script passes names `target` or a folder holding it under that folder."""
    copy = POSITIONAL_COPY_RE.match(line.strip())
    if not copy:
        return False
    lines = text.splitlines()
    var_dirs, _ = suite_refs._shell_var_dirs(lines, os.path.dirname(fpath))
    folder, var = var_dirs.get(copy.group("dir")), re.escape(copy.group("var"))
    code_lines = [line for line in lines if not line.lstrip().startswith("#")]
    code = "\n".join(code_lines)
    sets = re.findall(r"(?<![\w$])%s(\[[^]]*\])?(\+?)=(\S*)" % var, code)
    if folder is None or not sets or suite_refs.runs_strings(lines, frozenset()):
        return False
    if any(
        index or append or not re.fullmatch(r"""("?)\$\{?[1-9]\}?\1""", value)
        for index, append, value in sets
    ):
        return False
    dir_var = re.escape(copy.group("dir"))
    dir_sets = [c for c in code_lines if re.search(r"(?<![\w$])%s(\[[^]]*\])?\+?=" % dir_var, c)]
    if len(dir_sets) != 1 or not re.match(r"%s=" % dir_var, dir_sets[0]):
        return False
    plain = r"""(?:[A-Za-z_]\w*=("?)\$\{?[1-9]\}?\1\s*)+"""
    var_lines = [n for n, c in enumerate(code_lines) if re.search(r"(?<![\w$])%s=" % var, c)]
    if any(not re.fullmatch(plain, code_lines[n].strip()) for n in var_lines) or any(
        re.search(r"\$\{?%s\b" % var, c) for c in code_lines[: var_lines[0]]
    ):
        return False
    if re.search(
        r"\b(?:read|for|select|local|declare|typeset|mapfile|readarray|getopts|export|let|unset)\b"
        r"[^;\n]*\b%s\b|printf\s+-v\s*[\"']?%s\b|\(\([^)]*\b%s\b|\$\{%s:?=" % (var, var, var, var)
        + r"|\w+\s*\(\s*\)\s*\{|\bfunction\s+\w+|\bshopt\b|\bIFS=",
        code,
    ) or _sets_positional_args(code):
        return False
    words = _call_site_args(os.path.normpath(fpath), eval_norm)
    if words is None:
        return False
    for word in words:
        named = os.path.normpath(os.path.join(folder, word))
        if named == target or target.startswith(named + os.sep):
            return False
    return True


def _case_files(case, eval_norm):
    """`_case_suite_files` for the visibility check, reading literal heredoc bodies as references
    whenever the case may run what one writes."""
    files = select_mapping._case_suite_files(case, eval_norm, visibility=True)
    run = _written_files_run(files)
    if run:
        inert = False if run is True else run
        files = select_mapping._case_suite_files(case, eval_norm, True, inert_heredocs=inert)
    return files


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
    it, in any other form, and it never reads its own source. Text a literal heredoc writes out,
    a print-only line, a binding of a variable to the script's exact path, and a `plugins` entry
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
                if runs is None and _positional_copy_is_safe(fpath, text, line, target, eval_norm):
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
