"""The secret and machine-data floor (ADR 0107): run before every upload and before text reaches an online voice.

scan(texts, rules=None, host=None, user=None, extra=()) -> ScanResult
  texts   {source label: text}: narration, frame text, screenshot sidecars, the rendered PR section;
  rules   the gitleaks rules file redact.py loads (its own default when None);
  extra   regexes a stricter config adds (scan.extra_patterns); nothing can remove the floor, and one that does
          not compile is a finding, so a team's pattern is never silently dropped.
A finding names its source and kind, never the matched value. ok is False on any finding or when the redactor
fails closed (a rule did not load). Standard library plus redact.py beside this file.
"""
import getpass
import re
import socket
from collections import Counter
from dataclasses import dataclass, field

import redact

_LABEL = re.compile(r'<redacted:([\w.-]+)>|<email>')
# Stock account and host names (containers, CI runners, devcontainers): ordinary words that identify no one, so
# matching them would block narration such as "the root cause" or "the test runner".
GENERIC = frozenset({'root', 'user', 'admin', 'administrator', 'runner', 'ubuntu', 'vscode', 'node', 'codespace',
                     'dev', 'test', 'guest', 'localhost'})


@dataclass
class ScanResult:
    findings: list = field(default_factory=list)
    fail_closed: bool = False
    rule_count: int = 0

    @property
    def ok(self):
        return not self.findings and not self.fail_closed


def _labels(text):
    return Counter(m.group(1) or 'email' for m in _LABEL.finditer(text))


def _alone(word):
    """word not touching a word character or a hyphen: a user name, not part of a handle or path segment."""
    return re.compile(rf'(?<![\w-]){re.escape(word)}(?![\w-])', re.I)


def scan(texts, rules=None, host=None, user=None, extra=()):
    redactor = redact.load_redactor(rules) if rules is not None else redact.load_redactor()
    host = host if host is not None else socket.gethostname()
    try:
        user = user if user is not None else getpass.getuser()
    except (KeyError, OSError):
        user = ''
    machine = [('hostname', _alone(host))] if host and host.lower() not in GENERIC else []
    machine += [('user-name', _alone(user))] if len(user) >= 3 and user.lower() not in GENERIC else []
    result = ScanResult(fail_closed=redactor.fail_closed, rule_count=redactor.rule_count)
    for index, pattern in enumerate(extra):
        try:
            machine.append(('config-pattern', re.compile(pattern)))
        except (re.error, TypeError):
            result.findings.append({'source': f'scan.extra_patterns[{index}]', 'kind': 'invalid-pattern'})
    for source, text in texts.items():
        text = str(text)
        cleaned = redactor.redact(text)
        # Per-kind counts, not sets: a label already in the text must not hide a new secret of its kind.
        added = _labels(cleaned) - _labels(text)
        kinds = set(added)
        if cleaned.count('~') > text.count('~'):
            kinds.add('home-path')
        kinds |= {kind for kind, pattern in machine if pattern.search(text)}
        result.findings += [{'source': source, 'kind': k} for k in sorted(kinds)]
    return result
