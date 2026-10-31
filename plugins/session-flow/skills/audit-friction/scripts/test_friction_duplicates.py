"""Contract test for the `duplicates_dropped` total `friction.py mine` reports.

`aggregate` sums each stored record's `friction.duplicates_dropped`, and `render_mine` prints the
total in its summary line. A record without a `friction` block, or without the field, adds nothing.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent


def load_friction():
    spec = importlib.util.spec_from_file_location("friction_duplicates_under_test", SCRIPTS / "friction.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_aggregate_sums_duplicates_dropped_and_mine_prints_it():
    module = load_friction()
    records = [
        {"session_id": "a", "friction": {"duplicates_dropped": 2}},
        {"session_id": "b", "friction": {"duplicates_dropped": 3}},
        {"session_id": "c", "friction": {}},
        {"session_id": "d"},
    ]
    data = module.aggregate(records)
    assert data["duplicates_dropped"] == 5
    data["window"] = {"since": "2026-09-01", "until": "2026-09-30"}
    data["projects_roots"] = [{"root": "<projects-root>", "via": "default"}]
    data["wsl_distros_unchecked"] = []
    data["warnings"] = []
    assert "5 duplicate result records dropped." in module.render_mine(data)
