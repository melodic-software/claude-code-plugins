"""Gate, schema and shot cuts for /animation:produce. Standard library only."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / 'produce.py'


def run(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True, text=True,
    )


class Produce(unittest.TestCase):
    def test_gate_blocks_until_the_boards_are_approved(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'film'
            made = run('init', str(root), '--title', 'Harbor')
            self.assertEqual(made.returncode, 0, made.stderr)
            self.assertTrue((root / 'brief.md').is_file())
            self.assertTrue((root / 'boards' / 'storyboard.md').is_file())
            self.assertFalse((root / 'boards' / 'APPROVED').exists())
            blocked = run('gate', str(root))
            self.assertEqual(blocked.returncode, 1, blocked.stderr)
            self.assertIn('not approved', blocked.stderr)
            checked = run('check', str(root))
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertIn('boards', checked.stdout)
            (root / 'boards' / 'APPROVED').write_text('approved\n', encoding='utf-8')
            opened = run('gate', str(root))
            self.assertEqual(opened.returncode, 0, opened.stderr)
            self.assertIn('approved', opened.stdout)

    def test_cuts_come_from_shots_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'film'
            self.assertEqual(run('init', str(root), '--title', 'Harbor', '--style', 'woodcut-ink').returncode, 0)
            path = root / 'shots.json'
            data = json.loads(path.read_text(encoding='utf-8'))
            data['shots'].append({
                'id': 's2', 't0': 4.2, 'scene': 'scenes/s2.js', 'title': 'Turn',
            })
            path.write_text(json.dumps(data), encoding='utf-8')
            got = run('cuts', str(root))
            self.assertEqual(got.returncode, 0, got.stderr)
            self.assertEqual(got.stdout.strip(), '4.2')

    def test_a_shot_out_of_order_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'film'
            self.assertEqual(run('init', str(root), '--title', 'Harbor').returncode, 0)
            path = root / 'shots.json'
            data = json.loads(path.read_text(encoding='utf-8'))
            data['shots'].append({
                'id': 's2', 't0': 0, 'scene': 'scenes/s2.js', 'title': 'Turn',
            })
            path.write_text(json.dumps(data), encoding='utf-8')
            got = run('check', str(root))
            self.assertNotEqual(got.returncode, 0)
            self.assertIn('t0', got.stderr)

    def test_init_refuses_an_existing_production(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'film'
            self.assertEqual(run('init', str(root), '--title', 'Harbor').returncode, 0)
            again = run('init', str(root), '--title', 'Harbor')
            self.assertNotEqual(again.returncode, 0)


if __name__ == '__main__':
    unittest.main()
