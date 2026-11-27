r"""Redact secrets, emails and home paths from text before audit-sessions stores any of it, and fleet
identifiers from text a skill publishes.

Public API:
    load_redactor(path=RULES_FILE) -> Redactor
    Redactor.redact(text) -> str
    Redactor.excerpt(text, limit) -> str | None
    Redactor.skipped: dict[str, str]   rule id -> why it was skipped
    Redactor.fail_closed: bool         a rule was skipped or none loaded; excerpt() returns None
    Redactor.rule_count: int           gitleaks rules in force
    Redactor.version: str              the vendored gitleaks version, "" when unknown

    publish_redactor(sources, *, extra=(), machine=None, path=RULES_FILE) -> PublishRedactor
    PublishRedactor.redact(text) -> str
    PublishRedactor.placeholders: dict[str, str]   lowercased identifier -> placeholder
    PublishRedactor.fail_closed: bool              the secret rules failed closed

`publish_redactor` is for output that leaves the machine (a report a person may commit or paste,
issue or pull request text); stored records keep `Redactor` alone. Scripts reach it through
`publish.publisher`, which owns the fail-closed policy. Its identifiers come from the resolved
transcript sources (`transcript_sources.Sources`): each host name, the host of each via's last
argument (the ssh destination; its first DNS label too, and its `user@` part as a username), each
source name, each config dir, and a config dir's user segment (under a home directory, or the
directory before a dot-named last one). `machine` is this machine's (host names, usernames), read
from the system when None, and belongs to the host whose sources have no via. `extra` is more
identifiers, a path when it holds a separator.

What published text loses, and what replaces it: hosts are numbered in sorted host-name order, so
`<host-1>` is the same host in every string of one run and never encodes the name. A host name, via
host or machine name becomes `<host-N>` (with any private DNS suffix such as `.ts.net` or `.lan`), a
source name `<host-N:PLATFORM>`, a config dir `<host-N:config>` (`<config>` when several hosts list
it), a username `<user>`, an extra identifier `<identifier>`, an IP address `<ip>`, an email
`<email>`, a home path `~`, a secret `<redacted:RULE>`. Longer identifiers are replaced first, so a
config dir holding a host name or username goes whole. A config dir under `/mnt/<drive>` also
matches its `X:\`, `X:/` and `/x/` spellings, with any run of either separator; paths run again
after the home pass, so an extra `~/name` also catches it under any home directory, and an
extra under a home directory also claims its `~/` form. Any `*.ts.net` name left becomes `<host>`. Names are matched without
regard to case, after a non-alphanumeric or a `%2F`, `%5C`, `%40`, `\n`, `\t` or `\r` escape, and
before anything but a lowercase letter. A host name, alias or username shorter than `MIN_NAME`
characters is not an identifier, and the default sources' own host and source name are none.
"""

from __future__ import annotations

import getpass
import json
import re
import socket
import warnings
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Protocol

RULES_FILE = (
    Path(__file__).resolve().parents[1] / "vendor" / "gitleaks" / "gitleaks-rules.json"
)

_KINDS = ("host", "user", "email", "ip", "config", "identifier")
_TYPED = {kind: f"<{kind}>" for kind in _KINDS}
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
    (_EMAIL, _TYPED["email"]),
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
                text = rule.pattern.sub(_placeholder(f"<redacted:{rule.id}>"), text)
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


def _placeholder(label: str) -> Callable[[re.Match[str]], str]:
    """Replace a rule match up to the end of its last capture group, keeping the terminator gitleaks
    rules match after the secret and each line break the match held before it."""

    def swap(match: re.Match[str]) -> str:
        groups = [i for i in range(1, (match.re.groups or 0) + 1) if match.start(i) >= 0]
        first = min((match.start(i) for i in groups), default=match.start())
        cut = max((match.end(i) for i in groups), default=match.end())
        lead = match.string[match.start():first]
        return label + "\n" * lead.count("\n") + match.string[cut:match.end()]

    return swap


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


MIN_NAME = 2
_PLACEHOLDER = re.compile(r"(<(?:host-\d+(?::[\w-]+)?|" + "|".join(_KINDS) + r"|redacted:[\w-]+)>)")
_OCTET = r"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"
_IPV4 = re.compile(rf"(?<![\w.]){_OCTET}(?:\.{_OCTET}){{3}}(?!\.?\d|\w)")
_HEX = r"[0-9A-Fa-f]{1,4}"
_IPV6 = re.compile(
    rf"(?<![\w:.])(?:(?:{_HEX}:){{7}}{_HEX}|(?:{_HEX}:){{1,6}}(?::{_HEX}){{1,6}}|(?:{_HEX}:){{2,7}}:)(?![\w:.])"
)
_NAME_BEFORE = r"(?:(?<![A-Za-z0-9])|(?<=%2[Ff])|(?<=%5[Cc])|(?<=%40)|(?<=\\[ntr]))"
_DNS_SUFFIX = r"(?P<dns>(?:\.[A-Za-z0-9-]+)*\.(?:ts\.net|home\.arpa|localdomain|local|lan|internal|corp))?"
_NAME_AFTER = r"(?!(?-i:[a-z]))"
_PATH_AFTER = r"(?![\w.-]*\w)"
_TAILNET = re.compile(r"(?<![\w.-])(?:[A-Za-z0-9-]+\.)+ts\.net(?![\w-])", re.I)


class _Entry(Protocol):
    @property
    def name(self) -> str: ...
    @property
    def host(self) -> str: ...
    @property
    def platform(self) -> str: ...
    @property
    def config_dir(self) -> str: ...
    @property
    def via(self) -> tuple[str, ...] | None: ...


