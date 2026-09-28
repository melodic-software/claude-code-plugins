"""produce.py stops at the boards until the user writes boards/APPROVED."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
PRODUCE = HERE / "produce.py"


def run(*args):
    return subprocess.run(
        [sys.executable, str(PRODUCE), *args],
        capture_output=True,
        text=True,
        check=False,
    )


class ProduceGate(unittest.TestCase):
    def test_init_stops_until_the_user_approves(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "film"
            init = run("init", str(root), "--title", "Harbor", "--style", "woodcut-ink")
            self.assertEqual(init.returncode, 0, init.stderr)
            self.assertTrue((root / "brief.md").is_file())
            self.assertTrue((root / "boards" / "storyboard.md").is_file())
            self.assertFalse((root / "boards" / "APPROVED").exists())
            shots = json.loads((root / "shots.json").read_text(encoding="utf-8"))
            self.assertEqual(shots["shots"][0]["t0"], 0)
            self.assertEqual(shots["styles"], ["woodcut-ink"])

            checked = run("check", str(root))
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertIn("boards", checked.stdout)

            blocked = run("gate", str(root))
            self.assertEqual(blocked.returncode, 2, blocked.stderr)
            self.assertIn("not approved", blocked.stderr)

            (root / "boards" / "APPROVED").write_text("approved\n", encoding="utf-8")
            opened = run("gate", str(root))
            self.assertEqual(opened.returncode, 0, opened.stderr)
            self.assertIn("approved", opened.stdout)

            cuts = run("cuts", str(root))
            self.assertEqual(cuts.returncode, 0, cuts.stderr)
            self.assertEqual(cuts.stdout.strip(), "")

            shots["shots"].append(
                {"id": "s2", "t0": 1.5, "scene": "scenes/s2.js", "title": "Cross"}
            )
            (root / "shots.json").write_text(json.dumps(shots), encoding="utf-8")
            later = run("cuts", str(root))
            self.assertEqual(later.stdout.strip(), "1.5")

    def test_a_decreasing_t0_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "film"
            self.assertEqual(run("init", str(root), "--title", "Harbor").returncode, 0)
            shots = json.loads((root / "shots.json").read_text(encoding="utf-8"))
            shots["shots"] = [
                {"id": "b", "t0": 2, "scene": "scenes/b.js", "title": "Late"},
                {"id": "a", "t0": 0, "scene": "scenes/a.js", "title": "Early"},
            ]
            (root / "shots.json").write_text(json.dumps(shots), encoding="utf-8")
            checked = run("check", str(root))
            self.assertNotEqual(checked.returncode, 0)
            self.assertIn("t0", checked.stderr)


if __name__ == "__main__":
    unittest.main()
