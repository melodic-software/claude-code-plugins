"""Conditions a hint's match must also meet before the hint is kept.

A hint's optional ``requires`` object narrows a glob match with facts the walk
cannot express as a name: a file that holds no bytes, a sibling or child that
must be absent, a text no named config file may contain. Every requirement
fails closed: a fact that cannot be read counts as unmet, and the hint is
dropped.

Evaluation reads the entries the walk already recorded, plus one ``lstat`` per
named sibling or child and one read per named config file (cached for the
scan). It never lists a directory, so it adds no ``os.scandir`` call to a scan.
"""

from __future__ import annotations

import os
from collections.abc import Iterable
from pathlib import Path, PurePosixPath
from typing import Any

REQUIREMENTS = ("zero_bytes", "absent_siblings", "absent_children", "unreferenced")


class ConditionError(ValueError):
    """Raised on a malformed ``requires`` object."""


def _names(value: Any, field: str, *, bare: bool) -> None:
    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(item, str) and item for item in value)
    ):
        raise ConditionError(f"requires.{field} must be a non-empty array of strings")
    for item in value:
        parts = PurePosixPath(item.replace("\\", "/")).parts
        if item.startswith(("/", "\\")) or ".." in parts or ":" in item:
            raise ConditionError(f"requires.{field} entries must be relative: {item}")
        if bare and len(parts) != 1:
            raise ConditionError(f"requires.{field} entries must be bare names: {item}")


def validate_requires(requires: Any) -> None:
    if not isinstance(requires, dict) or not requires:
        raise ConditionError("hint requires must be a non-empty object")
    unknown = set(requires) - set(REQUIREMENTS)
    if unknown:
        raise ConditionError(
            f"unknown hint requirement(s): {', '.join(sorted(unknown))}; "
            f"supported: {', '.join(REQUIREMENTS)}"
        )
    if "zero_bytes" in requires and requires["zero_bytes"] is not True:
        raise ConditionError("requires.zero_bytes must be true")
    for field in ("absent_siblings", "absent_children"):
        if field in requires:
            _names(requires[field], field, bare=True)
    if "unreferenced" in requires:
        spec = requires["unreferenced"]
        if not isinstance(spec, dict) or set(spec) != {"text", "home_files"}:
            raise ConditionError(
                "requires.unreferenced must hold exactly text and home_files"
            )
        if not isinstance(spec["text"], str) or not spec["text"]:
            raise ConditionError(
                "requires.unreferenced.text must be a non-empty string"
            )
        _names(spec["home_files"], "unreferenced.home_files", bare=False)


class _Facts:
    """Lazily built, per-scan facts shared by every entry's evaluation."""

    def __init__(
        self,
        entries: list[dict[str, Any]],
        target: Path,
        home: Path | None,
        unwalked: set[str],
    ) -> None:
        self.entries = entries
        self.target = target
        self.home = home
        self.unwalked = unwalked
        self._content_dirs: set[str] | None = None
        self._file_bytes: dict[Path, bytes | None] = {}

    def content_dirs(self) -> set[str]:
        """Directories holding a non-directory or an unwalked descendant."""
        if self._content_dirs is None:
            found: set[str] = set()
            for entry in self.entries:
                if entry["kind"] != "directory":
                    found.update(str(p) for p in PurePosixPath(entry["path"]).parents)
            for unknown in self.unwalked:
                found.update(str(p) for p in PurePosixPath(unknown).parents)
            self._content_dirs = found
        return self._content_dirs

    def file_bytes(self, path: Path) -> bytes | None:
        """File contents, b"" when absent, None when it exists but cannot be read."""
        if path not in self._file_bytes:
            try:
                self._file_bytes[path] = path.read_bytes()
            except FileNotFoundError:
                self._file_bytes[path] = b""
            except OSError:
                self._file_bytes[path] = None
        return self._file_bytes[path]


def _present(directory: Path, names: list[str], field: str) -> str | None:
    """'field: why' for the first name present or uncheckable, else None."""
    for name in names:
        try:
            os.lstat(directory / name)
        except FileNotFoundError:
            continue
        except OSError as exc:
            return f"{field}: cannot check {name}: {exc.strerror}"
        return f"{field}: {name} is present"
    return None


def _unmet(
    requires: dict[str, Any], entry: dict[str, Any], facts: _Facts
) -> str | None:
    """The first unmet requirement as 'name: detail', or None when all hold."""
    path = facts.target.joinpath(*PurePosixPath(entry["path"]).parts)
    if requires.get("zero_bytes"):
        if entry["kind"] == "file":
            if entry.get("stat_size") != 0:
                return "zero_bytes: file holds bytes"
        elif entry["kind"] == "directory":
            if (
                entry["path"] in facts.unwalked
                or "not-walked" in entry.get("size_qualifiers", [])
                or entry["path"] in facts.content_dirs()
            ):
                return "zero_bytes: directory tree holds a file or an unwalked path"
        else:
            return (
                f"zero_bytes: {entry['kind']} entry is neither a file nor a directory"
            )
    if "absent_siblings" in requires:
        found = _present(path.parent, requires["absent_siblings"], "absent_siblings")
        if found:
            return found
    if "absent_children" in requires:
        if entry["kind"] != "directory":
            return "absent_children: entry is not a directory"
        found = _present(path, requires["absent_children"], "absent_children")
        if found:
            return found
    spec = requires.get("unreferenced")
    if spec:
        if facts.home is None:
            return "unreferenced: home directory unknown"
        needle = spec["text"].encode("utf-8")
        for relative in spec["home_files"]:
            text = facts.file_bytes(facts.home.joinpath(*PurePosixPath(relative).parts))
            if text is None:
                return f"unreferenced: cannot read ~/{relative}"
            if needle in text:
                return f"unreferenced: ~/{relative} names {spec['text']}"
    return None


def apply(
    entries: list[dict[str, Any]],
    hints: Iterable[dict[str, Any]],
    target: Path,
    home: Path | None,
    unwalked: set[str],
) -> int:
    """Drop each matched hint whose requirements fail; return how many were dropped.

    A dropped hint is recorded on the entry as ``unmet_hint_conditions``
    (``hint_id`` and ``detail``) so the report can say why a name that looks
    like a leftover is not one.
    """
    conditional = {hint["id"]: hint["requires"] for hint in hints if "requires" in hint}
    if not conditional:
        return 0
    facts = _Facts(entries, target, home, unwalked)
    dropped = 0
    for entry in entries:
        kept: list[dict[str, Any]] = []
        unmet: list[dict[str, str]] = []
        for hint in entry.get("hints", []):
            requires = conditional.get(hint["id"])
            detail = _unmet(requires, entry, facts) if requires else None
            if detail is None:
                kept.append(hint)
            else:
                unmet.append({"hint_id": hint["id"], "detail": detail})
        if unmet:
            entry["hints"] = kept
            entry["unmet_hint_conditions"] = unmet
            dropped += len(unmet)
    return dropped