class _Sources(Protocol):
    @property
    def origin(self) -> Literal["file", "default"]: ...
    def all(self) -> tuple[_Entry, ...]: ...


@dataclass(frozen=True)
class PublishRedactor:
    redactor: Redactor
    placeholders: Mapping[str, str]
    paths: tuple[tuple[re.Pattern[str], str], ...]
    names: re.Pattern[str] | None

    @property
    def fail_closed(self) -> bool:
        return self.redactor.fail_closed

    def _paths(self, text: str) -> str:
        for pattern, placeholder in self.paths:
            text = pattern.sub(placeholder, text)
        return text

    def _swap(self, match: re.Match[str]) -> str:
        placeholder = self.placeholders.get(match["name"].lower(), _TYPED["identifier"])
        return placeholder if placeholder.startswith("<host") else placeholder + (match["dns"] or "")

    def redact(self, text: str) -> str:
        text = self._paths(_EMAIL.sub(_TYPED["email"], text))
        text = self._paths(self.redactor.redact(text))
        if self.names:
            parts = _PLACEHOLDER.split(text)
            text = "".join(part if index % 2 else self.names.sub(self._swap, part) for index, part in enumerate(parts))
        text = _TAILNET.sub(_TYPED["host"], text)
        return _IPV6.sub(_TYPED["ip"], _IPV4.sub(_TYPED["ip"], text))


def _this_machine() -> tuple[tuple[str, ...], tuple[str, ...]]:
    try:
        user = getpass.getuser()
    except (OSError, KeyError, ImportError):
        user = ""
    return (socket.gethostname(),), (user,)


def _settle(claimed: set[str]) -> str:
    if len(claimed) == 1:
        return next(iter(claimed))
    if all(p.endswith(":config>") for p in claimed):
        return _TYPED["config"]
    return _TYPED["host"] if all(p.startswith("<host-") for p in claimed) else _TYPED["identifier"]


def _path_pattern(path: str) -> re.Pattern[str]:
    parts = [part for part in re.split(_SEP, path) if part]
    letter = None
    if path[0] in "\\/" and len(parts) > 1 and parts[0].lower() == "mnt" and len(parts[1]) == 1 and parts[1].isalpha():
        letter, parts = parts[1], parts[2:]
    elif re.fullmatch(r"[A-Za-z]:", parts[0]):
        letter, parts = parts[0][0], parts[1:]
    body = _SEP.join(map(re.escape, parts))
    if letter is None:
        head = _SEP if path[0] in "\\/" else ""
    else:
        head = rf"(?:{_SEP}mnt{_SEP}{letter}|(?<![A-Za-z0-9]){letter}:|{_SEP}{letter}){_SEP}"
    return re.compile(head + body + _PATH_AFTER, re.I)


def publish_redactor(
    sources: _Sources,
    *,
    extra: Iterable[str] = (),
    machine: tuple[Iterable[str], Iterable[str]] | None = None,
    path: Path = RULES_FILE,
) -> PublishRedactor:
    machine_hosts, machine_users = _this_machine() if machine is None else machine
    entries = sources.all()
    ordinal = {host: f"<host-{n}>" for n, host in enumerate(sorted({e.host for e in entries}), 1)}
    local = next((e.host for e in entries if e.via is None), None)
    machine_tag = ordinal[local] if local is not None else f"<host-{len(ordinal) + 1}>"
    names: dict[str, set[str]] = {}
    paths: dict[str, set[str]] = {}

    def claim(table: dict[str, set[str]], identifier: str, placeholder: str, minimum: int = MIN_NAME) -> None:
        identifier = identifier.strip()
        if table is paths:
            identifier = identifier.rstrip("\\/")
        if len(identifier) >= minimum:
            table.setdefault(identifier.lower(), set()).add(placeholder)

    def claim_host(name: str, tag: str) -> None:
        claim(names, name, tag)
        claim(names, name.split(".")[0], tag)

    for entry in entries:
        tag = ordinal[entry.host]
        if sources.origin != "default":
            claim(names, entry.host, tag)
            claim(names, entry.name, f"{tag[:-1]}:{entry.platform}>")
        claim(paths, entry.config_dir, f"{tag[:-1]}:config>", 1)
        home = _HOME.search(entry.config_dir)
        segments = [part for part in re.split(_SEP, entry.config_dir) if part]
        if home:
            claim(names, re.split(_SEP, home[0])[-1], _TYPED["user"])
        elif len(segments) > 1 and segments[-1].startswith("."):
            claim(names, segments[-2], _TYPED["user"])
        destination = entry.via[-1] if entry.via else ""
        if destination and not destination.startswith("-"):
            user, _, host = destination.removeprefix("ssh://").rpartition("@")
            claim_host(host.split(":")[0], tag)
            claim(names, user, _TYPED["user"])
    for name in machine_hosts:
        claim_host(name, machine_tag)
    for name in machine_users:
        claim(names, name, _TYPED["user"])
    for item in extra:
        item = item.strip()
        claim(paths if "/" in item or "\\" in item else names, item, _TYPED["identifier"], 1)
        home = _HOME.match(item)
        if home and item[home.end():]:
            claim(paths, "~" + item[home.end():], _TYPED["identifier"], 1)
    placeholders = {key: _settle(claimed) for key, claimed in {**names, **paths}.items()}
    ordered = sorted(names, key=len, reverse=True)
    return PublishRedactor(
        load_redactor(path),
        placeholders,
        tuple((_path_pattern(key), placeholders[key]) for key in sorted(paths, key=len, reverse=True)),
        re.compile(
            _NAME_BEFORE + "(?P<name>" + "|".join(map(re.escape, ordered)) + ")" + _DNS_SUFFIX + _NAME_AFTER, re.I
        )
        if ordered
        else None,
    )
