# test-scope: plugins/session-flow/scripts/tests/fixtures/projects/-work-repo/*.jsonl plugins/session-flow/scripts/away.py plugins/session-flow/scripts/away_files.py plugins/session-flow/scripts/away_launch.py plugins/session-flow/scripts/handoff_chain.py plugins/session-flow/scripts/handoff_fit.py plugins/session-flow/scripts/io_streams.py plugins/session-flow/scripts/plugin_paths.py plugins/session-flow/scripts/save_point.py plugins/session-flow/scripts/tests/shape4_chain.py
"""Contract tests for American spelling in what `fill`, `amend` and the away report write.

The stub `typos` replays the JSON line shape typos-cli 1.52.2 prints for
`typos --locale en-us --format json -` (one object per finding: type, path,
line_num, byte_offset in UTF-8 bytes, typo, corrections) and reports only when
called with `--locale en-us`. Like the repo's typos config, it skips the line
after an ignore-next-line directive. Its two British forms and their American
corrections are the ones real typos 1.52.2 gives for them under that locale.
"""

from __future__ import annotations

import json
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
found = skip = False
for number, line in enumerate(sys.stdin.buffer.read().split(b"\\n"), 1):
    skip, skipped = re.search(rb"#\\s*spellchecker:ignore-next-line", line) is not None, skip
    if skipped:
        continue
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
    text, applied = dialect.americanize(f"─ We {UK_MODELED} the owner's {UK_COLOR} — twice.")
    assert text == "─ We modeled the owner's color — twice."
    assert applied == [(UK_MODELED, "modeled"), (UK_COLOR, "color")]


def test_a_single_quoted_phrase_keeps_its_spelling(stub_path, monkeypatch):
    monkeypatch.setenv("PATH", stub_path)
    quoted = f"He said 'keep the {UK_COLOR}' and ‘the {UK_COLOR}’."
    assert dialect.americanize(quoted) == (quoted, [])


def test_quoted_code_blockquote_and_path_text_keeps_its_spelling(stub_path, monkeypatch):
    monkeypatch.setenv("PATH", stub_path)
    quoted = (
        f'The owner said "the {UK_COLOR} stays" and `{UK_COLOR}` is a key.\n'
        f"Run ``echo `{UK_COLOR}` {UK_COLOR}`` as written.\n"
        f"> keep the {UK_COLOR}\n"
        f"```\n{UK_COLOR}\n```\n"
        f"See docs/{UK_COLOR}.md and {UK_COLOR}.json.\n"
        f"Set {UK_COLOR}_map, set{UK_COLOR.capitalize()} and --{UK_COLOR}."
    )
    assert dialect.americanize(quoted) == (quoted, [])


def test_americanize_all_matches_one_call_per_text_with_one_typos_run(stub_path, monkeypatch):
    monkeypatch.setenv("PATH", stub_path)
    texts = [
        f"```\nan open fence: {UK_COLOR}",
        f"We {UK_MODELED} it.\nThe {UK_COLOR} too.",
        "   ",
        f'"the {UK_COLOR}" stays',
        f"Last {UK_COLOR}, {UK_MODELED}.",
    ]
    one_by_one = [dialect.americanize(text) for text in texts]
    calls = []
    real = dialect.subprocess.run
    monkeypatch.setattr(dialect.subprocess, "run", lambda *a, **k: calls.append(a) or real(*a, **k))
    assert dialect.americanize_all(texts) == one_by_one
    assert len(calls) == 1
    assert one_by_one[1] == ("We modeled it.\nThe color too.", [(UK_MODELED, "modeled"), (UK_COLOR, "color")])
    assert one_by_one[4] == ("Last color, modeled.", [(UK_COLOR, "color"), (UK_MODELED, "modeled")])


IGNORE_NEXT = "# spellchecker" ":ignore-next-line"


def test_americanize_all_keeps_a_directive_from_reaching_the_next_text(stub_path, monkeypatch):
    monkeypatch.setenv("PATH", stub_path)
    texts = [f"Notes\n{IGNORE_NEXT}", f"We {UK_COLOR} it."]
    calls = []
    real = dialect.subprocess.run
    monkeypatch.setattr(dialect.subprocess, "run", lambda *a, **k: calls.append(a) or real(*a, **k))
    assert dialect.americanize_all(texts) == [
        (texts[0], []),
        ("We color it.", [(UK_COLOR, "color")]),
    ]
    assert len(calls) == 2


def test_americanize_all_maps_findings_across_trailing_newlines_and_multiline_texts(stub_path, monkeypatch):
    monkeypatch.setenv("PATH", stub_path)
    texts = [
        f"ends in a newline {UK_MODELED}\n",
        f"{UK_COLOR} first\n",
        "one\ntwo\nthree",
        f"{UK_MODELED} on the first line\nand {UK_COLOR} on the second",
    ]
    assert dialect.americanize_all(texts) == [
        ("ends in a newline modeled\n", [(UK_MODELED, "modeled")]),
        ("color first\n", [(UK_COLOR, "color")]),
        ("one\ntwo\nthree", []),
        ("modeled on the first line\nand color on the second", [(UK_MODELED, "modeled"), (UK_COLOR, "color")]),
    ]


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
            "below-rail": f"Re-arm 1 of 1 — 1 lines:\n/loop 10m check the {UK_COLOR} of the build badge",
        },
    )
    assert filled.returncode == 0, err(filled) + out(filled)
    assert "We modeled the color pass on `main`" in body(path, "Resumption brief")
    assert f'- [h1] start: the color pass (owner-directed, "keep the {UK_COLOR}").' in body(path, "Direction changes")
    assert f"Fix the {UK_COLOR} of the banner please." in body(path, "Original goal")
    assert f"/loop 10m check the {UK_COLOR} of the build badge" in body(path, "Resume prompt")
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


def test_amend_writes_each_value_back_to_its_own_place(tmp_path, stub_path, monkeypatch):
    from test_save_point import hop_file
    from test_save_point_standing_decisions import SIDS, role_hop

    path = role_hop(make_repo(tmp_path), tmp_path)
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps(
            {
                "sections": {"Observations": f"- Alpha {UK_COLOR} observation."},
                "append": {"Direction changes": [f"- [h1] bravo: the owner {UK_MODELED} it (owner-directed)."]},
                "next": [f"Charlie {UK_COLOR} next step"],
                "retire": [{"ref": "[D1]", "reason": f"delta {UK_MODELED} reason"}],
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("PATH", stub_path)
    amended = run("amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z")
    assert amended.returncode == 0, err(amended) + out(amended)
    assert body(path, "Observations") == "- Alpha color observation."
    assert body(path, "Direction changes").endswith("- [h1] bravo: the owner modeled it (owner-directed).")
    assert "Charlie color next step" in body(path, "Resume prompt")
    own = hop_file(path.parent, path.name, 1, SIDS[0]).read_text(encoding="utf-8")
    assert "Retired: delta modeled reason" in own


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
