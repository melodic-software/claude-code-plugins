#!/usr/bin/env python3
"""Suite for asr_transcribe.add_nvidia_dll_directories over a temporary site-packages.

Run: python test_asr_transcribe.py
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "asr_transcribe", HERE / "asr_transcribe.py"
)
asr_transcribe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(asr_transcribe)


class AddNvidiaDllDirectoriesCase(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="asr-dll-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.site = self.root / "site-packages"
        (self.site / "nvidia" / "cublas" / "bin").mkdir(parents=True)
        (self.site / "nvidia" / "cudnn" / "bin").mkdir(parents=True)
        (self.site / "nvidia" / "nobin").mkdir(parents=True)
        (self.site / "nvidia" / "filebin").mkdir(parents=True)
        (self.site / "nvidia" / "filebin" / "bin").write_text("not a directory\n")
        self.plain = self.root / "plain"
        self.plain.mkdir()

    def run_on(self, platform):
        added = []
        with (
            mock.patch.object(sys, "platform", platform),
            mock.patch.object(sys, "path", [str(self.plain), str(self.site)]),
            mock.patch.object(os, "add_dll_directory", added.append, create=True),
        ):
            asr_transcribe.add_nvidia_dll_directories()
        return added

    def test_windows_adds_each_existing_nvidia_bin_directory(self):
        self.assertEqual(
            self.run_on("win32"),
            [
                str(self.site / "nvidia" / "cublas" / "bin"),
                str(self.site / "nvidia" / "cudnn" / "bin"),
            ],
        )

    def test_other_platforms_add_nothing(self):
        for platform in ("linux", "darwin"):
            with self.subTest(platform=platform):
                self.assertEqual(self.run_on(platform), [])


if __name__ == "__main__":
    unittest.main()
