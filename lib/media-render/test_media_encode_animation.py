"""The animation plugin's encode profiles. The argv tests pin the arguments render.py passed ffmpeg before it moved
onto media_encode, so a released film encodes the same; the round trips check each profile yields its format's codec.
The round trips skip without ffmpeg and ffprobe unless MEDIA_RENDER_REQUIRE_DEPS=1, which fails them instead."""
import os
import shutil
import tempfile
import unittest
from pathlib import Path

import media_encode

REQUIRE = os.environ.get('MEDIA_RENDER_REQUIRE_DEPS') == '1'
HAVE_FFMPEG = all(shutil.which(t) for t in ('ffmpeg', 'ffprobe'))
PINNED = {
    'animation-mp4': ['-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16'],
    'animation-webm': ['-c:v', 'libvpx-vp9', '-pix_fmt', 'yuv420p', '-crf', '30', '-b:v', '0'],
    'animation-gif': ['-vf', 'split[a][b];[a]palettegen[p];[b][p]paletteuse'],
}


class AnimationProfileArgvTest(unittest.TestCase):
    def test_each_profile_keeps_render_py_s_released_arguments(self):
        for name, argv in PINNED.items():
            with self.subTest(profile=name):
                self.assertEqual(media_encode.PROFILES[name]['video'], argv)


@unittest.skipUnless(HAVE_FFMPEG or REQUIRE, 'ffmpeg and ffprobe not installed')
class AnimationProfileEncodeTest(unittest.TestCase):
    def test_each_profile_writes_its_format_s_codec(self):
        self.assertTrue(HAVE_FFMPEG, 'ffmpeg or ffprobe missing and MEDIA_RENDER_REQUIRE_DEPS=1')
        expected = {'animation-mp4': ('mp4', 'h264,yuv420p'), 'animation-webm': ('webm', 'vp9,yuv420p'),
                    'animation-gif': ('gif', 'gif')}
        with tempfile.TemporaryDirectory() as tmp:
            for name, (ext, stream) in expected.items():
                with self.subTest(profile=name):
                    out = Path(tmp) / f'{name}.{ext}'
                    media_encode.run(['-f', 'lavfi', '-i', 'testsrc=size=64x48:rate=24:duration=0.25',
                                      *media_encode.PROFILES[name]['video'], out])
                    fields = 'codec_name' if ext == 'gif' else 'codec_name,pix_fmt'
                    got = media_encode.probe(['-select_streams', 'v:0', '-show_entries', f'stream={fields}',
                                              '-of', 'csv=p=0', out]).strip()
                    self.assertEqual(got, stream)


if __name__ == '__main__':
    unittest.main()
