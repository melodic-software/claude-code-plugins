"""Text-only classifiers for changes that run no eval case: decided-term swaps, routing
clauses in a description, and whole-comment-line deletions. Shared by `select_mapping.py`.
Python 3.8+, standard library only.
"""

import difflib
import os
import re

NO_RUN_SECTIONS = frozenset(["next", "related", "see also"])
ROUTING_HEADINGS = frozenset(
    [
        "boundaries",
        "scope boundary",
        "siblings",
        "routing",
        "handoff",
        "composition",
        "integration",
        "workflow position",
        "what this skill does not do",
    ]
)
HEADING_RENAME_TARGETS = ROUTING_HEADINGS | frozenset(["next", "related"])
HEADING_RE = re.compile(r"^(#{1,6})[ \t]+(.+?)[ \t]*$")

HUNK_HEADER_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
SKILL_TOKEN = r"(?<![\w/:.-])/?[a-z][a-z0-9-]*:[a-z][a-z0-9-]*(?![\w-])"
SKILL_TOKEN_RE = re.compile(SKILL_TOKEN)
ROUTING_SEGMENT_RE = re.compile(
    r"(?:^|,\s*)(?:(?:and|or|but)\s+)?(?:not for|skip|prefer)\b[^,]*?"
    + SKILL_TOKEN
    + r"[\s.;:)]*(?=,|$)",
    re.IGNORECASE,
)
DIRECTIVE_RE = re.compile(
    r"^(?:///\s*<|//\s*(?:go:|\+build|@ts-|eslint|prettier|istanbul|c8|biome|#region|#endregion)"
    r"|/\*\s*(?:eslint|istanbul|c8|@ts-)"
    r"|#\s*(?:shellcheck|type:|noqa|pylint|pyright|mypy|ruff|fmt:|-\*-|nosec|nosemgrep"
    r"|gitleaks|yamllint|requires|region|endregion|pragma|(?:vim?:.*)?coding[:=]))",
    re.IGNORECASE,
)
HEREDOC_RE = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")
BLOCK_SCALAR_RE = re.compile(
    r"^(\s*)(?:-[ \t]+|\S[^#]*:[ \t]*)(?:[!&]\S*[ \t]+)*[|>][-+0-9]*[ \t]*(?:#.*)?$"
)
HERE_STRING_RE = re.compile(r"@([\"'])\s*$")
STRING_QUOTES = {".py": ('"""', "'''"), ".toml": ('"""', "'''"), ".cs": ('"""',), ".go": ("`",)}
STRING_QUOTES.update(dict.fromkeys([".js", ".mjs", ".cjs", ".ts", ".mts", ".cts"], ("`",)))
CLAUSE_SPLIT_RE = re.compile(r"(?<=[.;])\s+")
SWAP_TOKEN_RE = re.compile(r"[A-Za-z]+|[0-9]+|\s+|\\.|[^\sA-Za-z0-9]")
HASH_COMMENT_EXTS = frozenset(
    [".yaml", ".yml", ".sh", ".bash", ".zsh", ".py", ".toml", ".ps1", ".psm1"]
)
SLASH_COMMENT_EXTS = frozenset(
    [".js", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".jsonc", ".go", ".cs"]
)
MEANING_FLIP_WORDS = frozenset(
    ["not", "never", "no", "don't", "only", "except", "unless", "cannot", "can't", "won't"]
)
SWAP_CONTEXT = 6
MAX_DECIDED_TERM_WORDS = 3


def flips_meaning(word):
    token = word.replace("\u2019", "'").strip(".,;:!?()\"'`*_").lower()
    return token in MEANING_FLIP_WORDS or token.endswith("n't")


def _term_words(text):
    """A term's tokens, lowercased, each whitespace run between words one space."""
    return tuple(
        " " if token.isspace() else token.lower()
        for token in SWAP_TOKEN_RE.findall(re.sub(r"[`*\"']", "", text).strip())
    )


def _parse_rejected_terms(text):
    """(rejected words, decided words) pairs from the table under a `Rejected` heading. The
    decided term is the cell's bold term, else its text before the first comma, semicolon or
    parenthesis; a longer phrase there is a doctrine, not a word to swap in."""
    pairs = []
    in_section = False
    past_header = False
    for line in text.splitlines():
        if line.startswith("#"):
            in_section = "rejected" in line.lower()
            past_header = False
            continue
        if not in_section or not line.lstrip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if not past_header:
            past_header = bool(cells) and set(cells[0]) <= set("-: ") and "-" in cells[0]
            continue
        if len(cells) < 2:
            continue
        bold = re.match(r"\*\*([^*]+)\*\*", cells[1])
        decided = _term_words(bold.group(1) if bold else re.split(r"[,;(]", cells[1])[0])
        if not decided or sum(not t.isspace() for t in decided) > MAX_DECIDED_TERM_WORDS:
            continue
        for rejected in re.sub(r"\*\([^)]*\)\*", "", cells[0]).split("/"):
            words = _term_words(rejected)
            if words and words != decided:
                pairs.append((words, decided))
    return tuple(pairs)


