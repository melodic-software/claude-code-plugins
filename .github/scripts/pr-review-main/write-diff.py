"""Write the main-run review's patch for BASE...HEAD of a repository.

usage: write-diff.py <repo> <base-sha> <head-sha> <out-file>

A file moved unchanged (git's 100% similarity) prints as its `rename from` and
`rename to` lines alone, so a pull request of pure moves stays inside the
review's size cap. Every other change prints whole, as `--no-renames` shows
it: an edited rename as a delete and an add, and a move into or out of a lane
source (babysit_review_evidence.lane_source, the gate's own predicate) or one
that changes the file mode as its old file deleted and its new file added,
so the reviewer reads what the lane source holds. `--text` shows a file git
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


def git(repo: str, *args: str) -> bytes:
    return subprocess.run(
        ["git", "-C", repo, *args], check=True, stdout=subprocess.PIPE
    ).stdout


def whole_paths(raw: bytes) -> list[str]:
    """The paths of each exact rename in `git diff --raw -z -M100%` output that
    must print whole: a lane source on either side, or a mode change."""
    fields = raw.split(b"\0")
    paths: list[str] = []
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
                or ev.lane_source(src)
                or ev.lane_source(dst)
            ):
                paths += [src, dst]
        else:
            i += 2
    return paths


def write_diff(repo: str, base: str, head: str) -> bytes:
    commits = f"{base}...{head}"
    whole = whole_paths(
        git(repo, "diff", "--raw", "-z", "-M100%", "--no-ext-diff", commits)
    )
    patch = git(
        repo, *DIFF, "-M100%", commits, "--", *(f":(exclude,literal){p}" for p in whole)
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
    return patch


if __name__ == "__main__":
    repo, base, head, out = sys.argv[1:5]
    Path(out).write_bytes(write_diff(repo, base, head))
