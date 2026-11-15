"""The ffmpeg- and Chromium-backed modules against real tools. Skips without ffmpeg/ffprobe (or Playwright for the
capture test) unless MEDIA_RENDER_REQUIRE_DEPS=1, which fails instead."""
import importlib.util
import os
import shutil
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import media_encode
import media_loudness
import media_sheet
import media_size
import media_verify

REQUIRE = os.environ.get('MEDIA_RENDER_REQUIRE_DEPS') == '1'
HAVE_FFMPEG = all(shutil.which(t) for t in ('ffmpeg', 'ffprobe'))
HAVE_PLAYWRIGHT = importlib.util.find_spec('playwright') is not None
TARGET = {'integrated_lufs': -16.0, 'tolerance_lu': 1.0, 'true_peak_max_dbtp': -1.0, 'limiter_true_peak_dbtp': -2.0,
          'loudness_range_lu': 11.0}


def png_size(path):
    w, h = struct.unpack('>II', Path(path).read_bytes()[16:24])
    return w, h


def needs(flag, what):
    if flag:
        return lambda f: f
    if REQUIRE:
        return lambda f: (lambda self: self.fail(f'{what} missing and MEDIA_RENDER_REQUIRE_DEPS=1'))
    return unittest.skip(f'{what} not installed')


class PureTest(unittest.TestCase):
    def test_concat_file_escapes_a_quote(self):
        self.assertEqual(media_encode.concat_file("it's.png"), "file 'it'\\''s.png'")

    def test_concat_list_repeats_the_last_frame(self):
        text = media_encode.concat_list([('/x/a.png', 1.5), ('/x/b.png', 2)])
        self.assertEqual(text.splitlines()[1:], ["file 'a.png'", 'duration 1.500', "file 'b.png'", 'duration 2.000',
                                                 "file 'b.png'"])

    def test_mux_keeps_the_explainer_arguments(self):
        with mock.patch('subprocess.run') as run:
            run.return_value.returncode = 0
            media_encode.mux('v.mp4', 'a.wav', 'c.srt', 'o.mp4')
        self.assertEqual(run.call_args.args[0], [
            'ffmpeg', '-v', 'error', '-y', '-i', 'v.mp4', '-i', 'a.wav', '-i', 'c.srt', '-map', '0:v:0', '-map',
            '1:a:0', '-map', '2:s:0', '-c:v', 'copy', '-c:a', 'aac', '-c:s', 'mov_text', '-metadata:s:s:0',
            'language=eng', 'o.mp4'])

    def test_plan_split_cuts_at_chapter_starts_and_refuses_an_oversize_chapter(self):
        # 100 B/s against 2,500 B with 10% headroom: 22.5 s a part at most.
        self.assertEqual(media_size.plan_split([0, 10, 20, 30], 40, 4_000, 2_500), [(0, 20), (20, 40)])
        with self.assertRaises(media_size.SizeError):
            media_size.plan_split([0, 30], 40, 4_000, 2_000)


