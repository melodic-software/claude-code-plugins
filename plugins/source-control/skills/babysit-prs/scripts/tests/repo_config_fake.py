"""A fake `gh` for the per-repository config read, shared by the engine tests.

Every script that resolves the ten policy keys reads the target repository's
`.claude/source-control.md` through `babysit_repo_config`. A test that reaches
that read installs `RepoConfigFake` so no real gh process runs and the
per-process cache never carries one test's view into the next.
"""

from __future__ import annotations

import base64
import json
import pathlib
import subprocess
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_repo_config as rc

NOT_FOUND = 404


def file_response(text: str) -> subprocess.CompletedProcess[str]:
    body = {
        "type": "file",
        "encoding": "base64",
        "content": base64.encodebytes(text.encode()).decode(),
    }
    return subprocess.CompletedProcess([], 0, json.dumps(body), "")


def http_error(status: int) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess([], 1, "", f"gh: request failed (HTTP {status})")


class RepoConfigFake:
    """Maps `owner/repo` to file text, or to an HTTP status int for a failure.

    A repository absent from the map has no config file (404 on the file, a
    readable root), so a test that does not care about repository config sees
    only its `userConfig` flags. A repository mapped to 404 is hidden from the
    token: the root listing answers 404 as well.
    """

    def __init__(self, files: dict[str, str | int] | None = None) -> None:
        self.files = {repo.casefold(): value for repo, value in (files or {}).items()}
        self.calls: list[list[str]] = []

    def __call__(self, args: list[str]) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)
        repo = "/".join(args[1].split("/")[1:3]).casefold()
        if args[1].endswith("/contents"):
            if self.files.get(repo) == NOT_FOUND:
                return http_error(NOT_FOUND)
            return subprocess.CompletedProcess([], 0, "[]", "")
        value = self.files.get(repo, NOT_FOUND)
        if isinstance(value, int):
            return http_error(value)
        return file_response(value)

    def install(self, case: unittest.TestCase) -> RepoConfigFake:
        rc.reset_cache()
        patcher = mock.patch.object(rc, "gh_capture", self)
        patcher.start()
        case.addCleanup(patcher.stop)
        case.addCleanup(rc.reset_cache)
        return self
