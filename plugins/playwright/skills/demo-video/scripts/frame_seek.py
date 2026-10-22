"""Frame-accurate seek time and short-read check for the demo-video quality-control contact sheets.
Standard library only, so the tests exercise the exact code quality_control.py uses where numpy, Pillow and
ffmpeg are absent.

`-ss` before `-i` decodes from the previous keyframe and keeps the first frame whose timestamp is at or after
the seek point. Seeking to fi / fps formatted to 4 decimals rounds up past the frame's own timestamp whenever
fi % 3 == 2 at 30 fps (338 / 30 = 11.26666... becomes 11.2667), which returns frame fi + 1, and for the last
frame returns no bytes with exit 0. Seeking half a frame early lands in the gap before frame fi instead.
"""


def seek_time(fi, fps):
    """The `-ss` value, in seconds, that makes ffmpeg's first kept frame frame `fi`: the middle of the gap before it."""
    return f'{max(0.0, (fi - 0.5) / fps):.4f}'


def check_frame(raw, fi, fps, width, height):
    """Return `raw` when it holds one full rgb24 frame, else raise ValueError naming the frame and its timestamp."""
    want = width * height * 3
    if len(raw) != want:
        raise ValueError(f'ffmpeg returned {len(raw)} bytes, not the {want} of one {width}x{height} rgb24 frame, '
                         f'for frame {fi} at {fi / fps:.4f}s')
    return raw