@needs(HAVE_FFMPEG, 'ffmpeg and ffprobe')
class FfmpegTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.frames = []
        for i, color in enumerate(('red', 'green', 'blue')):
            p = self.dir / f'f{i}.png'
            media_encode.run(['-f', 'lavfi', '-i', f'testsrc2=s=640x360,drawbox=c={color}:t=40', '-frames:v', '1', p])
            self.frames.append(p)
        self.wav = self.dir / 'tone.wav'
        media_encode.run(['-f', 'lavfi', '-i', 'sine=f=440:d=6', '-ac', '1', self.wav])

    def test_stills_with_audio_and_captions(self):
        (self.dir / 'c.srt').write_text('1\n00:00:00,000 --> 00:00:01,000\nHi\n\n', encoding='utf-8')
        (self.dir / 'c.ass').write_text(
            '[Script Info]\nPlayResX: 640\nPlayResY: 360\n\n[V4+ Styles]\nFormat: Name, Fontsize\nStyle: Default,20\n\n'
            '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
            'Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,Hi\n', encoding='utf-8')
        out = self.dir / 'v.mp4'
        media_encode.stills([(f, 2.0) for f in self.frames], out, audio=self.wav, srt=self.dir / 'c.srt',
                            ass=self.dir / 'c.ass', cwd=self.dir)
        info = media_verify.probe(out)
        codecs = sorted((s['codec_type'], s['codec_name']) for s in info['streams'])
        self.assertEqual(codecs, [('audio', 'aac'), ('subtitle', 'mov_text'), ('video', 'h264')])
        self.assertEqual(media_verify.stream_defects(info, 6.0, 30, audio=True, subtitle=True), [])
        shot = self.dir / 'at.png'
        media_verify.frame_at(out, 3.0, shot)
        self.assertGreater(media_verify.luma_ssim(self.frames[1], shot), 0.99)
        self.assertFalse(media_verify.blank(shot))

    def test_assemble_audio_inserts_silence(self):
        out = self.dir / 'a.wav'
        media_encode.assemble_audio(self.wav, [('silence', 1.5), ('narration', 0.0, 2.0)], out)
        self.assertAlmostEqual(float(media_verify.probe(out)['format']['duration']), 3.5, places=1)

    def test_blank_frame_detected(self):
        p = self.dir / 'black.png'
        media_encode.run(['-f', 'lavfi', '-i', 'color=c=black:s=64x36', '-frames:v', '1', p])
        self.assertTrue(media_verify.blank(p))

    def test_loudness_two_passes_reach_target(self):
        target_wav = self.dir / 'n.wav'
        mode = media_loudness.normalize(self.wav, target_wav, media_loudness.measure(self.wav, TARGET), TARGET)
        self.assertIn(mode, ('linear', 'dynamic'))
        self.assertEqual(media_loudness.defects(media_loudness.measure(target_wav, TARGET), TARGET), [])

    def test_contact_sheet_native_tiles_then_more_sheets_when_over_the_cap(self):
        made = media_sheet.sheets(self.frames, self.dir / 's')
        self.assertEqual(len(made), 1)
        self.assertEqual(png_size(made[0]['path']), (640 * 2 + 16, 360 * 2 + 16))
        smaller = max(m['bytes'] for m in made) - 1
        self.assertGreater(len(media_sheet.sheets(self.frames, self.dir / 't', max_bytes=smaller)), 1)
        with self.assertRaises(media_sheet.SheetError):
            media_sheet.sheets(self.frames, self.dir / 'u', max_bytes=10)

    def test_split_parts_fit_and_start_on_chapters(self):
        out = self.dir / 'v.mp4'
        media_encode.stills([(f, 2.0) for f in self.frames], out, cwd=self.dir)
        size = out.stat().st_size
        limit = int(size * 0.8)
        parts = media_size.split(out, [0.0, 2.0, 4.0], 6.0, self.dir / 'parts', limit=limit)
        self.assertGreater(len(parts), 1)
        self.assertTrue(all(p['bytes'] <= limit for p in parts))
        self.assertTrue(all(p['start_s'] in (0.0, 2.0, 4.0) for p in parts))
        self.assertEqual(parts[0]['start_s'], 0.0)

    def test_stitcher_command_substitutes_inputs_and_out(self):
        out = self.dir / 'copy.png'
        cmd = f'"{sys.executable}" -c "import shutil,sys; shutil.copy(sys.argv[1], sys.argv[-1])" {{inputs}} {{out}}'
        media_encode.stitcher(cmd, [self.frames[0]], out)
        self.assertEqual(out.read_bytes(), self.frames[0].read_bytes())

    def test_stitcher_runs_in_the_output_folder(self):
        work = self.dir / 'work'
        work.mkdir()
        out = work / 'out.txt'
        cmd = f'"{sys.executable}" -c "import os,sys; open(sys.argv[-1], \'w\').write(os.getcwd())" {{out}}'
        media_encode.stitcher(cmd, [], out)
        self.assertEqual(Path(out.read_text()).resolve(), work.resolve())

    def test_contact_sheet_reads_a_folder_with_a_quote_in_its_name(self):
        quoted = self.dir / "it's"
        quoted.mkdir()
        frames = [shutil.copy(f, quoted / f.name) for f in self.frames]
        self.assertEqual(len(media_sheet.sheets([Path(f) for f in frames], quoted / 's')), 1)


BAND = 0.24
SIZE = (1920, 1080)
PLAYER_WIDTH = 888   # GitHub's inline video player, in pixels
MIN_TEXT_PX = 14     # the smallest text height a reviewer can read in that player
SMALLEST_FONT = r"""() => {
  let least = Infinity;
  const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n = walk.nextNode(); n; n = walk.nextNode())
    if (n.textContent.trim()) least = Math.min(least, parseFloat(getComputedStyle(n.parentElement).fontSize));
  return least;
}"""


def also_changed(count):
    return {'template': 'also-changed', 'chapter': 'c', 'data': {
        'files': [{'path': f'src/module-{i:02d}/a-fairly-long-file-name-{i:02d}.py', 'summary': f'change {i}'}
                  for i in range(count)]}}


def frame(moment, part=None):
    import media_templates
    return media_templates.page(moment, 'Title', 'Chapter', (1, 1), SIZE, BAND, part=part)


