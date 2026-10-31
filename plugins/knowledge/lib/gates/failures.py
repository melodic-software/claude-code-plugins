"""Named check failures for a standing gate. Stdlib only. Python 3.9+."""

from __future__ import annotations

import sys
from typing import List, Optional


class Failures:
    """Named check failures, echoed to stderr as they land under ``prog``.

    With ``echo_limit`` set, only the first ``echo_limit`` are echoed and
    ``report_suppressed`` then names how many were not; without it every
    failure is echoed. ``items`` keeps every failure either way, so the count
    and the exit code are unaffected.
    """

    def __init__(self, prog: str, echo_limit: Optional[int] = None):
        self.prog = prog
        self.echo_limit = echo_limit
        self.items: List[str] = []

    def add(self, message: str) -> None:
        self.items.append(message)
        if self.echo_limit is None or len(self.items) <= self.echo_limit:
            sys.stderr.write(f"{self.prog}: FAIL: {message}\n")

    def report_suppressed(self) -> None:
        if self.echo_limit is None:
            return
        hidden = len(self.items) - self.echo_limit
        if hidden > 0:
            sys.stderr.write(f"{self.prog}: ... {hidden} more failure(s) not shown\n")
