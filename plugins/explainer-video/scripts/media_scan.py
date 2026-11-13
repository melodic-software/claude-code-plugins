# GENERATED from lib/media-render/media_scan.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""The secret and machine-data floor (ADR 0107): run before every upload and before text reaches an online voice.

scan(texts, rules=None, host=None, user=None, extra=()) -> ScanResult
  texts   {source label: text}: narration, frame text, screenshot sidecars, the rendered PR section;
  rules   the gitleaks rules file redact.py loads (its own default when None);
  extra   regexes a stricter config adds; nothing can remove the floor.
A finding names its source and kind, never the matched value. ok is False on any finding or when the redactor
fails closed (a rule did not load). Standard library plus redact.py beside this file.
"""
import getpass
import re
import socket
from dataclasses import dataclass, field

import redact

_LABEL = re.compile(r'<redacted:([\w.-]+)>|<email>')


@dataclass
class ScanResult:
    findings: list = field(default_factory=list)
    fail_closed: bool = False
    rule_count: int = 0

    @property
    def ok(self):
        return not self.findings and not self.fail_closed


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
    machine = [('hostname', _alone(host))] if host else []
    machine += [('user-name', _alone(user))] if len(user) >= 3 else []
    machine += [('config-pattern', re.compile(p)) for p in extra]
    result = ScanResult(fail_closed=redactor.fail_closed, rule_count=redactor.rule_count)
    for source, text in texts.items():
        text = str(text)
        cleaned = redactor.redact(text)
        kinds = {m.group(1) or 'email' for m in _LABEL.finditer(cleaned)} - {m.group(1) or 'email'
                                                                              for m in _LABEL.finditer(text)}
        if cleaned.count('~') > text.count('~'):
            kinds.add('home-path')
        kinds |= {kind for kind, pattern in machine if pattern.search(text)}
        result.findings += [{'source': source, 'kind': k} for k in sorted(kinds)]
    return result
