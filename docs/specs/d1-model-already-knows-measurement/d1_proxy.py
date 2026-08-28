#!/usr/bin/env python3
"""D1 proxy scanner — #3121 investigation.

Implements the proposed mechanical proxy from #3118/#3124 verbatim:

    "an instruction carrying no proper noun, path, threshold, version, or
     repo-specific fact is likely a no-op."

Stage 1  segment   : strip frontmatter / fenced code / HTML comments / headings /
                     tables / rules / pure-link lines; keep prose + list items.
Stage 2  split     : prose block -> sentences.
Stage 3  instruction: is the sentence a directive at all? (imperative or modal)
Stage 4  proxy     : flag when the sentence carries NONE of the five signals.
Stage 5  emit      : JSONL of every instruction sentence with its signals.

Deterministic. No model in the loop. Seeded sampling done downstream.
"""

import json
import re
import sys

# ---------------------------------------------------------------- stage 1

FRONTMATTER = re.compile(r"\A---\n.*?\n---\n", re.S)
HTML_COMMENT = re.compile(r"<!--.*?-->", re.S)


def segment(text):
    """Return prose blocks (str) from a markdown document."""
    text = FRONTMATTER.sub("", text)
    text = HTML_COMMENT.sub("", text)

    out, buf, in_fence, fence = [], [], False, None
    for line in text.split("\n"):
        stripped = line.strip()

        # fenced code blocks (``` or ~~~), tolerant of info strings
        m = re.match(r"^(`{3,}|~{3,})", stripped)
        if m:
            if not in_fence:
                in_fence, fence = True, m.group(1)[0]
            elif stripped[0] == fence:
                in_fence, fence = False, None
            continue
        if in_fence:
            continue

        # indented code block (4 spaces / tab) outside a list context
        if re.match(r"^(?: {4,}|\t)\S", line) and not re.match(
            r"^(?: {4,}|\t)[-*+]\s", line
        ):
            continue

        if not stripped:  # blank -> flush block
            if buf:
                out.append(" ".join(buf))
                buf = []
            continue
        if stripped.startswith("#"):  # heading
            if buf:
                out.append(" ".join(buf))
                buf = []
            continue
        if stripped.startswith("|"):  # table row
            continue
        if re.match(r"^([-*_])\1{2,}$", stripped):  # horizontal rule
            continue
        # pure link / image / badge line
        if re.match(r"^!?\[[^\]]*\]\([^)]*\)[.,]?$", stripped):
            continue
        if re.match(r"^<https?://\S+>$", stripped):
            continue

        # list item / blockquote start their own block
        if re.match(r"^([-*+]|\d+\.)\s+", stripped) or stripped.startswith(">"):
            if buf:
                out.append(" ".join(buf))
                buf = []
            stripped = re.sub(r"^([-*+]|\d+\.)\s+", "", stripped)
            stripped = re.sub(r"^>\s*", "", stripped)
            # checkbox marker is not prose
            stripped = re.sub(r"^\[[ xX]\]\s*", "", stripped)
            if stripped:
                buf.append(stripped)
            continue

        buf.append(stripped)

    if buf:
        out.append(" ".join(buf))
    return out


# ---------------------------------------------------------------- stage 2

# protect the common abbreviations that would otherwise split a sentence
ABBREV = [
    "e.g.",
    "i.e.",
    "etc.",
    "vs.",
    "cf.",
    "Dr.",
    "Mr.",
    "Ms.",
    "approx.",
    "Fig.",
    "No.",
    "al.",
    "St.",
    "Inc.",
    "min.",
    "max.",
]


