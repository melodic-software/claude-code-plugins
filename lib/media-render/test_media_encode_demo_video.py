"""Pins for the demo-video profile: the expected argv is what playwright:demo-video's produce.py passed ffmpeg before
its encode and narration mix moved here (AC11, unchanged output). A pin proves sameness, not correctness."""
import unittest
from unittest import mock

import media_encode


class DemoVideoProfileTest(unittest.TestCase):
    def test_video_arguments_are_the_demo_video_encode(self):
        self.assertEqual(media_encode.PROFILES['demo-video']['video'], [
            '-vf', 'scale=out_color_matrix=bt709:out_range=tv:flags=lanczos+accurate_rnd+full_chroma_int'
                   '+full_chroma_inp,format=yuv420p',
            '-c:v', 'libx264', '-profile:v', 'high', '-preset', 'slower', '-crf', '16',
            '-x264-params', 'colorprim=bt709:transfer=bt709:colormatrix=bt709:range=tv',
            '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
            '-movflags', '+faststart'])

    def test_mix_places_each_clip_at_its_start_over_the_copied_video(self):
        clips = [{'file': 'a.wav', 'start': 1.25, 'duration': 2.0},
                 {'file': 'b.wav', 'start': 4.0, 'duration': 1.5, 'trim': 0.3}]
        with mock.patch('subprocess.run') as run:
            run.return_value.returncode = 0
            media_encode.mix('v.mp4', clips, 'o.mp4', 428 / 30)
        graph = ('[1:a]atrim=start=0:duration=2.0,asetpts=PTS-STARTPTS,aresample=48000,adelay=1250:all=1[a0];'
                 '[2:a]atrim=start=0.3:duration=1.5,asetpts=PTS-STARTPTS,aresample=48000,adelay=4000:all=1[a1];'
                 '[a0][a1]amix=inputs=2:normalize=0:dropout_transition=0,apad[mixed]')
        self.assertEqual(run.call_args.args[0], [
            'ffmpeg', '-v', 'error', '-y', '-i', 'v.mp4', '-i', 'a.wav', '-i', 'b.wav', '-filter_complex', graph,
            '-map', '0:v', '-map', '[mixed]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k', '-t', '14.267',
            '-movflags', '+faststart', 'o.mp4'])


if __name__ == '__main__':
    unittest.main()
