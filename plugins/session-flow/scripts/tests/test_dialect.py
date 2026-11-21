"""Contract tests for American spelling in what `fill` and `amend` write.

The stub `typos` replays the JSON line shape typos-cli 1.52.2 prints for
`typos --locale en-us --format json -` (one object per finding: type, path,
line_num, byte_offset in UTF-8 bytes, typo, corrections) and reports only when
called with `--locale en-us`. The British and American pairs come from the
American dictionary: colour/color, modelled/modeled.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import pytest
from test_save_point import err, make_repo, out, run
from test_save_point_shape4_writer import body, fill, new

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import dialect  # noqa: E402

STUB = """\
import json, re, sys
WORDS = {"colour": "color", "Colour": "Color", "modelled": "modeled"}
if sys.argv[1:3] != ["--locale", "en-us"]:
    sys.exit(0)
found = False
for number, line in enumerate(sys.stdin.buffer.read().split(b"\\n"), 1):
    for match in re.finditer(rb"[A-Za-z]+", line):
        word = match.group().decode()
        if word in WORDS:
            found = True
            print(json.dumps({"type": "typo", "path": "-", "line_num": number,
                              "byte_offset": match.start(), "typo": word, "corrections": [WORDS[word]]}))
sys.exit(2 if found else 0)
"""

pytestmark = pytest.mark.skipif(os.name == "nt", reason="the stub typos is a shebang script")


def stub_bin(root: Path) -> str:
    """A PATH whose `typos` is the stub, with git beside it for the scripts' own git calls."""
    bin_dir = root / "stub-bin"
    bin_dir.mkdir()
    typos = bin_dir / "typos"
    typos.write_text(f"#!{sys.executable}\n{STUB}", encoding="utf-8")
    typos.chmod(0o755)
    (bin_dir / "git").symlink_to(shutil.which("git"))
    return str(bin_dir)


@pytest.fixture
def stub_path(tmp_path: Path) -> str:
    return stub_bin(tmp_path)


@pytest.fixture
def stubbed(stub_path: str, monkeypatch: pytest.MonkeyPatch) -> str:
    monkeypatch.setenv("PATH", stub_path)
    return stub_path


def test_an_authored_line_comes_back_american(stubbed):
    text, applied = dialect.americanize("─ We modelled the colour — twice.")
    assert text == "─ We modeled the color — twice."
    assert applied == [("modelled", "modeled"), ("colour", "color")]


def test_quoted_code_blockquote_and_path_text_keeps_its_spelling(stubbed):
    quoted = (
        'The owner said "the colour stays" and `colour` is a key.\n'
        "> keep the colour\n"
        "```\ncolour\n```\n"
        "See docs/colour.md and colour.json."
    )
    assert dialect.americanize(quoted) == (quoted, [])


def test_no_typos_on_path_leaves_the_text_and_prints_nothing(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("PATH", str(tmp_path))
    assert dialect.americanize("We modelled the colour.") == ("We modelled the colour.", [])
    assert capsys.readouterr().err == ""


def made(tmp_path: Path) -> Path:
    result = new(make_repo(tmp_path), tmp_path, None, k=1, shape="4")
    assert result.returncode == 0, err(result)
    return Path(out(result).strip())


def test_fill_writes_authored_slots_american_and_keeps_the_owner_words(tmp_path, stub_path, monkeypatch):
    path = made(tmp_path)
    monkeypatch.setenv("PATH", stub_path)
    filled = fill(
        path,
        tmp_path,
        {
            "brief": "We modelled the colour pass on `main`; read Current rules first.",
            "trail": '- [h1] start: the colour pass (owner-directed, "keep the colour").',
            "opening-ask": "Fix the colour of the banner please.",
        },
    )
    assert filled.returncode == 0, err(filled) + out(filled)
    assert "We modeled the color pass on `main`" in body(path, "Resumption brief")
    assert '- [h1] start: the color pass (owner-directed, "keep the colour").' in body(path, "Direction changes")
    assert "Fix the colour of the banner please." in body(path, "Original goal")
    assert "NOTE: slot 'brief': 'modelled' written as 'modeled' (American spelling)" in err(filled)


def test_fill_without_typos_writes_the_values_as_given(tmp_path, monkeypatch):
    path = made(tmp_path)
    bare = tmp_path / "bare-bin"
    bare.mkdir()
    monkeypatch.setenv("PATH", str(bare))
    filled = fill(path, tmp_path, {"brief": "We modelled the colour pass; read Current rules first."})
    assert filled.returncode == 0, err(filled) + out(filled)
    assert "We modelled the colour pass" in body(path, "Resumption brief")
    assert "American spelling" not in err(filled)


def test_amend_writes_next_lines_american(tmp_path, stub_path, monkeypatch):
    path = made(tmp_path)
    assert fill(path, tmp_path).returncode == 0
    payload = tmp_path / "amend.json"
    payload.write_text('{"next": ["Finish the colour pass"]}', encoding="utf-8")
    monkeypatch.setenv("PATH", stub_path)
    amended = run("amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z")
    assert amended.returncode == 0, err(amended) + out(amended)
    assert "Finish the color pass" in path.read_text(encoding="utf-8")
