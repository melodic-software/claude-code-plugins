#!/usr/bin/env python3
"""Policy for the unattended merge path of the babysit merge gate.

`resolve()` answers whether `babysit_merge.py --unattended` may merge in one
repository, and which login is its configured `merge.agent-identity`. The
readers behind that answer (pipeline config at the base SHA, effective rung,
kill switch, demotion record, identity, eligibility) are not built yet, so
`resolve()` returns an inert policy and every unattended merge refuses.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

AUTHORITY_UNCONFIGURED = "authority-unconfigured"


@dataclass(frozen=True)
class UnattendedPolicy:
    """The unattended merge policy for one repository.

    `reason` names the refusal that keeps the path inert; only None enables it,
    and it has no default, so no policy is enabled by omission.
    `agent_identity` is the configured `merge.agent-identity` login, stripped of
    surrounding whitespace, or None when unset or blank.
    """

    reason: str | None
    agent_identity: str | None = None

    def __post_init__(self) -> None:
        identity = (self.agent_identity or "").strip() or None
        object.__setattr__(self, "agent_identity", identity)

    @property
    def enabled(self) -> bool:
        return self.reason is None

    def report(self) -> dict[str, Any]:
        return {"enabled": self.enabled, "reason": self.reason}


def resolve(repo: str) -> UnattendedPolicy:
    """The unattended policy for `repo`: inert until the config reader exists."""
    return UnattendedPolicy(reason=AUTHORITY_UNCONFIGURED)
