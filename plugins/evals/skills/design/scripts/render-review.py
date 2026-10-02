#!/usr/bin/env python3
"""render-review - render candidate eval cases into one file a person reads and approves.

    render-review.py <cases.json> --format <name> --out <path>

<cases.json> holds a JSON array of case objects. Every format renders a table of
each case's fields, then one section per case holding its input (`prompt`, else
`input`). Case text is untrusted: the markdown format fences the input and
escapes table cells; the html format escapes every key and value.

A format is one function in FORMATS; adding one is a function plus a table entry.

Exit codes: 0 written; 2 usage error, unknown format, or unreadable input.
"""

import argparse
import html
import json
import re
import sys
from pathlib import Path

INPUT_KEYS = ("prompt", "input")
LEADING = (
    "id",
    "name",
    "difficulty",
    "why_hard",
    "source",
    "expected_output",
    "expectations",
    "golden_answer",
    "grading",
    "rubric",
)


def input_key(case):
    return next((key for key in INPUT_KEYS if key in case), None)


def columns(cases):
    """Every key any case carries except its input, known keys first."""
    keys = {key for case in cases for key in case if key != input_key(case)}
    return [key for key in LEADING if key in keys] + sorted(keys - set(LEADING))


def as_text(value):
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "; ".join(as_text(item) for item in value)
    return json.dumps(value, ensure_ascii=False)


def md_cell(value):
    """One table cell: a single line, HTML-inert, with no live link or image."""
    flat = re.sub(r"([\\\[\]|])", r"\\\1", " ".join(as_text(value).split()))
    return html.escape(flat, quote=False)


def longest_backtick_run(text):
    return max((len(run) for run in re.findall(r"`+", text)), default=0)


def render_markdown(cases):
    cols = columns(cases)
    lines = ["# Candidate cases", ""]
    lines.append("| " + " | ".join(md_cell(col) for col in cols) + " |")
    lines.append("|" + "---|" * len(cols))
    for case in cases:
        lines.append("| " + " | ".join(md_cell(case.get(col)) for col in cols) + " |")
    for case in cases:
        body = as_text(case.get(input_key(case)))
        fence = "`" * max(3, longest_backtick_run(body) + 1)
        lines += [
            "",
            f"## Case {md_cell(case.get('id'))}",
            "",
            fence + "text",
            body,
            fence,
        ]
    return "\n".join(lines) + "\n"


def esc(value):
    return html.escape(as_text(value), quote=True)


def render_html(cases):
    cols = columns(cases)
    parts = [
        "<!DOCTYPE html>",
        '<html lang="en"><head><meta charset="utf-8">',
        "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'\">",
        "<title>Candidate cases</title>",
        "<style>table{border-collapse:collapse}td,th{border:1px solid #888;padding:4px;"
        "vertical-align:top}pre{white-space:pre-wrap;border:1px solid #888;padding:8px}</style>",
        "</head><body><h1>Candidate cases</h1>",
        "<table><tr>" + "".join(f"<th>{esc(col)}</th>" for col in cols) + "</tr>",
    ]
    for case in cases:
        parts.append(
            "<tr>" + "".join(f"<td>{esc(case.get(col))}</td>" for col in cols) + "</tr>"
        )
    parts.append("</table>")
    for case in cases:
        parts.append(f"<h2>Case {esc(case.get('id'))}</h2>")
        parts.append(f"<pre>{esc(case.get(input_key(case)))}</pre>")
    parts.append("</body></html>")
    return "\n".join(parts) + "\n"


FORMATS = {"markdown": render_markdown, "html": render_html}


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Render candidate eval cases for review."
    )
    parser.add_argument("cases", help="path to a JSON array of case objects")
    parser.add_argument("--format", required=True, choices=sorted(FORMATS))
    parser.add_argument("--out", required=True, help="path of the file to write")
    args = parser.parse_args(argv)
    try:
        cases = json.loads(Path(args.cases).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        parser.error(f"cannot read {args.cases}: {error}")
    if not isinstance(cases, list) or not all(isinstance(case, dict) for case in cases):
        parser.error(f"{args.cases} must hold a JSON array of case objects")
    Path(args.out).write_text(FORMATS[args.format](cases), encoding="utf-8")
    print(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
