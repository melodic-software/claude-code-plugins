#!/usr/bin/env python3
"""Behavioral tests for the python3 App-Execution-Alias stub probe.

The probe exists so ``/disk-hygiene:setup check`` can FAIL cleanly when the
guard's launch name (``python3``) resolves to the zero-length WindowsApps alias
stub — a fail-open vector, because a guard that never runs emits neither exit 2
nor a ``deny`` decision and so cannot block a destructive tool call. The stub
signal (WindowsApps path component + zero length) is fabricated here so the
detection is exercised cross-platform, without needing a real Windows box or
executing anything.
"""

from __future__ import annotations

import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


probe = load_module("python3_alias_probe", "python3_alias_probe.py")


class ProbeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def make_file(self, relative: str, size: int) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "wb") as handle:
            if size:
                handle.write(b"\0" * size)
        return path

    def run_probe(self, argv: list[str]) -> dict[str, object]:
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(0, probe.main(argv))
        return json.loads(stdout.getvalue())

    def test_zero_length_windowsapps_stub_is_detected(self) -> None:
        stub = self.make_file("Microsoft/WindowsApps/python3.exe", 0)
        result = self.run_probe(["--path", str(stub)])
        self.assertEqual("store-alias-stub", result["verdict"])
        self.assertTrue(result["windowsapps"])
        self.assertEqual(0, result["size"])
        self.assertIn("guard", result["detail"].lower())

    def test_windowsapps_component_match_is_case_insensitive(self) -> None:
        stub = self.make_file("Microsoft/WINDOWSAPPS/python3.exe", 0)
        result = self.run_probe(["--path", str(stub)])
        self.assertEqual("store-alias-stub", result["verdict"])

    def test_real_interpreter_under_windowsapps_is_ok(self) -> None:
        # The Microsoft Store's genuine Python lives under a versioned WindowsApps
        # subdirectory and has a non-zero size — it must not be flagged as the stub.
        real = self.make_file(
            "Microsoft/WindowsApps/PythonSoftwareFoundation.Python.3.12_x/python3.exe",
            2048,
        )
        result = self.run_probe(["--path", str(real)])
        self.assertEqual("ok", result["verdict"])
        self.assertTrue(result["windowsapps"])
        self.assertEqual(2048, result["size"])

    def test_zero_length_outside_windowsapps_is_ok(self) -> None:
        # Zero length alone is not the signal; the WindowsApps component is required.
        empty = self.make_file("bin/python3", 0)
        result = self.run_probe(["--path", str(empty)])
        self.assertEqual("ok", result["verdict"])
        self.assertFalse(result["windowsapps"])

    def test_ordinary_interpreter_is_ok(self) -> None:
        real = self.make_file("usr/local/bin/python3", 4096)
        result = self.run_probe(["--path", str(real)])
        self.assertEqual("ok", result["verdict"])

    def test_missing_path_reports_not_found(self) -> None:
        with mock.patch.object(probe, "resolve", return_value=None):
            result = self.run_probe([])
        self.assertEqual("not-found", result["verdict"])
        self.assertIsNone(result["resolved_path"])

    def test_resolve_is_used_when_no_path_given(self) -> None:
        real = self.make_file("opt/python3", 512)
        with mock.patch.object(probe, "resolve", return_value=real):
            result = self.run_probe([])
        self.assertEqual("ok", result["verdict"])
        self.assertEqual(str(real), result["resolved_path"])

    def test_stat_failure_under_windowsapps_is_indeterminate(self) -> None:
        # An interpreter whose identity cannot be read is uncertainty about the
        # guard's own launch; the verdict must not be "ok" (which would pass), so
        # the skill fails closed on it.
        candidate = self.root / "Microsoft" / "WindowsApps" / "python3.exe"
        with mock.patch.object(probe.Path, "stat", side_effect=OSError("denied")):
            result = self.run_probe(["--path", str(candidate)])
        self.assertEqual("indeterminate", result["verdict"])
        self.assertTrue(result["windowsapps"])
        self.assertNotEqual("ok", result["verdict"])

    def test_stat_failure_outside_windowsapps_is_indeterminate(self) -> None:
        candidate = self.root / "bin" / "python3"
        with mock.patch.object(probe.Path, "stat", side_effect=OSError("denied")):
            result = self.run_probe(["--path", str(candidate)])
        self.assertEqual("indeterminate", result["verdict"])
        self.assertFalse(result["windowsapps"])

    def test_probe_never_executes_the_candidate(self) -> None:
        # Inspect-before-execute: detecting the stub must not run it (which would
        # pop the Store or hang). Guard against any subprocess use in the probe.
        stub = self.make_file("Microsoft/WindowsApps/python3.exe", 0)
        with mock.patch("subprocess.run", side_effect=AssertionError("executed")), \
                mock.patch("subprocess.Popen", side_effect=AssertionError("executed")):
            result = self.run_probe(["--path", str(stub)])
        self.assertEqual("store-alias-stub", result["verdict"])


if __name__ == "__main__":
    unittest.main()
