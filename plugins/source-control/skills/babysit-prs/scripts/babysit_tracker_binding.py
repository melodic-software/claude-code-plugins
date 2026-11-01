#!/usr/bin/env python3
"""The work-item tracker binding, as every babysit script reads it.

The binding is the `tracker` mapping of `YAML_PATH`. A repository that has not
moved it there is still bound by the legacy `LEGACY_PATH` at its root, the
fallback the work-items seam keeps (its CONTRACT.md "Setup (binding file)";
ADR 0075 fix 11). The babysit scripts read it from the default branch (the
admission label at the pull request's base branch), at the default convention
home `docs/conventions`, where they read `pr-pipeline.yaml` too.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Mapping

from babysit_util import json_object

YAML_PATH = "docs/conventions/work-items.yaml"
LEGACY_PATH = ".work-item-tracker.json"
# Each file that can bind the tracker, in the order `role_label` tries them.
PATHS = (YAML_PATH, LEGACY_PATH)


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
    rejects. The YAML file binds when it sets any `tracker` key, else the
    legacy file does; an empty legacy file maps nothing. Raises
    `BindingError` when `tracker` is a scalar or the legacy file is not
    JSON."""
    text = read(YAML_PATH)
    if text is not None:
        found = records(text)
        if "tracker" in found:
            raise BindingError(f"{YAML_PATH}: tracker is not a mapping")
        if any(key.startswith("tracker.") for key in found):
            return _label(found.get(f"tracker.config.role_labels.{role}"), default)
    text = read(LEGACY_PATH)
    if text is None or not text.strip():
        return default
    try:
        config = json.loads(text)
    except ValueError as exc:
        raise BindingError(f"{LEGACY_PATH} is not JSON: {exc}") from exc
    roles = json_object(
        json_object(json_object(config).get("config")).get("role_labels")
    )
    return _label(roles.get(role), default)


def _label(value: object, default: str) -> str:
    return value.strip() if isinstance(value, str) and value.strip() else default
