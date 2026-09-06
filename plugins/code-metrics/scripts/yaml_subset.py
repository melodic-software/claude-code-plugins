#!/usr/bin/env python3
"""A parser for the YAML subset this plugin reads (design thread T22).

The standard library has no YAML parser and the plugin forbids a third-party
one, so every surface it reads is written in this subset:

- block mappings (`key: value`, nested by indentation, two or more spaces);
- block sequences (`- item`, scalar or mapping items, a mapping item may start
  on the dash line);
- flow sequences of scalars (`[a, "b", 3]`), including the empty `[]`;
- scalars: single- and double-quoted strings, plain strings, integers,
  floats, `true`/`false`, `null`/`~`, and an empty value meaning `null`;
- `#` comments outside quotes, and blank lines.

Everything else is outside the subset and is reported with its line number
rather than parsed partially: flow mappings (`{`), anchors and aliases (`&`,
`*`), tags (`!`), block scalars (`|`, `>`), multi-document markers (`---`),
tab indentation, and duplicate keys.

Command line: `yaml_subset.py <file>` prints the parsed document as JSON and
exits 0; exit 2 on a usage error or a construct outside the subset (the message
names the construct and the line).
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any

MIN_PYTHON = (3, 9)


class YamlSubsetError(ValueError):
    def __init__(self, line: int, message: str) -> None:
        super().__init__(f"line {line}: {message}")
        self.line = line


_INT = re.compile(r"^[-+]?\d+$")
_FLOAT = re.compile(r"^[-+]?(\d+\.\d*|\.\d+|\d+)([eE][-+]?\d+)?$")


def _strip_comment(text: str) -> str:
    quote = None
    for index, ch in enumerate(text):
        if quote:
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
        elif ch == "#" and (index == 0 or text[index - 1] in " \t"):
            return text[:index].rstrip()
    return text.rstrip()


def _unquote(text: str, line: int) -> str:
    quote = text[0]
    if len(text) < 2 or text[-1] != quote:
        raise YamlSubsetError(line, "unterminated quoted string")
    body = text[1:-1]
    if quote == "'":
        return body.replace("''", "'")
    out = []
    i = 0
    escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "/": "/"}
    while i < len(body):
        ch = body[i]
        if ch == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            if nxt in escapes:
                out.append(escapes[nxt])
                i += 2
                continue
            raise YamlSubsetError(
                line, f"unsupported escape \\{nxt} in double-quoted string"
            )
        out.append(ch)
        i += 1
    return "".join(out)


def _scalar(text: str, line: int) -> Any:
    text = text.strip()
    if text == "":
        return None
    if text[0] in ("'", '"'):
        return _unquote(text, line)
    if text[0] == "{":
        raise YamlSubsetError(
            line, "flow mapping ({...}) is outside the subset; use block style"
        )
    if text[0] in ("&", "*"):
        raise YamlSubsetError(line, "anchors and aliases are outside the subset")
    if text[0] == "!":
        raise YamlSubsetError(line, "tags are outside the subset")
    if text in ("|", ">", "|-", ">-", "|+", ">+"):
        raise YamlSubsetError(line, "block scalars (| and >) are outside the subset")
    if text[0] == "[":
        return _flow_sequence(text, line)
    if text in ("null", "Null", "NULL", "~"):
        return None
    if text in ("true", "True", "TRUE"):
        return True
    if text in ("false", "False", "FALSE"):
        return False
    if _INT.match(text):
        return int(text)
    if _FLOAT.match(text):
        return float(text)
    return text


def _flow_sequence(text: str, line: int) -> list[Any]:
    if not text.endswith("]"):
        raise YamlSubsetError(line, "unterminated flow sequence")
    body = text[1:-1].strip()
    if body == "":
        return []
    items: list[str] = []
    current = ""
    quote = None
    depth = 0
    for ch in body:
        if quote:
            current += ch
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            current += ch
        elif ch == "[":
            depth += 1
            current += ch
        elif ch == "]":
            depth -= 1
            current += ch
        elif ch == "," and depth == 0:
            items.append(current)
            current = ""
        else:
            current += ch
    items.append(current)
    result: list[Any] = []
    for item in items:
        item = item.strip()
        if item.startswith("["):
            raise YamlSubsetError(line, "nested flow sequences are outside the subset")
        result.append(_scalar(item, line))
    return result


def _split_key(content: str, line: int) -> tuple[str, str] | None:
    """Return (key, rest) when the content is a mapping entry, else None."""
    if content.startswith(("'", '"')):
        quote = content[0]
        close = content.find(quote, 1)
        if close == -1:
            raise YamlSubsetError(line, "unterminated quoted key")
        key = _unquote(content[: close + 1], line)
        rest = content[close + 1 :]
        if rest.startswith(":") and (len(rest) == 1 or rest[1] in " \t"):
            return key, rest[1:].strip()
        return None
    match = re.match(r"^([^\s:\[\]{}#][^:#]*?):(?:\s+(.*))?$", content)
    if not match:
        if content.endswith(":"):
            return content[:-1].strip(), ""
        return None
    return match.group(1).strip(), (match.group(2) or "").strip()


class _Parser:
    def __init__(self, text: str) -> None:
        self.lines: list[tuple[int, int, str]] = []  # (indent, lineno, content)
        for number, raw in enumerate(text.splitlines(), 1):
            if raw.startswith("---") or raw.startswith("..."):
                raise YamlSubsetError(number, "document markers are outside the subset")
            stripped = _strip_comment(raw)
            if not stripped.strip():
                continue
            indent = len(stripped) - len(stripped.lstrip(" "))
            if stripped[indent : indent + 1] == "\t" or "\t" in stripped[:indent]:
                raise YamlSubsetError(number, "tab indentation is outside the subset")
            self.lines.append((indent, number, stripped[indent:]))
        self.pos = 0

    def parse(self) -> Any:
        if not self.lines:
            return None
        value = self._block(self.lines[0][0])
        if self.pos < len(self.lines):
            indent, number, content = self.lines[self.pos]
            raise YamlSubsetError(
                number, f"unexpected content at indent {indent}: {content!r}"
            )
        return value

    def _block(self, indent: int) -> Any:
        _, number, content = self.lines[self.pos]
        if content == "-" or content.startswith("- "):
            return self._sequence(indent)
        if _split_key(content, number) is None:
            raise YamlSubsetError(
                number, f"expected a mapping entry or sequence item, got {content!r}"
            )
        return self._mapping(indent)

    def _mapping(self, indent: int) -> dict[str, Any]:
        result: dict[str, Any] = {}
        while self.pos < len(self.lines):
            line_indent, number, content = self.lines[self.pos]
            if line_indent < indent:
                break
            if line_indent > indent:
                raise YamlSubsetError(
                    number, f"unexpected indent {line_indent} (expected {indent})"
                )
            split = _split_key(content, number)
            if split is None:
                raise YamlSubsetError(
                    number, f"expected a mapping entry, got {content!r}"
                )
            key, rest = split
            if key in result:
                raise YamlSubsetError(number, f"duplicate key {key!r}")
            self.pos += 1
            if rest == "":
                result[key] = self._nested(indent, number)
            else:
                result[key] = _scalar(rest, number)
        return result

    def _nested(self, parent_indent: int, number: int) -> Any:
        if self.pos < len(self.lines):
            child_indent, _, content = self.lines[self.pos]
            if child_indent > parent_indent:
                return self._block(child_indent)
            # A sequence may sit at the parent's indent (`key:` then `- item`).
            if child_indent == parent_indent and (
                content == "-" or content.startswith("- ")
            ):
                return self._sequence(child_indent)
        return None

    def _sequence(self, indent: int) -> list[Any]:
        result: list[Any] = []
        while self.pos < len(self.lines):
            line_indent, number, content = self.lines[self.pos]
            if line_indent < indent or not (content == "-" or content.startswith("- ")):
                break
            if line_indent > indent:
                raise YamlSubsetError(
                    number, f"unexpected indent {line_indent} (expected {indent})"
                )
            item = content[1:].strip()
            self.pos += 1
            if item == "":
                result.append(self._nested(indent, number))
                continue
            split = _split_key(item, number)
            if (
                split is not None
                and not item.startswith(("'", '"'))
                or (split is not None and item.startswith(("'", '"')) and ":" in item)
            ):
                # A mapping whose first entry sits on the dash line; the rest
                # of its entries are indented to the item column.
                item_indent = indent + 2
                key, rest = split
                mapping: dict[str, Any] = {}
                if rest == "":
                    mapping[key] = self._nested(item_indent, number)
                else:
                    mapping[key] = _scalar(rest, number)
                if (
                    self.pos < len(self.lines)
                    and self.lines[self.pos][0] == item_indent
                ):
                    more = self._mapping(item_indent)
                    for extra_key, value in more.items():
                        if extra_key in mapping:
                            raise YamlSubsetError(
                                number, f"duplicate key {extra_key!r}"
                            )
                        mapping[extra_key] = value
                result.append(mapping)
                continue
            result.append(_scalar(item, number))
        return result


def parse(text: str) -> Any:
    """Parse a document written in the subset; raise YamlSubsetError otherwise."""
    return _Parser(text).parse()


def load(path: str) -> Any:
    with open(path, encoding="utf-8") as handle:
        return parse(handle.read())


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: yaml_subset.py <file>", file=sys.stderr)
        return 2
    try:
        value = load(argv[0])
    except YamlSubsetError as exc:
        print(f"yaml_subset.py: {argv[0]}: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"yaml_subset.py: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(value, indent=2))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "yaml_subset.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