def _is_skill_token(token, plugins):
    """A `plugin:skill` token names a skill: it carries the leading slash, or its plugin part is a
    plugin in the repository (`mode:fast` is a value, not a skill)."""
    return token.startswith("/") or token.split(":", 1)[0] in plugins


def _routing_free_tokens(text, plugins=frozenset()):
    """Description tokens with each routing segment (`Not for ...`, `Skip ...` or `prefer ...` at a
    clause start or after a comma, ending with a skill token before the next comma) cut, the
    clause-ending `.` or `;` dropped, and each skill token's leading slash dropped, so only a
    change of form (`plugin:skill` to `/plugin:skill`) compares equal."""

    def cut(match):
        routed = re.findall(SKILL_TOKEN, match.group(0), re.IGNORECASE)[-1]
        return "" if _is_skill_token(routed, plugins) else match.group(0)

    def form(match):
        token = match.group(0)
        return token.lstrip("/") if _is_skill_token(token, plugins) else token

    kept = []
    for clause in CLAUSE_SPLIT_RE.split(text.strip()):
        clause = ROUTING_SEGMENT_RE.sub(cut, clause.rstrip(".;")).strip()
        if clause:
            kept.append(clause)
    return SWAP_TOKEN_RE.findall(SKILL_TOKEN_RE.sub(form, " ".join(kept)))


def _plural(words):
    return words[:-1] + (words[-1] + "s",)


def _swap_forms(rejected, decided):
    """(old, new) token forms one swap may take: the decided term, or its last word alone (as a
    `--lane` flag becomes `--area` for `focus area`), either side singular or plural, and the
    rejected term dropped after the decided one (`concern lane` to `concern`)."""
    news = [decided] + ([decided[-1:]] if len(decided) > 1 else [])
    for old in (rejected, _plural(rejected)):
        for new in news:
            yield old, new
            yield old, _plural(new)
        yield decided + (" ",) + old, decided
        yield decided + (" ",) + old, _plural(decided)


def _is_swap_run(old_tokens, new_tokens, pairs):
    """The old tokens become the new ones by swaps alone, every other token identical; a term
    matches case-insensitively, whitespace and punctuation byte for byte."""
    if not old_tokens or not new_tokens:
        return not old_tokens and not new_tokens
    if old_tokens[0] == new_tokens[0] and _is_swap_run(old_tokens[1:], new_tokens[1:], pairs):
        return True
    for rejected, decided in pairs:
        for old_form, new_form in _swap_forms(rejected, decided):
            if (
                tuple(t.lower() for t in old_tokens[: len(old_form)]) == old_form
                and tuple(t.lower() for t in new_tokens[: len(new_form)]) == new_form
                and _is_swap_run(old_tokens[len(old_form) :], new_tokens[len(new_form) :], pairs)
            ):
                return True
    return False


