# GENERATED from lib/html2md.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""Convert a documentation HTML page to markdown with the standard library only.

Keeps what a section map and a fact check need: ATX headings, fenced code with its language,
GFM tables, lists, inline code and links. The page is cropped to its first <main>, else its
first <article>; when that crop holds no H1, the page's own H1 (or its <title>) leads the output.

usage: html2md.py [IN.html]   reads stdin when no file is given; writes UTF-8 markdown with
                              LF newlines to stdout
"""

import re
import sys
from html import unescape
from html.parser import HTMLParser

SKIP = {
    "script",
    "style",
    "nav",
    "header",
    "footer",
    "aside",
    "noscript",
    "svg",
    "button",
    "form",
    "template",
}
BLOCK = {"p", "div", "section", "li", "tr", "dt", "dd", "blockquote", "figure", "br"}
ZW = re.compile(r"[​‌‍﻿]")
LANG = re.compile(r"(?:language|lang)-([\w+-]+)")
GLYPHS = re.compile("[\\s#¶§\U0001f517​-‍﻿]*")
HIDDEN = re.compile(r"sr-only|visually-hidden|screen-reader-text")
# no end tag follows these, so a hidden one has no text to drop
VOID = {"area", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


def squash(parts):
    return " ".join(ZW.sub("", "".join(parts)).split())


class Conv(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.skip, self.pre = [], 0, 0
        self.head = None  # (level, parts) while inside a heading
        self.perma = None  # text parts of a heading's in-page anchor, while inside one
        self.hide = None  # [tag, open count] of a heading's hidden element, inside one
        self.link = None  # (href, parts) while inside a link
        # index in out of the open fence line, until its language is known
        self.fence = None
        self.rows = self.cells = self.intable = 0
        self.h1 = []  # text of each H1 emitted

    def emit(self, s):
        if self.skip:
            return
        if self.head is not None:
            self.head[1].append(s)
        elif self.link is not None:
            self.link[1].append(s)
        else:
            self.out.append(s)

    def handle_starttag(self, tag, attrs):
        if tag in SKIP:
            self.skip += 1
            return
        a = dict(attrs)
        if re.fullmatch(r"h[1-6]", tag):
            self.head = (int(tag[1]), [])
        elif self.head is not None:
            # a heading is one line of text: wrappers are dropped; text hidden from sight or
            # from screen readers is dropped to its element's end tag; an in-page anchor's
            # text is held to its end tag and dropped only when it is a permalink glyph
            if self.hide is not None:
                self.hide[1] += tag == self.hide[0]
            elif tag not in VOID and (a.get("aria-hidden") == "true" or HIDDEN.search(a.get("class") or "")):
                self.hide = [tag, 1]
            elif (
                self.perma is None
                and tag == "a"
                and (a.get("href") or "").startswith("#")
            ):
                self.perma = []
            return
        elif tag == "pre":
            self.pre += 1
            self.emit("\n\n```")
            self.fence = (
                len(self.out) - 1 if not self.skip and self.link is None else None
            )
            self.set_lang(a)
            self.emit("\n")
        elif tag == "code" and self.pre:
            self.set_lang(a)
        elif tag == "code":
            self.emit("`")
        elif tag == "a" and not self.pre and self.link is None:
            self.link = (a.get("href") or "", [])
        elif tag == "li" and not self.pre:
            self.emit("\n- ")
        elif tag == "table":
            self.rows = 0
            self.intable += 1
            self.emit("\n\n")
        elif tag == "tr":
            self.cells = 0
            self.emit("\n|")
        elif tag in ("td", "th"):
            self.cells += 1
            self.emit(" ")
        elif tag in BLOCK and not self.pre:
            self.emit("\n\n" if tag == "p" else "\n")

    def set_lang(self, a):
        m = LANG.search(a.get("class") or "")
        lang = a.get("language") or a.get("data-language") or (m.group(1) if m else "")
        if lang and self.fence is not None and self.out[self.fence].endswith("```"):
            self.out[self.fence] += lang

    def handle_endtag(self, tag):
        if tag in SKIP:
            self.skip = max(0, self.skip - 1)
            return
        if re.fullmatch(r"h[1-6]", tag) and self.head is not None:
            lvl, parts = self.head
            self.head, self.perma, self.hide = None, None, None
            text = squash(parts)
            text = (text[:-1] if text.endswith("¶") else text).strip()
            if text and not self.skip:
                if lvl == 1:
                    self.h1.append(text)
                self.emit("\n\n" + "#" * lvl + " " + text + "\n\n")
        elif self.head is not None:
            if self.hide is not None:
                self.hide[1] -= tag == self.hide[0]
                if not self.hide[1]:
                    self.hide = None
            elif tag == "a" and self.perma is not None:
                text, self.perma = "".join(self.perma), None
                if not GLYPHS.fullmatch(text):
                    self.head[1].append(text)
            return
        elif tag == "pre":
            self.pre = max(0, self.pre - 1)
            fence = "```"
            if self.fence is not None:
                # widen past the longest backtick run so a ``` line inside cannot close it
                body = "".join(self.out[self.fence + 1 :])
                run = max(map(len, re.findall("`+", body)), default=0)
                fence = "`" * max(3, run + 1)
                self.out[self.fence] = self.out[self.fence].replace("```", fence, 1)
            self.fence = None
            self.emit("\n" + fence + "\n\n")
        elif tag == "code" and not self.pre:
            self.emit("`")
        elif tag == "a" and self.link is not None:
            href, parts = self.link
            self.link = None
            text = squash(parts)
            if text and href and not href.lower().startswith("javascript:"):
                self.emit(
                    f"[{text}](<{href}>)"
                    if re.search(r"[\s()<>]", href)
                    else f"[{text}]({href})"
                )
            elif text:
                self.emit(text)
        elif tag in ("td", "th"):
            self.emit(" |")
        elif tag == "tr":
            self.rows += 1
            if self.rows == 1:
                self.emit("\n|" + " --- |" * max(1, self.cells))
        elif tag == "table":
            self.intable = max(0, self.intable - 1)
            self.emit("\n\n")

    def handle_data(self, data):
        if self.hide is not None:
            return
        if self.perma is not None:
            if not self.skip:
                self.perma.append(data)
            return
        if self.pre and self.head is None:
            self.emit(data)
        else:
            self.emit(
                re.sub(r"\s+", " ", data.replace("|", "\\|") if self.intable else data)
            )


def markdown(html):
    """Markdown for an HTML fragment, and the text of each H1 it emitted."""
    c = Conv()
    c.feed(html)
    c.close()
    return "".join(c.out), c.h1


def page_title(html):
    """The page's first H1, else its og:title, else its <title>, as one line of text."""
    m = re.search(r"<h1\b.*?</h1>", html, re.S | re.I)
    h1 = markdown(m.group(0))[1] if m else []
    if h1:
        return h1[0]
    m = re.search(r"<meta\b[^>]*property=[\"']og:title[\"'][^>]*>", html, re.I)
    m = m and re.search(r"content=[\"']([^\"']*)", m.group(0), re.I)
    if not m:
        m = re.search(r"<title\b[^>]*>(.*?)</title>", html, re.S | re.I)
    return squash([unescape(re.sub(r"<[^>]*>", "", m.group(1)))]) if m else ""


def convert(html):
    html = html.replace("\r\n", "\n").replace("\r", "\n")
    m = re.search(r"<main\b.*?</main>", html, re.S | re.I) or re.search(
        r"<article\b.*?</article>", html, re.S | re.I
    )
    text, h1 = markdown(m.group(0) if m else html)
    if not h1:
        title = page_title(html)
        if title:
            text = "# " + title + "\n\n" + text
    text = ZW.sub("", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() + "\n"


def main():
    raw = (
        open(sys.argv[1], "rb").read() if len(sys.argv) > 1 else sys.stdin.buffer.read()
    )
    sys.stdout.buffer.write(convert(raw.decode("utf-8", "replace")).encode("utf-8"))


if __name__ == "__main__":
    main()
