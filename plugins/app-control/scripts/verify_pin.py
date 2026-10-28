#!/usr/bin/env python3
"""Check that an integrated app's control-skill folder in its checkout is the pinned commit.

    python3 -I verify_pin.py <checkout> <app> <sha>

Implements "Checkout off the pin" in reference/control-skill.md; that section is the rule. <sha> is
pins.<app> from the including control skill's committed config, or an empty string when unset.
Exit 0: the folder is the pinned one. Exit 1: refused; stderr carries the contract's message and a
`reason:` line naming the first check that failed. Exit 2: usage. Writes nothing into the checkout.
"""

import os
import re
import subprocess
import sys

SHA = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")
APP = re.compile(r"[A-Za-z0-9_-][A-Za-z0-9._-]*")
ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


class Refused(Exception):
    pass


def git(top, *args, stdin=None):
    return subprocess.run(
        [
            "git",
            "--no-replace-objects",
            "--literal-pathspecs",
            "-C",
            top,
            "-c",
            "core.fsmonitor=false",
            *args,
        ],
        input=stdin,
        capture_output=True,
        env=ENV,
        check=False,
    )


def git_ok(top, *args, stdin=None, why):
    res = git(top, *args, stdin=stdin)
    if res.returncode != 0:
        raise Refused(why)
    return res.stdout


def records(out):
    return [r for r in out.split(b"\0") if r]


def show(path):
    return os.fsdecode(path).encode("unicode_escape").decode("ascii")


def walk(root, rel):
    """Yield (relative path, absolute path) of every non-directory entry, never following a link."""
    with os.scandir(root) as it:
        for entry in it:
            sub = rel + b"/" + entry.name
            if entry.is_dir(follow_symlinks=False):
                yield from walk(entry.path, sub)
            else:
                yield sub, entry.path


def check(checkout, app, sha):
    if not APP.fullmatch(app):
        raise Refused(f"app name {show(os.fsencode(app))} is not a folder name")
    if not os.path.isdir(checkout):
        raise Refused("the checkout is not a directory")
    top = os.path.realpath(checkout)
    shown = git_ok(
        top, "rev-parse", "--show-toplevel", why="the checkout is not a git checkout"
    )
    if os.path.realpath(os.fsdecode(shown.rstrip(b"\n"))) != top:
        raise Refused("the checkout is not the top of its repository")
    rel_dir = os.fsencode(f".claude/skills/control-{app}")
    abs_dir = os.path.join(os.fsencode(top), rel_dir)
    if not os.path.isdir(abs_dir) or os.path.realpath(abs_dir) != abs_dir:
        raise Refused(f"{show(rel_dir)} is missing or passes through a symlink")
    pathspec = rel_dir.decode() + "/"

    git_ok(
        top,
        "cat-file",
        "-e",
        "--end-of-options",
        f"{sha}^{{commit}}",
        why="the pin is not a commit in the checkout's object store",
    )

    diff = git(
        top,
        "diff",
        "--quiet",
        "--no-ext-diff",
        "--no-textconv",
        "--end-of-options",
        sha,
        "HEAD",
        "--",
        pathspec,
    )
    if diff.returncode == 1:
        raise Refused(f"HEAD differs from the pin in {pathspec}")
    if diff.returncode != 0:
        raise Refused("git diff against HEAD failed")

    for rec in records(
        git_ok(top, "ls-files", "-v", "-z", "--", pathspec, why="git ls-files failed")
    ):
        tag, _, path = rec.partition(b" ")
        if tag != b"H":
            raise Refused(f"index flag {tag.decode(errors='replace')} on {show(path)}")

    tree = {}
    for rec in records(
        git_ok(
            top,
            "ls-tree",
            "-r",
            "-z",
            "--end-of-options",
            sha,
            "--",
            pathspec,
            why="git ls-tree failed",
        )
    ):
        meta, _, path = rec.partition(b"\t")
        mode, _, oid = meta.split(b" ")
        tree[path] = (mode, oid.decode())

    local_json = rel_dir + b"/config/local.json"
    walked = {}
    for rel, path in walk(abs_dir, rel_dir):
        walked[rel] = path
        if rel == local_json:
            continue
        if rel not in tree:
            raise Refused(f"untracked or ignored {show(rel)}")
        mode, oid = tree[rel]
        if mode == b"120000":
            text = git_ok(top, "cat-file", "blob", oid, why="git cat-file failed")
            if not os.path.islink(path) or os.readlink(path) != text:
                raise Refused(f"symlink {show(rel)} does not match the pin")
            try:
                target = os.path.realpath(path, strict=True)
            except OSError:
                raise Refused(f"symlink {show(rel)} does not resolve") from None
            if os.path.commonpath([target, abs_dir]) != abs_dir:
                raise Refused(f"symlink {show(rel)} resolves outside the folder")
            continue
        if os.path.islink(path) or not os.path.isfile(path):
            raise Refused(f"{show(rel)} is not a regular file")
        with open(path, "rb") as f:
            data = f.read()
        hashes = [data] if b"\r\n" not in data else [data, data.replace(b"\r\n", b"\n")]
        if not any(
            git_ok(
                top,
                "hash-object",
                "--no-filters",
                "--stdin",
                stdin=d,
                why="git hash-object failed",
            )
            .strip()
            .decode()
            == oid
            for d in hashes
        ):
            raise Refused(f"{show(rel)} differs from the pin")

    for path, (mode, _) in tree.items():
        if mode != b"160000" and path not in walked:
            raise Refused(f"missing {show(path)}")

    paths = sorted(set(tree) | set(walked))
    out = git_ok(
        top,
        "check-attr",
        "--stdin",
        "-z",
        "filter",
        stdin=b"".join(p + b"\0" for p in paths),
        why="git check-attr failed",
    )
    fields = records(out)
    for i in range(0, len(fields) - 2, 3):
        if fields[i + 2] != b"unspecified":
            raise Refused(f"{show(fields[i])} has a filter attribute")


def main(argv):
    if len(argv) != 4:
        print("usage: verify_pin.py <checkout> <app> <sha>", file=sys.stderr)
        return 2
    checkout, app, sha = argv[1:]
    setting = f"pins.{app}"
    if not sha:
        print(
            f"{setting} is unset: commit {setting}, for example through /app-control:map",
            file=sys.stderr,
        )
        return 1
    try:
        if not SHA.fullmatch(sha):
            raise Refused("not 40 or 64 lowercase hex characters")
        check(checkout, app, sha)
    except Refused as why:
        print(
            f"{setting} {show(os.fsencode(sha))}: fetch or check out", file=sys.stderr
        )
        print(f"reason: {why}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
