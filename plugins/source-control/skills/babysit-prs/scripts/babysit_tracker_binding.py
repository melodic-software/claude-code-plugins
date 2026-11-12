#!/usr/bin/env python3
"""The work-item tracker binding, as every babysit script reads it.

The binding is the `tracker` mapping of `YAML_PATH` (the work-items seam's
CONTRACT.md "Setup (binding file)"). A repository root `.work-item-tracker.json`
no longer binds: `/work-items:setup apply` copies it into `YAML_PATH`. The
babysit scripts read the binding from the default branch (the admission label at
the pull request's base branch), at the default convention home
`docs/conventions`, where they read `pr-pipeline.yaml` too.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping

YAML_PATH = "docs/conventions/work-items.yaml"
# Each file that can bind the tracker.
PATHS = (YAML_PATH,)


class BindingError(ValueError):
    """A binding file the reader cannot use."""


def role_label(
    read: Callable[[str], str | None],
    records: Callable[[str], Mapping[str, str]],
    role: str,
    default: str,
) -> str:
    """The binding's label for `role`, or `default` when no binding maps it
    to a non-blank string.

    `read(path)` is the file's text, or None when the file is absent; its
    failures pass through. `records(text)` is the YAML parser's
    `dotted.key -> value` records, and raises on a document the parser
    rejects. The YAML file binds when it sets any `tracker` key. Raises
    `BindingError` when `tracker` is a scalar."""
    text = read(YAML_PATH)
    if text is None:
        return default
    found = records(text)
    if "tracker" in found:
        raise BindingError(f"{YAML_PATH}: tracker is not a mapping")
    return _label(found.get(f"tracker.config.role_labels.{role}"), default)


def _label(value: object, default: str) -> str:
    return value.strip() if isinstance(value, str) and value.strip() else default
