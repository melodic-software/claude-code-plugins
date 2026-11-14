"""The pixel-art-webm profile: pixel-art's capture.py loops a scene's WAV under its recorded WebM."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import media_encode

HAVE_FFMPEG = all(shutil.which(t) for t in ('ffmpeg', 'ffprobe'))
REQUIRE = os.environ.get('MEDIA_RENDER_REQUIRE_DEPS') == '1'


def webm_mux_args(webm, wav, seconds, out):
    p = media_encode.PROFILES['pixel-art-webm']
    return ['-i', webm, '-stream_loop', '-1', '-i', wav, '-map', '0:v', '-map', '1:a', *p['video'], *p['audio'],
            '-t', str(seconds), out]


class PixelArtWebmTest(unittest.TestCase):
    def test_argv_keeps_the_capture_mux_arguments(self):
        with mock.patch('subprocess.run') as run:
            run.return_value.returncode = 0
            media_encode.run(webm_mux_args('in.webm', 'a.wav', 3, 'out.webm'))
        self.assertEqual(run.call_args.args[0], [
            'ffmpeg', '-v', 'error', '-y', '-i', 'in.webm', '-stream_loop', '-1', '-i', 'a.wav', '-map', '0:v',
            '-map', '1:a', '-c:v', 'copy', '-c:a', 'libopus', '-t', '3', 'out.webm'],
            'pixel-art-webm must copy the recorded video and encode the looped WAV as Opus')

    def test_mux_copies_video_and_loops_opus_audio_to_the_record_length(self):
        if not HAVE_FFMPEG:
            if REQUIRE:
                self.fail('ffmpeg/ffprobe missing and MEDIA_RENDER_REQUIRE_DEPS=1')
            self.skipTest('ffmpeg/ffprobe not installed')
        with tempfile.TemporaryDirectory() as tmp:
            webm, wav, out = (Path(tmp) / n for n in ('in.webm', 'a.wav', 'out.webm'))
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=size=64x48:rate=10:duration=3',
                            '-c:v', 'libvpx', str(webm)], check=True)
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=duration=0.5:sample_rate=48000',
                            str(wav)], check=True)
            media_encode.run(webm_mux_args(webm, wav, 2, out))
            codecs = media_encode.probe(['-show_entries', 'stream=codec_type,codec_name', '-of', 'csv=p=0', out])
            audio_seconds = float(media_encode.probe(['-select_streams', 'a', '-show_entries', 'format=duration',
                                                      '-of', 'csv=p=0', out]))
        self.assertEqual(codecs.split(), ['vp8,video', 'opus,audio'], 'video copied as VP8, audio encoded as Opus')
        self.assertAlmostEqual(audio_seconds, 2.0, delta=0.1,
                               msg='a 0.5 s WAV loops to fill the 2 s record length')


if __name__ == '__main__':
    unittest.main()