@needs(HAVE_PLAYWRIGHT, 'Playwright for Python')
class CaptureTest(unittest.TestCase):
    def test_capture_is_4k_and_blocks_network(self):
        import media_capture
        with tempfile.TemporaryDirectory() as d:
            html = '<html><body style="background:#123"><img src="https://example.invalid/x.png"><h1>Hi</h1></body></html>'
            (out,) = media_capture.capture([(html, Path(d) / 'a.png')])
            self.assertEqual(png_size(out), (3840, 2160))

    def test_the_fit_check_fails_a_list_that_runs_off_the_frame_and_passes_one_that_fits(self):
        import media_capture
        with tempfile.TemporaryDirectory() as d:
            (_, long), (_, short) = media_capture.capture_checked(
                [(frame(also_changed(30)), Path(d) / 'long.png'), (frame(also_changed(2)), Path(d) / 'short.png')],
                *SIZE, 1, BAND)
        self.assertTrue(any('below' in p for p in long), long)
        self.assertTrue(any('above' in p for p in long), f'the centered list should also run up over the header: {long}')
        self.assertEqual(short, [])

    def test_a_code_line_that_wraps_at_a_space_fits_the_frame(self):
        import media_capture
        text = ('Below the table, name every changed text file outside every ecosystem on one line: '
                '`Outside every ecosystem: <path>, <path>`. The line changes no Status and no Overall line.')
        moment = {'template': 'code-hunk', 'chapter': 'c', 'data': {
            'path': 'plugins/toolchain/skills/check/SKILL.md',
            'lines': [{'n': 156, 'kind': '+', 'text': text}]}}
        with tempfile.TemporaryDirectory() as d:
            ((_, problems),) = media_capture.capture_checked([(frame(moment), Path(d) / 'hunk.png')], *SIZE, 1, BAND)
        self.assertEqual(problems, [])

    def test_a_flow_diagram_keeps_its_nodes_and_arrows_on_one_row(self):
        from playwright.sync_api import sync_playwright
        nodes = [{'label': 'A .rs file changes', 'detail': 'no Rust record'},
                 {'label': 'Nothing claims it', 'detail': 'lint and check skip it'},
                 {'label': 'Report says PASS', 'detail': 'the file was never read'},
                 {'label': 'Reviewer trusts it', 'detail': 'and merges'}]
        moment = {'template': 'diagram', 'chapter': 'c', 'data': {'layout': 'flow', 'nodes': nodes}}
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={'width': SIZE[0], 'height': SIZE[1]}, java_script_enabled=False)
            page.set_content(frame(moment))
            rows = page.evaluate("""() => [...document.querySelectorAll('.flow > *')].map(e => {
              const r = e.getBoundingClientRect(); return [r.top, r.bottom]; })""")
            browser.close()
        self.assertEqual(len(rows), 2 * len(nodes) - 1)
        top = max(t for t, _ in rows)
        bottom = min(b for _, b in rows)
        self.assertLess(top, bottom, f'every node and arrow should share one row: {rows}')

    def test_a_long_pull_request_title_fits_the_title_frame(self):
        import media_capture
        import media_templates
        moment = {'template': 'title', 'chapter': 'c', 'data': {'subtitle': 'A walkthrough for reviewers'}}
        titles = ['feat(session-flow): ask whether a check could decide a retro finding before proposing a prose rule',
                  'feat(session-flow): ' + 'ask whether a check could decide each retro finding ' * 2 + 'first']
        with tempfile.TemporaryDirectory() as d:
            checked = media_capture.capture_checked(
                [(media_templates.page(moment, t, 'Chapter', (1, 1), SIZE, BAND), Path(d) / f'{i}.png')
                 for i, t in enumerate(titles)], *SIZE, 1, BAND)
        self.assertEqual([p for _, p in checked], [[], []])

    def test_paginate_covers_the_list_in_order_with_frames_that_each_fit(self):
        import media_capture
        import media_templates
        moment = also_changed(30)

        def render(a, b):
            return frame(media_templates.subset(moment, a, b), part=(2, 30))
        (cuts,) = media_capture.paginate([(render, 30)], *SIZE, 1, BAND)
        self.assertGreater(len(cuts), 1)
        self.assertEqual(cuts[0][0], 0)
        self.assertEqual(cuts[-1][1], 30)
        self.assertTrue(all(a[1] == b[0] for a, b in zip(cuts, cuts[1:])), cuts)
        with tempfile.TemporaryDirectory() as d:
            checked = media_capture.capture_checked([(render(a, b), Path(d) / f'{a}.png') for a, b in cuts],
                                                    *SIZE, 1, BAND)
        self.assertEqual([p for _, p in checked], [[]] * len(cuts))

    def test_every_template_s_smallest_text_reads_at_least_14_px_tall_in_an_888_px_player(self):
        from playwright.sync_api import sync_playwright
        moments = {
            'title': {'subtitle': 'A walkthrough'},
            'code-hunk': {'path': 'a.py', 'lines': [{'n': 1, 'kind': '+', 'text': 'x = 1'}], 'note': 'n'},
            'diagram': {'nodes': [{'label': 'A', 'detail': 'd'}, {'label': 'B'}], 'center': 'c', 'note': 'n'},
            'before-after': {'before': {'lines': ['a']}, 'after': {'lines': ['b']}},
            'risk-map': {'rows': [{'area': 'a', 'level': 'low', 'note': 'n'}]},
            'also-changed': {'files': [{'path': 'a.py', 'summary': 's'}]},
        }
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={'width': SIZE[0], 'height': SIZE[1]}, java_script_enabled=False)
            for template, data in moments.items():
                with self.subTest(template):
                    page.set_content(frame({'template': template, 'chapter': 'c', 'data': data}, part=(2, 3)))
                    smallest = page.evaluate(SMALLEST_FONT)
                    self.assertGreaterEqual(smallest * PLAYER_WIDTH / SIZE[0], MIN_TEXT_PX, f'{smallest} CSS px')
            browser.close()


if __name__ == '__main__':
    unittest.main()
