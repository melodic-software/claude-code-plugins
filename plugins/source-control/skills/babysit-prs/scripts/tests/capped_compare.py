"""Compare diff text built from the captured sample that
`.github/scripts/pr-merge/capped-compare.fixture.mjs` reads, so Python tests
feed the same GitHub output the JS tests do."""

from __future__ import annotations

import json
import pathlib
import re

FIXTURES = pathlib.Path(__file__).resolve().parents[6] / ".github/scripts/pr-merge/fixtures"


def _sample() -> tuple[list[dict], list[str]]:
    files = json.loads((FIXTURES / "compare-sample.json").read_text(encoding="utf-8"))["files"]
    with (FIXTURES / "compare-sample.diff").open(encoding="utf-8", newline="") as text:
        sections = re.split(r"(?m)^(?=diff --git )", text.read())[1:]
    return files, sections


def modified_as(paths: list[str]) -> str:
    """The sample's modified-file diff section once per path, its path
    rewritten to that path (capped-compare.fixture.mjs `modifiedAs`)."""
    files, sections = _sample()
    at = next(i for i, f in enumerate(files) if f["status"] == "modified")
    return "".join(sections[at].replace(files[at]["filename"], path) for path in paths)


def docs_diff(n: int) -> str:
    return modified_as([f"docs/{i}.md" for i in range(n)])
