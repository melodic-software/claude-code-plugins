"""Shared fixture plumbing for the docpage-digest gate suites.

Imported by test_check_fences_exact.py and test_check_snippets.py. A module,
not a suite: it defines no test methods, so importing it adds no cases to the
lane that imports it. Each suite keeps its own entry point because the plugin
gate resolves suites one file at a time.

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))

# Trailing space on KEEP is load-bearing: the hook strips it from a bare code
# span, and a fence must preserve it. The space lives inside the quotes so this
# file has no physical trailing whitespace (editorconfig).
KEEP = "keep me "


def gate_path(name: str) -> str:
    return os.path.join(HERE, name)


def write(dirpath: str, name: str, text: str) -> str:
    path = os.path.join(dirpath, name)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return path


class GateTestCase(unittest.TestCase):
    """Temp-dir fixture plus gate invocation for one gate script.

    A suite subclasses this once, setting ``gate`` to the script under test and
    ``source_text`` to the immutable source every case quotes from.
    """

    gate = ""
    source_text = ""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.source = write(self.dir, "source.md", self.source_text)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def invoke_argv(self, *args: str):
        return subprocess.run(
            [sys.executable, self.gate, *args],
            capture_output=True,
        )

    def invoke(self, source: str, digest: str):
        return self.invoke_argv("--source", source, "--digest", digest)

    def run_gate(self, digest_text: str, expect_code: int):
        digest = write(self.dir, "digest.md", digest_text)
        proc = self.invoke(self.source, digest)
        if proc.returncode != expect_code:
            raise AssertionError(
                f"exit {proc.returncode}, expected {expect_code}; "
                f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
            )
        return proc
