"""Which eval-suite files a case file names, copies or runs, for select-cases' mapping and its
agent-visibility check. Python 3.8+, standard library only.
"""

import collections
import importlib.util
import os
import re
import sys

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
HIDDEN_SCRIPT_EXTS = frozenset([".sh", ".bash"])
CD_PWD_RE = re.compile(
    r"""^["']?\$\(\s*cd\s+["']?(?P<arg>[^"'\s)]+)["']?\s*&&\s*pwd(?:\s+-[PL])?\s*\)"""
    r"""(?P<after>[^"'\s]*)["']?$"""
)
LITERAL_HEREDOC_RE = re.compile(
    r"""^\s*(?:cat|tee)(?:\s+(?:>>?\s*)?[^\s<>|;&]+)*\s*<<-?\s*(['"])([A-Za-z_]\w*)\1"""
    r"""\s*(?:>>?\s*[^\s<>|;&]+\s*)?$"""
)
RUNS_STRING_RE = re.compile(
    r"(?:^\s*|[;&|({]\s*|\b(?:then|do|else|exec|command|!)\s+)(?:eval|source|export|trap|alias|\.)\s"
    r"|\|\s*(?:ba|z)?sh\b|\b(?:ba|z)?sh\s+(?:-[A-Za-z]+\s+)*-[A-Za-z]*c\b"
)
CD_WORD_RE = re.compile(r"(?:^|[;&|({]\s*|\b(?:then|do|else)\s+)cd\b")
PLUGINS_FIELD_RE = re.compile(r"""^plugins:\s*\[\s*["'][^"']+["']\s*(?:,\s*["'][^"']+["']\s*)*\]\s*$""")
SCRIPT_RUN_RE = re.compile(
    r"""^(?:\(\s*cd\s+(?P<cd>"[^"]*"|'[^']*'|[^\s;&|]+)\s*&&\s*)?"""
    r"""(?:(?:exec|command|then|do|else|!)\s+)*(?:(?:bash|sh|source|\.)\s+(?:-(?!c\b)[A-Za-z]+\s+)*)?"""
    r"""(?P<path>"(?:\$\([^)]*\)|[^"])*"|'[^']*'|(?:\$\([^)]*\)|\$\{[^}]*\}|[^\s;&|<>"'(){}])+)"""
    r"""(?P<rest>(?:\s.*)?)$"""
)

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


def _parse_case_yaml_text(text):
    stripped = text.lstrip()
    if stripped.startswith("---"):
        stripped = stripped[3:]
    return validate_cases.parse_yaml(stripped)


