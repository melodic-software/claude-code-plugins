"""No entry in the gate scripts' directory shadows a standard-library module.

Python runs a script with the script's own directory first on `sys.path`, so a
`json.py` (or a `json/` package, or a compiled `json` module) beside the gate's
Python scripts would load in place of the standard library's. Running the gate with
`-I` or `-P` would also drop that directory, and with it the sibling imports
(`babysit_util`, `babysit_gh` and the rest) the gate relies on, so this suite
keeps the directory free of standard-library names instead.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import pathlib
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
SUFFIXES = tuple(importlib.machinery.all_suffixes())


def stdlib_shadows(directory: pathlib.Path) -> list[str]:
    """The entries of `directory` an import would take for a stdlib module."""
    shadows = []
    for entry in sorted(directory.iterdir()):
        if entry.is_dir():
            name = entry.name
        else:
            suffix = next((s for s in SUFFIXES if entry.name.endswith(s)), None)
            if suffix is None:
                continue
            name = entry.name[: -len(suffix)]
        if name in sys.stdlib_module_names:
            shadows.append(entry.name)
    return shadows


class NoScriptShadowsTheStandardLibrary(unittest.TestCase):
    def test_the_scripts_directory_has_no_stdlib_name(self) -> None:
        self.assertEqual(
            stdlib_shadows(SCRIPTS),
            [],
            f"{SCRIPTS} holds an entry named like a standard-library module;"
            " rename it so the gate imports the real module",
        )

    def test_every_sibling_module_resolves_from_the_scripts_directory(self) -> None:
        sys.path.insert(0, str(SCRIPTS))
        try:
            for script in sorted(SCRIPTS.glob("*.py")):
                with self.subTest(script.name):
                    spec = importlib.util.find_spec(script.stem)
                    self.assertIsNotNone(spec)
                    assert spec is not None and spec.origin is not None
                    self.assertEqual(pathlib.Path(spec.origin).resolve(), script)
        finally:
            sys.path.remove(str(SCRIPTS))

    def test_a_stdlib_named_module_or_package_is_caught(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name in ("babysit_util.py", "json.py", "socket.pyc", "README.md"):
                (root / name).touch()
            for name in ("logging", "tests"):
                (root / name).mkdir()
            self.assertEqual(
                stdlib_shadows(root), ["json.py", "logging", "socket.pyc"]
            )


if __name__ == "__main__":
    unittest.main()
