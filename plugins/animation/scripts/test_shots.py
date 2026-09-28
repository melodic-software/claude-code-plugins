"""shots.json owns cut times. Standard library only."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import shots  # noqa: E402


class ShotStarts(unittest.TestCase):
    def test_comma_list_stays_a_list(self):
        self.assertEqual(shots.shot_starts("0,4.2,9.8"), [0.0, 4.2, 9.8])
        self.assertEqual(shots.shot_starts("0-3"), [0.0, 3.0])
        self.assertIsNone(shots.shot_starts(None))
        self.assertIsNone(shots.shot_starts(""))

    def test_shots_json_is_the_owner(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "shots.json"
            path.write_text(
                json.dumps({"version": 1, "fps": 12, "shots": [{"id": "a", "t0": 0}, {"id": "b", "t0": 1.5}]}),
                encoding="utf-8",
            )
            self.assertEqual(shots.shot_starts(str(path)), [0.0, 1.5])

    def test_missing_json_file_is_an_error(self):
        with self.assertRaises(SystemExit) as caught:
            shots.shot_starts("/tmp/does-not-exist-shots.json")
        self.assertIn("not found", str(caught.exception))

    def test_cli_prints_starts(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "shots.json"
            path.write_text(json.dumps({"shots": [{"t0": 0}, {"t0": 2}]}), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, str(HERE / "shots.py"), str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.strip(), "0,2")


if __name__ == "__main__":
    unittest.main()
