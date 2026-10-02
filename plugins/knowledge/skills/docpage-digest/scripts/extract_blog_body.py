#!/usr/bin/env python3
"""Extract the article body of a claude.dev blog page as markdown.

Usage: python3 extract_blog_body.py <source.html> [<out.md>]

The body runs from the element carrying id="body" to the first
<div class="more-sec">, or to the end of the file when there is none. Without
<out.md> the markdown goes to stdout. Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import sys
from html.parser import HTMLParser

VOID = {"area", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
HEADINGS = {"h1", "h2", "h3", "h4", "h5", "h6"}
FLUSH_ON_START = HEADINGS | {"p", "figcaption", "blockquote"}


def classes(attrs: dict) -> list:
    return (attrs.get("class") or "").split()


class BodyExtractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []
        self.buf = []
        self.pre = None
        self.fence_lang = ""
        self.lists = []
        self.table = None
        self.cells = None
        self.href = None
        self.skip = 0
        self.lang_capture = False

    def flush(self, prefix=""):
        if self.cells is not None:
            # A block boundary inside a table row stays in the cell's text.
            self.buf.append(" ")
            return
        text = " ".join("".join(self.buf).split())
        if text:
            self.blocks.append(prefix + text)
        self.buf = []

    def flush_item(self):
        if not self.lists:
            self.flush()
            return
        entry = self.lists[-1]
        before = len(self.blocks)
        self.flush(entry[2])
        if len(self.blocks) > before:
            entry[2] = " " * len(entry[2])

    def start_skip(self, a):
        # Widget chrome: copy buttons, video controls, and the code header,
        # whose language label becomes the next fence's info string.
        self.skip = 1
        self.buf.append(" ")
        if "ch" in classes(a):
            self.fence_lang = ""

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if self.skip:
            if tag not in VOID:
                self.skip += 1
            if tag == "span" and "lang" in classes(a):
                self.lang_capture = True
            return
        if tag == "button" or (tag == "div" and "ch" in classes(a)):
            self.start_skip(a)
            return
        if self.pre is not None:
            if tag == "br":
                self.pre.append("\n")
            return
        if tag == "p" and self.lists:
            self.flush_item()
        elif tag in FLUSH_ON_START:
            self.flush()
        if tag in ("ul", "ol"):
            self.flush_item()
            self.lists.append([tag, 0, ""])
        if tag == "li" and self.lists:
            self.flush_item()
            entry = self.lists[-1]
            entry[1] += 1
            depth = len(self.lists) - 1
            entry[2] = "  " * depth + (f"{entry[1]}. " if entry[0] == "ol" else "- ")
        if tag == "pre":
            self.flush()
            self.pre = []
            self.fence_lang = (a.get("data-lang") or self.fence_lang).lower()
        if tag == "code":
            self.buf.append("`")
        if tag in ("strong", "b"):
            self.buf.append("**")
        if tag in ("em", "i"):
            self.buf.append("_")
        if tag == "a":
            self.href = a.get("href")
            self.buf.append("[")
        if tag == "table":
            self.flush()
            self.table = []
        if tag == "tr":
            self.cells = []
        if tag in ("td", "th"):
            self.buf = []
        if tag == "img":
            self.blocks.append(f"[IMG alt={a.get('alt')!r} src={a.get('src')!r}]")
        if tag in ("video", "source"):
            self.blocks.append(f"[{tag.upper()} " + " ".join(f"{k}={v!r}" for k, v in attrs) + "]")
        if tag == "svg":
            kept = " ".join(f"{k}={v!r}" for k, v in attrs if k in ("aria-label", "role", "viewBox"))
            self.blocks.append("[SVG " + kept + "]")
        if tag == "br":
            self.buf.append(" ")

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if self.skip:
            self.skip -= 1
            self.lang_capture = False
            return
        if self.pre is not None:
            if tag == "pre":
                body = "".join(self.pre)
                if body.startswith("\n"):
                    body = body[1:]
                self.blocks.append(f"```{self.fence_lang}\n{body.rstrip(chr(10))}\n```")
                self.pre = None
                self.fence_lang = ""
            return
        if tag == "a":
            self.buf.append(f"]({self.href})")
        if tag == "code":
            self.buf.append("`")
        if tag in ("strong", "b"):
            self.buf.append("**")
        if tag in ("em", "i"):
            self.buf.append("_")
        if tag in ("td", "th") and self.cells is not None:
            self.cells.append(" ".join("".join(self.buf).split()))
            self.buf = []
        if tag == "tr" and self.cells is not None:
            if self.table is not None:
                self.table.append("| " + " | ".join(self.cells) + " |")
                if len(self.table) == 1:
                    self.table.append("|" + "---|" * len(self.cells))
            self.cells = None
        if tag == "table" and self.table is not None:
            if self.table:
                self.blocks.append("\n".join(self.table))
            self.table = None
        if tag in HEADINGS:
            self.flush("#" * int(tag[1]) + " ")
        elif tag == "li" or (tag == "p" and self.lists):
            self.flush_item()
        elif tag in ("p", "figcaption"):
            self.flush("[CAPTION] " if tag == "figcaption" else "")
        elif tag == "blockquote":
            self.flush("> ")
        if tag in ("ul", "ol") and self.lists:
            self.flush_item()
            self.lists.pop()
        if tag in ("section", "figure", "div"):
            self.flush()

    def handle_data(self, data):
        if self.skip:
            if self.lang_capture:
                self.fence_lang += data.strip()
            return
        if self.pre is not None:
            self.pre.append(data)
            return
        self.buf.append(data)


def body_slice(src: str) -> str:
    marker = src.find('id="body"')
    if marker < 0:
        raise ValueError('no element with id="body"')
    start = src.find(">", marker) + 1
    end = src.find('<div class="more-sec"', start)
    return src[start : end if end >= 0 else len(src)]


def extract(src: str) -> str:
    parser = BodyExtractor()
    parser.feed(body_slice(src))
    parser.close()
    parser.flush()
    return "\n\n".join(parser.blocks) + "\n"


def main(argv=None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) not in (1, 2):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    with open(args[0], encoding="utf-8") as fh:
        src = fh.read()
    try:
        text = extract(src)
    except ValueError as err:
        print(f"extract_blog_body: {err}", file=sys.stderr)
        return 1
    if len(args) == 2:
        with open(args[1], "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