def _differs_only_by_swaps(old_tokens, new_tokens, pairs):
    """Each change the diff finds, widened by up to SWAP_CONTEXT identical tokens on each side
    so a swap the diff split (`concern lane` to `concern`) is seen whole, is a run of swaps."""
    matcher = difflib.SequenceMatcher(None, old_tokens, new_tokens, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        if not any(
            _is_swap_run(
                tuple(old_tokens[max(0, i1 - before) : i2 + after]),
                tuple(new_tokens[max(0, j1 - before) : j2 + after]),
                pairs,
            )
            for before in range(min(i1, j1, SWAP_CONTEXT) + 1)
            for after in range(SWAP_CONTEXT + 1)
        ):
            return False
    return True


def is_term_swap_only(old, new, pairs):
    """True when the texts differ and are byte-identical once each decided-term swap is
    replaced."""
    return bool(pairs) and old != new and _differs_only_by_swaps(
        SWAP_TOKEN_RE.findall(old), SWAP_TOKEN_RE.findall(new), pairs
    )


def is_routing_only_change(old, new, pairs, plugins=frozenset()):
    """True when, with routing clauses, skill-token form and decided-term swaps removed, the two
    texts are equal; `plugins` names the repository's plugins."""
    return _differs_only_by_swaps(
        _routing_free_tokens(old, plugins), _routing_free_tokens(new, plugins), pairs
    )


def _string_block_lines(ext, text):
    """1-based numbers of the lines `text` holds inside a shell heredoc, a PowerShell here-string,
    a YAML block scalar or a multi-line string, where a comment-shaped line is content."""
    inside = set()
    closer = None
    quotes = STRING_QUOTES.get(ext, ())
    for number, line in enumerate(text.splitlines(), 1):
        if isinstance(closer, int):
            if not line.strip() or len(line) - len(line.lstrip()) > closer:
                inside.add(number)
                continue
            closer = None
        elif closer is not None:
            inside.add(number)
            if closer.endswith("@"):
                done = line.startswith(closer)
            elif closer[0].isalpha() or closer[0] == "_":
                done = line.strip() == closer
            else:
                done = line.count(closer) % 2
            closer = None if done else closer
            continue
        heredoc = HEREDOC_RE.search(line) if ext in (".sh", ".bash", ".zsh") else None
        scalar = BLOCK_SCALAR_RE.match(line) if ext in (".yaml", ".yml") else None
        here = HERE_STRING_RE.search(line) if ext in (".ps1", ".psm1") else None
        if heredoc:
            closer = heredoc.group(2)
        elif here:
            closer = here.group(1) + "@"
        elif scalar:
            closer = len(scalar.group(1))
        else:
            closer = next((q for q in quotes if line.count(q) % 2), None)
    return frozenset(inside)


def comment_style(path, text=""):
    """(`hash` or `slash`, the lines of `text` inside a heredoc, block scalar or multi-line
    string) for a code, YAML or shell file; None for markdown and any other type, whose comments
    a model may read as instructions, and for a cgo file, whose preamble comment is C code."""
    ext = os.path.splitext(path)[1].lower()
    kind = "hash" if ext in HASH_COMMENT_EXTS else "slash" if ext in SLASH_COMMENT_EXTS else None
    if ext == ".go" and 'import "C"' in text:
        return None
    return (kind, _string_block_lines(ext, text)) if kind else None


def _comment_line_mask(lines, style):
    """Per line, whether a comment (or nothing) fills it. A `/*` line that does not close opens a
    block whose lines count only when a later line in `lines` ends it with `*/`; code after a
    comment never counts."""
    mask = []
    in_block = False
    opened = 0
    for line in lines:
        stripped = line.strip()
        if style == "hash":
            mask.append(
                not stripped
                or stripped.startswith("#")
                and not stripped.startswith(("#!", "#>"))
                and not stripped.endswith("#>")
            )
        elif in_block:
            closes = "*/" in stripped
            mask.append(not closes or stripped.endswith("*/") and stripped.count("*/") == 1)
            in_block = not closes
        elif not stripped or stripped.startswith("//"):
            mask.append(True)
        elif stripped.startswith("/*"):
            rest = stripped[2:]
            if "*/" not in rest:
                opened = len(mask)
                mask.append(True)
                in_block = True
            else:
                mask.append(rest.endswith("*/") and rest.count("*/") == 1)
        else:
            mask.append(False)
    if in_block:
        mask[opened:] = [False] * (len(mask) - opened)
    return [m and not DIRECTIVE_RE.match(line.strip()) for m, line in zip(mask, lines)]


def _hunk_is_no_run(old_lines, new_lines, pairs, style, old_start=1):
    """The hunk only deletes whole comment lines, none inside a string block, and swaps decided
    terms in the rest."""
    if style is not None:
        kind, inside = style
        mask = _comment_line_mask(old_lines, kind)
        kept = [
            line
            for number, (line, comment) in enumerate(zip(old_lines, mask), old_start)
            if not comment or number in inside
        ]
        if len(kept) < len(old_lines) and kept == new_lines:
            return True
        old_lines = kept
    return is_term_swap_only("\n".join(old_lines), "\n".join(new_lines), pairs)


def _raw_hunks(diff_text):
    hunks = []
    for line in diff_text.splitlines():
        if line.startswith("Binary files "):
            return None
        header = HUNK_HEADER_RE.match(line)
        if header:
            hunks.append((int(header.group(1)), [], []))
        elif hunks and line.startswith("-") and not line.startswith("---"):
            hunks[-1][1].append(line[1:])
        elif hunks and line.startswith("+") and not line.startswith("+++"):
            hunks[-1][2].append(line[1:])
    return hunks


def _heading_name(line):
    match = HEADING_RE.match(line)
    if not match:
        return None, None
    return match.group(1), match.group(2).rstrip(":").strip().lower()


def _is_routing_heading_rename(old_lines, new_lines):
    """Every old line is a routing heading renamed, at the same level, to another routing
    heading or to Next or Related."""
    if not old_lines or len(old_lines) != len(new_lines):
        return False
    for old, new in zip(old_lines, new_lines):
        old_level, old_name = _heading_name(old)
        new_level, new_name = _heading_name(new)
        if (
            old_level is None
            or old_level != new_level
            or old_name not in ROUTING_HEADINGS
            or new_name not in HEADING_RENAME_TARGETS
        ):
            return False
    return True


def _no_run_section_lines(text):
    """1-based line ranges of each `## Next`, `## Related` and `## See also` body, heading
    excluded. They name other skills for the person and change no tool call, so editing them
    runs nothing."""
    lines = text.splitlines()
    ranges = []
    for index, line in enumerate(lines):
        level, name = _heading_name(line)
        if level == "##" and name in NO_RUN_SECTIONS:
            end = next(
                (j for j in range(index + 1, len(lines)) if lines[j].startswith("## ")),
                len(lines),
            )
            ranges.append((index + 2, end))
    return tuple(ranges)
