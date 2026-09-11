"""Single origin of the hygiene engine's command-line grammar.

Two consumers read this declaration and must never restate it:

* ``hygiene.py`` ``build_parser`` derives every argparse subparser from it, so
  the engine accepts exactly the flags declared here.
* ``destructive_guard.py`` ``classify_exact_engine_command`` validates a literal
  shell invocation against it through ``match_invocation``, so the always-on
  guard admits exactly the shapes the engine parses and nothing wider.

A flag added here is therefore accepted by the engine and admitted by the guard
in the same edit; a flag added to either consumer directly has nowhere to go.

The guard is stricter than argparse on purpose, and the declaration carries
that asymmetry explicitly rather than leaving it to a positional restatement:

* ``required`` flags must open the invocation, in declaration order, before any
  optional flag. argparse accepts them in any order; the guard does not, so one
  canonical spelling is the only one it admits.
* A ``required`` flag that takes no value (``apply --execute``) is required by
  the GUARD only. The parser keeps it optional so the engine can refuse an
  ``apply`` without it with its own diagnostic instead of an argparse usage
  error.
* Optional flags follow the required head in any order, each at most once
  unless ``repeatable``; every value must be a literal argument (non-empty, not
  flag-shaped) and pass the flag's ``pattern`` or ``choices``. A flag whose
  value the guard can only judge with context it alone holds names an
  ``external_check``; the guard supplies that callable to ``match_invocation``.
* ``requires`` names another flag that must also be present.
* ``example`` is one literal the flag admits, carried beside the ``pattern``
  that enforces it so an invocation of any subcommand can be built from this
  declaration alone. That is what lets the agreement suite exercise a newly
  declared flag against both consumers without a test edit. Every value-taking
  flag has one except those naming an ``external_check``, whose only admissible
  value is context the guard resolves at runtime.

This module sits on the always-on ``Bash|PowerShell`` PreToolUse path, so it
imports nothing beyond ``re`` and builds its tables once at import.
"""

from __future__ import annotations

import re

TIERS = frozenset({"high", "medium", "low"})

# A literal that only the guard can validate, because the answer depends on the
# authorized data root it resolved for this session.
AUTHORIZED_DATA_ROOT = "authorized-data-root"


class Flag:
    """One command-line flag, as the parser declares it and the guard admits it."""

    __slots__ = (
        "name",
        "takes_value",
        "required",
        "repeatable",
        "choices",
        "pattern",
        "external_check",
        "requires",
        "value_type",
        "metavar",
        "example",
        "help",
    )

    def __init__(
        self,
        name: str,
        *,
        takes_value: bool = True,
        required: bool = False,
        repeatable: bool = False,
        choices: frozenset[str] | None = None,
        pattern: str | None = None,
        external_check: str | None = None,
        requires: str | None = None,
        value_type: str | None = None,
        metavar: str | None = None,
        example: str | None = None,
        help: str | None = None,
    ) -> None:
        self.name = name
        self.takes_value = takes_value
        self.required = required
        self.repeatable = repeatable
        self.choices = choices
        self.pattern = re.compile(pattern) if pattern is not None else None
        self.external_check = external_check
        self.requires = requires
        self.value_type = value_type
        self.metavar = metavar
        self.example = example
        self.help = help

    @property
    def dest(self) -> str:
        """The argparse attribute name (``--max-depth`` -> ``max_depth``)."""
        return self.name.lstrip("-").replace("-", "_")


class Subcommand:
    """One engine subcommand: its parser help and its flags in declaration order."""

    __slots__ = ("name", "help", "flags", "required", "optional", "_by_name")

    def __init__(self, name: str, flags: tuple[Flag, ...], *, help: str | None = None):
        self.name = name
        self.help = help
        self.flags = flags
        self.required = tuple(flag for flag in flags if flag.required)
        self.optional = tuple(flag for flag in flags if not flag.required)
        self._by_name = {flag.name: flag for flag in flags}

    def flag(self, name: str) -> Flag | None:
        return self._by_name.get(name)


def _data_root_flag() -> Flag:
    return Flag("--data-root", external_check=AUTHORIZED_DATA_ROOT)


# A directory basename with no separator and no self/parent reference.
_IMMEDIATE_BASENAME = r"(?!\.\.?$)[^/\\]+"

