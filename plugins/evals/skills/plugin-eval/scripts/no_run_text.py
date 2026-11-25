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
SKILL_TOKEN_RE = re.compile(r"(?<![\w/:.-])/?[a-z0-9][a-z0-9-]*:[a-z0-9][a-z0-9-]*(?![\w-])")
ROUTING_CLAUSE_RE = re.compile(r"^(?:not for|skip)\b|\bprefer\b", re.IGNORECASE)
CLAUSE_SPLIT_RE = re.compile(r"(?<=[.;])\s+")
SWAP_TOKEN_RE = re.compile(r"[A-Za-z]+|[0-9]+|\s+|\\.|[^\sA-Za-z0-9]")
HASH_COMMENT_EXTS = frozenset(
    [".yaml", ".yml", ".sh", ".bash", ".zsh", ".py", ".toml", ".rb", ".pl", ".ps1", ".psm1"]
)
SLASH_COMMENT_EXTS = frozenset(
    [".js", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".jsonc", ".go", ".cs"]
)
SWAP_CONTEXT = 6
MAX_DECIDED_TERM_WORDS = 3


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


def _routing_free_tokens(text):
    """Description tokens with each routing clause (`Not for ...`, `Skip ...` or `prefer ...`
    naming a `plugin:skill`) dropped, the clause-ending `.` or `;` with it, and every skill token,
    slash or not, made one placeholder."""
    kept = [
        clause.rstrip(".;")
        for clause in CLAUSE_SPLIT_RE.split(text.strip())
        if not (SKILL_TOKEN_RE.search(clause) and ROUTING_CLAUSE_RE.search(clause))
    ]
    return SWAP_TOKEN_RE.findall(SKILL_TOKEN_RE.sub(" SKILLTOKEN ", " ".join(kept)))


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


def is_routing_only_change(old, new, pairs):
    """True when, with routing clauses and decided-term swaps removed, the two texts are equal."""
    return _differs_only_by_swaps(_routing_free_tokens(old), _routing_free_tokens(new), pairs)


def comment_style(path):
    """`hash` or `slash` for a code, YAML or shell file; None for markdown and any other type,
    whose comments a model may read as instructions."""
    ext = os.path.splitext(path)[1].lower()
    if ext in HASH_COMMENT_EXTS:
        return "hash"
    if ext in SLASH_COMMENT_EXTS:
        return "slash"
    return None


def _comment_line_mask(lines, style):
    """Per line, whether a comment (or nothing) fills it. A `/*` line that does not close opens a
    block whose lines count until one ends with `*/`; code after a comment never counts."""
    mask = []
    in_block = False
    for line in lines:
        stripped = line.strip()
        if style == "hash":
            mask.append(not stripped or (stripped.startswith("#") and not stripped.startswith("#!")))
        elif in_block:
            closes = "*/" in stripped
            mask.append(not closes or stripped.endswith("*/") and stripped.count("*/") == 1)
            in_block = not closes
        elif not stripped or stripped.startswith("//"):
            mask.append(True)
        elif stripped.startswith("/*"):
            rest = stripped[2:]
            if "*/" not in rest:
                mask.append(True)
                in_block = True
            else:
                mask.append(rest.endswith("*/") and rest.count("*/") == 1)
        else:
            mask.append(False)
    return mask


def _hunk_is_no_run(old_lines, new_lines, pairs, style):
    """The hunk only deletes whole comment lines and swaps decided terms in the rest."""
    if style is not None:
        mask = _comment_line_mask(old_lines, style)
        kept = [line for line, comment in zip(old_lines, mask) if not comment]
        if len(kept) < len(old_lines) and kept == new_lines:
            return True
        old_lines = kept
    return is_term_swap_only("\n".join(old_lines), "\n".join(new_lines), pairs)


def _raw_hunks(diff_text):
    hunks = []
    for line in diff_text.splitlines():
        if line.startswith("Binary files "):
            return None
        if HUNK_HEADER_RE.match(line):
            hunks.append(([], []))
        elif hunks and line.startswith("-") and not line.startswith("---"):
            hunks[-1][0].append(line[1:])
        elif hunks and line.startswith("+") and not line.startswith("+++"):
            hunks[-1][1].append(line[1:])
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