def sentences(block):
    tmp = block
    for i, a in enumerate(ABBREV):
        tmp = tmp.replace(a, f"\x00{i}\x00")
    # don't split inside backticks
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z`\"'(\[*_])", tmp)
    out = []
    for p in parts:
        for i, a in enumerate(ABBREV):
            p = p.replace(f"\x00{i}\x00", a)
        p = p.strip()
        if p:
            out.append(p)
    return out


# ---------------------------------------------------------------- stage 3

MODALS = re.compile(
    r"\b(must|never|always|should|shall|do not|don't|avoid|prefer|ensure|"
    r"required|require|requires|may not|cannot|can't|need to|needs to|"
    r"make sure|be sure)\b",
    re.I,
)

# base-form verbs that open an imperative in this corpus
IMPERATIVE_OPENERS = {
    "use",
    "read",
    "run",
    "write",
    "add",
    "remove",
    "delete",
    "keep",
    "make",
    "check",
    "verify",
    "report",
    "surface",
    "emit",
    "apply",
    "treat",
    "pass",
    "call",
    "invoke",
    "resolve",
    "derive",
    "record",
    "cite",
    "stop",
    "skip",
    "prefer",
    "avoid",
    "ensure",
    "never",
    "always",
    "do",
    "don't",
    "leave",
    "route",
    "chain",
    "flag",
    "drop",
    "fix",
    "close",
    "open",
    "create",
    "update",
    "set",
    "give",
    "take",
    "put",
    "name",
    "state",
    "say",
    "tell",
    "ask",
    "answer",
    "reply",
    "start",
    "begin",
    "end",
    "continue",
    "return",
    "choose",
    "pick",
    "select",
    "consider",
    "note",
    "see",
    "follow",
    "hold",
    "count",
    "list",
    "scan",
    "search",
    "find",
    "look",
    "load",
    "bind",
    "attach",
    "carry",
    "quote",
    "escalate",
    "park",
    "reuse",
    "replace",
    "confirm",
    "measure",
    "test",
    "prove",
    "document",
    "describe",
    "explain",
    "define",
    "declare",
    "assume",
    "expect",
    "let",
    "allow",
    "block",
    "enforce",
    "validate",
    "capture",
    "collect",
    "merge",
    "commit",
    "push",
    "branch",
    "dispatch",
    "spawn",
    "wait",
    "retry",
    "handle",
    "catch",
    "ignore",
    "strip",
    "trim",
    "cut",
    "split",
    "join",
    "sort",
    "filter",
    "map",
    "reduce",
    "wrap",
    "unwrap",
    "mark",
    "tag",
    "label",
    "assign",
}


def is_instruction(s):
    plain = re.sub(r"`[^`]*`", " ", s)  # ignore code spans for opener test
    plain = re.sub(r"\*\*|__|\*|_", "", plain).strip()
    if not plain:
        return False
    first = re.split(r"[\s,;:]", plain, maxsplit=1)[0].lower().strip(".*_-—:")
    return first in IMPERATIVE_OPENERS or bool(MODALS.search(s))


# ---------------------------------------------------------------- stage 4

CODE_SPAN = re.compile(r"`[^`]+`")
PATHISH = re.compile(
    r"(/|\\)[\w.\-]+|[\w\-]+\.(md|sh|json|py|ts|js|yaml|yml|toml|txt|xml|cs)\b"
)
VERSION = re.compile(r"\bv?\d+\.\d+(\.\d+)?\b")
DIGIT = re.compile(r"\d")
ENVVAR = re.compile(r"\$\{?[A-Z_][A-Z0-9_]*\}?")

# words that are capitalised for emphasis / sentence-start, not proper nouns
NOT_PROPER = {
    "A",
    "An",
    "The",
    "This",
    "That",
    "These",
    "Those",
    "It",
    "If",
    "When",
    "Where",
    "While",
    "Do",
    "Don",
    "Never",
    "Always",
    "Use",
    "Read",
    "Run",
    "Write",
    "Add",
    "Keep",
    "Make",
    "Check",
    "Prefer",
    "Avoid",
    "Treat",
    "Every",
    "Each",
    "No",
    "Not",
    "Only",
    "Both",
    "Either",
    "Neither",
    "Because",
    "Before",
    "After",
    "Once",
    "Then",
    "So",
    "But",
    "And",
    "Or",
    "For",
    "To",
    "In",
    "On",
    "At",
    "By",
    "As",
    "Is",
    "Are",
    "Was",
    "Were",
    "Be",
    "Been",
    "Being",
    "Has",
    "Have",
    "Had",
    "Can",
    "Could",
    "Should",
    "Would",
    "Will",
    "Shall",
    "May",
    "Might",
    "Must",
    "Its",
    "Their",
    "Your",
    "You",
    "We",
    "They",
    "He",
    "She",
    "I",
    "One",
    "Two",
    "Three",
    "What",
    "Which",
    "Who",
    "Whom",
    "Whose",
    "How",
    "Why",
    "There",
    "Here",
    "Now",
    "Yes",
    "Stop",
    "Skip",
    "Report",
    "Surface",
    "Emit",
    "Apply",
    "Pass",
    "Call",
    "Leave",
    "Drop",
    "Fix",
    "Close",
    "Open",
    "Create",
    "Update",
    "Set",
    "State",
    "Say",
    "Ask",
    "Reply",
    "Start",
    "Return",
    "Choose",
    "Pick",
    "Note",
    "See",
    "Follow",
    "Count",
    "List",
    "Find",
    "Load",
    "Quote",
    "Confirm",
    "Measure",
    "Test",
    "Prove",
    "Define",
    "Assume",
    "Allow",
    "Enforce",
    "Capture",
    "Merge",
    "Commit",
    "Push",
    "Wait",
    "Retry",
    "Ignore",
    "Cut",
    "Split",
    "Sort",
    "Wrap",
    "Mark",
    "Tag",
    "Assign",
    "Resolve",
    "Derive",
    "Record",
    "Cite",
    "Route",
    "Chain",
    "Flag",
    "Verify",
    "Invoke",
    "Give",
    "Take",
    "Put",
    "Name",
    "Tell",
    "Answer",
    "Begin",
    "End",
    "Continue",
    "Consider",
    "Look",
    "Bind",
    "Attach",
    "Carry",
    "Escalate",
    "Park",
    "Reuse",
    "Replace",
    "Document",
    "Describe",
    "Explain",
    "Declare",
    "Expect",
    "Let",
    "Block",
    "Validate",
    "Collect",
    "Dispatch",
    "Spawn",
    "Handle",
    "Catch",
    "Strip",
    "Trim",
    "Join",
    "Filter",
    "Remove",
    "Delete",
    "Search",
    "Scan",
    "Hold",
    "Label",
}


def signals(s):
    """Return the five D1 signals present in the sentence."""
    found = {}
    found["code_span"] = bool(CODE_SPAN.search(s))
    bare = CODE_SPAN.sub(" ", s)  # signals outside code spans too
    found["path"] = bool(PATHISH.search(s))
    found["version"] = bool(VERSION.search(s))
    found["threshold"] = bool(DIGIT.search(s))
    found["envvar"] = bool(ENVVAR.search(s))

    props = []
    # strip the leading token before hunting proper nouns
    body = re.sub(r"^\W*\w+\b", "", bare)
    for m in re.finditer(r"\b[A-Z][a-zA-Z]*\b", body):
        w = m.group(0)
        if w in NOT_PROPER:
            continue
        if w.isupper() and len(w) > 1:  # ALL-CAPS = emphasis, not a name
            continue
        props.append(w)
    found["proper_noun"] = bool(props)
    found["proper_nouns"] = sorted(set(props))
    return found


def flagged(sig):
    """D1 proxy: flag when NONE of the five signal families is present."""
    return not (
        sig["code_span"]
        or sig["path"]
        or sig["version"]
        or sig["threshold"]
        or sig["envvar"]
        or sig["proper_noun"]
    )


# ---------------------------------------------------------------- driver


def stratum_of(path):
    if path in ("CLAUDE.md", "AGENTS.md") or "output-styles" in path:
        return "S5-root-instruction"
    if "/agents/" in path:
        return "S4-agent-definition"
    if path.endswith("SKILL.md"):
        return "S1-skill-body"
    if "/skills/" in path:
        return "S2-skill-subdoc"
    return "S3-plugin-reference"


def main(paths, out_path):
    rows = []
    for p in paths:
        try:
            with open(p, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        for block in segment(text):
            for s in sentences(block):
                if len(s) < 12:
                    continue
                if not is_instruction(s):
                    continue
                sig = signals(s)
                rows.append(
                    {
                        "file": p,
                        "stratum": stratum_of(p),
                        "sentence": s,
                        "flagged": flagged(sig),
                        "signals": {
                            k: v for k, v in sig.items() if k != "proper_nouns"
                        },
                        "proper_nouns": sig["proper_nouns"],
                    }
                )

    with open(out_path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")

    total = len(rows)
    flag = sum(1 for r in rows if r["flagged"])
    print(f"instruction sentences : {total}")
    print(f"flagged by D1 proxy   : {flag}  ({100.0 * flag / max(total, 1):.1f}%)")
    print()
    strata = {}
    for r in rows:
        d = strata.setdefault(r["stratum"], [0, 0])
        d[0] += 1
        d[1] += 1 if r["flagged"] else 0
    for k in sorted(strata):
        t, f = strata[k]
        print(f"  {k:24s} {f:6d} / {t:6d}  ({100.0 * f / max(t, 1):.1f}%)")


if __name__ == "__main__":
    file_list = sys.argv[1]
    out = sys.argv[2]
    with open(file_list, encoding="utf-8") as fh:
        ps = [ln.strip() for ln in fh if ln.strip()]
    main(ps, out)
