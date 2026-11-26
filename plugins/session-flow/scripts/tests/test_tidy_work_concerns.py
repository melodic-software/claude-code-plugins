from __future__ import annotations

import ast
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
del _leaked_git_var

_TESTS_DIR = Path(__file__).resolve().parent
if str(_TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(_TESTS_DIR))

from test_tidy_work import (  # noqa: E402
    HANDOFF_STALE,
    HOME_HANDOFF,
    SCRIPT,
    SHIPPED,
    STATE,
    age,
    build,
    clean,
    handoff,
    links,
    report,
    run_cli,
    run_tidy,
    three_chain,
    write,
)


@pytest.fixture
def env(tmp_path: Path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    home.mkdir()
    repo.mkdir()
    subprocess.run(
        ["git", "-c", "init.defaultBranch=main", "init", "-q", str(repo)], check=True
    )
    write(repo / ".work" / ".gitignore", "*\n")
    return tmp_path, home, repo


def test_a_stray_file_in_the_archive_dir_is_unknown_and_kept(env):
    archive = three_chain(env)
    write(archive.parent / "notes.txt", "stray")
    age(archive.parent / "notes.txt", 60)
    items = report(env, *links(env[0], STATE))
    assert items["notes.txt"]["kind"] == "unknown"


def test_tidy_work_imports_zero_private_save_point_symbols():
    tree_ast = ast.parse(SCRIPT.read_text(encoding="utf-8"), filename=str(SCRIPT))
    private_refs: list[str] = []
    for node in ast.walk(tree_ast):
        if isinstance(node, ast.ImportFrom) and node.module == "save_point":
            for alias in node.names:
                if alias.name.startswith("_"):
                    private_refs.append(f"from save_point import {alias.name}")
        elif (
            isinstance(node, ast.Attribute)
            and isinstance(node.value, ast.Name)
            and node.value.id == "save_point"
            and node.attr.startswith("_")
        ):
            private_refs.append(f"save_point.{node.attr}")
    assert private_refs == [], f"private save_point imports/refs remain: {private_refs}"


def test_double_star_self_ignore_guard_accepted_uniformly(env):
    tmp, _, repo = env
    outside = tmp / "outside-ds"
    write(outside / ".gitignore", "**\n")
    write(outside / "notes.txt", "x")
    res = run_cli(env, "--json", "--offline", "--memory-dir", str(outside))
    assert res.returncode == 0, res.stderr

    write(repo / ".work" / ".gitignore", "**\n")
    handoff(repo / ".work" / "handoffs" / HANDOFF_STALE, SHIPPED)
    age(repo / ".work" / "handoffs" / HANDOFF_STALE, 60)
    clean_res = clean(env, "--apply")
    assert clean_res.returncode == 0, clean_res.stderr
    assert not (repo / ".work" / "handoffs" / HANDOFF_STALE).exists()


def test_concern_dirs_include_built_in_skill_directories(monkeypatch):
    monkeypatch.syspath_prepend(str(SCRIPT.parent))
    import tidy_work

    expected = {
        "reviews",
        "exports",
        "overengineering",
        "enforceability",
        "docs-hygiene",
        "lanes",
        "coupling",
        "recommend-skills",
        "testing",
        "testing-cleanup",
        "testing-cleanup-plan",
    }
    assert expected.issubset(set(tidy_work.CONCERN_DIRS))


def test_extra_concern_dirs_from_cli_and_convention_home_yaml(env):
    _, _, repo = env
    work = repo / ".work"
    write(
        repo / "docs" / "conventions" / "session-flow.yaml",
        "extra_concern_dirs:\n  - team-scratch\n",
    )
    write(work / "team-scratch" / "run-1.md", "keep")
    write(work / "cli-concern" / "item.json", "{}")
    age(work / "team-scratch", 60)
    age(work / "cli-concern", 60)

    items = report(env, "--offline", "--extra-concern-dir", "cli-concern")
    assert items["run-1.md"]["kind"] == "concern"
    assert items["run-1.md"]["keep"]
    assert items["item.json"]["kind"] == "concern"
    assert items["item.json"]["keep"]

    bad = run_cli(env, "--offline", "--extra-concern-dir", "bad/name")
    assert bad.returncode == 2


def test_git_clone_classified_kept_and_skips_git_objects_walk(env, monkeypatch):
    _, _, repo = env
    work = repo / ".work"
    clone = work / "throwaway-clone"
    write(clone / ".git" / "HEAD", "ref: refs/heads/main\n")
    write(clone / ".git" / "objects" / "ab" / "cdef1234", "object-bytes")
    write(clone / "README.md", "hello")
    age(clone, 60)

    wt = work / "linked-wt"
    write(wt / ".git", "gitdir: /some/where/.git/worktrees/linked-wt\n")
    write(wt / "file.txt", "work")
    age(wt, 60)

    items = report(env, "--offline")
    assert items["throwaway-clone"]["kind"] == "git-clone"
    assert items["throwaway-clone"]["keep"]
    assert items["linked-wt"]["kind"] == "git-clone"
    assert items["linked-wt"]["keep"]

    text_out = run_cli(env, "--offline").stdout
    assert "git clone" in text_out.lower()

    clean_res = run_tidy(env, "clean", "--offline", "--apply")
    assert clean_res.returncode == 0
    assert clone.exists() and wt.exists()

    monkeypatch.syspath_prepend(str(SCRIPT.parent))
    import tidy_work

    walked_bases: list[str] = []
    real_walk = os.walk

    def spy_walk(top, *args, **kwargs):
        for base, dirs, files in real_walk(top, *args, **kwargs):
            walked_bases.append(base)
            yield base, dirs, files

    monkeypatch.setattr(tidy_work.os, "walk", spy_walk)
    tidy_work._tree_stats(clone)
    assert not any("objects" in Path(b).parts for b in walked_bases), walked_bases


def test_recovery_archive_files_and_dirs_classified_and_kept(env):
    _, _, repo = env
    work = repo / ".work"
    for name in ("rescue.bundle", "snap.tar.gz", "export.tgz", "dump.zip"):
        write(work / name, "archive-bytes")
        age(work / name, 60)
    write(work / "backup-dir" / "old.bundle", "bundle-bytes")
    age(work / "backup-dir", 60)

    items = report(env, "--offline")
    for name in (
        "rescue.bundle",
        "snap.tar.gz",
        "export.tgz",
        "dump.zip",
        "backup-dir",
    ):
        assert items[name]["kind"] == "recovery-archive", name
        assert items[name]["keep"], name

    text_out = run_cli(env, "--offline").stdout
    assert "recovery archive" in text_out.lower()

    clean_res = run_tidy(env, "clean", "--offline", "--apply")
    assert clean_res.returncode == 0
    for name in (
        "rescue.bundle",
        "snap.tar.gz",
        "export.tgz",
        "dump.zip",
        "backup-dir",
    ):
        assert (work / name).exists(), name


def test_scope_filters_roots_between_all_repo_and_home(env):
    build(env)
    tmp, _, _ = env

    repo_only = json.loads(
        run_cli(env, "--json", "--offline", "--scope", "repo").stdout
    )
    assert [r["label"] for r in repo_only["roots"]] == ["memory"]
    assert all(i["root"] == "memory" for i in repo_only["items"])

    home_only = json.loads(
        run_cli(env, "--json", "--offline", "--scope", "home").stdout
    )
    assert [r["label"] for r in home_only["roots"]] == ["home"]
    assert [Path(i["path"]).name for i in home_only["items"]] == [HOME_HANDOFF]

    outside = tmp / "not-a-repo"
    outside.mkdir()
    res = run_cli(env, "--json", "--offline", "--scope", "home", cwd=outside)
    assert res.returncode == 0, res.stderr
    payload = json.loads(res.stdout)
    assert [r["label"] for r in payload["roots"]] == ["home"]


def test_home_running_retros_repo_qualified_attribution(env):
    _, home, _ = env
    retros = home / ".work" / "running-retros"
    fm_retro = "20260101T100000Z-running-retro-auth.md"
    hdr_retro = "20260102T100000Z-running-retro-deploy.md"
    write(
        retros / fm_retro,
        "---\ntype: running-retro\nrepo: melodic-software/claude-code-plugins\n---\n\nShipped in #42.\n",
    )
    write(
        retros / hdr_retro,
        "---\ntype: running-retro\n---\n\n# Running retro ledger — melodic-software/dotfiles\n\nFixed #7.\n",
    )
    age(retros, 60)

    table = {
        "melodic-software/claude-code-plugins#42": "merged",
        "melodic-software/dotfiles#7": "closed",
    }
    items = report(env, "--scope", "home", *links(env[0], table))
    assert items[fm_retro]["links"] == {
        "melodic-software/claude-code-plugins#42": "merged"
    }
    assert not items[fm_retro]["keep"]
    assert items[hdr_retro]["links"] == {"melodic-software/dotfiles#7": "closed"}
    assert not items[hdr_retro]["keep"]
