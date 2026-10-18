"""render.py and capture.mjs over a real headless render. Needs node and playwright-core with Chromium (the
capture.mjs --probe lookup) and skips without them; ANIMATION_REQUIRE_DEPS covers numpy and opencv, not the browser."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def have_chromium():
    if not shutil.which('node'):
        return False
    return subprocess.run(['node', str(HERE / 'capture.mjs'), '--probe'], capture_output=True).returncode == 0


HAVE = have_chromium()

# A scene whose shared code sets the hooks first and whose own setup finishes after a top-level await: the first
# film of the evidence run, which read DURATION before its await and wrote a tenth of its frames with exit 0.
LATE = """const c = document.getElementById('c'); c.width = 8; c.height = 8;
window.DURATION = 1;
window.renderFrame = async () => { c.getContext('2d').fillRect(0, 0, 8, 8); };
await new Promise(r => setTimeout(r, 300));
window.DURATION = 2;
"""
SHORT = """const c = document.getElementById('c'); c.width = 8; c.height = 8;
window.DURATION = 1;
window.renderFrame = async () => { c.getContext('2d').fillRect(0, 0, 8, 8); };
"""


@unittest.skipUnless(HAVE, 'needs node and playwright-core with Chromium')
class Render(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def render(self, source, *extra):
        scene = self.dir / 'scene.js'
        scene.write_text(source, encoding='utf-8')
        out = self.dir / 'frames'
        r = subprocess.run([sys.executable, str(HERE / 'render.py'), str(scene), str(out), '--fps', '10',
                            '--workers', '1', *extra], capture_output=True, text=True)
        meta = out / 'render.json'
        return r, json.loads(meta.read_text(encoding='utf-8')) if meta.is_file() else None

    def shots(self, t1):
        path = self.dir / 'shots.json'
        path.write_text(json.dumps({'fps': 10, 'size': [8, 8], 'shots': [
            {'id': 's1', 't0': 0, 't1': t1, 'scene': 'scene.js', 'pack': 'woodcut-ink'}]}), encoding='utf-8')
        return path

    def test_capture_waits_for_the_scene_module_s_top_level_awaits(self):
        r, meta = self.render(LATE)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((meta['duration'], meta['frames']), (2, 20))
        self.assertEqual(len(list((self.dir / 'frames').glob('f*.png'))), 20)

    def test_a_film_shorter_than_its_shot_list_fails(self):
        r, _ = self.render(SHORT, '--shots', str(self.shots(2)))
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn('does not cover the shot list through 2', r.stderr)

    def test_a_film_that_matches_its_shot_list_passes(self):
        r, _ = self.render(SHORT, '--shots', str(self.shots(1)))
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == '__main__':
    unittest.main()
