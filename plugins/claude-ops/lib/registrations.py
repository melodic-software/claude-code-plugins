"""The registrations behind one extracted name, in either shape the data takes.

A name maps to one registration object, or to a list when two distinct
registrations share the name (a collision). Consumers read through this helper
so neither shape is a special case, and so the extractor that writes the shape
and every consumer that reads it agree on exactly one rule.

Python 3.11+, standard library only.
"""

from __future__ import annotations

from typing import Any


def registrations_of(entry: Any) -> list[dict[str, Any]]:
    """Every registration behind one name; anything else yields no registrations."""
    if isinstance(entry, list):
        return [item for item in entry if isinstance(item, dict)]
    if isinstance(entry, dict):
        return [entry]
    return []