SUBCOMMANDS: tuple[Subcommand, ...] = (
    Subcommand(
        "scan",
        (
            Flag("--target", required=True, example="target-dir"),
            Flag("--output", required=True, example="snapshot.json"),
            Flag("--policy", example="policy.json"),
            Flag("--project-dir", example="project-dir"),
            _data_root_flag(),
            Flag(
                "--max-depth",
                pattern=r"[1-9][0-9]{0,3}",
                value_type="int",
                example="3",
            ),
            Flag("--confirmed-large-scan", takes_value=False),
            # --quiet only shapes the engine's stdout, so admitting it widens no
            # capability: it cannot reach a path the same invocation without it
            # could not already reach.
            Flag(
                "--quiet",
                takes_value=False,
                help=(
                    "omit children_rollup from stdout and shorten the note; the "
                    "snapshot file still carries every row, so read per-child "
                    "detail there. Stdout shaping only: the scan itself is "
                    "unchanged"
                ),
            ),
            Flag(
                "--root-children",
                takes_value=False,
                help=(
                    "admit an OS-managed volume root only as a listing of "
                    "immediate non-OS child directories; requires explicit "
                    "--root-child selection before any subtree is audited"
                ),
            ),
            Flag(
                "--root-child",
                repeatable=True,
                pattern=_IMMEDIATE_BASENAME,
                requires="--root-children",
                metavar="NAME",
                example="Projects",
                help=(
                    "immediate child directory basename to audit under "
                    "--root-children; repeatable; never inferred"
                ),
            ),
        ),
        help="inventory a target without mutating it",
    ),
    Subcommand(
        "preview",
        (
            Flag("--snapshot", required=True, example="snapshot.json"),
            Flag("--plan", required=True, example="plan.json"),
            _data_root_flag(),
        ),
    ),
    Subcommand(
        "handoff-verify",
        (
            Flag("--snapshot", required=True, example="snapshot.json"),
            Flag("--paths", required=True, example="paths.json"),
            Flag("--vcs-evidence", example="vcs-evidence.json"),
            _data_root_flag(),
        ),
        help="re-verify approved paths for the manual handoff lane (read-only)",
    ),
    Subcommand(
        "apply",
        (
            Flag("--execute", takes_value=False, required=True),
            Flag("--snapshot", required=True, example="snapshot.json"),
            Flag("--plan", required=True, example="plan.json"),
            Flag("--confirm-tier", required=True, choices=TIERS, example="high"),
            Flag(
                "--approval-token",
                required=True,
                pattern=r"[0-9a-f]{24}",
                example="0123456789abcdef01234567",
            ),
            Flag("--report", required=True, example="report.json"),
            _data_root_flag(),
        ),
    ),
)

# Ordered so a disclosure can name the read-only subcommands first and the
# mutating one last.
SUBCOMMAND_NAMES: tuple[str, ...] = tuple(spec.name for spec in SUBCOMMANDS)
_SUBCOMMANDS_BY_NAME = {spec.name: spec for spec in SUBCOMMANDS}


def subcommand(name: str) -> Subcommand | None:
    return _SUBCOMMANDS_BY_NAME.get(name)


def is_argument(value: str) -> bool:
    """A literal flag value: non-empty and not itself flag-shaped."""
    return bool(value) and not value.startswith("-")


def literal_value_ok(flag: Flag, value: str) -> bool:
    """Everything about a value this declaration can judge without context."""
    if not is_argument(value):
        return False
    if flag.choices is not None and value not in flag.choices:
        return False
    return flag.pattern is None or flag.pattern.fullmatch(value) is not None


def match_invocation(
    name: str,
    words: list[str],
    external_checks: dict[str, object] | None = None,
) -> bool:
    """True when ``words`` (the tokens after the subcommand) are one exact shape.

    ``external_checks`` maps an ``external_check`` label to a callable taking
    the literal value and returning bool. A flag whose label has no callable
    fails closed.
    """
    spec = subcommand(name)
    if spec is None:
        return False
    checks = external_checks or {}

    def value_ok(flag: Flag, value: str) -> bool:
        if not literal_value_ok(flag, value):
            return False
        if flag.external_check is None:
            return True
        check = checks.get(flag.external_check)
        return callable(check) and bool(check(value))

    index = 0
    for flag in spec.required:
        if index >= len(words) or words[index] != flag.name:
            return False
        index += 1
        if flag.takes_value:
            if index >= len(words) or not value_ok(flag, words[index]):
                return False
            index += 1

    seen: set[str] = set()
    while index < len(words):
        flag = spec.flag(words[index])
        if flag is None or flag.required or (flag.name in seen and not flag.repeatable):
            return False
        seen.add(flag.name)
        index += 1
        if flag.takes_value:
            if index >= len(words) or not value_ok(flag, words[index]):
                return False
            index += 1

    return all(
        flag.requires in seen
        for flag in spec.optional
        if flag.requires is not None and flag.name in seen
    )
