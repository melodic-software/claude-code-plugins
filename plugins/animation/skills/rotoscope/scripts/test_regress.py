"""regress.py --synthetic as a test: the render, encode and decode contracts and the regression cases.

Standard library only at module level, so collection works without numpy; the test skips, naming what is missing,
when the plugin's prerequisites (prereq.check) do not all pass.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / 'scripts'))
import prereq  # noqa: E402

MISSING = [f'{name} ({detail})' for name, status, detail, _ in prereq.check() if status == 'FAIL']


@unittest.skipUnless(not MISSING, f"animation prerequisites missing: {', '.join(MISSING)}")
class SyntheticRegress(unittest.TestCase):
    def test_synthetic(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = subprocess.run([sys.executable, str(HERE / 'regress.py'), '--synthetic', str(Path(tmp) / 'work')],
                               capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout[-4000:] + r.stderr[-4000:])


if __name__ == '__main__':
    unittest.main()
