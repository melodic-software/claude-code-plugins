"""Contract tests for American spelling in what `fill`, `amend` and the away report write.

The stub `typos` replays the JSON line shape typos-cli 1.52.2 prints for
`typos --locale en-us --format json -` (one object per finding: type, path,
line_num, byte_offset in UTF-8 bytes, typo, corrections) and reports only when
called with `--locale en-us`. Its two British forms and their American
corrections are the ones real typos 1.52.2 gives for them under that locale.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import pytest
from test_away import Away
from test_save_point import err, make_repo, out, run
from test_save_point_shape4_writer import body, fill, new

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import dialect  # noqa: E402

UK_COLOR, UK_MODELED = "colour", "modelled"  # spellchecker:disable-line
AMERICAN = {UK_COLOR: "color", UK_MODELED: "modeled"}

STUB = f"""\
import json, re, sys
WORDS = {AMERICAN!r}
if sys.argv[1:3] != ["--locale", "en-us"]:
    sys.exit(0)
found = False
for number, line in enumerate(sys.stdin.buffer.read().split(b"\\n"), 1):
    for match in re.finditer(rb"[A-Za-z]+", line):
        word = match.group().decode()
        if word in WORDS:
            found = True
            print(json.dumps({{"type": "typo", "path": "-", "line_num": number,
                              "byte_offset": match.start(), "typo": word, "corrections": [WORDS[word]]}}))
sys.exit(2 if found else 0)
"""

pytestmark = pytest.mark.skipif(os.name == "nt", reason="the stub typos is a shebang script")


def bin_dir(root: Path, name: str, typos: bool) -> str:
    """A PATH holding git and, when `typos`, the stub typos."""
    folder = root / name
    folder.mkdir()
    (folder / "git").symlink_to(shutil.which("git"))
    if typos:
        stub = folder / "typos"
        stub.write_text(f"#!{sys.executable}\n{STUB}", encoding="utf-8")
        stub.chmod(0o755)
    return str(folder)


@pytest.fixture
def stub_path(tmp_path: Path) -> str:
    return bin_dir(tmp_path, "stub-bin", typos=True)


@pytest.fixture
def bare_path(tmp_path: Path) -> str:
    return bin_dir(tmp_path, "bare-bin", typos=False)


def test_an_authored_line_comes_back_american(stub_path, monkeypatch):
    monkeypatch.setenv("PATH", stub_path)
    text, applied = dialect.americanize(f"─ We {UK_MODELED} the {UK_COLOR} — twice.")
    assert text == "─ We modeled the color — twice."
    assert applied == [(UK_MODELED, "modeled"), (UK_COLOR, "color")]


def test_quoted_code_blockquote_and_path_text_keeps_its_spelling(stub_path, monkeypatch):
    monkeypatch.setenv("PATH", stub_path)
    quoted = (
        f'The owner said "the {UK_COLOR} stays" and `{UK_COLOR}` is a key.\n'
        f"> keep the {UK_COLOR}\n"
        f"```\n{UK_COLOR}\n```\n"
        f"See docs/{UK_COLOR}.md and {UK_COLOR}.json."
    )
    assert dialect.americanize(quoted) == (quoted, [])


def test_no_typos_on_path_leaves_the_text_and_prints_nothing(bare_path, monkeypatch, capsys):
    monkeypatch.setenv("PATH", bare_path)
    line = f"We {UK_MODELED} the {UK_COLOR}."
    assert dialect.americanize(line) == (line, [])
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
            "brief": f"We {UK_MODELED} the {UK_COLOR} pass on `main`; read Current rules first.",
            "trail": f'- [h1] start: the {UK_COLOR} pass (owner-directed, "keep the {UK_COLOR}").',
            "opening-ask": f"Fix the {UK_COLOR} of the banner please.",
        },
    )
    assert filled.returncode == 0, err(filled) + out(filled)
    assert "We modeled the color pass on `main`" in body(path, "Resumption brief")
    assert f'- [h1] start: the color pass (owner-directed, "keep the {UK_COLOR}").' in body(path, "Direction changes")
    assert f"Fix the {UK_COLOR} of the banner please." in body(path, "Original goal")
    assert f"NOTE: slot 'brief': '{UK_MODELED}' written as 'modeled' (American spelling)" in err(filled)


def test_fill_without_typos_writes_the_values_as_given(tmp_path, bare_path, monkeypatch):
    path = made(tmp_path)
    monkeypatch.setenv("PATH", bare_path)
    filled = fill(path, tmp_path, {"brief": f"We {UK_MODELED} the {UK_COLOR} pass; read Current rules first."})
    assert filled.returncode == 0, err(filled) + out(filled)
    assert f"We {UK_MODELED} the {UK_COLOR} pass" in body(path, "Resumption brief")
    assert "American spelling" not in err(filled)


def test_amend_writes_next_lines_american(tmp_path, stub_path, monkeypatch):
    path = made(tmp_path)
    assert fill(path, tmp_path).returncode == 0
    payload = tmp_path / "amend.json"
    payload.write_text(f'{{"next": ["Finish the {UK_COLOR} pass"]}}', encoding="utf-8")
    monkeypatch.setenv("PATH", stub_path)
    amended = run("amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z")
    assert amended.returncode == 0, err(amended) + out(amended)
    assert "Finish the color pass" in path.read_text(encoding="utf-8")


DONE = f'## Done\n\n- We {UK_MODELED} the {UK_COLOR} pass.\n- Kept "the {UK_COLOR} stays".\n> keep the {UK_COLOR}\n\n'


def away_with_done(tmp_path: Path) -> Away:
    ctx = Away(tmp_path)
    ctx.start("--kind", "trip", "--scope", f"the {UK_COLOR} pass")
    report = ctx.report()
    text = report.read_text(encoding="utf-8")
    report.write_text(text[: text.index("## Done")] + DONE + text[text.index("## Found") :], encoding="utf-8")
    return ctx


def test_away_refresh_writes_its_sections_american_and_keeps_quotes_and_header(tmp_path, stub_path):
    ctx = away_with_done(tmp_path)
    assert ctx.cli("refresh", env=ctx.env(PATH=stub_path)).returncode == 0
    text = ctx.report().read_text(encoding="utf-8")
    assert "- We modeled the color pass." in text
    assert f'"the {UK_COLOR} stays"' in text and f"> keep the {UK_COLOR}" in text
    assert f"- Scope: the {UK_COLOR} pass" in text


def test_away_refresh_without_typos_leaves_the_report_as_written(tmp_path, bare_path):
    ctx = away_with_done(tmp_path)
    assert ctx.cli("refresh", env=ctx.env(PATH=bare_path)).returncode == 0
    assert DONE in ctx.report().read_text(encoding="utf-8")
