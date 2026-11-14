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


@needs(HAVE_PLAYWRIGHT, 'Playwright for Python')
class CaptureTest(unittest.TestCase):
    def test_capture_is_4k_and_blocks_network(self):
        import media_capture
        with tempfile.TemporaryDirectory() as d:
            html = '<html><body style="background:#123"><img src="https://example.invalid/x.png"><h1>Hi</h1></body></html>'
            (out,) = media_capture.capture([(html, Path(d) / 'a.png')])
            self.assertEqual(png_size(out), (3840, 2160))


if __name__ == '__main__':
    unittest.main()
