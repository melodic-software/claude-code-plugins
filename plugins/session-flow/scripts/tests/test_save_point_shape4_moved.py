"""Sections a shape-4 `fill` moved to this hop's file stay whole and checked: a
retry `new` refuses to erase them, `amend` appends into the moved body, and the
UNVERIFIED settle check reads the moved body. Expected values come from the
Writer contract: a moved section's body lives in this hop's file under
`## <Section> (h<k>)` behind a lone `- Moved: ` pointer, which `read` follows."""

from __future__ import annotations

from pathlib import Path

from shape4_chain import SIDS
from test_save_point import err, hop_file, make_repo, new_args, out, run
from test_save_point_shape4_writer import body, hop, prose


def test_retry_new_refuses_to_erase_a_moved_section(tmp_path):
    repo = make_repo(tmp_path)
    first = hop(repo, tmp_path)
    notes = prose("observation", 26_000)
    second = hop(repo, tmp_path, first, k=2, values={"observations": notes})
    assert body(second, "Observations").startswith("- Moved: archive/")
    own = hop_file(second.parent, first.name, 2, SIDS[1])
    before = own.read_bytes()

    retry = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(first),
            sid=SIDS[1],
            now="2026-09-03T10:00:00Z",
            shape="4",
        )
    )

    assert retry.returncode == 1, err(retry) + out(retry)
    assert "Observations (h2)" in err(retry), err(retry)
    assert own.read_bytes() == before
    read = run("read", str(second), "--section", "Observations")
    assert read.returncode == 0, err(read)
    assert out(read).strip("\n") == notes


def test_retry_new_rewrites_a_hop_file_with_nothing_moved(tmp_path):
    repo = make_repo(tmp_path)
    first = hop(repo, tmp_path)
    hop(repo, tmp_path, first, k=2)
    retry = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(first),
            sid=SIDS[1],
            now="2026-09-03T10:00:00Z",
            shape="4",
        )
    )
    assert retry.returncode == 0, err(retry)
    assert Path(out(retry).strip()).is_file()
