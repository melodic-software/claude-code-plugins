"""produce.py: boards, the approval digest, and shots.json as the cut list."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / 'produce.py'


def run(args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)


def fill(prod):
    """Boards that pass, and two shot modules."""
    (prod / 'brief.md').write_text(
        '# Brief\n\nSubject: a harbor at dusk\nLength: 2s\nAudience: the user\n'
        'Packs: woodcut-ink\nDelivery: mp4\n', encoding='utf-8')
    (prod / 'boards/style-guide.md').write_text(
        '# Style guide\n\nPack: woodcut-ink\n\nDiffers from the pack:\n'
        '- camera push-in, judgment\n', encoding='utf-8')
    (prod / 'boards/vibe.md').write_text('# Vibe\n\nCredit: none; no reference image.\n', encoding='utf-8')
    (prod / 'boards/palette.json').write_text(json.dumps({
        'pack': 'woodcut-ink', 'ink': '#14110e', 'paper': '#f3ead7',
        'tones': [{'lv': 1, 'color': '#8a8175'}], 'tolerance': 5,
    }, indent=2) + '\n', encoding='utf-8')
    png = prod / 'boards/storyboard/s1.png'
    png.write_bytes(b'\x89PNG\r\n')
    (prod / 'boards/storyboard.json').write_text(json.dumps({'panels': [{
        'shot': 's1', 'panel': 1, 't': 0, 'png': 'boards/storyboard/s1.png',
        'action': 'the lamp lights', 'camera': 'static', 'caption': None,
    }]}, indent=2) + '\n', encoding='utf-8')
    for stem, body in (('keeper', 'a figure'),):
        (prod / 'boards/models' / f'{stem}.md').write_text(f'# {stem}\n\n{body}\n', encoding='utf-8')
        (prod / 'boards/models' / f'{stem}.js').write_text('export function draw() {}\n', encoding='utf-8')
        (prod / 'boards/models' / f'{stem}.png').write_bytes(b'\x89PNG\r\n')
    (prod / 'scenes').mkdir(exist_ok=True)
    (prod / 'scenes/s1.js').write_text('window.DURATION = 2\n', encoding='utf-8')
    (prod / 'shots.json').write_text(json.dumps({
        'fps': 24, 'size': [64, 48],
        'shots': [{'id': 's1', 't0': 0, 't1': 2, 'scene': 'scenes/s1.js', 'pack': 'woodcut-ink'}],
    }, indent=2) + '\n', encoding='utf-8')


class ProduceTest(unittest.TestCase):
    def test_skeleton_fails_boards_until_filled(self):
        with tempfile.TemporaryDirectory() as tmp:
            prod = Path(tmp) / 'film'
            made = run(['init', str(prod)])
            self.assertEqual(made.returncode, 0, made.stderr)
            self.assertTrue((prod / 'boards/storyboard.json').is_file())
            again = run(['init', str(prod)])
            self.assertEqual(again.returncode, 0)
            self.assertIn('already has brief.md', again.stdout)
            (prod / 'boards/vibe.md').unlink()   # an interrupted init: brief.md exists, a board file does not
            (prod / 'brief.md').write_text('# Mine\n', encoding='utf-8')
            run(['init', str(prod)])
            self.assertTrue((prod / 'boards/vibe.md').is_file())
            self.assertEqual((prod / 'brief.md').read_text(encoding='utf-8'), '# Mine\n')
            (prod / 'brief.md').unlink()
            run(['init', str(prod)])
            boards = run(['boards', str(prod)])
            self.assertEqual(boards.returncode, 1)
            self.assertIn('Subject', boards.stdout)
            fill(prod)
            self.assertEqual(run(['boards', str(prod)]).returncode, 0)

    def test_shots_stay_closed_until_approval_and_reclose_when_boards_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            prod = Path(tmp) / 'film'
            run(['init', str(prod)])
            fill(prod)
            closed = run(['shots', str(prod)])
            self.assertEqual(closed.returncode, 2)
            self.assertIn('not approved', closed.stdout)
            self.assertEqual(run(['approve', str(prod), '--note', 'boards look right']).returncode, 0)
            opened = run(['shots', str(prod)])
            self.assertEqual(opened.returncode, 0, opened.stdout)
            cuts = run(['cuts', str(prod)])
            self.assertEqual(cuts.returncode, 0)
            self.assertEqual(cuts.stdout.strip(), '0')
            (prod / 'boards/vibe.md').write_text('# Vibe\n\nCredit: a second pass.\n', encoding='utf-8')
            stale = run(['shots', str(prod)])
            self.assertEqual(stale.returncode, 2)
            review = run(['review', str(prod)])
            self.assertEqual(review.returncode, 2)

    def test_review_matches_render_json_and_names_the_pack_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            prod = Path(tmp) / 'film'
            run(['init', str(prod)])
            fill(prod)
            run(['approve', str(prod), '--note', 'yes'])
            frames = prod / 'frames'
            frames.mkdir()
            (frames / 'render.json').write_text(json.dumps({
                'scene': str(prod / 'scenes/s1.js'), 'adapter': 'native', 'adapter_version': '0.2.0',
                'browser_build': 'test', 'fps': 24, 'size': [64, 48], 'frames': 48, 'duration': 2,
            }) + '\n', encoding='utf-8')
            out = run(['review', str(prod)])
            self.assertEqual(out.returncode, 0, out.stdout)
            self.assertIn(f'inkstats.py {frames} --cuts {prod / "shots.json"} --pack {HERE.parent / "styles" / "woodcut-ink"}', out.stdout)
            meta = json.loads((frames / 'render.json').read_text(encoding='utf-8'))
            meta['duration'] = 9
            (frames / 'render.json').write_text(json.dumps(meta) + '\n', encoding='utf-8')
            bad = run(['review', str(prod)])
            self.assertEqual(bad.returncode, 1)
            self.assertIn('duration', bad.stdout)

    def test_pack_is_shell_quoted_and_names_only_resolve_inside_styles(self):
        sys.path.insert(0, str(HERE))
        import produce
        self.assertEqual(produce.pack_arg('woodcut-ink'), str(HERE.parent / 'styles' / 'woodcut-ink'))
        self.assertEqual(produce.pack_arg('x; rm -rf ~'), "'x; rm -rf ~'")
        self.assertEqual(produce.pack_arg('../styles/woodcut-ink'), '../styles/woodcut-ink')

    def test_panel_png_outside_boards_is_part_of_the_approval(self):
        with tempfile.TemporaryDirectory() as tmp:
            prod = Path(tmp) / 'film'
            run(['init', str(prod)])
            fill(prod)
            (prod / 'assets').mkdir()
            png = prod / 'assets/panel.png'
            png.write_bytes((prod / 'boards/storyboard/s1.png').read_bytes())
            board = json.loads((prod / 'boards/storyboard.json').read_text(encoding='utf-8'))
            board['panels'][0]['png'] = 'assets/panel.png'
            (prod / 'boards/storyboard.json').write_text(json.dumps(board), encoding='utf-8')
            self.assertEqual(run(['approve', str(prod), '--note', 'yes']).returncode, 0)
            self.assertEqual(run(['shots', str(prod)]).returncode, 0)
            png.write_bytes(png.read_bytes() + b'changed')
            self.assertEqual(run(['shots', str(prod)]).returncode, 2)

    def test_storyboard_png_cannot_escape_and_gap_in_shots_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            prod = Path(tmp) / 'film'
            run(['init', str(prod)])
            fill(prod)
            board = json.loads((prod / 'boards/storyboard.json').read_text(encoding='utf-8'))
            board['panels'][0]['png'] = '../outside.png'
            (prod / 'boards/storyboard.json').write_text(json.dumps(board), encoding='utf-8')
            escaped = run(['boards', str(prod)])
            self.assertEqual(escaped.returncode, 1)
            self.assertIn('escapes', escaped.stdout)
            fill(prod)
            shots = json.loads((prod / 'shots.json').read_text(encoding='utf-8'))
            shots['shots'].append({
                'id': 's2', 't0': 3, 't1': 4, 'scene': 'scenes/s1.js', 'pack': 'woodcut-ink'})
            (prod / 'shots.json').write_text(json.dumps(shots), encoding='utf-8')
            run(['approve', str(prod), '--note', 'yes'])
            gap = run(['shots', str(prod)])
            self.assertEqual(gap.returncode, 1)
            self.assertIn('must meet the previous t1', gap.stdout)


if __name__ == '__main__':
    unittest.main()
