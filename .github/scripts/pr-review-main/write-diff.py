"""Write the main-run review's patch for BASE...HEAD of a repository.

usage: write-diff.py <repo> <base-sha> <head-sha> <out-file> <max-bytes>

The patch is `--no-renames`, so every file prints whole, unless that patch is
over max-bytes, the review's size cap. Then a file moved unchanged (git's 100%
similarity) prints as its `rename from` and `rename to` lines alone, so a pull
request of pure moves fits, and every other change still prints whole. A move
prints whole even then when the reviewer could not judge it from the other
changes: a move into or out of a lane source
(babysit_review_evidence.lane_source, the gate's own predicate), one that
changes the file mode or moves a symlink or a submodule, and one whose new
path (or its last directory and name) an added line of the patch names, so a
change that runs a moved file shows what it runs. `--text` shows a file git
would call binary as text, and no attribute, diff driver or textconv in the
repository runs. The caller applies its binary, size and line caps to the
result.
"""

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(
    0,
    str(
        Path(__file__).resolve().parents[3]
        / "plugins/source-control/skills/babysit-prs/scripts"
    ),
)
import babysit_review_evidence as ev  # noqa: E402

DIFF = ["diff", "--text", "--no-ext-diff", "--no-textconv", "--no-color"]
# A symlink's or a submodule's mode: the rename lines show neither target.
LINK_MODES = {"120000", "160000"}
# A move that may run or load: an executable, a path under a directory a
# plugin or Claude Code loads from, or a file such a tool reads by its name.
EXEC_MODE = "100755"
LOADED_SEGMENTS = {"skills", "agents", "commands", "hooks"}
LOADED_NAMES = {
    "SKILL.md",
    "hooks.json",
    "plugin.json",
    "marketplace.json",
    "conftest.py",
    "__init__.py",
    "settings.json",
}


def loaded(mode: str, path: str) -> bool:
    parts = path.split("/")
    return (
        mode == EXEC_MODE
        or bool(LOADED_SEGMENTS.intersection(parts[:-1]))
        or parts[-1] in LOADED_NAMES
    )


def git(repo: str, *args: str) -> bytes:
    return subprocess.run(
        ["git", "-C", repo, *args], check=True, stdout=subprocess.PIPE
    ).stdout


def renames(raw: bytes) -> tuple[list[str], list[tuple[str, str]]]:
    """From `git diff --raw -z -M100%` output, the paths of each rename that
    must print whole, and the pure moves that may collapse."""
    fields = raw.split(b"\0")
    whole: list[str] = []
    moves: list[tuple[str, str]] = []
    i = 0
    while i < len(fields) and fields[i]:
        old_mode, new_mode, _, _, status = (
            fields[i].decode("ascii").lstrip(":").split(" ")
        )
        if status[0] in "RC":
            src, dst = (os.fsdecode(f) for f in fields[i + 1 : i + 3])
            i += 3
            if (
                status != "R100"
                or old_mode != new_mode
                or {old_mode, new_mode} & LINK_MODES
                or loaded(old_mode, src)
                or loaded(new_mode, dst)
                or ev.lane_source(src)
                or ev.lane_source(dst)
            ):
                whole += [src, dst]
            else:
                moves.append((src, dst))
        else:
            i += 2
    return whole, moves


def named(path: str, added: bytes) -> bool:
    """Whether an added line names `path`, its last directory and name, its
    name, or its name without the extension. Matching too much only prints
    more."""
    name = path.split("/")[-1]
    forms = {path, "/".join(path.split("/")[-2:]), name, name.rsplit(".", 1)[0]}
    return any(form and os.fsencode(form) in added for form in forms)


def write_diff(repo: str, base: str, head: str, max_bytes: int) -> bytes:
    commits = f"{base}...{head}"
    plain = git(repo, *DIFF, "--no-renames", commits)
    if len(plain) <= max_bytes:
        return plain
    whole, moves = renames(
        git(repo, "diff", "--raw", "-z", "-M100%", "--no-ext-diff", commits)
    )
    while True:
        patch = git(
            repo,
            *DIFF,
            "-M100%",
            commits,
            "--",
            *(f":(exclude,literal){p}" for p in whole),
        )
        if whole:
            patch += git(
                repo,
                *DIFF,
                "--no-renames",
                commits,
                "--",
                *(f":(literal){p}" for p in whole),
            )
        # Every `+` line, file headers too: a content line can look like one.
        added = b"\n".join(line for line in patch.split(b"\n") if line.startswith(b"+"))
        # A move printed whole adds lines, which may name another move.
        shown = [move for move in moves if named(move[1], added)]
        if not shown:
            return patch
        for move in shown:
            moves.remove(move)
            whole += list(move)


if __name__ == "__main__":
    repo, base, head, out, max_bytes = sys.argv[1:6]
    Path(out).write_bytes(write_diff(repo, base, head, int(max_bytes)))
