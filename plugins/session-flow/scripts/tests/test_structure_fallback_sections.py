# test-scope: plugins/session-flow/reference/structure.md
"""The Python-absent fallback's hand-written section list matches the shape-4 ShapeSpec."""

from __future__ import annotations

import re
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from handoff_chain import SHAPES  # noqa: E402

STRUCTURE = SCRIPTS.parent / "reference" / "structure.md"


def _fallback_rows() -> list[str]:
    text = STRUCTURE.read_text(encoding="utf-8")
    start = text.index("**Python-absent fallback.**")
    end = text.index("\n### ", start)
    return re.findall(r"^\| \d+ \| ([^|]+?) \|", text[start:end], re.M)


def test_fallback_lists_every_shape4_section_in_shapespec_order():
    assert _fallback_rows() == [s.name for s in SHAPES[4].sections]


def _fallback_block() -> str:
    text = STRUCTURE.read_text(encoding="utf-8")
    start = text.index("**Python-absent fallback.**")
    return text[start : text.index("\n### ", start)]


def test_fallback_names_every_shape4_retire_heading_and_the_pointer_lines():
    block = _fallback_block()
    headings = {s.retire_heading for s in SHAPES[4].sections if s.retire_heading}
    missing = [h for h in sorted(headings) if f"## {h}" not in block]
    assert not missing, missing
    for pointer in ("- Retired entries:", "- Folded:", "Retired:"):
        assert pointer in block, pointer
