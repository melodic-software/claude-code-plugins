"""Tests for vendor_gitleaks_rules.py over the offline fixture gitleaks-sample.toml.

Every expected regex below is the fixture pattern rewritten by hand to Python `re` syntax.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import date
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "vendor_gitleaks_rules.py"
FIXTURE = HERE / "fixtures" / "vendor-gitleaks-rules" / "gitleaks-sample.toml"


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )


@pytest.fixture
def vendored(tmp_path: Path) -> dict:
    out = tmp_path / "rules.json"
    result = run(
        str(FIXTURE), "--source-version", "v0.0.0-fixture", "--output", str(out)
    )
    assert result.returncode == 0, result.stderr
    return json.loads(out.read_text(encoding="utf-8"))


def regex_of(vendored: dict, rule_id: str) -> str:
    return next(r["regex"] for r in vendored["rules"] if r["id"] == rule_id)


@pytest.mark.parametrize(
    ("rule_id", "expected"),
    [
        ("leading-flag", r"(?i)\bleading_[a-z]{8}\b"),
        ("mid-flag", r"""\b(p8e-(?i:[a-z0-9]{32}))(?:[\x60'"\s;]|\\[nr]|$)"""),
        ("top-level-mid-flag", r"lin_api_(?i:[a-z0-9]{40})"),
        ("escaped-paren", r"\((?i:x\))"),
        ("class-with-paren", r"([)](?i:x))y"),
        ("go-end-of-text", r"\b(sha256~[\w-]{43})(?:[^\w-]|\Z)"),
        ("posix-class", r"\b(pat[0-9A-Za-z]{14}\.[a-f0-9]{64})\b"),
        ("negated-posix-class", r"[^0-9x]"),
    ],
)
def test_rule_is_rewritten_to_python_syntax(
    vendored: dict, rule_id: str, expected: str
) -> None:
    assert regex_of(vendored, rule_id) == expected


def test_keywords_are_carried_over(vendored: dict) -> None:
    by_id = {r["id"]: r for r in vendored["rules"]}
    assert by_id["mid-flag"]["keywords"] == ["p8e-"]
    assert by_id["escaped-paren"]["keywords"] == []


def test_rules_python_cannot_use_are_excluded_with_reasons(vendored: dict) -> None:
    excluded = {e["id"]: e["reason"] for e in vendored["excluded"]}
    assert set(excluded) == {"path-only", "unsupported-syntax", "nested-set-warning"}
    assert "no content regex" in excluded["path-only"]
    assert "bad escape" in excluded["unsupported-syntax"]
    assert "nested set" in excluded["nested-set-warning"].lower()
    assert len(vendored["rules"]) == 8


def test_provenance_is_recorded(vendored: dict) -> None:
    assert vendored["source"] == str(FIXTURE)
    assert vendored["source_version"] == "v0.0.0-fixture"
    assert vendored["vendored"] == date.today().isoformat()


def test_dry_run_prints_counts_and_writes_nothing(tmp_path: Path) -> None:
    out = tmp_path / "rules.json"
    result = run(
        str(FIXTURE), "--source-version", "v0", "--output", str(out), "--dry-run"
    )
    assert result.returncode == 0, result.stderr
    assert "8 rules, 3 excluded" in result.stdout
    assert not out.exists()


def test_source_with_no_usable_rule_exits_1_and_writes_nothing(tmp_path: Path) -> None:
    source = tmp_path / "paths-only.toml"
    source.write_text("[[rules]]\nid = \"p\"\npath = '''x'''\n", encoding="utf-8")
    out = tmp_path / "rules.json"
    result = run(str(source), "--source-version", "v0", "--output", str(out))
    assert result.returncode == 1
    assert not out.exists()


def test_unreadable_source_exits_2(tmp_path: Path) -> None:
    result = run(
        str(tmp_path / "missing.toml"),
        "--source-version",
        "v0",
        "--output",
        str(tmp_path / "o.json"),
    )
    assert result.returncode == 2
    assert "missing.toml" in result.stderr
