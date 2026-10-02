"""Redact secrets, emails and home paths from text before audit-sessions stores any of it.

Public API:
    load_redactor(path=RULES_FILE) -> Redactor
    Redactor.redact(text) -> str
    Redactor.excerpt(text, limit) -> str | None
    Redactor.skipped: dict[str, str]   rule id -> why it was skipped
    Redactor.fail_closed: bool         a rule was skipped or none loaded; excerpt() returns None
    Redactor.rule_count: int           gitleaks rules in force
"""

from __future__ import annotations

import json
import re
import warnings
from dataclasses import dataclass, field
from pathlib import Path

RULES_FILE = (
    Path(__file__).resolve().parents[1] / "vendor" / "gitleaks" / "gitleaks-rules.json"
)

_SEP = r"[\\/]+"
# A user segment ends at a separator; a spaced name counts only when a separator follows it.
_NAME_CHAR = r"""[^\\/\s"'`<>|:*?,;()\[\]{}]"""
_NAME = rf"{_NAME_CHAR}+(?: {_NAME_CHAR}+)*(?={_SEP})|{_NAME_CHAR}+"
# Windows, Git Bash and WSL spellings fold case; the POSIX homes do not.
_HOME = re.compile(
    rf"(?<![\w.~-])(?:(?i:[a-z]:|/mnt/[a-z]|/[a-z]){_SEP}(?i:users)|/home|/Users){_SEP}(?:{_NAME})"
)
_EMAIL = re.compile(
    r"(?<![\w.%+-])[\w.%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"
)
_KEYWORD = r"key|secret|token|passw(?:or)?d|passphrase|pwd|(?<![a-z])pass(?![a-z])"
# A quoted key leaves its closing quote before the separator, separators can repeat (`=>`, `:=`),
# and a quoted value runs to its own closing quote.
_ASSIGNMENT = re.compile(
    rf"""(?i)({_KEYWORD})(["']?(?:\s*[:=]+>?)+\s*)(?!<redacted:)("[^"]*"|'[^']*'|\S+)"""
)
# Prose ("my password is X") is redacted only when X holds a digit or symbol, so a plain word stays.
_PROSE = re.compile(
    r"(?i)\b(passw(?:or)?d|passphrase|pwd|secret|token)(\s+(?:(?:is|was|-)\s+)?)"
    r"(?!<redacted:)(?=[^\s,;]*[\d!@#$%^&*])[^\s,;]+"
)
_URL_CREDENTIAL = re.compile(r"(?i)\b([a-z][a-z0-9+.-]*://[^\s:/@]*:)[^\s@/]+(?=@)")
_BEARER = re.compile(r"(?i)\b(bearer)(\s+)(?!<redacted:)[A-Za-z0-9._~+/=-]{8,}")
_BASIC = re.compile(r"(?i)\b(authorization\s*:\s*basic)(\s+)(?!<redacted:)[A-Za-z0-9+/=]{8,}")
_PASSES = (
    (_URL_CREDENTIAL, r"\1<redacted:url-credential>"),
    (_BEARER, r"\1\2<redacted:bearer>"),
    (_BASIC, r"\1\2<redacted:basic-auth>"),
    (_ASSIGNMENT, r"\1\2<redacted:generic-assignment>"),
    (_PROSE, r"\1\2<redacted:prose-credential>"),
    (_EMAIL, "<email>"),
    (_HOME, "~"),
)


@dataclass(frozen=True)
class Rule:
    id: str
    pattern: re.Pattern[str]
    keywords: tuple[str, ...]


@dataclass(frozen=True)
class Redactor:
    rules: tuple[Rule, ...]
    skipped: dict[str, str] = field(default_factory=dict)

    @property
    def fail_closed(self) -> bool:
        return bool(self.skipped) or not self.rules

    @property
    def rule_count(self) -> int:
        return len(self.rules)

    def redact(self, text: str) -> str:
        # A rule runs only when one of its keywords appears, as gitleaks does.
        lowered = text.lower()
        for rule in self.rules:
            if not rule.keywords or any(k in lowered for k in rule.keywords):
                text = rule.pattern.sub(f"<redacted:{rule.id}>", text)
        for pattern, replacement in _PASSES:
            text = pattern.sub(replacement, text)
        return text

    def excerpt(self, text: str, limit: int) -> str | None:
        """Redact, then truncate to `limit` characters; None while failing closed."""
        if self.fail_closed:
            return None
        return self.redact(text)[:limit]


def _compile(regex: str) -> re.Pattern[str]:
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return re.compile(regex)


def load_redactor(path: Path = RULES_FILE) -> Redactor:
    """Never raises: an unreadable file or rule lands in `skipped`, which fails closed."""
    try:
        entries = list(json.loads(path.read_text(encoding="utf-8"))["rules"])
    except (OSError, ValueError, KeyError, TypeError) as exc:
        return Redactor((), {path.name: f"{type(exc).__name__}: {exc}"})
    rules: list[Rule] = []
    skipped: dict[str, str] = {}
    for index, entry in enumerate(entries):
        rule_id = (
            str(entry.get("id", f"#{index}"))
            if isinstance(entry, dict)
            else f"#{index}"
        )
        try:
            rules.append(
                Rule(
                    rule_id, _compile(entry["regex"]), tuple(entry.get("keywords", []))
                )
            )
        except (re.error, Warning, KeyError, TypeError) as exc:
            skipped[rule_id] = f"{type(exc).__name__}: {exc}"
    return Redactor(tuple(rules), skipped)
