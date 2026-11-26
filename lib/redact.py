"""Redact secrets, emails and home paths from text before audit-sessions stores any of it.

Public API:
    load_redactor(path=RULES_FILE) -> Redactor
    Redactor.redact(text) -> str
    Redactor.excerpt(text, limit) -> str | None
    Redactor.skipped: dict[str, str]   rule id -> why it was skipped
    Redactor.fail_closed: bool         a rule was skipped or none loaded; excerpt() returns None
    Redactor.rule_count: int           gitleaks rules in force
    Redactor.version: str              the vendored gitleaks version, "" when unknown
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
_NAME_CHAR = r"""[^\\/\s"'`<>|:*?,;()\[\]{}]"""
_NAME = rf"{_NAME_CHAR}+(?: {_NAME_CHAR}+)*(?={_SEP})|{_NAME_CHAR}+"
_HOME = re.compile(
    rf"(?<![\w.~-])(?:(?i:[a-z]:|/mnt/[a-z]|/[a-z]){_SEP}(?i:users)|/home|/Users){_SEP}(?:{_NAME})"
)
_EMAIL = re.compile(
    r"(?<![\w.%+-])[\w.%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"
)
_KEYWORD = r"key|secret|token|passw(?:or)?d|passphrase|pwd|(?<![a-z])(?:pass|pw)(?![a-z])"
_ASSIGNMENT = re.compile(
    rf"""(?i)({_KEYWORD})(["']?(?:\s*[:=]+>?)+\s*)(?!<redacted:)("[^"]*"|'[^']*'|\S+)"""
)
_PROSE = re.compile(
    r"(?i)\b(passw(?:or)?d|passphrase|pwd|secret|token)(\s+(?:(?:is|was|-)\s+)?)"
    r"(?!<redacted:)(?=[^\s,;]*[\d!@#$%^&*])[^\s,;]+"
)
_URL_CREDENTIAL = re.compile(
    r"(?i)(?<![a-z0-9+.-])([a-z][a-z0-9+.-]{0,30}://[^\s:/@]*:)(?:(\S+)(?=@)|\S*)"
)


def _url_credential(match: re.Match[str]) -> str:
    return match[0] if match[2] is None else match[1] + "<redacted:url-credential>"


_BEARER = re.compile(r"(?i)\b(bearer)(\s+)(?!<redacted:)[A-Za-z0-9._~+/=-]{8,}")
_BASIC = re.compile(
    r"""(?i)\b(authorization["']?\s*:\s*["']?basic)(\s+)(?!<redacted:)[A-Za-z0-9+/=]{8,}"""
)
_PRIVATE_KEY = re.compile(
    r"-----BEGIN ([A-Z ]*)PRIVATE KEY-----.*?(?:-----END \1PRIVATE KEY-----|\Z)", re.S
)
_CLI_PASSWORD = re.compile(
    r"""(?i)(?<![\w-])((?:mysql|mysqldump|mysqladmin|mariadb)\b[^\n|;&]*?\s(?-i:-p))"""
    r"""(?!<redacted:)('[^']*'|"[^"]*"|[^\s'"]\S*)"""
)
_PRE_PASSES = (
    (re.compile(r"sk-ant-oat01-[A-Za-z0-9_-]+"), "anthropic-oauth-token"),
    (re.compile(r"sk-ant-oat02-[A-Za-z0-9_-]+"), "anthropic-oauth-token"),
    (re.compile(r"ghs_[A-Za-z0-9._-]{36,}"), "github-app-token"),
)
_PASSES = (
    (_PRIVATE_KEY, "<redacted:private-key>"),
    (_URL_CREDENTIAL, _url_credential),
    (_CLI_PASSWORD, r"\1<redacted:cli-password>"),
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
    version: str = ""

    @property
    def fail_closed(self) -> bool:
        return bool(self.skipped) or not self.rules

    @property
    def rule_count(self) -> int:
        return len(self.rules)

    def redact(self, text: str) -> str:
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        for index, (pattern, _) in enumerate(_PRE_PASSES):
            text = pattern.sub(f"<redacted:pre-{index}>", text)
        lowered = text.lower()
        for rule in self.rules:
            if not rule.keywords or any(k in lowered for k in rule.keywords):
                text = rule.pattern.sub(f"<redacted:{rule.id}>", text)
        for pattern, replacement in _PASSES:
            text = pattern.sub(replacement, text)
        for index, (_, label) in enumerate(_PRE_PASSES):
            text = text.replace(f"<redacted:pre-{index}>", f"<redacted:{label}>")
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
        data = json.loads(path.read_text(encoding="utf-8"))
        entries = list(data["rules"])
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
    return Redactor(tuple(rules), skipped, str(data.get("source_version", "")))