def _read_text_safe(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            return handle.read()
    except OSError:
        return ""


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


def _suffix_after(text, start, end):
    quote = text[start - 1] if start > 0 and text[start - 1] in ('"', "'") else None
    if quote and text[end : end + 2] == quote + "/":
        end, quote = end + 1, None
    if end >= len(text) or text[end] != "/":
        return ""
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


def _top_level_text(text):
    """`text` with every quoted run, `$(...)` and `${...}` cut, or None when it does not read
    cleanly (a backtick, an unbalanced bracket or an open quote)."""
    out, index, quote = [], 0, None
    while index < len(text):
        char = text[index]
        if char == "\\" and quote != "'":
            index += 2
            continue
        if quote == "'":
            quote = None if char == "'" else quote
        elif text.startswith(("$(", "${"), index):
            opener = text[index + 1]
            close = _match_close(text, index + 2, opener, ")" if opener == "(" else "}")
            if close is None:
                return None
            index = close + 1
            continue
        elif quote == '"':
            quote = None if char == '"' else quote
        elif char == "`":
            return None
        elif char in "'\"":
            quote = char
        else:
            out.append(char)
        index += 1
    return None if quote else "".join(out)


def _is_lone_assignment(line):
    """`line` (its trailing comment cut) only assigns one word: nothing runs after or with it."""
    start = no_run_text.shell_comment_start(line)
    rhs = SHELL_ASSIGN_RE.match(line[:start] if start is not None else line).group(2).strip()
    top = _top_level_text(rhs)
    return top is not None and not re.search(r"[\s;&|<>()]", top)


def _shell_var_dirs(lines, base_dir):
    """{variable: the path it holds} for assignments `_line_refs` can resolve, and the 0-based
    numbers of the lines that do nothing but such an assignment."""
    var_dirs = {}
    assign_lines = set()
    for line_no, line in enumerate(lines):
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        assign = SHELL_ASSIGN_RE.match(line)
        if not assign:
            continue
        var_name, rhs = assign.group(1), assign.group(2).strip()
        if not _is_lone_assignment(line):
            line_no = None
        dn_match = DIRNAME_INNER_RE.search(rhs)
        if dn_match:
            var_dirs[var_name] = _dirname_resolved(rhs, dn_match, base_dir)
            assign_lines.add(line_no)
            continue
        cd_pwd = CD_PWD_RE.match(rhs)
        if cd_pwd:
            arg = cd_pwd.group("arg")
            for known_var, known_dir in list(var_dirs.items()):
                use = re.match(r"\$\{?" + re.escape(known_var) + r"\}?(?![A-Za-z0-9_])", arg)
                if use:
                    resolved = _resolve_shell_subpath(known_dir, arg[use.end() :])
                    var_dirs[var_name] = _resolve_shell_subpath(resolved, cd_pwd.group("after"))
                    assign_lines.add(line_no)
                    break
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
    assign_lines.discard(None)
    return var_dirs, assign_lines


def _holds_suite(path, eval_norm):
    return path == eval_norm or eval_norm.startswith(path + os.sep)


def _match_close(line, index, opener, closer):
    """Index of the `closer` that balances an `opener` already open before `index`, skipping
    quoted text; None when the line ends first."""
    depth, quote = 1, None
    while index < len(line):
        char = line[index]
        if char == "\\" and quote != "'":
            index += 2
            continue
        if quote:
            quote = None if char == quote else quote
        elif char in "'\"":
            quote = char
        elif char in (opener, closer):
            depth += 1 if char == opener else -1
            if not depth:
                return index
        index += 1
    return None


def _quoted_tail(line, start):
    """The literal text that ends the double-quoted word whose expansion starts at `start`, after
    its last expansion and with no `/` in it, such as `.txt` in `"$dir/$1.txt"`: whatever the
    expansions hold, the path the word names ends with it. None when there is no such text, or the
    word is not one whole double-quoted word or does not read cleanly."""
    if start == 0 or line[start - 1] != '"':
        return None
    index, last = start, None
    while index < len(line) and line[index] != '"':
        char = line[index]
        if char == "\\":
            index += 2
            continue
        if char == "`":
            return None
        if line.startswith(("$(", "${"), index):
            close = _match_close(line, index + 2, line[index + 1], ")" if line[index + 1] == "(" else "}")
            if close is None:
                return None
            index = last = close + 1
            continue
        name = re.match(r"\$(?:[A-Za-z_]\w*|[0-9@*#?$!-])", line[index:])
        if name:
            index = last = index + name.end()
            continue
        index += 1
    if index >= len(line) or line[index + 1 : index + 2] not in ("", " ", "\t", ";", "&", "|", ")", "<", ">"):
        return None
    tail = line[last:index] if last is not None else ""
    return tail if tail and "/" not in tail else None


def _line_refs(line, base_dir, var_dirs, eval_norm, wide=None, tails=None):
    """The suite paths `line` names; one naming the suite folder or a folder above it goes into
    `wide` when given. `tails` maps each path to the `_quoted_tail` of each occurrence naming it,
    None for an occurrence without one."""
    refs = set()

    def keep(resolved, tail=None):
        if _in_eval_suite(resolved, eval_norm):
            refs.add(resolved)
            if tails is not None:
                tails.setdefault(resolved, set()).add(tail)
        elif wide is not None and _holds_suite(resolved, eval_norm):
            wide.add(resolved)

    for dn_match in DIRNAME_INNER_RE.finditer(line):
        keep(_dirname_resolved(line, dn_match, base_dir))
    for token in _extract_relative_paths(line):
        keep(os.path.normpath(os.path.join(base_dir, token)))
    for var_name, var_dir in var_dirs.items():
        var_re = re.compile(
            r"\$\{" + re.escape(var_name) + r"\}|\$" + re.escape(var_name) + r"(?![A-Za-z0-9_])"
        )
        for match in var_re.finditer(line):
            suffix = _suffix_after(line, match.start(), match.end())
            keep(_resolve_shell_subpath(var_dir, suffix), _quoted_tail(line, match.start()))
    return refs


def runs_strings(lines, inside):
    """Some code line outside the heredoc and string lines `inside` (1-based) pipes into a shell,
    runs a string (`eval`, `bash -c`, `trap`, `alias`), sources a file or exports a variable, so
    text this reading takes as literal may run."""
    return any(
        number not in inside and not line.lstrip().startswith("#") and RUNS_STRING_RE.search(line)
        for number, line in enumerate(lines, 1)
    )


def literal_heredoc_lines(lines):
    """0-based numbers of the body lines of each `cat` or `tee` heredoc with a quoted delimiter,
    which the shell writes out as literal text and never runs; an unterminated one counts none,
    and none count when the file's strings do not read cleanly, an opener sits in a string, or
    the file pipes into a shell, sources, evaluates or exports anything."""
    inside = no_run_text._string_block_lines(".sh", "\n".join(lines))
    if inside is None or runs_strings(lines, inside):
        return set()
    found, body, closer = set(), [], None
    for number, line in enumerate(lines):
        if closer is None and number + 1 in inside:
            continue
        if closer is not None:
            if line.lstrip("\t") == closer:
                found.update(body)
                closer = None
            else:
                body.append(number)
            continue
        opener = LITERAL_HEREDOC_RE.match(line)
        if opener:
            closer, body = opener.group(2), []
    return found


def binding_lines(fpath, text, target):
    """Lines of `fpath` that only bind a variable to exactly `target`, for a variable every use
    of which `_line_refs` resolves: never exported, renamed, indirected or expanded with an
    operator, in a file with no `eval`."""
    lines = text.splitlines()
    var_dirs, assign_lines = _shell_var_dirs(lines, os.path.dirname(fpath))
    code = "\n".join(line for line in lines if not line.lstrip().startswith("#"))
    if re.search(r"\beval\b|\$\{!|\b(?:declare|local|typeset)\s+-[a-zA-Z]*[nx]", code):
        return set()
    found = set()
    for line_no in assign_lines:
        name = re.escape(SHELL_ASSIGN_RE.match(lines[line_no]).group(1))
        if var_dirs.get(SHELL_ASSIGN_RE.match(lines[line_no]).group(1)) != target:
            continue
        if re.search(r"\bexport\b.*\b%s\b|\$\{#?%s(?!\w)[^}]|\$\{#%s\}" % (name, name, name), code):
            continue
        found.add(lines[line_no])
    return found


def _plain_cd_run(shape, base_dir, var_dirs, eval_norm):
    """A run line with no `(cd <dir> && ` prefix, or one whose `<dir>` names nothing in or above
    the suite and after whose script nothing else runs, so no argument is read relative to a
    suite folder."""
    if shape.group("cd") is None:
        return True
    wide = set()
    if _line_refs(shape.group("cd"), base_dir, var_dirs, eval_norm, wide) or wide:
        return False
    rest = shape.group("rest").rstrip()
    top = _top_level_text(rest[:-1] if rest.endswith(")") else rest)
    return top is not None and not re.search(r"[;&|()]", top)


def _suite_ref_sites(fpath, text, eval_norm, visibility=False):
    """Each reference `fpath` makes into the suite: (line, refs, runs, rest, rest_refs, wide,
    narrow), where `runs` is the one script a shell line or a `scaffold_script` value executes,
    `rest` the line after that script's path, `wide` whether it names the suite folder or one
    above, and `narrow` maps each ref every occurrence of which names only paths ending in one of
    its tails (`_quoted_tail`) to those tails. With `visibility`, the body of a literal `cat` or
    `tee` heredoc is skipped, and so is a top-level `plugins: [...]` line of a `case.yaml` or
    `prompt.md` naming the plugin the suite belongs to, which is the plugin loaded by default."""
    base_dir = os.path.dirname(fpath)
    lines = text.splitlines()
    var_dirs, assign_lines = _shell_var_dirs(lines, base_dir)
    is_shell = os.path.splitext(fpath)[1].lower() in HIDDEN_SCRIPT_EXTS
    skipped = literal_heredoc_lines(lines) if visibility and is_shell else set()
    own_plugin = os.path.basename(fpath) in ("case.yaml", "prompt.md") and visibility
    sites = []
    for line_no, line in enumerate(lines):
        if line_no in assign_lines or line_no in skipped:
            continue
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        wide, tails = set(), {}
        refs = _line_refs(line, base_dir, var_dirs, eval_norm, wide, tails)
        if own_plugin and PLUGINS_FIELD_RE.match(line):
            entries = [
                os.path.normpath(os.path.join(base_dir, entry))
                for entry in re.findall(r"""["']([^"']+)["']""", line)
            ]
            if all(e == os.path.dirname(eval_norm) or not _holds_suite(e, eval_norm) for e in entries):
                wide = set()
            refs.update(e for e in entries if _in_eval_suite(e, eval_norm))
        if not refs and not wide:
            continue
        narrow = {ref: found for ref, found in tails.items() if None not in found}
        runs, rest, rest_refs = None, line, refs
        shape = SCRIPT_RUN_RE.match(stripped) if is_shell else None
        if shape:
            path_refs = _line_refs(shape.group("path"), base_dir, var_dirs, eval_norm)
            if len(path_refs) == 1 and _plain_cd_run(shape, base_dir, var_dirs, eval_norm):
                runs = next(iter(path_refs))
                rest = shape.group("rest")
                rest_refs = _line_refs(rest, base_dir, var_dirs, eval_norm)
        if visibility and is_shell and runs is None:
            top = _top_level_text(stripped)
            if CD_WORD_RE.search(stripped if top is None else top):
                wide = wide or refs
        sites.append((line, refs, runs, rest, rest_refs, bool(wide), narrow))

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
                            runs = resolved if field == "scaffold_script" else None
                            sites.append((None, {resolved}, runs, "", set(), False, {}))
                        elif _holds_suite(resolved, eval_norm):
                            sites.append((None, set(), None, "", set(), True, {}))
    return sites


def _extract_suite_refs(fpath, text, eval_norm):
    return {ref for site in _suite_ref_sites(fpath, text, eval_norm) for ref in site[1]}


def _case_suite_files(case, eval_norm, visibility=False):
    """{path: (text, sites)} for every file of `case` and every suite file they reach, with
    `visibility` passed to `_suite_ref_sites`."""
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

    files = {}
    while queue:
        fpath = queue.popleft()
        if fpath in files:
            continue
        text = _read_text_safe(fpath)
        sites = _suite_ref_sites(fpath, text, eval_norm, visibility) if text else []
        files[fpath] = (text, sites)
        for site in sites:
            for ref_path in site[1]:
                if os.path.isfile(ref_path) and ref_path not in files:
                    queue.append(ref_path)
    return files


def _case_suite_references(case, eval_norm):
    return {
        ref
        for _, sites in _case_suite_files(case, eval_norm).values()
        for site in sites
        for ref in site[1]
    }


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
